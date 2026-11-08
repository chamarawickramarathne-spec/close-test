package com.testerloop.app

import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.testerloop.app.core.AppUpdater
import com.testerloop.app.ui.AppVm
import com.testerloop.app.ui.CampaignRoute
import com.testerloop.app.ui.Phase
import com.testerloop.app.ui.ShellScreen
import com.testerloop.app.ui.UiEvent
import com.testerloop.app.ui.auth.AuthScreen
import com.testerloop.app.ui.splash.SplashScreen
import com.testerloop.app.ui.theme.TesterLoopTheme
import com.testerloop.app.worker.UsageReader
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.launch

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
        )
        setContent {
            TesterLoopTheme {
                TesterLoopRoot(vm = hiltViewModel())
            }
        }
    }
}

@Composable
fun TesterLoopRoot(vm: AppVm) {
    val ui by vm.ui.collectAsStateWithLifecycle()
    val navController = rememberNavController()
    val snackbar = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current

    LaunchedEffect(Unit) {
        vm.events.collect { event ->
            when (event) {
                is UiEvent.OpenUrl -> {
                    val uri = Uri.parse(event.url)
                    val allowed = uri.scheme == "https" &&
                        (uri.host == "play.google.com" || uri.host == "groups.google.com")
                    if (allowed) {
                        runCatching {
                            context.startActivity(
                                Intent(Intent.ACTION_VIEW, uri)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            )
                        }.onFailure {
                            scope.launch { snackbar.showSnackbar("No browser is available for that link.") }
                        }
                    } else {
                        scope.launch { snackbar.showSnackbar("That link cannot be opened.") }
                    }
                }
                is UiEvent.Message -> scope.launch { snackbar.showSnackbar(event.text) }
                UiEvent.OpenUsageSettings -> runCatching {
                    context.startActivity(UsageReader.usageAccessIntent())
                }.onFailure {
                    scope.launch { snackbar.showSnackbar("Usage settings are not available on this device.") }
                }
                UiEvent.OpenInstallPermission -> runCatching {
                    context.startActivity(AppUpdater.installPermissionIntent(context))
                }.onFailure {
                    scope.launch {
                        snackbar.showSnackbar("Install permission settings are not available on this device.")
                    }
                }
                UiEvent.CloseCampaign -> navController.popBackStack()
            }
        }
    }

    LaunchedEffect(ui.phase) {
        when (ui.phase) {
            Phase.Auth -> navController.navigate("auth") {
                popUpTo(navController.graph.id) { inclusive = true }
                launchSingleTop = true
            }
            Phase.Ready -> navController.navigate("shell") {
                popUpTo(navController.graph.id) { inclusive = true }
                launchSingleTop = true
            }
            Phase.Splash -> Unit
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbar, modifier = Modifier.navigationBarsPadding()) },
        contentWindowInsets = WindowInsets(0, 0, 0, 0)
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = "splash",
            modifier = Modifier.fillMaxSize().padding(padding)
        ) {
            composable("splash") { SplashScreen() }
            composable("auth") { AuthScreen(ui = ui, vm = vm) }
            composable("shell") {
                ShellScreen(ui = ui, vm = vm, onProject = { id ->
                    navController.navigate("campaign/$id")
                })
            }
            composable("campaign/{id}") { entry ->
                val id = entry.arguments?.getString("id").orEmpty()
                CampaignRoute(ui = ui, campaignId = id, onBack = { navController.popBackStack() }, vm = vm)
            }
        }
    }
}

