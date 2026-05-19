package cool.happyword.wordmagic.ui.battle

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/** Visual tokens for a single HP damage floater (V0.8.3 §6.5). */
internal data class DamageFloaterStyle(
    val text: String,
    val color: Color,
    val fontSizeSp: Int,
    val hasStroke: Boolean,
    val shadowRadius: Float,
    val shadowColor: Color,
)

internal fun pickFloaterStyle(amount: Int): DamageFloaterStyle {
    if (amount >= 2) {
        return DamageFloaterStyle(
            text = "-2",
            color = Color(0xFF7F1D1D),
            fontSizeSp = 20,
            hasStroke = false,
            shadowRadius = 2f,
            shadowColor = Color(0x66000000),
        )
    }
    return DamageFloaterStyle(
        text = "-1",
        color = Color(0xFFF87171),
        fontSizeSp = 18,
        hasStroke = true,
        shadowRadius = 0f,
        shadowColor = Color.Transparent,
    )
}

internal data class FloaterPending(
    val id: Int,
    val amount: Int,
    val stackOffsetDp: Dp,
)

internal enum class BattleFloaterSide {
    Player,
    Monster,
}

private const val FLOATER_DURATION_MS = 450L
private const val MAX_FLOATERS_PER_SIDE = 4
internal val FLOATER_STACK_OFFSET_DP = 6.dp

/**
 * Short-lived "-1" / "-2" label that rises above a battle character card.
 * Parent owns queueing; this composable only animates and calls [onDispose].
 */
@Composable
internal fun DamageFloaterLabel(
    amount: Int,
    stackOffsetDp: Dp,
    testTag: String,
    onDispose: () -> Unit,
) {
    val style = remember(amount) { pickFloaterStyle(amount) }
    val opacity = remember { Animatable(0f) }
    val offsetY = remember { Animatable(0f) }

    LaunchedEffect(amount, stackOffsetDp) {
        val halfMs = FLOATER_DURATION_MS / 2
        opacity.snapTo(0f)
        offsetY.snapTo(0f)
        opacity.animateTo(1f, tween(halfMs.toInt(), easing = FastOutSlowInEasing))
        offsetY.animateTo(-14f - stackOffsetDp.value, tween(halfMs.toInt(), easing = FastOutSlowInEasing))
        delay(halfMs)
        opacity.animateTo(0f, tween(halfMs.toInt(), easing = FastOutSlowInEasing))
        offsetY.animateTo(-28f - stackOffsetDp.value, tween(halfMs.toInt(), easing = FastOutSlowInEasing))
        delay(halfMs)
        onDispose()
    }

    val textShadow = if (style.hasStroke) {
        Shadow(color = Color.White, blurRadius = 2f)
    } else {
        Shadow(color = style.shadowColor, offset = androidx.compose.ui.geometry.Offset(0f, 1f), blurRadius = style.shadowRadius)
    }

    Text(
        text = style.text,
        modifier = Modifier
            .offset(y = offsetY.value.dp)
            .graphicsLayer { alpha = opacity.value }
            .testTag(testTag),
        style = TextStyle(
            fontSize = style.fontSizeSp.sp,
            fontWeight = FontWeight.Bold,
            color = style.color,
            shadow = textShadow,
        ),
    )
}

@Composable
internal fun DamageFloaterStack(
    floaters: List<FloaterPending>,
    side: BattleFloaterSide,
    modifier: Modifier = Modifier,
    onDispose: (Int) -> Unit,
) {
    Box(modifier = modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            floaters.forEachIndexed { index, item ->
                val tag = if (index == floaters.lastIndex) {
                    if (side == BattleFloaterSide.Player) {
                        "BattleDamageFloaterLabel_player"
                    } else {
                        "BattleDamageFloaterLabel_monster"
                    }
                } else {
                    val base = if (side == BattleFloaterSide.Player) {
                        "BattleDamageFloaterLabel_player"
                    } else {
                        "BattleDamageFloaterLabel_monster"
                    }
                    "${base}_${item.id}"
                }
                DamageFloaterLabel(
                    amount = item.amount,
                    stackOffsetDp = item.stackOffsetDp,
                    testTag = tag,
                    onDispose = { onDispose(item.id) },
                )
            }
        }
    }
}

internal fun pushBattleFloater(
    current: List<FloaterPending>,
    nextKey: Int,
    amount: Int,
): Pair<List<FloaterPending>, Int> {
    val dmg = if (amount >= 2) 2 else 1
    val next = current.toMutableList()
    if (next.size >= MAX_FLOATERS_PER_SIDE) {
        next.removeAt(0)
    }
    val pending = FloaterPending(
        id = nextKey,
        amount = dmg,
        stackOffsetDp = FLOATER_STACK_OFFSET_DP * next.size,
    )
    next.add(pending)
    return next to (nextKey + 1)
}
