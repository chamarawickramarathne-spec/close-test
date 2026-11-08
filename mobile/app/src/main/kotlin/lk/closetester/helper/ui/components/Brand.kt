package lk.closetester.helper.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import lk.closetester.helper.ui.theme.Coral
import lk.closetester.helper.ui.theme.Ink
import lk.closetester.helper.ui.theme.Teal
import lk.closetester.helper.ui.theme.TealDeep

@Composable
fun BrandMark(size: Dp = 34.dp) {
    Canvas(modifier = Modifier.size(size)) {
        val s = this.size.minDimension
        val corner = s * 0.3f
        drawRoundRect(
            brush = Brush.linearGradient(listOf(Teal, TealDeep)),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(corner, corner)
        )
        val stroke = s * 0.11f
        val r = s * 0.24f
        val c = Offset(this.size.width / 2f, this.size.height / 2f)
        val loop = Path().apply {
            addOval(androidx.compose.ui.geometry.Rect(center = c, radius = r))
        }
        drawPath(loop, color = Color.White, style = Stroke(width = stroke, cap = StrokeCap.Round))
        drawCircle(color = Coral, radius = s * 0.075f, center = Offset(c.x + r * 0.95f, c.y - r * 0.95f))
    }
}

@Composable
fun BrandWordmark(modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        BrandMark()
        Text(
            text = "TesterLoop",
            style = MaterialTheme.typography.titleLarge.copy(
                fontWeight = FontWeight.ExtraBold,
                fontSize = 18.sp,
                color = Ink
            )
        )
    }
}
