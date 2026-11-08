package lk.closetester.helper.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import lk.closetester.helper.ui.theme.Bad
import lk.closetester.helper.ui.theme.BadSoft
import lk.closetester.helper.ui.theme.Coral
import lk.closetester.helper.ui.theme.CoralSoft
import lk.closetester.helper.ui.theme.Good
import lk.closetester.helper.ui.theme.GoodSoft
import lk.closetester.helper.ui.theme.Line
import lk.closetester.helper.ui.theme.Muted
import lk.closetester.helper.ui.theme.SurfaceWarm
import lk.closetester.helper.ui.theme.Teal
import lk.closetester.helper.ui.theme.TealSoft
import lk.closetester.helper.ui.theme.Warn
import lk.closetester.helper.ui.theme.WarnSoft

enum class PillTone { Neutral, Teal, Good, Warn, Bad, Coral }

@Composable
fun StatusPill(text: String, tone: PillTone = PillTone.Neutral, modifier: Modifier = Modifier) {
    val (fg, bg) = when (tone) {
        PillTone.Neutral -> Muted to SurfaceWarm
        PillTone.Teal -> Teal to TealSoft
        PillTone.Good -> Good to GoodSoft
        PillTone.Warn -> Warn to WarnSoft
        PillTone.Bad -> Bad to BadSoft
        PillTone.Coral -> Coral to CoralSoft
    }
    Box(
        modifier = modifier
            .background(bg, RoundedCornerShape(50))
            .padding(horizontal = 10.dp, vertical = 5.dp)
    ) {
        Text(text, style = MaterialTheme.typography.labelMedium, color = fg, maxLines = 1)
    }
}

@Composable
fun ProgressTrack(
    progress: Float,
    modifier: Modifier = Modifier,
    color: Color = Teal,
    track: Color = TealSoft,
    height: Dp = 8.dp
) {
    val clamped = progress.coerceIn(0f, 1f)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height)
            .background(track, RoundedCornerShape(50))
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(clamped)
                .height(height)
                .background(color, RoundedCornerShape(50))
        )
    }
}

@Composable
fun Avatar(initials: String, size: Dp = 42.dp, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier.size(size).background(Teal, CircleShape),
        contentAlignment = Alignment.Center
    ) {
        Text(
            initials,
            style = MaterialTheme.typography.titleSmall,
            color = Color.White
        )
    }
}

@Composable
fun MetricTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    hint: String? = null,
    accent: Color = Teal
) {
    Column(
        modifier = modifier
            .background(SurfaceWarm.copy(alpha = 0.6f), RoundedCornerShape(16.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp)
    ) {
        Text(value, style = MaterialTheme.typography.headlineMedium.copy(color = accent), maxLines = 1)
        Spacer(Modifier.height(2.dp))
        Text(label.uppercase(), style = MaterialTheme.typography.labelSmall, color = Muted, maxLines = 1)
        if (hint != null) {
            Spacer(Modifier.height(2.dp))
            Text(hint, style = MaterialTheme.typography.bodySmall, color = Muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
fun KeyValueRow(label: String, value: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth().padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = Muted, modifier = Modifier.weight(1f))
        Text(
            value,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurface,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

@Composable
fun Dot(active: Boolean, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(8.dp)
            .background(if (active) Teal else Line, CircleShape)
    )
}

@Composable
fun InfoBanner(
    title: String,
    body: String,
    modifier: Modifier = Modifier,
    tone: PillTone = PillTone.Teal
) {
    val bg = when (tone) {
        PillTone.Teal -> TealSoft
        PillTone.Good -> GoodSoft
        PillTone.Warn -> WarnSoft
        PillTone.Bad -> BadSoft
        PillTone.Coral -> CoralSoft
        PillTone.Neutral -> SurfaceWarm
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(bg, RoundedCornerShape(16.dp))
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurface)
        Text(body, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.72f))
    }
}
