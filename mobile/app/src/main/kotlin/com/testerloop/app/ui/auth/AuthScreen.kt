package com.testerloop.app.ui.auth

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Visibility
import androidx.compose.material.icons.rounded.VisibilityOff
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.testerloop.app.ui.AppVm
import com.testerloop.app.ui.AuthMode
import com.testerloop.app.ui.onEmail
import com.testerloop.app.ui.onFullName
import com.testerloop.app.ui.onNewPassword
import com.testerloop.app.ui.onPassword
import com.testerloop.app.ui.onResetCode
import com.testerloop.app.ui.submitAuth
import com.testerloop.app.ui.switchAuth
import com.testerloop.app.ui.UiState
import com.testerloop.app.ui.components.BackExitHandler
import com.testerloop.app.ui.components.BrandWordmark
import com.testerloop.app.ui.components.FormError
import com.testerloop.app.ui.components.InfoBanner
import com.testerloop.app.ui.components.TlButton
import com.testerloop.app.ui.components.TlField
import com.testerloop.app.ui.components.PillTone
import com.testerloop.app.ui.components.TlTextAction
import com.testerloop.app.ui.theme.Bg
import com.testerloop.app.ui.theme.Muted

@Composable
fun AuthScreen(ui: UiState, vm: AppVm) {
    var passwordVisible by remember { mutableStateOf(false) }
    val busy = ui.authBusy
    val parentMode = when (ui.authMode) {
        AuthMode.SignUp, AuthMode.Recover -> AuthMode.Login
        AuthMode.RecoverCode -> AuthMode.Recover
        AuthMode.Login -> null
    }

    BackHandler(enabled = parentMode != null) { parentMode?.let { vm.switchAuth(it) } }
    BackExitHandler(enabled = parentMode == null) { vm.message("Press back again to exit") }

    val eyebrow = when (ui.authMode) {
        AuthMode.Login -> "WELCOME BACK"
        AuthMode.SignUp -> "NEW TESTER"
        AuthMode.Recover -> "RESET PASSWORD"
        AuthMode.RecoverCode -> "CHECK YOUR EMAIL"
    }
    val headline = when (ui.authMode) {
        AuthMode.Login -> "Sign in to your tester bench."
        AuthMode.SignUp -> "Join projects. File reports. Get paid."
        AuthMode.Recover -> "We'll email you a reset code."
        AuthMode.RecoverCode -> "Choose a new password."
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Bg)
            .statusBarsPadding()
            .navigationBarsPadding()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp, vertical = 24.dp)
    ) {
        BrandWordmark()
        Spacer(Modifier.height(40.dp))
        Text(eyebrow, style = MaterialTheme.typography.labelMedium, color = Muted)
        Spacer(Modifier.height(6.dp))
        Text(headline, style = MaterialTheme.typography.displaySmall)
        Spacer(Modifier.height(8.dp))
        Text(
            if (ui.authMode == AuthMode.SignUp) {
                "The email you sign up with is also the Google address you add to the Play test."
            } else {
                "Closed testing for Android apps, without the spreadsheet."
            },
            style = MaterialTheme.typography.bodyMedium,
            color = Muted
        )

        if (!ui.authNotice.isNullOrBlank()) {
            Spacer(Modifier.height(18.dp))
            InfoBanner("Good to know", ui.authNotice, tone = PillTone.Teal)
        }

        Spacer(Modifier.height(26.dp))

        when (ui.authMode) {
            AuthMode.SignUp -> {
                TlField(
                    value = ui.fullName,
                    onValueChange = vm::onFullName,
                    label = "Display name",
                    placeholder = "Amara Silva",
                    enabled = !busy
                )
                Spacer(Modifier.height(14.dp))
            }
            AuthMode.RecoverCode -> {
                TlField(
                    value = ui.resetCode,
                    onValueChange = vm::onResetCode,
                    label = "Reset code",
                    placeholder = "123456",
                    keyboardType = KeyboardType.NumberPassword,
                    enabled = !busy
                )
                Spacer(Modifier.height(14.dp))
            }
            else -> Unit
        }

        if (ui.authMode != AuthMode.RecoverCode) {
            TlField(
                value = ui.email,
                onValueChange = vm::onEmail,
                label = "Email",
                placeholder = "you@example.com",
                keyboardType = KeyboardType.Email,
                enabled = !busy
            )
            Spacer(Modifier.height(14.dp))
        }

        if (ui.authMode != AuthMode.Recover) {
            val value = if (ui.authMode == AuthMode.RecoverCode) ui.newPassword else ui.password
            val onChange: (String) -> Unit =
                if (ui.authMode == AuthMode.RecoverCode) vm::onNewPassword else vm::onPassword
            TlField(
                value = value,
                onValueChange = onChange,
                label = if (ui.authMode == AuthMode.RecoverCode) "New password" else "Password",
                placeholder = "At least 8 characters",
                keyboardType = KeyboardType.Password,
                imeAction = ImeAction.Done,
                enabled = !busy,
                visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(),
                trailing = {
                    IconButton(onClick = { passwordVisible = !passwordVisible }) {
                        Icon(
                            if (passwordVisible) Icons.Rounded.VisibilityOff else Icons.Rounded.Visibility,
                            contentDescription = if (passwordVisible) "Hide password" else "Show password",
                            tint = Muted
                        )
                    }
                }
            )
        }

        FormError(ui.authError, modifier = Modifier.padding(top = 10.dp))

        Spacer(Modifier.height(22.dp))
        TlButton(
            text = when (ui.authMode) {
                AuthMode.Login -> "Sign in"
                AuthMode.SignUp -> "Create account"
                AuthMode.Recover -> "Send reset code"
                AuthMode.RecoverCode -> "Update password"
            },
            onClick = vm::submitAuth,
            loading = busy
        )

        Spacer(Modifier.height(14.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center
        ) {
            when (ui.authMode) {
                AuthMode.Login -> {
                    TlTextAction("Create account", { vm.switchAuth(AuthMode.SignUp) }, enabled = !busy)
                    TlTextAction("Forgot password?", { vm.switchAuth(AuthMode.Recover) }, enabled = !busy)
                }
                AuthMode.SignUp -> TlTextAction("I already have an account", { vm.switchAuth(AuthMode.Login) }, enabled = !busy)
                AuthMode.Recover -> TlTextAction("Back to sign in", { vm.switchAuth(AuthMode.Login) }, enabled = !busy)
                AuthMode.RecoverCode -> TlTextAction("Use a different email", { vm.switchAuth(AuthMode.Recover) }, enabled = !busy)
            }
        }
        Spacer(Modifier.height(24.dp))
        Text(
            "Tester workspace only. Use TesterLoop on Windows for developer work and TesterLoop Admin for operations.",
            style = MaterialTheme.typography.bodySmall,
            color = Muted
        )
    }
}


