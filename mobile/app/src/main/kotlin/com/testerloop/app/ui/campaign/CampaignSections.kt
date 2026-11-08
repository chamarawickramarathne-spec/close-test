package com.testerloop.app.ui.campaign

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.testerloop.app.core.PlayLink
import com.testerloop.app.core.formatDate
import com.testerloop.app.core.humanState
import com.testerloop.app.core.isActiveCampaign
import com.testerloop.app.core.projectClock
import com.testerloop.app.data.api.AvailableItem
import com.testerloop.app.data.api.MineItem
import com.testerloop.app.ui.AppVm
import com.testerloop.app.ui.UiState
import com.testerloop.app.ui.components.Hairline
import com.testerloop.app.ui.components.InfoBanner
import com.testerloop.app.ui.components.KeyValueRow
import com.testerloop.app.ui.components.PillTone
import com.testerloop.app.ui.components.ProgressTrack
import com.testerloop.app.ui.components.SectionHeader
import com.testerloop.app.ui.components.StatusPill
import com.testerloop.app.ui.components.TlButton
import com.testerloop.app.ui.components.TlCard
import com.testerloop.app.ui.components.TlSecondaryButton
import com.testerloop.app.ui.components.TlTextAction
import com.testerloop.app.ui.components.stateTone
import com.testerloop.app.ui.openUsageSettings
import com.testerloop.app.ui.syncUsageNow
import com.testerloop.app.ui.theme.Muted

@Composable
internal fun CampaignHero(mine: MineItem?, available: AvailableItem?) {
    TlCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    mine?.appName ?: available?.appName ?: "Project",
                    style = MaterialTheme.typography.titleLarge
                )
                Text(
                    mine?.packageName ?: available?.packageName ?: "Package not set",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted
                )
            }
            StatusPill(
                humanState(mine?.state ?: "open"),
                if (mine != null) stateTone(mine.state) else PillTone.Teal
            )
        }
        Spacer(Modifier.height(16.dp))
        if (mine != null) {
            val clock = mine.projectClock()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    if (clock.started) clock.daysLabel else clock.waitingLabel,
                    style = MaterialTheme.typography.titleMedium
                )
                Spacer(Modifier.weight(1f))
                Text(
                    "Seat ${mine.seatNumber ?: "—"}",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted
                )
            }
            Spacer(Modifier.height(8.dp))
            ProgressTrack(progress = clock.progress)
            Spacer(Modifier.height(10.dp))
            Text(
                if (clock.started) {
                    "The project clock starts when the 12th tester confirms opt-in. Opting out resets your seat."
                } else {
                    "${clock.confirmedLabel}. The 14-day clock starts when all ${clock.requiredTesters} testers confirm."
                },
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        } else if (available != null) {
            Row {
                Text("${available.seatsFree} seats free", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.width(8.dp))
                Text(
                    "· ${available.requiredTesters} testers for 14 days",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted,
                    modifier = Modifier.align(Alignment.CenterVertically)
                )
            }
        }
    }
}

@Composable
internal fun OptInCard(
    ui: UiState,
    item: MineItem,
    onConfirm: () -> Unit,
    onOptOut: () -> Unit,
    onUsageSettings: () -> Unit
) {
    val verified = item.optInVerification == "google_group"
    TlCard {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text("Google Group opt-in", style = MaterialTheme.typography.titleSmall)
                Text(
                    if (verified) "Confirmed on ${formatDate(item.optInVerifiedAt)}"
                    else "We check that your Google address is an active member of this project's group.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted
                )
            }
            StatusPill(
                if (verified) "VERIFIED" else if (item.state == "joined") "JOINED" else "UNVERIFIED",
                if (verified) PillTone.Good else PillTone.Warn
            )
        }
        Spacer(Modifier.height(14.dp))
        if (verified) {
            Text(
                "Keep the group membership active for the full 14 days. Removing yourself or leaving the group can drop your seat.",
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        } else {
            if (ui.usageAccess) {
                TlButton(
                    text = "Confirm opt-in",
                    onClick = onConfirm,
                    loading = ui.optInBusyId == item.campaignId
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    "If the check fails, the seat is released so you can fix access and rejoin.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted
                )
            } else {
                InfoBanner(
                    title = "Usage access is required",
                    body = "Allow usage access before confirming opt-in. TesterLoop records daily foreground time for this project.",
                    tone = PillTone.Warn
                )
                Spacer(Modifier.height(10.dp))
                TlSecondaryButton(text = "Allow usage access", onClick = onUsageSettings)
                Spacer(Modifier.height(8.dp))
                Text(
                    "Return here after allowing access, then confirm your opt-in.",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted
                )
            }
        }
        Spacer(Modifier.height(6.dp))
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
            TlTextAction(
                text = "Opt out of this project",
                onClick = onOptOut,
                color = MaterialTheme.colorScheme.error,
                enabled = ui.optInBusyId == null
            )
        }
    }
}

@Composable
internal fun AccessCard(item: MineItem, onPlay: () -> Unit, onInstall: () -> Unit) {
    val active = isActiveCampaign(item.campaignState)
    TlCard {
        SectionHeader("Your access")
        Spacer(Modifier.height(8.dp))
        KeyValueRow("Play link", if (PlayLink.isValid(item.playOptInUrl)) "Ready" else "Waiting for operations")
        Spacer(Modifier.height(12.dp))
        TlSecondaryButton(
            text = "Open Play test",
            onClick = onPlay,
            enabled = PlayLink.isValid(item.playOptInUrl)
        )
        Spacer(Modifier.height(8.dp))
        TlSecondaryButton(
            text = if (active) "Check installed app" else "Project closed",
            onClick = onInstall,
            enabled = active
        )
        Spacer(Modifier.height(6.dp))
        Hairline()
        Spacer(Modifier.height(8.dp))
        Text(
            if (active) {
                "Keep the tested app installed. TesterLoop records an install check every day until the project closes."
            } else {
                "Daily install checks stopped when this project closed. No new checks are recorded."
            },
            style = MaterialTheme.typography.bodySmall,
            color = Muted
        )
    }
}

@Composable
internal fun UsageCard(ui: UiState, item: MineItem, vm: AppVm) {
    val usage = item.usageStatus
    TlCard {
        SectionHeader("Usage tracking")
        Spacer(Modifier.height(8.dp))
        if (usage == null) {
            Text(
                "No usage data yet. Open the tested app, then sync from your profile.",
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        } else {
            KeyValueRow("Installed", if (usage.installed) "Yes" else "No")
            KeyValueRow("Days used", "${usage.distinctDaysUsed} days")
            KeyValueRow("Continuous", "${usage.continuousDaysUsed} of 14 days")
            KeyValueRow("Requirement", if (usage.meetsUsageRequirement) "Met" else "In progress")
            KeyValueRow("Last usage", formatDate(usage.lastUsageAt))
        }
        if (ui.usageAccess) {
            Spacer(Modifier.height(10.dp))
            Text(
                "Foreground time is recorded only for the apps you are testing.",
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        } else {
            Spacer(Modifier.height(12.dp))
            InfoBanner(
                title = "Usage access is off",
                body = "Enable usage access so TesterLoop can record your daily foreground time.",
                tone = PillTone.Warn
            )
            Spacer(Modifier.height(10.dp))
            TlSecondaryButton(text = "Allow usage access", onClick = vm::openUsageSettings)
        }
        Spacer(Modifier.height(8.dp))
        TlSecondaryButton(text = "Sync now", onClick = vm::syncUsageNow)
    }
}
