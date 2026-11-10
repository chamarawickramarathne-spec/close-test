package lk.closetester.helper.ui

import androidx.lifecycle.viewModelScope
import lk.closetester.helper.core.AppConfig
import lk.closetester.helper.data.api.AuthRequest
import lk.closetester.helper.data.api.AuthResponse
import lk.closetester.helper.data.api.SendActivationRequest
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
            val message = apiMessage(e)
            if (message.contains("not activated", ignoreCase = true)) {
                store.clearSession()
                updateState {
                    it.copy(
                        authBusy = false,
                        authMode = AuthMode.Login,
                        authError = null,
                        authNotice = "Your account is not activated yet. Open the activation email, then sign in again.",
                        email = email,
                        lastEmail = email
                    )
                }
            } else {
                failAuth(e)
            }
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
            val access = resp.accessToken?.takeIf { it.isNotBlank() }
            val refresh = resp.refreshToken?.takeIf { it.isNotBlank() }
            if (access == null || refresh == null) {
                updateState {
                    it.copy(
                        authBusy = false,
                        authMode = AuthMode.Login,
                        password = "",
                        authError = "The account was created but TesterLoop needs Supabase email confirmation switched off to send the activation email. Ask operations to check the authentication settings."
                    )
                }
                return@launch
            }
            store.replaceSession(access, refresh)
            try {
                api.sendActivation(
                    AppConfig.SUPABASE_ANON_KEY,
                    "Bearer $access",
                    SendActivationRequest(email)
                ).orThrow()
            } finally {
                store.clearSession()
            }
            updateState {
                it.copy(
                    authBusy = false,
                    authMode = AuthMode.Activation,
                    password = "",
                    authError = null,
                    authNotice = "We sent a 24-hour activation link to $email. Open it, then sign in.",
                    email = email,
                    lastEmail = email,
                    fullName = ""
                )
            }
        } catch (e: Exception) {
            store.clearSession()
            updateState {
                it.copy(
                    authBusy = false,
                    authMode = AuthMode.Login,
                    authError = apiMessage(e),
                    authNotice = "Your account was created. Request a new activation email, then sign in."
                )
            }
        }
    }
}

internal fun AppVm.resendActivation() {
    val email = ui.value.email.trim()
    if (!isEmail(email)) return updateState { it.copy(authError = "Enter a valid email address.") }
    updateState { it.copy(authBusy = true, authError = null, authNotice = null) }
    viewModelScope.launch {
        try {
            api.sendActivation(
                AppConfig.SUPABASE_ANON_KEY,
                null,
                SendActivationRequest(email)
            ).orThrow()
            updateState {
                it.copy(
                    authBusy = false,
                    authMode = AuthMode.Activation,
                    authNotice = "If that account is waiting for activation, a new link is on its way. Check your email.",
                    lastEmail = email
                )
            }
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
