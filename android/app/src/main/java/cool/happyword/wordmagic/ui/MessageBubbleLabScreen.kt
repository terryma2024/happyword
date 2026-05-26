package cool.happyword.wordmagic.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cool.happyword.wordmagic.ui.components.MessageBubble
import cool.happyword.wordmagic.ui.components.MessageBubbleBox
import cool.happyword.wordmagic.ui.components.MessageBubblePoint
import cool.happyword.wordmagic.ui.components.MessageBubbleShadow
import cool.happyword.wordmagic.ui.components.MessageBubbleTail
import cool.happyword.wordmagic.ui.components.MessageBubbleTailPreset
import cool.happyword.wordmagic.ui.components.buildMessageBubbleTailPreset

private val labPresets = listOf(
    MessageBubbleTailPreset.TopLeft,
    MessageBubbleTailPreset.TopMiddle,
    MessageBubbleTailPreset.TopRight,
    MessageBubbleTailPreset.BottomLeft,
    MessageBubbleTailPreset.BottomMiddle,
    MessageBubbleTailPreset.BottomRight,
    MessageBubbleTailPreset.LeftTop,
    MessageBubbleTailPreset.LeftMiddle,
    MessageBubbleTailPreset.LeftBottom,
    MessageBubbleTailPreset.RightTop,
    MessageBubbleTailPreset.RightMiddle,
    MessageBubbleTailPreset.RightBottom,
)

private val fillPalette = listOf(
    Color(0xFFEEE6FF),
    Color(0xFFFFFDF6),
    Color(0xFFE8F4FF),
    Color(0xFFFCEAEA),
    Color(0xFFE8F8EE),
)

private val strokePalette = listOf(
    Color(0xFF8B5CF6),
    Color(0xFFE7D7B6),
    Color(0xFF4A90E2),
    Color(0xFFE63946),
    Color(0xFF2E8B57),
)

@Stable
private data class MessageBubbleLabState(
    val width: Float = 224f,
    val height: Float = 96f,
    val radius: Float = 18f,
    val borderWidth: Float = 1f,
    val paddingX: Float = 10f,
    val paddingY: Float = 10f,
    val fillColor: Color = Color(0xFFFFFDF6),
    val strokeColor: Color = Color(0xFFE7D7B6),
    val shadowEnabled: Boolean = true,
    val shadowRadius: Float = 12f,
    val shadowOffsetX: Float = 0f,
    val shadowOffsetY: Float = 4f,
    val selectedPreset: MessageBubbleTailPreset = MessageBubbleTailPreset.BottomRight,
    val tail: MessageBubbleTail = buildMessageBubbleTailPreset(
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
    ),
)

@Composable
fun MessageBubbleLabScreen(onBack: () -> Unit) {
    var state by remember { mutableStateOf(MessageBubbleLabState()) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .verticalScroll(rememberScrollState())
            .topChromeSafeInsets()
            .padding(
                start = PageChromeInsets.bodyHorizontal,
                top = PageChromeInsets.bodyTop,
                end = PageChromeInsets.bodyHorizontal,
                bottom = PageChromeInsets.bodyBottom,
            )
            .testTag("MessageBubbleLabScreen"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier.testTag("MessageBubbleLabBackButton"),
            )
            Text(
                "Message Bubble Lab",
                modifier = Modifier.padding(start = 16.dp),
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF1D3557),
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.Top,
        ) {
            DemoPanel(state)
            LiveOutputPanel(state)
            PresetsPanel(
                state = state,
                onApplyPreset = { preset ->
                    state = state.copy(
                        selectedPreset = preset,
                        tail = buildMessageBubbleTailPreset(preset, state.labBox()),
                    )
                },
                onMoveTip = { dx, dy ->
                    state = state.copy(
                        tail = state.tail.copy(
                            tip = MessageBubblePoint(
                                x = state.tail.tip.x + dx,
                                y = state.tail.tip.y + dy,
                            ),
                        ),
                    )
                },
            )
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalAlignment = Alignment.Top,
        ) {
            TailGeometryPanel(
                state = state,
                onAdjust = { point, axis, delta ->
                    state = state.adjustTail(point, axis, delta)
                },
            )
            BubbleBoxPanel(
                state = state,
                onAdjust = { key, delta ->
                    val next = state.adjustBox(key, delta)
                    state = if (next.selectedPreset == state.selectedPreset) next else next
                },
            )
            VisualStylePanel(
                state = state,
                onAdjust = { key, delta -> state = state.adjustVisual(key, delta) },
                onToggleShadow = { state = state.copy(shadowEnabled = !state.shadowEnabled) },
                onCycleFill = { state = state.copy(fillColor = nextColor(state.fillColor, fillPalette)) },
                onCycleStroke = { state = state.copy(strokeColor = nextColor(state.strokeColor, strokePalette)) },
            )
        }
    }
}

@Composable
private fun DemoPanel(state: MessageBubbleLabState) {
    LabPanel(title = "Demo") {
        Box(
            modifier = Modifier
                .width(380.dp)
                .height(300.dp)
                .background(Color(0xFFFAF8FF), RoundedCornerShape(16.dp))
                .testTag("MessageBubbleLabPreview"),
            contentAlignment = Alignment.Center,
        ) {
            MessageBubble(
                width = state.width.dp,
                height = state.height.dp,
                radius = state.radius.dp,
                borderWidth = state.borderWidth.dp,
                fillColor = state.fillColor,
                strokeColor = state.strokeColor,
                contentPadding = PaddingValues(horizontal = state.paddingX.dp, vertical = state.paddingY.dp),
                tail = state.tail,
                bubbleShadow = MessageBubbleShadow(
                    radius = if (state.shadowEnabled) state.shadowRadius.dp else 0.dp,
                    color = Color(0x33000000),
                    offsetX = if (state.shadowEnabled) state.shadowOffsetX.dp else 0.dp,
                    offsetY = if (state.shadowEnabled) state.shadowOffsetY.dp else 0.dp,
                ),
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Text("Fern Lizard", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = Color(0xFF6B4A23))
                    Text(
                        "My green clue darts away.",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color(0xFF1D3557),
                        textAlign = TextAlign.Center,
                    )
                    Text("我的绿色线索飞跑。", fontSize = 11.sp, color = Color(0xFF6E5F54), textAlign = TextAlign.Center)
                }
            }
        }
    }
}

@Composable
private fun LiveOutputPanel(state: MessageBubbleLabState) {
    LabPanel(title = "Live Output") {
        Box(
            modifier = Modifier
                .width(380.dp)
                .height(300.dp)
                .background(Color(0xFFF4F0FF), RoundedCornerShape(12.dp))
                .padding(10.dp)
                .testTag("MessageBubbleLabOutput"),
        ) {
            Text(
                text = state.outputText(),
                fontSize = 10.sp,
                color = Color(0xFF3B2A65),
                fontFamily = FontFamily.Monospace,
            )
        }
    }
}

@Composable
private fun PresetsPanel(
    state: MessageBubbleLabState,
    onApplyPreset: (MessageBubbleTailPreset) -> Unit,
    onMoveTip: (Float, Float) -> Unit,
) {
    LabPanel(title = "Presets") {
        FlowRow(
            modifier = Modifier.width(380.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            labPresets.forEach { preset ->
                LabChipButton(
                    label = preset.name,
                    selected = state.selectedPreset == preset,
                    modifier = Modifier
                        .width(118.dp)
                        .testTag("MessageBubbleLabPreset${preset.name}"),
                    onClick = { onApplyPreset(preset) },
                )
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 10.dp)) {
            LabChipButton("Tip X -", onClick = { onMoveTip(-4f, 0f) }, modifier = Modifier.testTag("MessageBubbleLabTipXMinus"))
            LabChipButton("Tip X +", onClick = { onMoveTip(4f, 0f) }, modifier = Modifier.testTag("MessageBubbleLabTipXPlus"))
            LabChipButton("Tip Y -", onClick = { onMoveTip(0f, -4f) }, modifier = Modifier.testTag("MessageBubbleLabTipYMinus"))
            LabChipButton("Tip Y +", onClick = { onMoveTip(0f, 4f) }, modifier = Modifier.testTag("MessageBubbleLabTipYPlus"))
        }
    }
}

@Composable
private fun TailGeometryPanel(
    state: MessageBubbleLabState,
    onAdjust: (TailPointKey, AxisKey, Float) -> Unit,
) {
    LabPanel(title = "Tail Geometry") {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 6.dp)) {
            LabPill("free triangle")
            LabPill("preset -> points")
            LabPill("dp")
        }
        ValueStepper("Base start x", state.tail.baseStart.x, "dp", { onAdjust(TailPointKey.BaseStart, AxisKey.X, -2f) }, { onAdjust(TailPointKey.BaseStart, AxisKey.X, 2f) }, "MessageBubbleLabBaseStartX")
        ValueStepper("Base start y", state.tail.baseStart.y, "dp", { onAdjust(TailPointKey.BaseStart, AxisKey.Y, -2f) }, { onAdjust(TailPointKey.BaseStart, AxisKey.Y, 2f) }, "MessageBubbleLabBaseStartY")
        ValueStepper("Base end x", state.tail.baseEnd.x, "dp", { onAdjust(TailPointKey.BaseEnd, AxisKey.X, -2f) }, { onAdjust(TailPointKey.BaseEnd, AxisKey.X, 2f) }, "MessageBubbleLabBaseEndX")
        ValueStepper("Base end y", state.tail.baseEnd.y, "dp", { onAdjust(TailPointKey.BaseEnd, AxisKey.Y, -2f) }, { onAdjust(TailPointKey.BaseEnd, AxisKey.Y, 2f) }, "MessageBubbleLabBaseEndY")
        ValueStepper("Tip x", state.tail.tip.x, "dp", { onAdjust(TailPointKey.Tip, AxisKey.X, -2f) }, { onAdjust(TailPointKey.Tip, AxisKey.X, 2f) }, "MessageBubbleLabTipXDirect")
        ValueStepper("Tip y", state.tail.tip.y, "dp", { onAdjust(TailPointKey.Tip, AxisKey.Y, -2f) }, { onAdjust(TailPointKey.Tip, AxisKey.Y, 2f) }, "MessageBubbleLabTipYDirect")
    }
}

@Composable
private fun BubbleBoxPanel(state: MessageBubbleLabState, onAdjust: (BoxValueKey, Float) -> Unit) {
    LabPanel(title = "Bubble Box") {
        ValueStepper("Width", state.width, "dp", { onAdjust(BoxValueKey.Width, -10f) }, { onAdjust(BoxValueKey.Width, 10f) }, "MessageBubbleLabWidth")
        ValueStepper("Height", state.height, "dp", { onAdjust(BoxValueKey.Height, -10f) }, { onAdjust(BoxValueKey.Height, 10f) }, "MessageBubbleLabHeight")
        ValueStepper("Padding X", state.paddingX, "dp", { onAdjust(BoxValueKey.PaddingX, -2f) }, { onAdjust(BoxValueKey.PaddingX, 2f) }, "MessageBubbleLabPaddingX")
        ValueStepper("Padding Y", state.paddingY, "dp", { onAdjust(BoxValueKey.PaddingY, -2f) }, { onAdjust(BoxValueKey.PaddingY, 2f) }, "MessageBubbleLabPaddingY")
        ValueStepper("Corner radius", state.radius, "dp", { onAdjust(BoxValueKey.Radius, -2f) }, { onAdjust(BoxValueKey.Radius, 2f) }, "MessageBubbleLabRadius")
        ValueStepper("Border width", state.borderWidth, "dp", { onAdjust(BoxValueKey.BorderWidth, -1f) }, { onAdjust(BoxValueKey.BorderWidth, 1f) }, "MessageBubbleLabBorder")
    }
}

@Composable
private fun VisualStylePanel(
    state: MessageBubbleLabState,
    onAdjust: (VisualValueKey, Float) -> Unit,
    onToggleShadow: () -> Unit,
    onCycleFill: () -> Unit,
    onCycleStroke: () -> Unit,
) {
    LabPanel(title = "Visual Style") {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Fill / Stroke", modifier = Modifier.width(92.dp), fontSize = 11.sp, color = Color(0xFF4A4268))
            LabChipButton(state.fillColor.toHex(), onClick = onCycleFill, modifier = Modifier.width(112.dp).testTag("MessageBubbleLabFillColor"))
            LabChipButton(state.strokeColor.toHex(), onClick = onCycleStroke, modifier = Modifier.width(112.dp).testTag("MessageBubbleLabStrokeColor"))
        }
        ValueStepper("Shadow r", state.shadowRadius, "dp", { onAdjust(VisualValueKey.ShadowRadius, -2f) }, { onAdjust(VisualValueKey.ShadowRadius, 2f) }, "MessageBubbleLabShadowRadius")
        ValueStepper("Shadow x", state.shadowOffsetX, "dp", { onAdjust(VisualValueKey.ShadowX, -1f) }, { onAdjust(VisualValueKey.ShadowX, 1f) }, "MessageBubbleLabShadowX")
        ValueStepper("Shadow y", state.shadowOffsetY, "dp", { onAdjust(VisualValueKey.ShadowY, -1f) }, { onAdjust(VisualValueKey.ShadowY, 1f) }, "MessageBubbleLabShadowY")
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Shadow", modifier = Modifier.width(92.dp), fontSize = 11.sp, color = Color(0xFF4A4268))
            LabChipButton(
                if (state.shadowEnabled) "on" else "off",
                onClick = onToggleShadow,
                modifier = Modifier.width(72.dp).testTag("MessageBubbleLabShadowToggle"),
            )
            LabPill("auto seamless")
            LabPill("internal only")
        }
    }
}

@Composable
private fun LabPanel(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier.width(380.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color(0xFF2E225C))
        content()
    }
}

@Composable
private fun ValueStepper(
    label: String,
    value: Float,
    unit: String,
    onMinus: () -> Unit,
    onPlus: () -> Unit,
    tagPrefix: String,
) {
    Row(
        modifier = Modifier
            .width(380.dp)
            .padding(bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(label, modifier = Modifier.width(92.dp), fontSize = 11.sp, color = Color(0xFF4A4268))
        OutlinedButton(
            onClick = onMinus,
            modifier = Modifier
                .height(28.dp)
                .width(38.dp)
                .testTag("${tagPrefix}Minus"),
            contentPadding = PaddingValues(0.dp),
        ) {
            Text("-", fontSize = 14.sp)
        }
        Text(
            value.trimmed(),
            modifier = Modifier
                .height(28.dp)
                .width(126.dp)
                .border(1.dp, Color(0xFFD8C6FF), RoundedCornerShape(8.dp))
                .padding(top = 6.dp)
                .testTag("${tagPrefix}Value"),
            textAlign = TextAlign.Center,
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF4A3A8A),
        )
        OutlinedButton(
            onClick = onPlus,
            modifier = Modifier
                .height(28.dp)
                .width(38.dp)
                .testTag("${tagPrefix}Plus"),
            contentPadding = PaddingValues(0.dp),
        ) {
            Text("+", fontSize = 14.sp)
        }
        Text(unit, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = Color(0xFF4A4268))
    }
}

@Composable
private fun LabChipButton(
    label: String,
    modifier: Modifier = Modifier,
    selected: Boolean = false,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        modifier = modifier
            .height(30.dp)
            .defaultMinSize(minWidth = 1.dp),
        shape = RoundedCornerShape(15.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (selected) Color(0xFF8B5CF6) else Color(0xFFF5F0FF),
            contentColor = if (selected) Color.White else Color(0xFF5B36D6),
        ),
        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
    ) {
        Text(label, fontSize = 10.sp, maxLines = 1)
    }
}

@Composable
private fun LabPill(label: String) {
    Text(
        label,
        modifier = Modifier
            .height(28.dp)
            .border(1.dp, Color(0xFFD8C6FF), RoundedCornerShape(14.dp))
            .padding(horizontal = 12.dp, vertical = 7.dp),
        fontSize = 10.sp,
        fontWeight = FontWeight.Bold,
        color = Color(0xFF5B36D6),
    )
}

private enum class TailPointKey { BaseStart, BaseEnd, Tip }
private enum class AxisKey { X, Y }
private enum class BoxValueKey { Width, Height, PaddingX, PaddingY, Radius, BorderWidth }
private enum class VisualValueKey { ShadowRadius, ShadowX, ShadowY }

private fun MessageBubbleLabState.labBox(): MessageBubbleBox = MessageBubbleBox(
    width = width,
    height = height,
    borderWidth = borderWidth,
    tailBase = 24f,
    tailLength = 16f,
    inset = 28f,
    tipInset = 12f,
)

private fun MessageBubbleLabState.adjustTail(point: TailPointKey, axis: AxisKey, delta: Float): MessageBubbleLabState {
    fun adjust(current: MessageBubblePoint): MessageBubblePoint {
        return when (axis) {
            AxisKey.X -> current.copy(x = current.x + delta)
            AxisKey.Y -> current.copy(y = current.y + delta)
        }
    }
    return copy(
        tail = when (point) {
            TailPointKey.BaseStart -> tail.copy(baseStart = adjust(tail.baseStart))
            TailPointKey.BaseEnd -> tail.copy(baseEnd = adjust(tail.baseEnd))
            TailPointKey.Tip -> tail.copy(tip = adjust(tail.tip))
        },
    )
}

private fun MessageBubbleLabState.adjustBox(key: BoxValueKey, delta: Float): MessageBubbleLabState {
    return when (key) {
        BoxValueKey.Width -> copy(width = (width + delta).coerceAtLeast(40f))
        BoxValueKey.Height -> copy(height = (height + delta).coerceAtLeast(40f))
        BoxValueKey.PaddingX -> copy(paddingX = (paddingX + delta).coerceAtLeast(0f))
        BoxValueKey.PaddingY -> copy(paddingY = (paddingY + delta).coerceAtLeast(0f))
        BoxValueKey.Radius -> copy(radius = (radius + delta).coerceAtLeast(0f))
        BoxValueKey.BorderWidth -> copy(borderWidth = (borderWidth + delta).coerceAtLeast(0f))
    }
}

private fun MessageBubbleLabState.adjustVisual(key: VisualValueKey, delta: Float): MessageBubbleLabState {
    return when (key) {
        VisualValueKey.ShadowRadius -> copy(shadowRadius = (shadowRadius + delta).coerceAtLeast(0f))
        VisualValueKey.ShadowX -> copy(shadowOffsetX = (shadowOffsetX + delta).coerceAtLeast(-80f))
        VisualValueKey.ShadowY -> copy(shadowOffsetY = (shadowOffsetY + delta).coerceAtLeast(-80f))
    }
}

private fun MessageBubbleLabState.outputText(): String {
    return """preset: $selectedPreset
unit: dp
tail: {
  baseStart: { x: ${tail.baseStart.x.trimmed()}, y: ${tail.baseStart.y.trimmed()} },
  baseEnd: { x: ${tail.baseEnd.x.trimmed()}, y: ${tail.baseEnd.y.trimmed()} },
  tip: { x: ${tail.tip.x.trimmed()}, y: ${tail.tip.y.trimmed()} }
}
shadow: {
  radius: ${shadowRadius.trimmed()},
  offsetX: ${shadowOffsetX.trimmed()},
  offsetY: ${shadowOffsetY.trimmed()}
}"""
}

private fun nextColor(current: Color, palette: List<Color>): Color {
    val currentIndex = palette.indexOf(current)
    return palette[(currentIndex + 1).floorMod(palette.size)]
}

private fun Int.floorMod(divisor: Int): Int = ((this % divisor) + divisor) % divisor

private fun Float.trimmed(): String {
    return if (this == toInt().toFloat()) toInt().toString() else toString()
}

private fun Color.toHex(): String {
    return "#%06X".format(toArgb() and 0xFFFFFF)
}
