package cool.happyword.wordmagic.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.annotation.RawRes
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.caverock.androidsvg.SVG
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.CheckInCalendar
import cool.happyword.wordmagic.core.CheckInSnapshot
import cool.happyword.wordmagic.core.CheckInWeekRow
import cool.happyword.wordmagic.core.LearningReport
import cool.happyword.wordmagic.core.MonsterCatalog
import cool.happyword.wordmagic.core.PackSelectionStore
import cool.happyword.wordmagic.core.RedemptionRecord
import cool.happyword.wordmagic.core.RedemptionHistoryStore
import cool.happyword.wordmagic.core.TodayPlanService
import cool.happyword.wordmagic.core.TodayPlanUi
import cool.happyword.wordmagic.core.TodayPlanWordRow
import cool.happyword.wordmagic.core.WishItem
import cool.happyword.wordmagic.core.WishlistState
import cool.happyword.wordmagic.core.WordPack
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun PackManagerScreen(
    packs: List<WordPack>,
    selection: PackSelectionStore,
    message: String,
    onToggleActive: (WordPack) -> Unit,
    onTogglePin: (WordPack) -> Unit,
    onSync: () -> Unit,
    onBack: () -> Unit,
) {
    val activeCountText = "已激活 ${selection.activePackIds.size} / ${PackSelectionStore.MAX_ACTIVE}"
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF8FAFC))
            .topChromeSafeInsets()
            .padding(
                start = PageChromeInsets.homeAlignedHorizontal,
                top = PageChromeInsets.bodyTop,
                end = PageChromeInsets.homeAlignedHorizontal,
                bottom = PageChromeInsets.bodyBottom,
            )
            .testTag("PackManagerScreen"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                HarmonyPageTopBackButton(
                    onClick = onBack,
                    modifier = Modifier.testTag("PackManagerBack"),
                )
                Text(
                    "📦 我的词包",
                    modifier = Modifier.padding(start = 12.dp).testTag("PackManagerTitle"),
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF1F2937),
                )
                Spacer(Modifier.weight(1f))
                Button(
                    onClick = onSync,
                    modifier = Modifier.height(40.dp).testTag("PackManagerSyncButton"),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEAF2F8), contentColor = Color(0xFF457B9D)),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 14.dp, vertical = 0.dp),
                ) {
                    Text("🔄 同步词包", fontSize = 15.sp)
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 18.dp, bottom = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(activeCountText, modifier = Modifier.testTag("PackManagerActiveCount"), fontSize = 14.sp, color = Color(0xFF6B7280))
                Spacer(Modifier.weight(1f))
                Text("固定：防止满分自动轮换 · 开关：切换激活", fontSize = 12.sp, color = Color(0xFF9CA3AF))
            }
            if (message.isNotBlank()) {
                val messageTag = when {
                    message.contains("已关闭") && message.contains("以激活") -> "PackManagerAutoRotateToast"
                    message == "请先取消固定一个词包" -> "PackManagerCapRefuseToast"
                    else -> "PackManagerLimitMessage"
                }
                val messageColor = if (messageTag == "PackManagerLimitMessage") Color(0xFF147C42) else Color(0xFFD94141)
                Text(message, color = messageColor, modifier = Modifier.padding(vertical = 6.dp).testTag(messageTag))
            }
        }
        items(packs) { pack ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color.White, RoundedCornerShape(10.dp))
                    .padding(horizontal = 16.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(
                    sourceLabel(pack.source.name),
                    modifier = Modifier
                        .background(packSourceColor(pack.source.name), RoundedCornerShape(4.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                        .testTag("PackSourceTag_${pack.id}"),
                    fontSize = 11.sp,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                )
                Text(pack.nameEn, modifier = Modifier.weight(1f).testTag("PackLabel_${pack.id}"), fontSize = 16.sp, color = Color(0xFF1F2937))
                if (pack.id in selection.activePackIds) {
                    Button(
                        onClick = { onTogglePin(pack) },
                        modifier = Modifier.height(36.dp).testTag("PackPin_${pack.id}"),
                        shape = RoundedCornerShape(8.dp),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (pack.id in selection.pinnedPackIds) Color(0xFFFEF3C7) else Color(0xFFF3F4F6),
                            contentColor = if (pack.id in selection.pinnedPackIds) Color(0xFFB45309) else Color(0xFF6B7280),
                        ),
                        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                    ) {
                        Text(if (pack.id in selection.pinnedPackIds) "已固定" else "📌 固定", fontSize = 13.sp)
                    }
                } else {
                    Spacer(Modifier.height(36.dp).width(72.dp))
                }
                Switch(
                    checked = pack.id in selection.activePackIds,
                    onCheckedChange = { onToggleActive(pack) },
                    modifier = Modifier.testTag("PackToggle_${pack.id}"),
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = Color.White,
                        checkedTrackColor = Color(0xFFFFB400),
                        uncheckedThumbColor = Color.White,
                        uncheckedTrackColor = Color(0xFFE5E7EB),
                    ),
                )
            }
        }
    }
}

@Composable
fun WishlistScreen(
    coinAccount: CoinAccount,
    wishlist: WishlistState,
    message: String,
    giftBoxVisible: Boolean = false,
    giftBoxTrigger: Int = 0,
    recentlyRedeemedWishId: String? = null,
    /** When parent PIN is configured (6 digits): show "+ 添加" and remove on custom wishes. */
    showAddCustomEntry: Boolean = false,
    onRedeem: (WishItem) -> Unit,
    onHistory: () -> Unit,
    onAddCustom: () -> Unit,
    onRequestRemoveCustom: (WishItem) -> Unit,
    onBack: () -> Unit,
) {
    BackHandler(enabled = giftBoxVisible) {}
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF8F9FA))
            .testTag("WishlistScreen"),
    ) {
        LazyColumn(
            Modifier
                .fillMaxSize()
                .topChromeSafeInsets()
                .padding(
                    start = PageChromeInsets.homeAlignedHorizontal,
                    top = PageChromeInsets.bodyTop,
                    end = PageChromeInsets.homeAlignedHorizontal,
                    bottom = PageChromeInsets.bodyBottom,
                ),
        ) {
            item {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    HarmonyPageTopBackButton(
                        onClick = {
                            if (!giftBoxVisible) onBack()
                        },
                        modifier = Modifier.testTag("WishlistBackButton"),
                    )
                    Text(
                        "魔法愿望单",
                        modifier = Modifier
                            .weight(1f)
                            .testTag("WishlistTitle"),
                        fontSize = 26.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF1D3557),
                        textAlign = TextAlign.Center,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Button(
                            onClick = {
                                if (!giftBoxVisible) onHistory()
                            },
                            modifier = Modifier
                                .height(36.dp)
                                .testTag("WishlistHistoryButton"),
                            shape = RoundedCornerShape(8.dp),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEAF2F8), contentColor = Color(0xFF1D3557)),
                            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                        ) {
                            Text("历史", fontSize = 14.sp)
                        }
                        if (showAddCustomEntry) {
                            Button(
                                onClick = {
                                    if (!giftBoxVisible) onAddCustom()
                                },
                                modifier = Modifier
                                    .height(36.dp)
                                    .testTag("WishlistAddCustomButton"),
                                shape = RoundedCornerShape(8.dp),
                                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEAF2F8), contentColor = Color(0xFF1D3557)),
                                contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                            ) {
                                Text("+ 添加", fontSize = 14.sp)
                            }
                        }
                        Text(
                            "我的魔法币: ${coinAccount.balance} ✨",
                            modifier = Modifier.testTag("WishlistBalance"),
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Medium,
                            color = Color(0xFFFFB400),
                        )
                    }
                }
                if (message.isNotBlank()) {
                    Text(message, modifier = Modifier.padding(top = 8.dp).testTag("WishlistMessage"), color = Color(0xFFD94141))
                }
                Spacer(Modifier.height(8.dp))
            }
            items(wishlist.allWishes()) { wish ->
                val gap = wish.cost - coinAccount.balance
                Card(
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 6.dp)
                        .testTag("WishCard_${wish.id}"),
                    shape = RoundedCornerShape(14.dp),
                    colors = CardDefaults.cardColors(containerColor = Color.White),
                    elevation = CardDefaults.cardElevation(defaultElevation = 2.dp),
                ) {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(wish.icon, fontSize = 32.sp, modifier = Modifier.testTag("WishIcon_${wish.id}"))
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                wish.title,
                                modifier = Modifier.testTag("WishName_${wish.id}"),
                                fontSize = 18.sp,
                                fontWeight = FontWeight.Medium,
                                color = Color(0xFF1D3557),
                            )
                            Text(
                                "${wish.cost} ✨",
                                fontSize = 14.sp,
                                color = Color(0xFFFFB400),
                            )
                        }
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            when {
                                wish.id == recentlyRedeemedWishId -> {
                                    Text(
                                        "已兑换 ✓",
                                        modifier = Modifier.testTag("WishConfirmed_${wish.id}"),
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = Color(0xFF2ECC71),
                                    )
                                }
                                coinAccount.balance >= wish.cost -> {
                                    Button(
                                        onClick = { onRedeem(wish) },
                                        modifier = Modifier
                                            .width(108.dp)
                                            .height(40.dp)
                                            .testTag("WishRedeem_${wish.id}"),
                                        shape = RoundedCornerShape(8.dp),
                                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE63946), contentColor = Color.White),
                                        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                                    ) {
                                        Text("申请兑换", fontSize = 15.sp)
                                    }
                                }
                                else -> {
                                    Text(
                                        "还差 $gap ✨",
                                        modifier = Modifier.testTag("WishGap_${wish.id}"),
                                        fontSize = 13.sp,
                                        color = Color(0xFF888888),
                                    )
                                }
                            }
                            if (wish.custom && showAddCustomEntry) {
                                Button(
                                    onClick = {
                                        if (!giftBoxVisible) {
                                            onRequestRemoveCustom(wish)
                                        }
                                    },
                                    modifier = Modifier
                                        .size(32.dp)
                                        .testTag("WishRemove_${wish.id}"),
                                    shape = RoundedCornerShape(8.dp),
                                    colors = ButtonDefaults.buttonColors(
                                        containerColor = Color(0xFFF1F2F4),
                                        contentColor = Color(0xFF888888),
                                    ),
                                    contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                                ) {
                                    Text("✕", fontSize = 14.sp)
                                }
                            }
                        }
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
        if (giftBoxVisible) {
            WishlistGiftBoxModal(trigger = giftBoxTrigger)
        }
    }
}

private const val GIFT_RIBBON_FLY_RADIUS = 90f
private const val GIFT_RIBBON_UPWARD_BIAS = 25f
private const val GIFT_RIBBON_GRAVITY_DROP = 120f
private val giftRibbonColors = listOf(
    Color(0xFFE63946),
    Color(0xFFF4C430),
    Color(0xFF457B9D),
    Color(0xFFF78DA7),
)

private data class GiftRibbon(val id: Int, val angleDeg: Float, val color: Color)

private fun generateGiftRibbons(count: Int): List<GiftRibbon> {
    if (count <= 0) return emptyList()
    val step = 360f / count
    return List(count) { index ->
        val jitter = ((index * 37) % 21) - 10
        GiftRibbon(
            id = index,
            angleDeg = index * step + jitter,
            color = giftRibbonColors[index % giftRibbonColors.size],
        )
    }
}

private fun computeGiftRibbonTarget(angleDeg: Float): Pair<Float, Float> {
    val angleRad = angleDeg * PI.toFloat() / 180f
    return Pair(
        cos(angleRad) * GIFT_RIBBON_FLY_RADIUS,
        sin(angleRad) * GIFT_RIBBON_FLY_RADIUS - GIFT_RIBBON_UPWARD_BIAS,
    )
}

@Composable
private fun WishlistGiftBoxModal(trigger: Int) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.5f))
            .clickable(onClick = {})
            .testTag("WishlistGiftBoxModal"),
        contentAlignment = Alignment.Center,
    ) {
        GiftBox(trigger = trigger, modifier = Modifier.testTag("WishlistGiftBox"))
    }
}

@Composable
private fun GiftBox(trigger: Int, modifier: Modifier = Modifier) {
    val ribbons = remember { generateGiftRibbons(10) }
    val boxScale = remember { Animatable(1f) }
    val lidTy = remember { Animatable(0f) }
    val lidRotation = remember { Animatable(0f) }
    val ribbonProgress = remember { Animatable(0f) }
    var ribbonsVisible by remember { mutableStateOf(false) }
    var openMarkerVisible by remember { mutableStateOf(false) }

    LaunchedEffect(trigger) {
        if (trigger <= 0) return@LaunchedEffect
        ribbonsVisible = false
        openMarkerVisible = false
        boxScale.snapTo(1f)
        lidTy.snapTo(0f)
        lidRotation.snapTo(0f)
        ribbonProgress.snapTo(0f)

        openMarkerVisible = true
        launch {
            boxScale.animateTo(1.08f, tween(durationMillis = 100, easing = FastOutSlowInEasing))
            boxScale.animateTo(1f, tween(durationMillis = 100, easing = FastOutSlowInEasing))
        }
        launch { lidTy.animateTo(-40f, tween(durationMillis = 200, easing = FastOutSlowInEasing)) }
        launch { lidRotation.animateTo(-15f, tween(durationMillis = 200, easing = FastOutSlowInEasing)) }
        ribbonsVisible = true
        launch { ribbonProgress.animateTo(1f, tween(durationMillis = 900, easing = FastOutSlowInEasing)) }
        delay(900)
        ribbonsVisible = false
        delay(600)
        openMarkerVisible = false
        launch { lidTy.animateTo(0f, tween(durationMillis = 180, easing = FastOutSlowInEasing)) }
        launch { lidRotation.animateTo(0f, tween(durationMillis = 180, easing = FastOutSlowInEasing)) }
    }

    Box(
        modifier = modifier
            .size(width = 220.dp, height = 200.dp)
            .graphicsLayer {
                scaleX = boxScale.value
                scaleY = boxScale.value
            },
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size(width = 120.dp, height = 80.dp)
                .offset(y = 28.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(Color(0xFFE63946)),
        )
        Box(
            modifier = Modifier
                .size(width = 8.dp, height = 80.dp)
                .offset(y = 28.dp)
                .background(Color(0xFFF4C430)),
        )
        Box(
            modifier = Modifier
                .size(width = 132.dp, height = 32.dp)
                .offset(y = (-34 + lidTy.value).dp)
                .graphicsLayer { rotationZ = lidRotation.value }
                .testTag("GiftBoxLid"),
            contentAlignment = Alignment.Center,
        ) {
            Box(
                modifier = Modifier
                    .matchParentSize()
                    .clip(RoundedCornerShape(6.dp))
                    .background(Color(0xFFE63946)),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(width = 24.dp, height = 10.dp)
                        .clip(RoundedCornerShape(5.dp))
                        .graphicsLayer { rotationZ = 25f }
                        .background(Color(0xFFF4C430)),
                )
                Box(
                    modifier = Modifier
                        .size(width = 24.dp, height = 10.dp)
                        .clip(RoundedCornerShape(5.dp))
                        .graphicsLayer { rotationZ = -25f }
                        .background(Color(0xFFF4C430)),
                )
            }
        }
        if (openMarkerVisible) {
            Box(Modifier.size(1.dp).alpha(0f).testTag("GiftBoxOpenMarker"))
        }
        if (ribbonsVisible) {
            ribbons.forEach { ribbon ->
                val target = computeGiftRibbonTarget(ribbon.angleDeg)
                val progress = ribbonProgress.value
                val phase1 = (progress / 0.33f).coerceIn(0f, 1f)
                val phase2 = ((progress - 0.33f) / 0.67f).coerceIn(0f, 1f)
                val x = target.first * phase1
                val y = target.second * phase1 + GIFT_RIBBON_GRAVITY_DROP * phase2
                Box(
                    modifier = Modifier
                        .size(width = 10.dp, height = 18.dp)
                        .offset(x = x.dp, y = y.dp)
                        .graphicsLayer {
                            alpha = 1f - phase2
                            rotationZ = ribbon.angleDeg
                        }
                        .clip(RoundedCornerShape(3.dp))
                        .background(ribbon.color)
                        .testTag("GiftBoxRibbon${ribbon.id}"),
                )
            }
        }
    }
}

@Composable
fun RedemptionHistoryScreen(history: RedemptionHistoryStore, onBack: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF8F9FA))
            .topChromeSafeInsets()
            .padding(
                start = PageChromeInsets.bodyHorizontal,
                top = PageChromeInsets.bodyTop,
                end = PageChromeInsets.bodyHorizontal,
                bottom = PageChromeInsets.bodyBottom,
            )
            .testTag("RedemptionHistoryScreen"),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .padding(bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier.testTag("RedemptionHistoryBackButton"),
            )
            Text(
                text = "兑换记录",
                modifier = Modifier
                    .weight(1f)
                    .testTag("RedemptionHistoryTitle"),
                fontSize = 26.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF1D3557),
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
            Spacer(Modifier.width(48.dp))
        }
        Spacer(Modifier.height(4.dp))
        if (history.records.isEmpty()) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "还没有兑换记录",
                    modifier = Modifier.testTag("RedemptionHistoryEmpty"),
                    fontSize = 16.sp,
                    color = Color(0xFF888888),
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(10.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(top = 8.dp, bottom = 24.dp),
            ) {
                items(history.records, key = { it.id }) { record ->
                    RedemptionHistoryRecordRow(record)
                }
            }
        }
    }
}

private val redemptionLocalTsFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")

/** Matches HarmonyOS `formatLocalTimestamp` in `RedemptionRecord.ets`. */
private fun formatRedemptionLocalTimestamp(ms: Long): String =
    redemptionLocalTsFormatter.format(
        Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).toLocalDateTime(),
    )

@Composable
private fun RedemptionHistoryRecordRow(record: RedemptionRecord) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth(0.92f)
                .testTag("RedemptionRecordCard_${record.id}"),
            shape = RoundedCornerShape(12.dp),
            color = Color.White,
            shadowElevation = 2.dp,
        ) {
            Row(
                Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(record.iconEmoji, fontSize = 28.sp)
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(
                        record.title,
                        modifier = Modifier.testTag("RedemptionRecordName_${record.id}"),
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Medium,
                        color = Color(0xFF1D3557),
                    )
                    Text(
                        formatRedemptionLocalTimestamp(record.redeemedAtMs),
                        modifier = Modifier.testTag("RedemptionRecordTime_${record.id}"),
                        fontSize = 13.sp,
                        color = Color(0xFF888888),
                    )
                }
                Text(
                    text = "-${record.cost} ✨",
                    modifier = Modifier.testTag("RedemptionRecordCost_${record.id}"),
                    fontSize = 15.sp,
                    color = Color(0xFFE63946),
                )
            }
        }
    }
}

@Composable
fun MonsterCodexScreen(catalog: MonsterCatalog, onPrevious: () -> Unit, onNext: () -> Unit, onBack: () -> Unit) {
    val context = LocalContext.current
    val current = catalog.current()
    val hasPrevious = catalog.index > 0
    val hasNext = catalog.index < catalog.entries.lastIndex
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFFFAFBFD))
            .topChromeSafeInsets()
            .padding(
                start = PageChromeInsets.bodyHorizontal,
                top = PageChromeInsets.bodyTop,
                end = PageChromeInsets.bodyHorizontal,
                bottom = PageChromeInsets.bodyBottom,
            )
            .testTag("MonsterCodexScreen"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp),
        ) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .testTag("MonsterCodexBack"),
            )
            Text(
                "怪物图鉴",
                modifier = Modifier.align(Alignment.Center),
                fontSize = 25.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF0B3B63),
            )
        }
        Spacer(Modifier.height(2.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CodexArrowButton(
                text = "⬅️",
                enabled = hasPrevious,
                tag = "MonsterCodexPrevious",
                onClick = onPrevious,
            )
            Box(
                modifier = Modifier
                    .size(148.dp)
                    .clip(RoundedCornerShape(22.dp))
                    .background(Color.White)
                    .border(1.dp, Color(0xFFE1E1E1), RoundedCornerShape(22.dp)),
                contentAlignment = Alignment.Center,
            ) {
                SvgRawImage(
                    monsterResource(context, current.rawResourceName),
                    modifier = Modifier
                        .height(110.dp)
                        .aspectRatio(1f)
                        .testTag("MonsterCodexImage"),
                )
            }
            CodexArrowButton(
                text = "➡️",
                enabled = hasNext,
                tag = "MonsterCodexNext",
                onClick = onNext,
            )
        }
        Spacer(Modifier.height(10.dp))
        Text(current.nameEn, modifier = Modifier.testTag("MonsterCodexName"), fontSize = 26.sp, fontWeight = FontWeight.Bold, color = Color(0xFF0B3B63))
        Text(
            "「${current.kindZh}」",
            modifier = Modifier
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFFE2F5FC))
                .padding(horizontal = 22.dp, vertical = 2.dp)
                .testTag("MonsterCodexKind"),
            fontSize = 15.sp,
            color = Color(0xFF0C85B6),
        )
        Spacer(Modifier.height(4.dp))
        Text(
            current.levelLabelZh,
            modifier = Modifier
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFFD84545))
                .padding(horizontal = 18.dp, vertical = 3.dp)
                .testTag("MonsterCodexLevelBadge_${current.id}"),
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
        )
        Spacer(Modifier.height(2.dp))
        Text("${catalog.index + 1} / ${catalog.entries.size}", modifier = Modifier.testTag("MonsterCodexPosition"), fontSize = 14.sp, color = Color(0xFF8A8A8A))
        Spacer(Modifier.height(12.dp))
        Text(
            current.descriptionZh,
            modifier = Modifier
                .fillMaxWidth(0.9f)
                .testTag("MonsterCodexDescription"),
            color = Color(0xFF333333),
            fontSize = 15.sp,
            lineHeight = 22.sp,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun CodexArrowButton(text: String, enabled: Boolean, tag: String, onClick: () -> Unit) {
    CenteredCircleTextButton(
        text = text,
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .defaultMinSize(minWidth = 56.dp, minHeight = 56.dp)
            .testTag(tag),
        size = 56.dp,
        fontSize = 28.sp,
        fontWeight = FontWeight.Bold,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (enabled) Color(0xFFFDE3E7) else Color(0xFFF6F8FA),
            contentColor = Color(0xFF1F2937),
            disabledContainerColor = Color(0xFFF6F8FA),
            disabledContentColor = Color(0xFF1F2937).copy(alpha = 0.42f),
        ),
    )
}

@Composable
fun TodayPlanScreen(plan: TodayPlanUi, onCheckIn: () -> Unit, onReport: () -> Unit, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFFF8F9FA))
            .testTag("TodayPlanScreen"),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .topChromeSafeInsets()
                .padding(
                    start = PageChromeInsets.homeAlignedHorizontal,
                    end = PageChromeInsets.homeAlignedHorizontal,
                    top = PageChromeInsets.bodyTop,
                    bottom = 12.dp,
                ),
        ) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier.testTag("TodayPlanBackButton"),
            )
            Text(
                "今日学习计划",
                modifier = Modifier
                    .weight(1f)
                    .testTag("TodayPlanTitle"),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF1D3557),
                textAlign = TextAlign.Center,
            )
            Button(
                onClick = onCheckIn,
                modifier = Modifier
                    .size(40.dp)
                    .testTag("TodayPlanCheckInButton"),
                shape = CircleShape,
                contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFFECFDF5),
                    contentColor = Color.Unspecified,
                ),
                elevation = ButtonDefaults.buttonElevation(
                    defaultElevation = 0.dp,
                    pressedElevation = 0.dp,
                    disabledElevation = 0.dp,
                    hoveredElevation = 0.dp,
                    focusedElevation = 0.dp,
                ),
            ) {
                Image(
                    painter = painterResource(id = R.drawable.icon_checkin),
                    contentDescription = "打卡日历",
                    modifier = Modifier.size(26.dp),
                    contentScale = ContentScale.Fit,
                )
            }
            Spacer(Modifier.width(8.dp))
            CenteredCircleTextButton(
                text = "📊",
                onClick = onReport,
                modifier = Modifier.testTag("TodayPlanReportButton"),
                size = 40.dp,
                fontSize = 20.sp,
                fontWeight = FontWeight.Normal,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color(0xFF1D3557),
                ),
            )
        }
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = PageChromeInsets.homeAlignedHorizontal)
                .padding(bottom = PageChromeInsets.bodyBottom),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            TodayPlanHeaderCard(plan)
            if (plan.total() == 0) {
                TodayPlanEmptyState()
            }
            if (plan.review.isNotEmpty()) {
                TodayPlanBucketSection(
                    title = "复习",
                    sectionTag = "TodayPlanReviewRequiredSection",
                    sourceLabel = "复习",
                    sourceColor = Color(0xFFE63946),
                    rows = plan.review,
                )
            }
            if (plan.learning.isNotEmpty()) {
                TodayPlanBucketSection(
                    title = "学习中",
                    sectionTag = "TodayPlanLearningSection",
                    sourceLabel = "学习",
                    sourceColor = Color(0xFF457B9D),
                    rows = plan.learning,
                )
            }
            if (plan.newWords.isNotEmpty()) {
                TodayPlanBucketSection(
                    title = "新词",
                    sectionTag = "TodayPlanNewSection",
                    sourceLabel = "新词",
                    sourceColor = Color(0xFF2A9D8F),
                    rows = plan.newWords,
                )
            }
        }
    }
}

@Composable
fun CheckInCalendarScreen(snapshot: CheckInSnapshot, onBack: () -> Unit) {
    BackHandler(onBack = onBack)
    var visibleMonth by remember { mutableStateOf(LocalDate.now().withDayOfMonth(1)) }
    val weeks = CheckInCalendar.buildMonthWeeks(visibleMonth.toString(), snapshot.checkedDayKeys.toSet())
    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFFF8F9FA))
            .testTag("CheckInCalendarScreen"),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .topChromeSafeInsets()
                .padding(
                    start = PageChromeInsets.homeAlignedHorizontal,
                    end = PageChromeInsets.homeAlignedHorizontal,
                    top = PageChromeInsets.bodyTop,
                    bottom = 12.dp,
                ),
        ) {
            HarmonyPageTopBackButton(onClick = onBack, modifier = Modifier.testTag("CheckInBackButton"))
            Text(
                "打卡日历",
                modifier = Modifier.weight(1f).testTag("CheckInPageTitle"),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF1D3557),
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.size(40.dp))
        }
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = PageChromeInsets.homeAlignedHorizontal)
                .padding(bottom = PageChromeInsets.bodyBottom),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                CheckInSummaryPill("连续 ${snapshot.currentStreak} 天", "当前连击", Color(0xFFDCFCE7), "CheckInCurrentStreak")
                CheckInSummaryPill("${snapshot.bestStreak} 天", "最佳连续", Color(0xFFFEF3C7), "CheckInBestStreak")
                CheckInSummaryPill(checkInCloudState(snapshot), "同步状态", Color(0xFFEAF2F8), "CheckInCloudState")
            }
            Text(
                snapshot.weeklyBonusDayKeys.lastOrNull()?.let { "最近一次连续奖励：$it +50" } ?: "连续 7 天后额外奖励 50 积分",
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(12.dp))
                    .background(Color(0xFFFEF3C7))
                    .padding(horizontal = 14.dp, vertical = 10.dp)
                    .testTag("CheckInWeeklyBonusBanner"),
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF92400E),
            )
            CheckInMonthCard(
                visibleMonth = visibleMonth,
                weeks = weeks,
                onPrevious = { visibleMonth = visibleMonth.minusMonths(1).withDayOfMonth(1) },
                onNext = { visibleMonth = visibleMonth.plusMonths(1).withDayOfMonth(1) },
            )
        }
    }
}

@Composable
private fun RowScope.CheckInSummaryPill(value: String, label: String, background: Color, tag: String) {
    Column(
        Modifier
            .weight(1f)
            .clip(RoundedCornerShape(12.dp))
            .background(background)
            .padding(vertical = 12.dp, horizontal = 8.dp)
            .testTag(tag),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = Color(0xFF1D3557), maxLines = 1)
        Text(label, fontSize = 11.sp, color = Color(0xFF64748B))
    }
}

@Composable
private fun CheckInMonthCard(
    visibleMonth: LocalDate,
    weeks: List<CheckInWeekRow>,
    onPrevious: () -> Unit,
    onNext: () -> Unit,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White)
            .padding(12.dp)
            .testTag("CheckInCalendarGrid"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            CenteredCircleIconButton(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowLeft,
                contentDescription = "上个月",
                onClick = onPrevious,
                modifier = Modifier.testTag("CheckInPrevMonthButton"),
                size = 36.dp,
                iconSize = 24.dp,
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFDCFCE7), contentColor = Color(0xFF065F46)),
            )
            Text(
                "${visibleMonth.year}年${visibleMonth.monthValue}月",
                modifier = Modifier.weight(1f).testTag("CheckInMonthLabel"),
                textAlign = TextAlign.Center,
                fontSize = 18.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF1D3557),
            )
            CenteredCircleIconButton(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = "下个月",
                onClick = onNext,
                modifier = Modifier.testTag("CheckInNextMonthButton"),
                size = 36.dp,
                iconSize = 24.dp,
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFDCFCE7), contentColor = Color(0xFF065F46)),
            )
        }
        Row(Modifier.fillMaxWidth()) {
            listOf("日", "一", "二", "三", "四", "五", "六").forEach {
                Text(it, modifier = Modifier.weight(1f), textAlign = TextAlign.Center, fontSize = 12.sp, color = Color(0xFF64748B))
            }
        }
        weeks.forEach { week ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                week.cells.forEach { cell ->
                    Text(
                        if (cell.inMonth) {
                            if (cell.checked) "${cell.label} ✓" else cell.label
                        } else {
                            ""
                        },
                        modifier = Modifier
                            .weight(1f)
                            .height(38.dp)
                            .clip(RoundedCornerShape(10.dp))
                            .background(if (cell.checked) Color(0xFF22C55E) else if (cell.inMonth) Color(0xFFF8FAFC) else Color.White)
                            .testTag(if (cell.inMonth) "CheckInDay_${cell.dayKey}" else "CheckInBlank"),
                        textAlign = TextAlign.Center,
                        fontSize = 13.sp,
                        fontWeight = if (cell.checked) FontWeight.Bold else FontWeight.Normal,
                        color = if (cell.checked) Color.White else Color(0xFF334155),
                    )
                }
            }
        }
    }
}

private fun checkInCloudState(snapshot: CheckInSnapshot): String =
    when {
        snapshot.pendingSync -> "等待同步"
        snapshot.lastSyncedAtMs > 0L -> "云端已同步"
        else -> "本地保存"
    }

@Composable
private fun TodayPlanHeaderCard(plan: TodayPlanUi) {
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(Color.White)
            .border(1.dp, Color(0xFFE0E0E0), RoundedCornerShape(16.dp))
            .padding(16.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                plan.regionDisplayName,
                modifier = Modifier.testTag("TodayPlanRegionName"),
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF3F2F1A),
            )
            Spacer(Modifier.weight(1f))
            Text(
                plan.dayKey,
                modifier = Modifier.testTag("TodayPlanDayKey"),
                fontSize = 14.sp,
                color = Color(0xFF7B7B7B),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            plan.progressText,
            modifier = Modifier.testTag("TodayPlanProgressText"),
            fontSize = 16.sp,
            color = Color(0xFF5A4A35),
        )
    }
}

@Composable
private fun TodayPlanEmptyState() {
    Column(
        Modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "今天没有可以学习的单词，先去玩一局冒险吧！",
            modifier = Modifier.testTag("TodayPlanEmptyText"),
            fontSize = 15.sp,
            color = Color(0xFF7B7B7B),
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun TodayPlanBucketSection(
    title: String,
    sectionTag: String,
    sourceLabel: String,
    sourceColor: Color,
    rows: List<TodayPlanWordRow>,
) {
    Column(
        Modifier
            .fillMaxWidth()
            .testTag(sectionTag),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color(0xFF1D3557))
            Spacer(Modifier.weight(1f))
            Text("${rows.size}", fontSize = 14.sp, color = Color(0xFF7B7B7B))
        }
        rows.forEach { row ->
            TodayPlanWordRowCard(row, sourceLabel, sourceColor)
        }
    }
}

@Composable
private fun TodayPlanWordRowCard(row: TodayPlanWordRow, sourceLabel: String, sourceColor: Color) {
    val memoryLabel = TodayPlanService.describeMemoryStat(row.stat)
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color.White)
            .border(1.dp, Color(0xFFE0E0E0), RoundedCornerShape(12.dp))
            .padding(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    row.entry.word,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF1D3557),
                )
                if (row.doneHighlight) {
                    Spacer(Modifier.width(6.dp))
                    Text(
                        "✓",
                        modifier = Modifier
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color(0xFFDCF7F2))
                            .padding(horizontal = 8.dp, vertical = 2.dp)
                            .testTag("TodayPlanReviewDone-${row.entry.id}"),
                        fontSize = 14.sp,
                        color = Color(0xFF2A9D8F),
                    )
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(
                row.entry.meaning,
                fontSize = 13.sp,
                color = Color(0xFF5A4A35),
            )
        }
        Spacer(Modifier.width(8.dp))
        Text(
            sourceLabel,
            fontSize = 12.sp,
            color = Color.White,
            modifier = Modifier
                .clip(RoundedCornerShape(10.dp))
                .background(sourceColor)
                .padding(horizontal = 8.dp, vertical = 2.dp),
        )
        Spacer(Modifier.width(6.dp))
        Text(
            memoryLabel,
            fontSize = 12.sp,
            color = Color(0xFF3F2F1A),
            modifier = Modifier
                .clip(RoundedCornerShape(10.dp))
                .background(Color(0xFFFFE7B5))
                .padding(horizontal = 8.dp, vertical = 2.dp),
        )
    }
}

@Composable
fun LearningReportScreen(report: LearningReport, onBack: () -> Unit) {
    val scroll = rememberScrollState()
    val cfg = LocalConfiguration.current
    val shortDp = minOf(cfg.screenWidthDp, cfg.screenHeightDp)
    val padClass = shortDp >= 600
    val contentModifier =
        if (padClass) {
            Modifier.widthIn(max = 720.dp).fillMaxWidth()
        } else {
            Modifier.fillMaxWidth()
        }
    val reviewBarFraction = max(1, report.reviewCompletionPct) / 100f
    val reviewBarTint =
        if (report.reviewCompletionPct > 0) Color(0xFF2A9D8F) else Color(0xFFEAEAEA)

    Column(
        Modifier
            .fillMaxSize()
            .background(Color(0xFFF8F9FA))
            .testTag("LearningReportScreen"),
    ) {
        Row(
            Modifier
                .fillMaxWidth()
                .topChromeSafeInsets()
                .padding(horizontal = 44.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier
                    .testTag("LearningReportBackButton"),
            )
            Text(
                "学习报告",
                modifier = Modifier
                    .weight(1f)
                    .testTag("LearningReportTitle"),
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF1D3557),
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.width(48.dp))
        }

        Column(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .verticalScroll(scroll)
                .padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(
                modifier = contentModifier.padding(horizontal = 44.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color.White)
                        .border(1.dp, Color(0xFFE0E0E0), RoundedCornerShape(16.dp))
                        .padding(16.dp),
                ) {
                    Text("总正确率", fontSize = 14.sp, color = Color(0xFF7B7B7B))
                    Text(
                        "${report.accuracyPct}%",
                        modifier = Modifier.testTag("LearningReportAccuracy"),
                        fontSize = 40.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF1D3557),
                    )
                    Text(
                        "已答 ${report.totalCorrect} / ${report.totalSeen} 题",
                        modifier = Modifier.testTag("LearningReportAccuracySub"),
                        fontSize = 14.sp,
                        color = Color(0xFF5A4A35),
                    )
                }

                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color.White)
                        .border(1.dp, Color(0xFFE0E0E0), RoundedCornerShape(16.dp))
                        .padding(16.dp),
                ) {
                    Text(
                        "单词掌握情况",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF1D3557),
                    )
                    Spacer(Modifier.height(8.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        LearningReportStatePill(
                            label = "掌握",
                            value = report.masteredCount,
                            color = Color(0xFF2A9D8F),
                            testTag = "LearningReportMastered",
                        )
                        LearningReportStatePill(
                            label = "熟悉",
                            value = report.familiarCount,
                            color = Color(0xFF457B9D),
                            testTag = "LearningReportFamiliar",
                        )
                        LearningReportStatePill(
                            label = "学习中",
                            value = report.learningCount,
                            color = Color(0xFFE9C46A),
                            testTag = "LearningReportLearning",
                        )
                        LearningReportStatePill(
                            label = "新词",
                            value = report.newCount,
                            color = Color(0xFFA8DADC),
                            testTag = "LearningReportNewCount",
                        )
                    }
                }

                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color.White)
                        .border(1.dp, Color(0xFFE0E0E0), RoundedCornerShape(16.dp))
                        .padding(16.dp),
                ) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "今日复习进度",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color(0xFF1D3557),
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            "${report.reviewDoneTodayCount} / ${max(report.reviewDueCount, report.reviewDoneTodayCount)}",
                            modifier = Modifier.testTag("LearningReportReviewCount"),
                            fontSize = 14.sp,
                            color = Color(0xFF5A4A35),
                        )
                    }
                    Spacer(Modifier.height(8.dp))
                    Box(
                        Modifier
                            .fillMaxWidth()
                            .height(12.dp)
                            .testTag("LearningReportReviewBar"),
                    ) {
                        Box(
                            Modifier
                                .fillMaxSize()
                                .clip(RoundedCornerShape(6.dp))
                                .background(Color(0xFFEAEAEA)),
                        )
                        Box(
                            Modifier
                                .fillMaxHeight()
                                .fillMaxWidth(reviewBarFraction)
                                .clip(RoundedCornerShape(6.dp))
                                .background(reviewBarTint),
                        )
                    }
                    Text(
                        "${report.reviewCompletionPct}% 完成",
                        modifier = Modifier.testTag("LearningReportReviewPct"),
                        fontSize = 13.sp,
                        color = Color(0xFF5A4A35),
                    )
                }

                Column(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(16.dp))
                        .background(Color.White)
                        .border(1.dp, Color(0xFFE0E0E0), RoundedCornerShape(16.dp))
                        .padding(16.dp)
                        .testTag("LearningReportPackSection"),
                ) {
                    Text(
                        "词包详情",
                        fontSize = 16.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF1D3557),
                    )
                    Spacer(Modifier.height(8.dp))
                    for (row in report.packs) {
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .testTag("pack-${row.packId}"),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(row.name, fontSize = 14.sp, color = Color(0xFF1D3557))
                            Spacer(Modifier.weight(1f))
                            Text(
                                "${row.totalCorrect} / ${row.totalSeen}",
                                fontSize = 13.sp,
                                color = Color(0xFF5A4A35),
                                modifier = Modifier.padding(end = 12.dp),
                            )
                            Text(
                                if (row.totalSeen > 0) "${row.accuracyPct}%" else "—",
                                fontSize = 13.sp,
                                color = Color(0xFF5A4A35),
                            )
                        }
                    }
                }

                if (report.totalSeen == 0) {
                    Column(
                        Modifier
                            .fillMaxWidth()
                            .padding(top = 16.dp, bottom = 16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            "还没有学习记录，先去玩一局冒险吧！",
                            modifier = Modifier.testTag("LearningReportEmptyText"),
                            fontSize = 14.sp,
                            color = Color(0xFF7B7B7B),
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun RowScope.LearningReportStatePill(
    label: String,
    value: Int,
    color: Color,
    testTag: String,
) {
    Column(
        modifier = Modifier
            .weight(1f)
            .clip(RoundedCornerShape(12.dp))
            .background(color)
            .padding(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "$value",
            modifier = Modifier.testTag(testTag),
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold,
            color = Color.White,
        )
        Text(label, fontSize = 12.sp, color = Color.White)
    }
}

@Composable
private fun SvgRawImage(@RawRes rawRes: Int, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val bitmap = remember(rawRes) {
        context.resources.openRawResource(rawRes).use { input ->
            val svg = SVG.getFromInputStream(input)
            val width = svg.documentWidth.takeIf { it > 0f } ?: 512f
            val height = svg.documentHeight.takeIf { it > 0f } ?: 512f
            Bitmap.createBitmap(width.toInt(), height.toInt(), Bitmap.Config.ARGB_8888).also { bmp ->
                svg.renderToCanvas(Canvas(bmp))
            }
        }
    }
    Image(bitmap = bitmap.asImageBitmap(), contentDescription = null, modifier = modifier, contentScale = ContentScale.Fit)
}

@RawRes
private fun monsterResource(context: Context, name: String): Int {
    val resolved = context.resources.getIdentifier(name, "raw", context.packageName)
    return if (resolved != 0) resolved else R.raw.character_slime
}

private fun sourceLabel(source: String): String = when (source) {
    "Family" -> "家庭"
    "Global" -> "官方"
    else -> "内置"
}

private fun packSourceColor(source: String): Color = when (source) {
    "Family" -> Color(0xFF0EA5E9)
    "Global" -> Color(0xFF10B981)
    else -> Color(0xFF9CA3AF)
}
