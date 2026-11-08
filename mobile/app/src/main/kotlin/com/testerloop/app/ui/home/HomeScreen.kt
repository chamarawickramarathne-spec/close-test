package com.testerloop.app.ui.home

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowForward
import androidx.compose.material.icons.rounded.CheckCircleOutline
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.testerloop.app.core.firstNameOf
import com.testerloop.app.core.initialsOf
import com.testerloop.app.core.projectClock
import com.testerloop.app.ui.UiState
import com.testerloop.app.ui.components.Avatar
import com.testerloop.app.ui.components.EmptyState
import com.testerloop.app.ui.components.Hairline
import com.testerloop.app.ui.components.InfoBanner
import com.testerloop.app.ui.components.JoinedProjectCard
import com.testerloop.app.ui.components.MetricTile
import com.testerloop.app.ui.components.PillTone
import com.testerloop.app.ui.components.ProgressTrack
import com.testerloop.app.ui.components.ReportRow
import com.testerloop.app.ui.components.SectionHeader
import com.testerloop.app.ui.components.TlButton
import com.testerloop.app.ui.components.TlCard
import com.testerloop.app.ui.components.TlTextAction
import com.testerloop.app.ui.theme.Muted
import com.testerloop.app.ui.theme.TealSoft
import com.testerloop.app.ui.theme.TealDeep
import com.testerloop.app.ui.theme.White
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun HomeScreen(
    ui: UiState,
    onProject: (String) -> Unit,
    onBrowse: () -> Unit,
    onProfile: () -> Unit,
    onRefresh: () -> Unit,
    onDismissError: () -> Unit
) {
    val name = firstNameOf(ui.tester?.displayName)
    val clocks = ui.mine.map { it.projectClock() }
    val bestDays = clocks.maxOfOrNull { it.days } ?: 0
    val anyClockStarted = clocks.any { it.started }
    val today = SimpleDateFormat("EEEE d MMMM", Locale.getDefault()).format(Date())
    val needsOptIn = ui.mine.filter { it.state == "joined" || it.optInVerification != "google_group" }
    val attentionCount = needsOptIn.size + if (!ui.usageAccess && ui.mine.isNotEmpty()) 1 else 0

    LazyColumn(
        modifier = Modifier.fillMaxWidth().statusBarsPadding(),
        contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(today.uppercase(), style = MaterialTheme.typography.labelMedium, color = Muted)
                    Spacer(Modifier.height(4.dp))
                    Text(
                        if (name.isBlank()) "Hello, tester" else "Hello, $name",
                        style = MaterialTheme.typography.headlineMedium
                    )
                }
                IconButton(onClick = onRefresh) {
                    if (ui.refreshing) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Rounded.Refresh, contentDescription = "Refresh", tint = Muted)
                    }
                }
                Avatar(initialsOf(ui.tester?.displayName), size = 42.dp)
            }
        }

        item {
            Surface(
                shape = RoundedCornerShape(24.dp),
                color = TealDeep,
                modifier = Modifier.fillMaxWidth()
            ) {
                Column(modifier = Modifier.padding(20.dp)) {
                    Text(
                        "LONGEST PROJECT CLOCK",
                        style = MaterialTheme.typography.labelMedium,
                        color = White.copy(alpha = 0.66f)
                    )
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.Bottom) {
                        Text(
                            "$bestDays",
                            style = MaterialTheme.typography.displaySmall.copy(fontSize = MaterialTheme.typography.displaySmall.fontSize * 1.4f),
                            color = White
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(
                            "of 14 days",
                            style = MaterialTheme.typography.titleMedium,
                            color = White.copy(alpha = 0.8f),
                            modifier = Modifier.padding(bottom = 6.dp)
                        )
                    }
                    Spacer(Modifier.height(14.dp))
                    ProgressTrack(
                        progress = bestDays / 14f,
                        track = White.copy(alpha = 0.18f),
                        color = White
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        when {
                            ui.mine.isEmpty() -> "Join a project to start your first project clock."
                            !anyClockStarted -> "The 14-day clock starts when 12 testers have confirmed opt-in."
                            else -> "Each project needs 12 testers opted in for 14 continuous days."
                        },
                        style = MaterialTheme.typography.bodySmall,
                        color = White.copy(alpha = 0.78f)
                    )
                }
            }
        }

        if (!ui.loadError.isNullOrBlank()) {
            item {
                Column {
                    InfoBanner("Couldn't refresh", ui.loadError, tone = PillTone.Bad)
                    TlTextAction("Dismiss", onDismissError)
                }
            }
        }

        item {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                MetricTile("Joined", ui.mine.size.toString(), Modifier.weight(1f))
                MetricTile("Open", ui.available.size.toString(), Modifier.weight(1f), accent = MaterialTheme.colorScheme.secondary)
                MetricTile("Reports", ui.reports.size.toString(), Modifier.weight(1f), accent = TealDeep)
            }
        }

        if (attentionCount > 0) {
            item {
                TlCard {
                    SectionHeader("Needs attention")
                    Spacer(Modifier.height(10.dp))
                    if (!ui.usageAccess && ui.mine.isNotEmpty()) {
                        AttentionRow(
                            title = "Allow usage access",
                            body = "TesterLoop records daily foreground time for joined projects.",
                            onClick = onProfile
                        )
                    }
                    needsOptIn.take(3).forEach { item ->
                        AttentionRow(
                            title = item.appName ?: "Project",
                            body = if (item.state == "joined") "Confirm your Google Group opt-in." else "Verify your Google Group membership.",
                            onClick = { onProject(item.campaignId) }
                        )
                    }
                }
            }
        }

        item {
            SectionHeader(
                title = "Active projects",
                trailing = if (ui.mine.isNotEmpty()) {
                    { TlTextAction("View all", onBrowse) }
                } else null
            )
        }

        if (ui.loading) {
            item {
                Box(modifier = Modifier.fillMaxWidth().padding(vertical = 28.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                }
            }
        } else if (ui.mine.isEmpty()) {
            item {
                TlCard {
                    EmptyState(
                        title = "No projects yet",
                        body = "Browse open closed tests and join with one tap.",
                        icon = { Icon(Icons.Rounded.CheckCircleOutline, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
                    )
                    TlButton("Browse open projects", onClick = onBrowse)
                }
            }
        } else {
            items(ui.mine.take(4), key = { it.campaignId }) { item ->
                JoinedProjectCard(item = item, onClick = { onProject(item.campaignId) })
            }
        }

        if (ui.reports.isNotEmpty()) {
            item {
                SectionHeader(title = "Recent reports")
            }
            item {
                TlCard {
                    ui.reports.take(3).forEachIndexed { index, report ->
                        if (index > 0) {
                            Spacer(Modifier.height(10.dp))
                            Hairline()
                            Spacer(Modifier.height(10.dp))
                        }
                        ReportRow(report)
                    }
                }
            }
        }

        if (ui.mine.isNotEmpty()) {
            item {
                TlCard(color = TealSoft) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Rounded.ArrowForward, contentDescription = null, tint = Color(0xFF115E59))
                        Spacer(Modifier.width(10.dp))
                        Text(
                            "Keep the app installed and open it daily for your usage checks.",
                            style = MaterialTheme.typography.bodySmall,
                            color = Color(0xFF115E59)
                        )
                    }
                }
            }
        }

    }
}

@Composable
private fun AttentionRow(title: String, body: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(body, style = MaterialTheme.typography.bodySmall, color = Muted)
        }
        Spacer(Modifier.width(8.dp))
        TlTextAction("Open", onClick)
    }
}

