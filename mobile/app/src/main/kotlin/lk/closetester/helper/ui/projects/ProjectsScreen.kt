package lk.closetester.helper.ui.projects

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.WorkOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import lk.closetester.helper.ui.UiState
import lk.closetester.helper.ui.join
import lk.closetester.helper.ui.components.EmptyState
import lk.closetester.helper.ui.components.JoinedProjectCard
import lk.closetester.helper.ui.components.OpenProjectCard
import lk.closetester.helper.ui.components.SegmentedTabs
import lk.closetester.helper.ui.components.TlCard
import lk.closetester.helper.ui.components.TlTextAction
import lk.closetester.helper.ui.theme.Muted

@Composable
fun ProjectsScreen(
    ui: UiState,
    onProject: (String) -> Unit,
    onJoin: (String) -> Unit,
    onTab: (Int) -> Unit,
    onRefresh: () -> Unit
) {
    Column(modifier = Modifier.fillMaxWidth().statusBarsPadding()) {
        Row(
            modifier = Modifier.padding(start = 20.dp, end = 8.dp, top = 12.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("PROJECTS", style = MaterialTheme.typography.labelMedium, color = Muted)
                Spacer(Modifier.height(4.dp))
                Text("Your closed tests.", style = MaterialTheme.typography.headlineMedium)
            }
            IconButton(onClick = onRefresh) {
                if (ui.refreshing) {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                } else {
                    Icon(Icons.Rounded.Refresh, contentDescription = "Refresh", tint = Muted)
                }
            }
        }

        SegmentedTabs(
            options = listOf("Joined (${ui.mine.size})", "Open (${ui.available.size})"),
            selected = ui.projectsTab,
            onSelect = onTab,
            modifier = Modifier.padding(horizontal = 20.dp)
        )
        Spacer(Modifier.height(14.dp))

        LazyColumn(
            modifier = Modifier.fillMaxWidth(),
            contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (ui.loading) {
                item {
                    Box(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
                    }
                }
            } else if (ui.projectsTab == 0) {
                if (ui.mine.isEmpty()) {
                    item {
                        TlCard {
                            EmptyState(
                                title = "Nothing joined yet",
                                body = "Open projects are free to join. Each one needs 12 testers for 14 days.",
                                icon = { Icon(Icons.Rounded.WorkOutline, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
                            )
                            TlTextAction("See open projects", { onTab(1) })
                        }
                    }
                } else {
                    items(ui.mine, key = { it.campaignId }) { item ->
                        JoinedProjectCard(item = item, onClick = { onProject(item.campaignId) })
                    }
                }
            } else {
                if (ui.available.isEmpty()) {
                    item {
                        TlCard {
                            EmptyState(
                                title = "No open projects",
                                body = "New closed tests appear here as developers launch them. Pull refresh later.",
                                icon = { Icon(Icons.Rounded.WorkOutline, contentDescription = null, tint = MaterialTheme.colorScheme.primary) }
                            )
                        }
                    }
                } else {
                    items(ui.available, key = { it.campaignId }) { item ->
                        OpenProjectCard(
                            item = item,
                            joining = ui.joiningId == item.campaignId,
                            onJoin = { onJoin(item.campaignId) },
                            onClick = { onProject(item.campaignId) }
                        )
                    }
                }
            }
        }
    }
}


