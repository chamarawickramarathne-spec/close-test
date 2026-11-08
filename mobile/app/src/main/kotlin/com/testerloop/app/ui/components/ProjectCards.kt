package com.testerloop.app.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowForward
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.testerloop.app.core.formatDate
import com.testerloop.app.core.humanState
import com.testerloop.app.data.api.AvailableItem
import com.testerloop.app.data.api.MineItem
import com.testerloop.app.data.api.ReportItem
import com.testerloop.app.data.api.UsageStatus
import com.testerloop.app.ui.theme.Muted
import com.testerloop.app.ui.theme.Teal

@Composable
fun JoinedProjectCard(
    item: MineItem,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    TlCard(modifier = modifier, onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    item.appName ?: "Untitled project",
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    item.packageName ?: "Package not set",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            Spacer(Modifier.width(10.dp))
            StatusPill(humanState(item.state), stateTone(item.state))
        }
        Spacer(Modifier.height(14.dp))
        ProgressTrack(progress = item.days / 14f, color = Teal)
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "${item.days} of 14 days",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurface
            )
            Spacer(Modifier.weight(1f))
            Text(
                if (item.optInVerification == "google_group") "Verified" else "Confirm opt-in",
                style = MaterialTheme.typography.bodySmall,
                color = if (item.optInVerification == "google_group") Teal else Muted
            )
            Icon(
                Icons.Rounded.ArrowForward,
                contentDescription = null,
                tint = Muted,
                modifier = Modifier.size(16.dp)
            )
        }
    }
}

@Composable
fun OpenProjectCard(
    item: AvailableItem,
    joining: Boolean,
    onJoin: () -> Unit,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    TlCard(modifier = modifier, onClick = onClick) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    item.appName ?: "Untitled project",
                    style = MaterialTheme.typography.titleMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                Spacer(Modifier.height(2.dp))
                Text(
                    item.packageName ?: "Package not set",
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
            StatusPill("${item.seatsFree} seats", PillTone.Teal)
        }
        Spacer(Modifier.height(12.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Needs ${item.requiredTesters} testers for 14 days",
                style = MaterialTheme.typography.bodySmall,
                color = Muted,
                modifier = Modifier.weight(1f)
            )
            if (joining) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = Teal
                )
                Spacer(Modifier.width(8.dp))
            }
        }
        Spacer(Modifier.height(10.dp))
        TlButton(
            text = if (joining) "Joining" else "Join project",
            onClick = onJoin,
            loading = joining,
            enabled = item.seatsFree > 0
        )
    }
}

@Composable
fun ReportRow(report: ReportItem, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        StatusPill(
            (report.severity ?: "minor").replaceFirstChar { it.uppercase() },
            when (report.severity) {
                "blocker" -> PillTone.Bad
                "major" -> PillTone.Warn
                "cosmetic" -> PillTone.Neutral
                else -> PillTone.Coral
            }
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(
                report.title ?: "Report",
                style = MaterialTheme.typography.titleSmall,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                listOfNotNull(report.appName, formatDate(report.createdAt)).joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = Muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                reportUsageLabel(report.usage),
                style = MaterialTheme.typography.bodySmall,
                color = Muted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            reportInstallLabel(report)?.let { label ->
                Text(
                    label,
                    style = MaterialTheme.typography.bodySmall,
                    color = Muted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
        StatusPill(humanState(report.status), if (report.status == "resolved") PillTone.Good else PillTone.Neutral)
    }
}

private fun reportUsageLabel(usage: UsageStatus?): String = when {
    usage == null -> "Usage not captured"
    !usage.available -> "Usage not reported"
    usage.installed -> "Installed · ${usage.continuousDaysUsed} of 14 days"
    else -> "Not installed · ${usage.continuousDaysUsed} of 14 days"
}

private fun reportInstallLabel(report: ReportItem): String? {
    if (report.installHistory.isEmpty()) return null
    val checked = report.installHistory.count { it.checked }
    if (checked == 0) return "Install checks: none recorded"
    val installed = report.installHistory.count { it.checked && it.installed == true }
    return "Install checks: $installed of $checked days installed"
}

fun stateTone(state: String?): PillTone = when (state?.lowercase()) {
    "live" -> PillTone.Good
    "at_risk" -> PillTone.Warn
    "passed" -> PillTone.Teal
    "cancelled" -> PillTone.Bad
    "awaiting_link", "pending" -> PillTone.Coral
    else -> PillTone.Neutral
}
