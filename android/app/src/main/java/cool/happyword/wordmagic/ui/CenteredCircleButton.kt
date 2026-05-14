package cool.happyword.wordmagic.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonColors
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ButtonElevation
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp

/** Single-line glyph: removes Android font padding so symbols center like HarmonyOS. */
fun circleGlyphTextStyle(fontSize: TextUnit, fontWeight: FontWeight = FontWeight.Normal): TextStyle = TextStyle(
    fontSize = fontSize,
    lineHeight = fontSize,
    fontWeight = fontWeight,
    textAlign = TextAlign.Center,
    platformStyle = PlatformTextStyle(includeFontPadding = false),
)

/**
 * Circular [Button] with no content padding and glyph text centered in the circle.
 * Use for stepper −/+, emoji chips, and other single-glyph circle controls (not page back — use [HarmonyPageTopBackButton]).
 */
@Composable
fun CenteredCircleTextButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp,
    enabled: Boolean = true,
    fontSize: TextUnit,
    fontWeight: FontWeight = FontWeight.Bold,
    colors: ButtonColors,
    elevation: ButtonElevation = ButtonDefaults.buttonElevation(
        defaultElevation = 0.dp,
        pressedElevation = 0.dp,
        disabledElevation = 0.dp,
        hoveredElevation = 0.dp,
        focusedElevation = 0.dp,
    ),
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.size(size),
        shape = CircleShape,
        contentPadding = PaddingValues(0.dp),
        colors = colors,
        elevation = elevation,
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Text(text = text, style = circleGlyphTextStyle(fontSize, fontWeight))
        }
    }
}

/**
 * Circular icon button — use for back arrows where [Text] glyphs look optically off-center vs HarmonyOS.
 */
@Composable
fun CenteredCircleIconButton(
    imageVector: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Dp,
    iconSize: Dp,
    enabled: Boolean = true,
    colors: ButtonColors,
    elevation: ButtonElevation = ButtonDefaults.buttonElevation(
        defaultElevation = 0.dp,
        pressedElevation = 0.dp,
        disabledElevation = 0.dp,
        hoveredElevation = 0.dp,
        focusedElevation = 0.dp,
    ),
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.size(size),
        shape = CircleShape,
        contentPadding = PaddingValues(0.dp),
        colors = colors,
        elevation = elevation,
    ) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = imageVector,
                contentDescription = contentDescription,
                modifier = Modifier.size(iconSize),
                tint = LocalContentColor.current,
            )
        }
    }
}

/** Page chrome back control — same look as Monster Codex (48dp circle, white fill, navy arrow). */
@Composable
fun HarmonyPageTopBackButton(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    size: Dp = 48.dp,
    iconSize: Dp = 28.dp,
    colors: ButtonColors = ButtonDefaults.buttonColors(
        containerColor = Color.White,
        contentColor = Color(0xFF0B3B63),
    ),
    contentDescription: String? = "Back",
) {
    CenteredCircleIconButton(
        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
        contentDescription = contentDescription,
        onClick = onClick,
        modifier = modifier,
        size = size,
        iconSize = iconSize,
        enabled = enabled,
        colors = colors,
    )
}
