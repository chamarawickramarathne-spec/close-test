package lk.closetester.helper.ui

import lk.closetester.helper.data.api.AvailableItem
import lk.closetester.helper.data.api.MineItem
import lk.closetester.helper.data.api.ReportItem
import lk.closetester.helper.data.api.Tester

enum class Phase { Splash, Auth, Ready }

enum class AuthMode { Login, SignUp, Recover, RecoverCode, Activation }

data class UiState(
    val phase: Phase = Phase.Splash,
    val authMode: AuthMode = AuthMode.Login,
    val email: String = "",
    val password: String = "",
    val fullName: String = "",
    val resetCode: String = "",
    val newPassword: String = "",
    val lastEmail: String = "",
    val authBusy: Boolean = false,
    val authError: String? = null,
    val authNotice: String? = null,
    val tester: Tester? = null,
    val mine: List<MineItem> = emptyList(),
    val available: List<AvailableItem> = emptyList(),
    val reports: List<ReportItem> = emptyList(),
    val loading: Boolean = false,
    val refreshing: Boolean = false,
    val loadError: String? = null,
    val tab: Int = 0,
    val projectsTab: Int = 0,
    val campaignId: String? = null,
    val campaignLoading: Boolean = false,
    val campaignError: String? = null,
    val joiningId: String? = null,
    val optInBusyId: String? = null,
    val reportBusy: Boolean = false,
    val reportError: String? = null,
    val reportSuccess: Int = 0,
    val profileName: String = "",
    val profileGoogle: String = "",
    val profileRegion: String = "",
    val profileBusy: Boolean = false,
    val profileError: String? = null,
    val profileNotice: String? = null,
    val deviceError: String? = null,
    val usageAccess: Boolean = false
)

sealed interface UiEvent {
    data class OpenUrl(val url: String) : UiEvent
    data class Message(val text: String) : UiEvent
    object OpenUsageSettings : UiEvent
    object CloseCampaign : UiEvent
}
