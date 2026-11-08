package lk.closetester.helper.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.PersonOutline
import androidx.compose.material.icons.rounded.Work
import androidx.compose.material.icons.rounded.WorkOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.activity.compose.BackHandler
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import lk.closetester.helper.ui.campaign.CampaignScreen
import lk.closetester.helper.ui.components.BackExitHandler
import lk.closetester.helper.ui.components.Hairline
import lk.closetester.helper.ui.home.HomeScreen
import lk.closetester.helper.ui.profile.ProfileScreen
import lk.closetester.helper.ui.projects.ProjectsScreen
import lk.closetester.helper.ui.theme.Bg
import lk.closetester.helper.ui.theme.Muted
import lk.closetester.helper.ui.theme.Teal
import lk.closetester.helper.ui.theme.TealSoft

@Composable
fun ShellScreen(ui: UiState, vm: AppVm, onProject: (String) -> Unit) {
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { vm.refreshUsageAccess() }
    BackHandler(enabled = ui.tab != 0) { vm.setTab(0) }
    BackExitHandler(enabled = ui.tab == 0) { vm.message("Press back again to exit") }

    Column(modifier = Modifier.fillMaxSize().background(Bg)) {
        Box(modifier = Modifier.weight(1f)) {
            when (ui.tab) {
                0 -> HomeScreen(
                    ui = ui,
                    onProject = onProject,
                    onBrowse = { vm.setTab(1) },
                    onProfile = { vm.setTab(2) },
                    onRefresh = vm::refresh,
                    onDismissError = vm::dismissLoadError
                )
                1 -> ProjectsScreen(
                    ui = ui,
                    onProject = onProject,
                    onJoin = vm::join,
                    onTab = vm::setProjectsTab,
                    onRefresh = vm::refresh
                )
                else -> ProfileScreen(ui = ui, vm = vm)
            }
        }
        TlBottomBar(selected = ui.tab, onSelect = { vm.setTab(it) })
    }
}

@Composable
fun CampaignRoute(ui: UiState, campaignId: String, onBack: () -> Unit, vm: AppVm) {
    CampaignScreen(ui = ui, campaignId = campaignId, onBack = onBack, vm = vm)
}

private data class TabItem(
    val label: String,
    val icon: ImageVector,
    val selectedIcon: ImageVector
)

private val tabs = listOf(
    TabItem("Home", Icons.Rounded.Home, Icons.Rounded.Home),
    TabItem("Projects", Icons.Rounded.WorkOutline, Icons.Rounded.Work),
    TabItem("Profile", Icons.Rounded.PersonOutline, Icons.Rounded.Person)
)

@Composable
private fun TlBottomBar(selected: Int, onSelect: (Int) -> Unit) {
    Surface(color = MaterialTheme.colorScheme.surface) {
        Column {
            Hairline()
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 10.dp, vertical = 6.dp)
            ) {
                tabs.forEachIndexed { index, item ->
                    val active = index == selected
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(16.dp))
                            .clickable { onSelect(index) }
                            .padding(vertical = 6.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Box(
                            modifier = Modifier
                                .size(34.dp)
                                .background(if (active) TealSoft else MaterialTheme.colorScheme.surface, CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = if (active) item.selectedIcon else item.icon,
                                contentDescription = item.label,
                                tint = if (active) Teal else Muted,
                                modifier = Modifier.size(21.dp)
                            )
                        }
                        Spacer(Modifier.height(3.dp))
                        Text(
                            item.label,
                            style = MaterialTheme.typography.labelSmall,
                            color = if (active) Teal else Muted
                        )
                    }
                }
            }
        }
    }
}
