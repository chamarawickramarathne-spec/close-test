package lk.closetester.helper.ui

fun AppVm.onEmail(value: String) = updateState { it.copy(email = value, authError = null) }

fun AppVm.onPassword(value: String) = updateState { it.copy(password = value, authError = null) }

fun AppVm.onFullName(value: String) = updateState { it.copy(fullName = value, authError = null) }

fun AppVm.onResetCode(value: String) =
    updateState { it.copy(resetCode = value.filter { c -> c.isDigit() }, authError = null) }

fun AppVm.onNewPassword(value: String) = updateState { it.copy(newPassword = value, authError = null) }

fun AppVm.switchAuth(mode: AuthMode) {
    updateState {
        it.copy(
            authMode = mode,
            authBusy = false,
            authError = null,
            authNotice = null,
            password = "",
            resetCode = "",
            newPassword = "",
            fullName = ""
        )
    }
}

fun AppVm.dismissAuthError() = updateState { it.copy(authError = null) }

fun AppVm.submitAuth() {
    val state = ui.value
    if (state.authBusy) return
    when (state.authMode) {
        AuthMode.Login -> login()
        AuthMode.SignUp -> signUp()
        AuthMode.Recover -> sendResetCode()
        AuthMode.RecoverCode -> applyResetCode()
        AuthMode.Activation -> resendActivation()
    }
}
