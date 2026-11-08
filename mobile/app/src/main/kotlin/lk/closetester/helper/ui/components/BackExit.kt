package lk.closetester.helper.ui.components

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.SystemClock
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext

@Composable
fun BackExitHandler(enabled: Boolean = true, onHint: () -> Unit) {
    val context = LocalContext.current
    var lastBack by remember { mutableLongStateOf(0L) }

    LaunchedEffect(enabled) {
        if (!enabled) lastBack = 0L
    }

    BackHandler(enabled = enabled) {
        val now = SystemClock.elapsedRealtime()
        if (lastBack != 0L && now - lastBack <= 2000L) {
            context.findActivity()?.finish()
        } else {
            lastBack = now
            onHint()
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
