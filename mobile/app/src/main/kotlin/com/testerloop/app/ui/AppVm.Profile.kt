package com.testerloop.app.ui

import androidx.lifecycle.viewModelScope
import com.testerloop.app.core.AppConfig
import com.testerloop.app.data.api.UpdateProfileRequest
import com.testerloop.app.data.api.apiMessage
import com.testerloop.app.data.api.orThrow
import kotlinx.coroutines.launch

fun AppVm.openProfile() {
    val tester = ui.value.tester
    updateState {
        it.copy(
            profileName = tester?.displayName.orEmpty(),
            profileGoogle = tester?.googleEmail ?: tester?.email.orEmpty(),
            profileRegion = tester?.region.orEmpty(),
            profileError = null,
            profileNotice = null
        )
    }
}

fun AppVm.onProfileName(value: String) = updateState { it.copy(profileName = value, profileError = null, profileNotice = null) }
fun AppVm.onProfileGoogle(value: String) = updateState { it.copy(profileGoogle = value, profileError = null, profileNotice = null) }
fun AppVm.onProfileRegion(value: String) = updateState { it.copy(profileRegion = value, profileError = null, profileNotice = null) }

fun AppVm.saveProfile() {
    val state = ui.value
    if (state.profileBusy) return
    val name = state.profileName.trim()
    val google = state.profileGoogle.trim().lowercase()
    val region = state.profileRegion.trim()
    val devices = state.tester?.devices.orEmpty()

    if (name.length < 2) {
        updateState { it.copy(profileError = "Display name must be at least two characters.") }
        return
    }
    if (!Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(google)) {
        updateState { it.copy(profileError = "Enter a valid Google account email.") }
        return
    }

    updateState { it.copy(profileBusy = true, profileError = null, profileNotice = null) }
    viewModelScope.launch {
        try {
            session.withAuth { token ->
                api.updateTesterProfile(
                    AppConfig.SUPABASE_ANON_KEY,
                    "Bearer $token",
                    UpdateProfileRequest(
                        displayName = name,
                        googleEmail = google,
                        region = region.ifBlank { null },
                        devices = devices
                    )
                ).orThrow()
            }
            loadDashboard(initial = false)
            updateState {
                it.copy(
                    profileBusy = false,
                    profileNotice = "Profile saved.",
                    profileName = name,
                    profileGoogle = google
                )
            }
        } catch (e: Exception) {
            updateState { it.copy(profileBusy = false, profileError = apiMessage(e)) }
            if (e is com.testerloop.app.data.local.SessionExpiredException) handleActionError(e)
        }
    }
}
