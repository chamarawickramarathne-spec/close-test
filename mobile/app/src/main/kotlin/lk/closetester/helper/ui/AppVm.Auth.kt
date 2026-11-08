package lk.closetester.helper.ui

import androidx.lifecycle.viewModelScope
import lk.closetester.helper.core.AppConfig
import lk.closetester.helper.data.api.AuthRequest
import lk.closetester.helper.data.api.AuthResponse
import lk.closetester.helper.data.api.apiMessage
import lk.closetester.helper.data.api.orThrow
import kotlinx.coroutines.launch

class AppException(message: String) : Exception(message)

internal fun AppVm.login() {
    val state = ui.value
    val email = state.email.trim()
    if (!isEmail(email)) return updateState { it.copy(authError = "Enter a valid email address.") }
    if (state.password.isBlank()) return updateState { it.copy(authError = "Enter your password.") }
    updateState { it.copy(authBusy = true, authError = null, authNotice = null) }
    viewModelScope.launch {
        try {
            val resp = api.signIn(
                AppConfig.SUPABASE_ANON_KEY,
                AuthRequest(email = email, password = state.password)
            )
            handleAuth(resp, email)
        } catch (e: Exception) {
            failAuth(e)
        }
    }
}

internal fun AppVm.signUp() {
    val state = ui.value
    val email = state.email.trim()
    val name = state.fullName.trim()
    if (name.length < 2) return updateState { it.copy(authError = "Enter your display name.") }
    if (!isEmail(email)) return updateState { it.copy(authError = "Enter a valid email address.") }
    if (state.password.length < 8) return updateState { it.copy(authError = "Use a password of at least 8 characters.") }
    updateState { it.copy(authBusy = true, authError = null, authNotice = null) }
    viewModelScope.launch {
        try {
            val resp = api.signUp(
                AppConfig.SUPABASE_ANON_KEY,
                AuthRequest(
                    email = email,
                    password = state.password,
                    data = mapOf(
                        "role" to "tester",
                        "display_name" to name,
                        "google_email" to email
                    )
                )
            )
            handleAuth(resp, email)
        } catch (e: Exception) {
            failAuth(e)
        }
    }
}

internal suspend fun AppVm.handleAuth(resp: AuthResponse, email: String) {
    val access = resp.accessToken?.takeIf { it.isNotBlank() }
    val refresh = resp.refreshToken?.takeIf { it.isNotBlank() }
    if (access == null || refresh == null) {
        updateState {
            it.copy(
                authBusy = false,
                authMode = AuthMode.Login,
                password = "",
                authNotice = "Account created. Confirm your email, then sign in."
            )
        }
        return
    }
    store.replaceSession(access, refresh)
    try {
        requireTester(access)
    } catch (e: Exception) {
        store.clearSession()
        throw e
    }
    store.saveLastEmail(email)
    updateState {
        it.copy(
            phase = Phase.Ready,
            authBusy = false,
            authError = null,
            authNotice = null,
            password = "",
            resetCode = "",
            newPassword = "",
            fullName = "",
            lastEmail = email,
            email = email
        )
    }
    loadDashboard(initial = true)
}

internal fun AppVm.sendResetCode() {
    val email = ui.value.email.trim()
    if (!isEmail(email)) return updateState { it.copy(authError = "Enter a valid email address.") }
    updateState { it.copy(authBusy = true, authError = null, authNotice = null) }
    viewModelScope.launch {
        try {
            api.recover(AppConfig.SUPABASE_ANON_KEY, mapOf("email" to email)).orThrow()
            updateState {
                it.copy(
                    authBusy = false,
                    authMode = AuthMode.RecoverCode,
                    authNotice = "Enter the code from the email, then choose a new password."
                )
            }
        } catch (e: Exception) {
            failAuth(e)
        }
    }
}

internal fun AppVm.applyResetCode() {
    val state = ui.value
    val email = state.email.trim()
    if (state.resetCode.length < 6) return updateState { it.copy(authError = "Enter the code from the email.") }
    if (state.newPassword.length < 8) return updateState { it.copy(authError = "Use a password of at least 8 characters.") }
    updateState { it.copy(authBusy = true, authError = null, authNotice = null) }
    viewModelScope.launch {
        try {
            val resp = api.verifyRecovery(
                AppConfig.SUPABASE_ANON_KEY,
                mapOf("type" to "recovery", "token" to state.resetCode, "email" to email)
            )
            val access = resp.accessToken?.takeIf { it.isNotBlank() }
                ?: throw AppException("That code is invalid or has expired.")
            api.updatePassword(
                AppConfig.SUPABASE_ANON_KEY,
                "Bearer $access",
                mapOf("password" to state.newPassword)
            ).orThrow()
            store.clearSession()
            updateState {
                it.copy(
                    authBusy = false,
                    authMode = AuthMode.Login,
                    password = "",
                    resetCode = "",
                    newPassword = "",
                    authNotice = "Password updated. Sign in with your new password."
                )
            }
        } catch (e: Exception) {
            failAuth(e)
        }
    }
}

internal suspend fun AppVm.failAuth(e: Exception) {
    updateState { it.copy(authBusy = false, authError = apiMessage(e), authNotice = null) }
}

internal fun isEmail(value: String): Boolean =
    Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(value)
