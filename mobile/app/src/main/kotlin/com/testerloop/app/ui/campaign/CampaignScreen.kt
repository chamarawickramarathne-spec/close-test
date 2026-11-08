package com.testerloop.app.ui.campaign

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import com.testerloop.app.ui.AppVm
import com.testerloop.app.ui.UiState
import com.testerloop.app.ui.checkInstall
import com.testerloop.app.ui.clearReportError
import com.testerloop.app.ui.confirmOptIn
import com.testerloop.app.ui.join
import com.testerloop.app.ui.openPlay
import com.testerloop.app.ui.openUsageSettings
import com.testerloop.app.ui.optOut
import com.testerloop.app.ui.submitReport
import com.testerloop.app.ui.components.EmptyState
import com.testerloop.app.ui.components.ReportRow
import com.testerloop.app.ui.components.SectionHeader
import com.testerloop.app.ui.components.TlButton
import com.testerloop.app.ui.components.TlCard
import com.testerloop.app.ui.components.TlTextAction
import com.testerloop.app.ui.components.TlTopBar
import com.testerloop.app.ui.theme.Bg
import com.testerloop.app.ui.theme.Muted

@Composable
fun CampaignScreen(ui: UiState, campaignId: String, onBack: () -> Unit, vm: AppVm) {
    val mine = ui.mine.firstOrNull { it.campaignId == campaignId }
    val available = ui.available.firstOrNull { it.campaignId == campaignId }
    val appName = mine?.appName ?: available?.appName ?: "Project"
    var showReport by remember { mutableStateOf(false) }
    var reportMark by remember { mutableStateOf(ui.reportSuccess) }
    var confirmOptOut by remember { mutableStateOf(false) }

    BackHandler(enabled = !showReport && !confirmOptOut) {
        vm.closeCampaign()
        onBack()
    }

    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.refreshUsageAccess() }
    LaunchedEffect(campaignId) {
        vm.refreshUsageAccess()
        vm.openCampaign(campaignId)
    }
    LaunchedEffect(ui.reportSuccess) {
        if (showReport && ui.reportSuccess != reportMark) {
            showReport = false
            reportMark = ui.reportSuccess
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(Bg)) {
        TlTopBar(
            title = appName,
            subtitle = mine?.packageName ?: available?.packageName,
            onBack = {
                vm.closeCampaign()
                onBack()
            }
        )

        if (mine == null && available == null) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                if (ui.refreshing) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                } else {
                    EmptyState(
                        title = "Project unavailable",
                        body = "This project is no longer open to you. Refresh the projects list and try again."
                    )
                }
            }
            return@Column
        }

        LazyColumn(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item { CampaignHero(mine = mine, available = available) }

            if (mine == null && available != null) {
                item {
                    TlCard {
                        Text("How joining works", style = MaterialTheme.typography.titleSmall)
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "Join to claim a seat, then confirm that you are a member of the Google Group. Keep the app installed and open it daily for 14 days.",
                            style = MaterialTheme.typography.bodySmall,
                            color = Muted
                        )
                        Spacer(Modifier.height(14.dp))
                        TlButton(
                            text = if (ui.joiningId == campaignId) "Joining" else "Join project",
                            onClick = { vm.join(campaignId) },
                            loading = ui.joiningId == campaignId,
                            enabled = available.seatsFree > 0
                        )
                    }
                }
            }

            if (mine != null) {
                item {
                    OptInCard(
                        ui = ui,
                        item = mine,
                        onConfirm = { vm.confirmOptIn(campaignId) },
                        onOptOut = { confirmOptOut = true },
                        onUsageSettings = vm::openUsageSettings
                    )
                }
                item {
                    AccessCard(
                        item = mine,
                        onPlay = { vm.openPlay(campaignId) },
                        onInstall = { vm.checkInstall(campaignId) }
                    )
                }
                item { UsageCard(ui = ui, item = mine, vm = vm) }

                item {
                    val reports = ui.reports.filter { it.campaignId == campaignId }
                    SectionHeader(
                        title = "Your reports (${reports.size})",
                        trailing = {
                            TlTextAction("File a report", {
                                reportMark = ui.reportSuccess
                                vm.clearReportError()
                                showReport = true
                            })
                        }
                    )
                }
                if (ui.reports.none { it.campaignId == campaignId }) {
                    item {
                        TlCard {
                            EmptyState(
                                title = "No reports yet",
                                body = "Found a crash, a broken flow or a visual bug? File it while the details are fresh."
                            )
                        }
                    }
                } else {
                    items(ui.reports.filter { it.campaignId == campaignId }, key = { it.id }) { report ->
                        TlCard { ReportRow(report) }
                    }
                }
            }
        }
    }

    if (showReport) {
        ReportSheet(
            campaignId = campaignId,
            usage = mine?.usageStatus,
            busy = ui.reportBusy,
            error = ui.reportError,
            onDismiss = { showReport = false; vm.clearReportError() },
            onSubmit = vm::submitReport
        )
    }

    if (confirmOptOut) {
        AlertDialog(
            onDismissRequest = { confirmOptOut = false },
            title = { Text("Opt out of this project?") },
            text = { Text("Your 14-day clock for this project resets to zero. You can rejoin while seats remain.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmOptOut = false
                    vm.optOut(campaignId)
                }) { Text("Opt out") }
            },
            dismissButton = {
                TextButton(onClick = { confirmOptOut = false }) { Text("Stay opted in") }
            }
        )
    }
}
