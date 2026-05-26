package cool.happyword.wordmagic.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

@Stable
data class MessageBubblePoint(val x: Float, val y: Float)

@Stable
data class MessageBubbleTail(
    val baseStart: MessageBubblePoint,
    val baseEnd: MessageBubblePoint,
    val tip: MessageBubblePoint,
)

@Stable
data class MessageBubbleBox(
    val width: Float,
    val height: Float,
    val borderWidth: Float,
    val tailBase: Float,
    val tailLength: Float,
    val inset: Float,
    val tipInset: Float = 0f,
)

@Stable
data class MessageBubbleFrame(
    val width: Float,
    val height: Float,
    val offsetX: Float,
    val offsetY: Float,
)

@Stable
data class MessageBubbleShadow(
    val radius: Dp = 0.dp,
    val color: Color = Color.Transparent,
    val offsetX: Dp = 0.dp,
    val offsetY: Dp = 0.dp,
)

enum class MessageBubbleTailPreset {
    TopLeft,
    TopMiddle,
    TopRight,
    BottomLeft,
    BottomMiddle,
    BottomRight,
    LeftTop,
    LeftMiddle,
    LeftBottom,
    RightTop,
    RightMiddle,
    RightBottom,
}

private enum class MessageBubbleTailSide {
    Top,
    Right,
    Bottom,
    Left,
}

private data class MessageBubbleShadowPadding(val x: Float, val y: Float)

private data class MessageBubbleShadowLayer(
    val offsetX: Dp,
    val offsetY: Dp,
    val opacity: Float,
)

fun messageBubbleFrame(width: Float, height: Float, tail: MessageBubbleTail?): MessageBubbleFrame {
    if (tail == null) {
        return MessageBubbleFrame(width = width, height = height, offsetX = 0f, offsetY = 0f)
    }
    val minX = min(0f, min(tail.baseStart.x, min(tail.baseEnd.x, tail.tip.x)))
    val minY = min(0f, min(tail.baseStart.y, min(tail.baseEnd.y, tail.tip.y)))
    val maxX = max(width, max(tail.baseStart.x, max(tail.baseEnd.x, tail.tip.x)))
    val maxY = max(height, max(tail.baseStart.y, max(tail.baseEnd.y, tail.tip.y)))
    return MessageBubbleFrame(
        width = maxX - minX,
        height = maxY - minY,
        offsetX = if (minX == 0f) 0f else -minX,
        offsetY = if (minY == 0f) 0f else -minY,
    )
}

fun buildMessageBubbleTailPreset(
    preset: MessageBubbleTailPreset,
    box: MessageBubbleBox,
): MessageBubbleTail {
    if (preset.name.startsWith("Top")) {
        val startX = horizontalBaseStart(preset, box)
        return MessageBubbleTail(
            baseStart = MessageBubblePoint(startX, 0f),
            baseEnd = MessageBubblePoint(startX + box.tailBase, 0f),
            tip = MessageBubblePoint(horizontalTipX(preset, box, startX), -box.tailLength),
        )
    }
    if (preset.name.startsWith("Bottom")) {
        val startX = horizontalBaseStart(preset, box)
        return MessageBubbleTail(
            baseStart = MessageBubblePoint(startX, box.height),
            baseEnd = MessageBubblePoint(startX + box.tailBase, box.height),
            tip = MessageBubblePoint(horizontalTipX(preset, box, startX), box.height + box.tailLength),
        )
    }
    if (preset.name.startsWith("Left")) {
        val startY = verticalBaseStart(preset, box)
        return MessageBubbleTail(
            baseStart = MessageBubblePoint(0f, startY),
            baseEnd = MessageBubblePoint(0f, startY + box.tailBase),
            tip = MessageBubblePoint(-box.tailLength, verticalTipY(preset, box, startY)),
        )
    }
    val startY = verticalBaseStart(preset, box)
    return MessageBubbleTail(
        baseStart = MessageBubblePoint(box.width, startY),
        baseEnd = MessageBubblePoint(box.width, startY + box.tailBase),
        tip = MessageBubblePoint(box.width + box.tailLength, verticalTipY(preset, box, startY)),
    )
}

@Composable
fun MessageBubble(
    modifier: Modifier = Modifier,
    width: Dp = 224.dp,
    height: Dp = 96.dp,
    radius: Dp = 18.dp,
    borderWidth: Dp = 1.dp,
    fillColor: Color = Color(0xFFFFFDF6),
    strokeColor: Color = Color(0xFFE7D7B6),
    contentPadding: PaddingValues = PaddingValues(horizontal = 10.dp, vertical = 10.dp),
    tail: MessageBubbleTail? = defaultMessageBubbleTail(),
    bubbleShadow: MessageBubbleShadow = MessageBubbleShadow(
        radius = 12.dp,
        color = Color(0x33000000),
        offsetX = 0.dp,
        offsetY = 4.dp,
    ),
    content: @Composable () -> Unit = {},
) {
    val density = LocalDensity.current
    val widthValue = width.value
    val heightValue = height.value
    val frame = messageBubbleFrame(widthValue, heightValue, tail)
    val shadowPadding = messageBubbleShadowPadding(bubbleShadow)
    val outerWidth = (frame.width + shadowPadding.x * 2f).dp
    val outerHeight = (frame.height + shadowPadding.y * 2f).dp

    Box(
        modifier = modifier.size(outerWidth, outerHeight),
        contentAlignment = Alignment.TopStart,
    ) {
        Canvas(Modifier.size(outerWidth, outerHeight)) {
            val scale = density.density
            val tailPx = tail?.scale(scale)
            val path = messageBubblePath(
                width = width.toPx(),
                height = height.toPx(),
                radius = radius.toPx(),
                tail = tailPx,
            )
            val shadowPaddingPx = Offset(shadowPadding.x.dp.toPx(), shadowPadding.y.dp.toPx())
            messageBubbleShadowLayers(bubbleShadow).forEach { layer ->
                translate(
                    left = shadowPaddingPx.x + layer.offsetX.toPx(),
                    top = shadowPaddingPx.y + layer.offsetY.toPx(),
                ) {
                    drawPath(
                        path = path,
                        color = bubbleShadow.color.copy(alpha = bubbleShadow.color.alpha * layer.opacity),
                    )
                }
            }
            translate(left = shadowPaddingPx.x, top = shadowPaddingPx.y) {
                drawPath(path = path, color = fillColor)
                if (borderWidth > 0.dp) {
                    drawPath(
                        path = path,
                        color = strokeColor,
                        style = androidx.compose.ui.graphics.drawscope.Stroke(width = borderWidth.toPx()),
                    )
                }
            }
        }
        Box(
            modifier = Modifier
                .offset(
                    x = (shadowPadding.x + frame.offsetX).dp,
                    y = (shadowPadding.y + frame.offsetY).dp,
                )
                .size(width, height)
                .padding(contentPadding),
            contentAlignment = Alignment.Center,
        ) {
            content()
        }
    }
}

fun defaultMessageBubbleTail(): MessageBubbleTail = buildMessageBubbleTailPreset(
    preset = MessageBubbleTailPreset.BottomRight,
    box = MessageBubbleBox(
        width = 224f,
        height = 96f,
        borderWidth = 1f,
        tailBase = 24f,
        tailLength = 16f,
        inset = 28f,
        tipInset = 12f,
    ),
)

private fun horizontalBaseStart(preset: MessageBubbleTailPreset, box: MessageBubbleBox): Float {
    return when (preset) {
        MessageBubbleTailPreset.TopLeft,
        MessageBubbleTailPreset.BottomLeft -> clampStart(box.inset, box.width, box.tailBase)
        MessageBubbleTailPreset.TopRight,
        MessageBubbleTailPreset.BottomRight -> clampStart(box.width - box.inset - box.tailBase, box.width, box.tailBase)
        else -> clampStart((box.width - box.tailBase) / 2f, box.width, box.tailBase)
    }
}

private fun verticalBaseStart(preset: MessageBubbleTailPreset, box: MessageBubbleBox): Float {
    return when (preset) {
        MessageBubbleTailPreset.LeftTop,
        MessageBubbleTailPreset.RightTop -> clampStart(box.inset, box.height, box.tailBase)
        MessageBubbleTailPreset.LeftBottom,
        MessageBubbleTailPreset.RightBottom -> clampStart(box.height - box.inset - box.tailBase, box.height, box.tailBase)
        else -> clampStart((box.height - box.tailBase) / 2f, box.height, box.tailBase)
    }
}

private fun horizontalTipX(preset: MessageBubbleTailPreset, box: MessageBubbleBox, baseStart: Float): Float {
    return when (preset) {
        MessageBubbleTailPreset.TopLeft,
        MessageBubbleTailPreset.BottomLeft -> box.tipInset
        MessageBubbleTailPreset.TopRight,
        MessageBubbleTailPreset.BottomRight -> box.width - box.tipInset
        else -> baseStart + box.tailBase / 2f
    }
}

private fun verticalTipY(preset: MessageBubbleTailPreset, box: MessageBubbleBox, baseStart: Float): Float {
    return when (preset) {
        MessageBubbleTailPreset.LeftTop,
        MessageBubbleTailPreset.RightTop -> box.tipInset
        MessageBubbleTailPreset.LeftBottom,
        MessageBubbleTailPreset.RightBottom -> box.height - box.tipInset
        else -> baseStart + box.tailBase / 2f
    }
}

private fun clampStart(start: Float, length: Float, base: Float): Float {
    return start.coerceIn(0f, length - base)
}

private fun MessageBubbleTail.scale(scale: Float): MessageBubbleTail = MessageBubbleTail(
    baseStart = MessageBubblePoint(baseStart.x * scale, baseStart.y * scale),
    baseEnd = MessageBubblePoint(baseEnd.x * scale, baseEnd.y * scale),
    tip = MessageBubblePoint(tip.x * scale, tip.y * scale),
)

private fun messageBubbleShadowPadding(shadow: MessageBubbleShadow): MessageBubbleShadowPadding {
    if (shadow.radius <= 0.dp) {
        return MessageBubbleShadowPadding(x = 0f, y = 0f)
    }
    return MessageBubbleShadowPadding(
        x = abs(shadow.offsetX.value) + shadow.radius.value,
        y = abs(shadow.offsetY.value) + shadow.radius.value,
    )
}

private fun messageBubbleShadowLayers(shadow: MessageBubbleShadow): List<MessageBubbleShadowLayer> {
    if (shadow.radius <= 0.dp) return emptyList()
    return listOf(
        MessageBubbleShadowLayer(shadow.offsetX, shadow.offsetY, 0.45f),
    )
}

private fun messageBubblePath(width: Float, height: Float, radius: Float, tail: MessageBubbleTail?): Path {
    val r = min(radius, min(width / 2f, height / 2f))
    val frame = messageBubbleFrame(width, height, tail)
    val x = frame.offsetX
    val y = frame.offsetY
    val shiftedTail = tail?.let {
        MessageBubbleTail(
            baseStart = it.baseStart.shift(frame),
            baseEnd = it.baseEnd.shift(frame),
            tip = it.tip.shift(frame),
        )
    }
    val side = tail?.let { detectTailSide(width, height, it) }

    return Path().apply {
        moveTo(x + r, y)
        if (side == MessageBubbleTailSide.Top && shiftedTail != null) {
            lineTo(shiftedTail.baseStart.x, shiftedTail.baseStart.y)
            lineTo(shiftedTail.tip.x, shiftedTail.tip.y)
            lineTo(shiftedTail.baseEnd.x, shiftedTail.baseEnd.y)
        }
        lineTo(x + width - r, y)
        quadraticTo(x + width, y, x + width, y + r)
        if (side == MessageBubbleTailSide.Right && shiftedTail != null) {
            lineTo(shiftedTail.baseStart.x, shiftedTail.baseStart.y)
            lineTo(shiftedTail.tip.x, shiftedTail.tip.y)
            lineTo(shiftedTail.baseEnd.x, shiftedTail.baseEnd.y)
        }
        lineTo(x + width, y + height - r)
        quadraticTo(x + width, y + height, x + width - r, y + height)
        if (side == MessageBubbleTailSide.Bottom && shiftedTail != null) {
            lineTo(shiftedTail.baseEnd.x, shiftedTail.baseEnd.y)
            lineTo(shiftedTail.tip.x, shiftedTail.tip.y)
            lineTo(shiftedTail.baseStart.x, shiftedTail.baseStart.y)
        }
        lineTo(x + r, y + height)
        quadraticTo(x, y + height, x, y + height - r)
        if (side == MessageBubbleTailSide.Left && shiftedTail != null) {
            lineTo(shiftedTail.baseEnd.x, shiftedTail.baseEnd.y)
            lineTo(shiftedTail.tip.x, shiftedTail.tip.y)
            lineTo(shiftedTail.baseStart.x, shiftedTail.baseStart.y)
        }
        lineTo(x, y + r)
        quadraticTo(x, y, x + r, y)
        close()
    }
}

private fun MessageBubblePoint.shift(frame: MessageBubbleFrame): MessageBubblePoint {
    return MessageBubblePoint(x + frame.offsetX, y + frame.offsetY)
}

private fun detectTailSide(width: Float, height: Float, tail: MessageBubbleTail): MessageBubbleTailSide {
    return when {
        tail.baseStart.y == 0f && tail.baseEnd.y == 0f -> MessageBubbleTailSide.Top
        tail.baseStart.x == width && tail.baseEnd.x == width -> MessageBubbleTailSide.Right
        tail.baseStart.y == height && tail.baseEnd.y == height -> MessageBubbleTailSide.Bottom
        tail.baseStart.x == 0f && tail.baseEnd.x == 0f -> MessageBubbleTailSide.Left
        else -> MessageBubbleTailSide.Bottom
    }
}
