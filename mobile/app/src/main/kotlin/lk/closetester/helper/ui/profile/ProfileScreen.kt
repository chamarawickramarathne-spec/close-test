package lk.closetester.helper.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import lk.closetester.helper.BuildConfig
import lk.closetester.helper.core.initialsOf
import lk.closetester.helper.ui.AppVm
import lk.closetester.helper.ui.UiState
import lk.closetester.helper.ui.onProfileGoogle
import lk.closetester.helper.ui.onProfileName
import lk.closetester.helper.ui.onProfileRegion
import lk.closetester.helper.ui.openProfile
import lk.closetester.helper.ui.openUsageSettings
import lk.closetester.helper.ui.saveProfile
import lk.closetester.helper.ui.syncUsageNow
import lk.closetester.helper.ui.components.Avatar
import lk.closetester.helper.ui.components.FormError
import lk.closetester.helper.ui.components.Hairline
import lk.closetester.helper.ui.components.InfoBanner
import lk.closetester.helper.ui.components.KeyValueRow
import lk.closetester.helper.ui.components.PillTone
import lk.closetester.helper.ui.components.TlButton
import lk.closetester.helper.ui.components.TlSecondaryButton
import lk.closetester.helper.ui.components.SectionHeader
import lk.closetester.helper.ui.components.TlCard
import lk.closetester.helper.ui.components.TlField
import lk.closetester.helper.ui.components.TlTextAction
import lk.closetester.helper.ui.theme.Ink
import lk.closetester.helper.ui.theme.Muted
import lk.closetester.helper.ui.theme.TealDeep

@Composable
fun ProfileScreen(vm: AppVm, ui: UiState) {
    var confirmSignOut by remember { mutableStateOf(false) }
    val tester = ui.tester

    LifecycleResumeEffect(Unit) {
        vm.openProfile()
        onPauseOrDispose { }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp, vertical = 18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        SectionHeader("Profile")

        TlCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Avatar(initialsOf(ui.profileName), size = 52.dp)
                Spacer(Modifier.width(12.dp))
                Column {
                    Text(
                        tester?.displayName ?: ui.profileName.ifBlank { "Tester" },
                        style = MaterialTheme.typography.titleMedium,
                        color = Ink
                    )
                    Text(
                        ui.email,
                        style = MaterialTheme.typography.bodySmall,
                        color = Muted
                    )
                }
            }
            Spacer(Modifier.height(14.dp))
            Hairline()
            Spacer(Modifier.height(6.dp))
            KeyValueRow("Google account", tester?.googleEmail ?: "Not set")
            KeyValueRow("Region", tester?.region?.takeIf { it.isNotBlank() } ?: "Not set")
            KeyValueRow(
                "Device type",
                tester?.mobileDeviceName?.takeIf { it.isNotBlank() } ?: "Not reported yet"
            )
            KeyValueRow(
                "Reliability",
                tester?.reliability?.let { "${(it * 100).toInt()}%" } ?: "Not set"
            )
            FormError(ui.deviceError, modifier = Modifier.padding(top = 6.dp))
        }

        SectionHeader("Edit profile")
        TlCard {
            TlField(
                value = ui.profileName,
                onValueChange = vm::onProfileName,
                label = "Display name",
                placeholder = "Your name",
                enabled = !ui.profileBusy
            )
            Spacer(Modifier.height(12.dp))
            TlField(
                value = ui.profileGoogle,
                onValueChange = vm::onProfileGoogle,
                label = "Google account email",
                placeholder = "you@gmail.com",
                keyboardType = KeyboardType.Email,
                enabled = !ui.profileBusy
            )
            Spacer(Modifier.height(12.dp))
            TlField(
                value = ui.profileRegion,
                onValueChange = vm::onProfileRegion,
                label = "Region",
                placeholder = "City, country",
                enabled = !ui.profileBusy
            )
            Spacer(Modifier.height(6.dp))
            Text(
                "Device type is captured automatically when you sign in to TesterLoop Mobile on this phone.",
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
            FormError(ui.profileError, modifier = Modifier.padding(top = 8.dp))
            if (!ui.profileNotice.isNullOrBlank()) {
                Spacer(Modifier.height(10.dp))
                InfoBanner("Saved", ui.profileNotice, tone = PillTone.Good)
            }
            Spacer(Modifier.height(14.dp))
            TlButton(
                text = if (ui.profileBusy) "Saving..." else "Save profile",
                onClick = { vm.saveProfile() },
                enabled = !ui.profileBusy
            )
        }

        SectionHeader("Usage access")
        TlCard {
            Text("ANDROID PERMISSION", style = MaterialTheme.typography.labelMedium, color = Muted)
            Spacer(Modifier.height(8.dp))
            Text(
                if (ui.usageAccess) {
                    "Usage access is allowed. TesterLoop records foreground time for joined projects only."
                } else {
                    "Usage access is off. Allow it so the app can record foreground time for joined projects."
                },
                style = MaterialTheme.typography.bodyMedium,
                color = Ink
            )
            Spacer(Modifier.height(12.dp))
            TlSecondaryButton(
                text = if (ui.usageAccess) "Usage settings" else "Allow usage access",
                onClick = { vm.openUsageSettings() }
            )
            Spacer(Modifier.height(8.dp))
            TlSecondaryButton(
                text = "Sync usage now",
                onClick = { vm.syncUsageNow() }
            )
        }

        SectionHeader("Session")
        TlCard {
            KeyValueRow("Version", BuildConfig.VERSION_NAME)
            Spacer(Modifier.height(6.dp))
            TlTextAction("Sign out", { confirmSignOut = true }, color = TealDeep)
            Spacer(Modifier.height(4.dp))
            Text(
                "Signing out keeps your remembered email but removes this session from the device.",
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }
    }

    if (confirmSignOut) {
        AlertDialog(
            onDismissRequest = { confirmSignOut = false },
            title = { Text("Sign out?") },
            text = { Text("You will need your email and password to sign in again.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmSignOut = false
                    vm.signOut()
                }) { Text("Sign out") }
            },
            dismissButton = {
                TextButton(onClick = { confirmSignOut = false }) { Text("Cancel") }
            }
        )
    }
}

