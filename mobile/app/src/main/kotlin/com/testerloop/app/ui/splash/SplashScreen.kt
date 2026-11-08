package com.testerloop.app.ui.splash

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.unit.dp
import com.testerloop.app.ui.components.BrandMark
import com.testerloop.app.ui.theme.Bg
import com.testerloop.app.ui.theme.Muted
import com.testerloop.app.ui.theme.Teal

@Composable
fun SplashScreen() {
    BackHandler(enabled = true) { }

    val transition = rememberInfiniteTransition(label = "splash")
    val alpha by transition.animateFloat(
        initialValue = 0.55f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "alpha"
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Bg)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        BrandMark(size = 76.dp)
        Spacer(Modifier.height(22.dp))
        Text("TesterLoop", style = MaterialTheme.typography.displaySmall)
        Spacer(Modifier.height(6.dp))
        Text(
            "Closed testing, in one loop.",
            style = MaterialTheme.typography.bodyMedium,
            color = Muted
        )
        Spacer(Modifier.height(36.dp))
        CircularProgressIndicator(
            modifier = Modifier.alpha(alpha),
            color = Teal,
            strokeWidth = 2.5.dp
        )
        Spacer(Modifier.height(14.dp))
        Text("Checking your session", style = MaterialTheme.typography.bodySmall, color = Muted)
    }
}
