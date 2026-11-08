package com.testerloop.app.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp

private val TlColors = lightColorScheme(
    primary = Teal,
    onPrimary = White,
    primaryContainer = TealSoft,
    onPrimaryContainer = TealDeep,
    secondary = Coral,
    onSecondary = White,
    secondaryContainer = CoralSoft,
    onSecondaryContainer = Coral,
    background = Bg,
    onBackground = Ink,
    surface = Surface,
    onSurface = Ink,
    surfaceVariant = SurfaceWarm,
    onSurfaceVariant = InkSoft,
    outline = Line,
    outlineVariant = Line,
    error = Bad,
    onError = White,
    errorContainer = BadSoft,
    onErrorContainer = Bad
)

private val TlShapes = Shapes(
    extraSmall = RoundedCornerShape(10.dp),
    small = RoundedCornerShape(12.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp)
)

@Composable
fun TesterLoopTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = TlColors,
        typography = TlType,
        shapes = TlShapes,
        content = content
    )
}
