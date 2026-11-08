package lk.closetester.helper.ui

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import lk.closetester.helper.core.AppConfig
import lk.closetester.helper.data.api.EnsureRoleRequest
import lk.closetester.helper.data.api.SupabaseApi
import lk.closetester.helper.data.api.apiMessage
import lk.closetester.helper.data.api.orThrow
import lk.closetester.helper.data.local.InstallHistoryStore
import lk.closetester.helper.data.local.SessionExpiredException
import lk.closetester.helper.data.local.SessionManager
import lk.closetester.helper.data.local.SessionStore
import lk.closetester.helper.worker.UsageReader
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.launch
import retrofit2.HttpException
import javax.inject.Inject

private class RoleException :
    Exception("This app needs a tester profile. Operations accounts use TesterLoop Admin.")

@HiltViewModel
class AppVm @Inject constructor(
    internal val api: SupabaseApi,
    internal val session: SessionManager,
    internal val store: SessionStore,
    internal val installStore: InstallHistoryStore,
    @ApplicationContext internal val appContext: Context
) : ViewModel() {

    private val _ui = MutableStateFlow(UiState())
    val ui: StateFlow<UiState> = _ui.asStateFlow()

    private val _events = Channel<UiEvent>(Channel.BUFFERED)
    val events = _events.receiveAsFlow()

    init {
        bootstrap()
    }

    internal fun updateState(block: (UiState) -> UiState) {
        _ui.value = block(_ui.value)
    }

    private fun bootstrap() {
        viewModelScope.launch {
            val saved = store.lastEmailFlow.first()
            updateState { it.copy(lastEmail = saved, email = it.email.ifBlank { saved }) }
            if (!session.hasSession()) {
                updateState { it.copy(phase = Phase.Auth) }
                return@launch
            }
            try {
                session.withAuth { token -> requireTester(token) }
                updateState { it.copy(phase = Phase.Ready) }
                loadDashboard(initial = true)
            } catch (_: SessionExpiredException) {
                updateState { it.copy(phase = Phase.Auth) }
            } catch (e: Exception) {
                updateState { it.copy(phase = Phase.Auth, authError = apiMessage(e)) }
            }
        }
    }

    internal suspend fun requireTester(token: String) {
        val auth = "Bearer $token"
        var me = api.whoami(AppConfig.SUPABASE_ANON_KEY, auth)
        var role = (me["role"] as? String)?.trim()?.lowercase()
        if (role.isNullOrEmpty()) {
            api.claimProfile(AppConfig.SUPABASE_ANON_KEY, auth).orThrow()
            me = api.whoami(AppConfig.SUPABASE_ANON_KEY, auth)
            role = (me["role"] as? String)?.trim()?.lowercase()
        }
        if (role == "admin") throw RoleException()

        if ((me["tester_id"] as? String).isNullOrBlank()) {
            api.ensureAccountRole(
                AppConfig.SUPABASE_ANON_KEY,
                auth,
                EnsureRoleRequest("tester")
            ).orThrow()
            me = api.whoami(AppConfig.SUPABASE_ANON_KEY, auth)
        }
        if ((me["tester_id"] as? String).isNullOrBlank()) throw RoleException()
    }

    internal suspend fun loadDashboard(initial: Boolean) {
        updateState {
            if (initial) it.copy(loading = true, loadError = null)
            else it.copy(refreshing = true, loadError = null)
        }
        try {
            val dash = session.withAuth { token ->
                api.testerDashboard(AppConfig.SUPABASE_ANON_KEY, "Bearer $token")
            }
            updateState {
                it.copy(
                    loading = false,
                    refreshing = false,
                    tester = dash.tester,
                    mine = dash.mine,
                    available = dash.available,
                    reports = dash.reports,
                    usageAccess = UsageReader.hasUsageAccess(appContext)
                )
            }
            syncMobileDevice()
            captureInstallTracking(dash)
        } catch (_: SessionExpiredException) {
            updateState { it.copy(loading = false, refreshing = false) }
            endSession("Your session expired. Sign in again.")
        } catch (e: Exception) {
            updateState {
                it.copy(loading = false, refreshing = false, loadError = apiMessage(e))
            }
        }
    }

    fun refresh() {
        if (_ui.value.phase != Phase.Ready || _ui.value.loading) return
        viewModelScope.launch { loadDashboard(initial = false) }
    }

    fun refreshUsageAccess() {
        val granted = UsageReader.hasUsageAccess(appContext)
        if (granted != _ui.value.usageAccess) {
            updateState { it.copy(usageAccess = granted) }
        }
    }

    private suspend fun endSession(message: String) {
        session.signOut()
        val saved = store.lastEmailFlow.first()
        _ui.value = UiState(phase = Phase.Auth, email = saved, lastEmail = saved, authError = message)
    }

    fun dismissLoadError() = updateState { it.copy(loadError = null) }
    fun dismissProfileNotice() = updateState { it.copy(profileNotice = null) }

    fun setTab(index: Int) = updateState { it.copy(tab = index) }
    fun setProjectsTab(index: Int) = updateState { it.copy(projectsTab = index) }

    fun signOut() {
        viewModelScope.launch {
            val saved = store.lastEmailFlow.first()
            session.signOut()
            _ui.value = UiState(phase = Phase.Auth, email = saved, lastEmail = saved)
        }
    }

    fun openCampaign(id: String) {
        updateState { it.copy(campaignId = id, campaignError = null, reportError = null) }
        viewModelScope.launch {
            val mine = _ui.value.mine.firstOrNull { it.campaignId == id }
            val available = _ui.value.available.firstOrNull { it.campaignId == id }
            if (mine == null && available == null) {
                loadDashboard(initial = false)
            } else if ((mine?.packageName ?: available?.packageName).isNullOrBlank()) {
                loadDashboard(initial = false)
            }
        }
    }

    fun closeCampaign() = updateState { it.copy(campaignId = null, campaignError = null, reportError = null) }

    internal fun sendEvent(event: UiEvent) {
        viewModelScope.launch { _events.send(event) }
    }

    internal fun message(text: String) = sendEvent(UiEvent.Message(text))

    internal fun handleActionError(e: Exception) {
        if (e is SessionExpiredException || (e is HttpException && e.code() == 401)) {
            viewModelScope.launch { endSession(apiMessage(e)) }
        } else {
            message(apiMessage(e))
        }
    }
}

