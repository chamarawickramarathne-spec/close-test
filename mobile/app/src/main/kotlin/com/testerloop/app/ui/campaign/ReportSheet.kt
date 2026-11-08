package com.testerloop.app.ui.campaign

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.testerloop.app.data.api.UsageStatus
import com.testerloop.app.ui.components.FormError
import com.testerloop.app.ui.components.Hairline
import com.testerloop.app.ui.components.SectionHeader
import com.testerloop.app.ui.components.TlButton
import com.testerloop.app.ui.components.TlCard
import com.testerloop.app.ui.components.TlField
import com.testerloop.app.ui.components.TlTextAction
import com.testerloop.app.ui.theme.Coral
import com.testerloop.app.ui.theme.CoralSoft
import com.testerloop.app.ui.theme.Ink
import com.testerloop.app.ui.theme.Line
import com.testerloop.app.ui.theme.Muted

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ReportSheet(
    campaignId: String,
    usage: UsageStatus?,
    buildLabel: String?,
    busy: Boolean,
    error: String?,
    onDismiss: () -> Unit,
    onSubmit: (campaignId: String, severity: String, title: String, body: String) -> Unit
) {
    var severity by rememberSaveable { mutableStateOf("minor") }
    var title by rememberSaveable { mutableStateOf("") }
    var body by rememberSaveable { mutableStateOf("") }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .navigationBarsPadding()
                .padding(start = 20.dp, end = 20.dp, bottom = 24.dp)
        ) {
            Text("FILE A REPORT", style = MaterialTheme.typography.labelMedium, color = Muted)
            Spacer(Modifier.height(4.dp))
            Text("Tell operations what broke.", style = MaterialTheme.typography.headlineMedium)
            Spacer(Modifier.height(18.dp))

            Text("SEVERITY", style = MaterialTheme.typography.labelSmall, color = Muted)
            Spacer(Modifier.height(8.dp))
            val options = listOf(
                "minor" to "Minor",
                "major" to "Major",
                "blocker" to "Blocker",
                "cosmetic" to "Cosmetic"
            )
            options.chunked(2).forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    row.forEach { (value, label) ->
                        SeverityPill(
                            label = label,
                            selected = severity == value,
                            modifier = Modifier.weight(1f),
                            onClick = { severity = value }
                        )
                    }
                }
                Spacer(Modifier.height(8.dp))
            }

            ReportUsagePreview(usage)

            Spacer(Modifier.height(10.dp))
            TlField(
                value = title,
                onValueChange = { title = it },
                label = "Title",
                placeholder = "Crash when opening settings",
                enabled = !busy
            )
            Spacer(Modifier.height(14.dp))
            TlField(
                value = body,
                onValueChange = { body = it },
                label = "What happened",
                placeholder = "Steps, expected result and what you saw.",
                singleLine = false,
                minLines = 4,
                enabled = !busy
            )
            Spacer(Modifier.height(14.dp))
            ReportBuildLabel(buildLabel)

            FormError(error, modifier = Modifier.padding(top = 10.dp))

            Spacer(Modifier.height(18.dp))
            TlButton(
                text = "File report",
                onClick = { onSubmit(campaignId, severity, title, body) },
                loading = busy
            )
            Spacer(Modifier.height(6.dp))
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center) {
                TlTextAction("Cancel", onDismiss, enabled = !busy)
            }
            Spacer(Modifier.height(8.dp))
            Hairline()
            Spacer(Modifier.height(10.dp))
            Text(
                "Your device model, usage summary and daily install checks since you joined are attached automatically. Reports are visible to operations only.",
                style = MaterialTheme.typography.bodySmall,
                color = Muted
            )
        }
    }
}

@Composable
private fun ReportBuildLabel(buildLabel: String?) {
    TlCard {
        SectionHeader("Build version")
        Spacer(Modifier.height(6.dp))
        Text(
            buildLabel ?: "App not installed on this device",
            style = MaterialTheme.typography.bodyMedium,
            color = Ink
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "Read from the installed app automatically. You do not need to enter it.",
            style = MaterialTheme.typography.bodySmall,
            color = Muted
        )
    }
}

@Composable
private fun ReportUsagePreview(usage: UsageStatus?) {
    TlCard {
        SectionHeader("Attached with this report")
        Spacer(Modifier.height(6.dp))
        Text(
            when {
                usage == null -> "Usage was not captured for this report."
                !usage.available -> "No install or usage data was reported for this project yet."
                usage.installed -> "Installed · ${usage.continuousDaysUsed} of 14 continuous days"
                else -> "Not installed · ${usage.continuousDaysUsed} of 14 continuous days"
            },
            style = MaterialTheme.typography.bodySmall,
            color = Ink
        )
        Spacer(Modifier.height(4.dp))
        Text(
            "This preview is saved with the report for operations. Install checks from your join date are saved with your reports automatically.",
            style = MaterialTheme.typography.bodySmall,
            color = Muted
        )
    }
}

@Composable
private fun SeverityPill(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Surface(
        onClick = onClick,
        modifier = modifier.height(42.dp),
        shape = RoundedCornerShape(12.dp),
        color = if (selected) CoralSoft else MaterialTheme.colorScheme.surface,
        border = BorderStroke(1.dp, if (selected) Coral else Line)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                label,
                style = MaterialTheme.typography.titleSmall,
                color = if (selected) Coral else Ink
            )
        }
    }
}
