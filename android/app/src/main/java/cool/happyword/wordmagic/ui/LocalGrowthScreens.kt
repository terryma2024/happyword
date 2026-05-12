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
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.caverock.androidsvg.SVG
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.LearningReport
import cool.happyword.wordmagic.core.MonsterCatalog
import cool.happyword.wordmagic.core.PackSelectionStore
import cool.happyword.wordmagic.core.RedemptionHistoryStore
import cool.happyword.wordmagic.core.TodayPlan
import cool.happyword.wordmagic.core.WishItem
import cool.happyword.wordmagic.core.WishlistState
import cool.happyword.wordmagic.core.WordPack
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
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
    val activeCountText = "已激活 ${selection.activePackIds.size} / 5"
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF8FAFC))
            .padding(horizontal = 32.dp, vertical = 16.dp)
            .testTag("PackManagerScreen"),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Button(
                    onClick = onBack,
                    modifier = Modifier.size(44.dp).testTag("PackManagerBack"),
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFF3F4F6), contentColor = Color(0xFF1F2937)),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
                ) {
                    Text("←", fontSize = 22.sp)
                }
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
                modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 18.dp, bottom = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(activeCountText, modifier = Modifier.testTag("PackManagerActiveCount"), fontSize = 14.sp, color = Color(0xFF6B7280))
                Spacer(Modifier.weight(1f))
                Text("固定：防止满分自动轮换 · 开关：切换激活", fontSize = 12.sp, color = Color(0xFF9CA3AF))
            }
            if (message.isNotBlank()) {
                Text(message, color = Color(0xFFD94141), modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp).testTag("PackManagerLimitMessage"))
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
    onRedeem: (WishItem) -> Unit,
    onHistory: () -> Unit,
    onBack: () -> Unit,
) {
    BackHandler(enabled = giftBoxVisible) {}
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFFF6E7))
            .testTag("WishlistScreen"),
    ) {
        LazyColumn(Modifier.fillMaxSize().padding(horizontal = 40.dp, vertical = 20.dp)) {
            item {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Text("愿望", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
                    Spacer(Modifier.weight(1f))
                    Text("✨ ${coinAccount.balance}", modifier = Modifier.testTag("WishlistCoinBalance"), fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color(0xFF6A442B))
                    Spacer(Modifier.width(12.dp))
                    OutlinedButton(onClick = onHistory, modifier = Modifier.testTag("WishlistHistoryButton")) { Text("历史") }
                    Spacer(Modifier.width(8.dp))
                    OutlinedButton(onClick = onBack) { Text("返回") }
                }
                if (message.isNotBlank()) {
                    Text(message, modifier = Modifier.padding(top = 6.dp).testTag("WishlistMessage"), color = Color(0xFFD94141))
                }
            }
            items(wishlist.allWishes()) { wish ->
                Card(Modifier.fillMaxWidth().padding(vertical = 6.dp), shape = RoundedCornerShape(18.dp)) {
                    Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(44.dp).clip(CircleShape).background(Color(0xFFFFE0A6)), contentAlignment = Alignment.Center) {
                            Text(wish.icon.take(2), fontSize = 18.sp, textAlign = TextAlign.Center)
                        }
                        Spacer(Modifier.width(12.dp))
                        Text(wish.title, Modifier.weight(1f), fontSize = 19.sp, fontWeight = FontWeight.Bold, color = Color(0xFF3B2418))
                        Text("${wish.cost}", fontWeight = FontWeight.Black, color = Color(0xFF6A442B))
                        Spacer(Modifier.width(10.dp))
                        if (wish.id == recentlyRedeemedWishId) {
                            Text(
                                "已兑换 ✓",
                                modifier = Modifier
                                    .clip(RoundedCornerShape(16.dp))
                                    .background(Color(0xFFFFE0A6))
                                    .padding(horizontal = 14.dp, vertical = 8.dp)
                                    .testTag("WishRedeemed_${wish.id}"),
                                color = Color(0xFF6A442B),
                                fontWeight = FontWeight.Black,
                            )
                        } else {
                            Button(onClick = { onRedeem(wish) }, modifier = Modifier.testTag("WishRedeem_${wish.id}"), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050))) {
                                Text("兑换")
                            }
                        }
                    }
                }
            }
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
    LazyColumn(Modifier.fillMaxSize().background(Color.White).padding(24.dp).testTag("RedemptionHistoryScreen")) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text("兑换历史", fontSize = 28.sp, fontWeight = FontWeight.Black)
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onBack) { Text("返回") }
            }
        }
        if (history.records.isEmpty()) {
            item { Text("暂无兑换记录", Modifier.padding(top = 18.dp), color = Color(0xFF777777)) }
        }
        items(history.records) { record ->
            Text("${record.title} · -${record.cost} · ${record.status}", Modifier.padding(vertical = 8.dp).testTag("RedemptionRecord_${record.id}"))
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
            .background(Color.White)
            .padding(horizontal = 44.dp, vertical = 18.dp)
            .testTag("MonsterCodexScreen"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("怪物图鉴", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = onBack, modifier = Modifier.testTag("MonsterCodexBack")) { Text("返回") }
        }
        Spacer(Modifier.height(14.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CodexArrowButton(
                text = "⬅",
                enabled = hasPrevious,
                tag = "MonsterCodexPrevious",
                onClick = onPrevious,
            )
            Box(
                modifier = Modifier
                    .size(188.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(Color.White)
                    .border(1.dp, Color(0xFFE0E0E0), RoundedCornerShape(20.dp)),
                contentAlignment = Alignment.Center,
            ) {
                SvgRawImage(
                    monsterResource(context, current.rawResourceName),
                    modifier = Modifier
                        .height(152.dp)
                        .aspectRatio(1f)
                        .testTag("MonsterCodexImage"),
                )
            }
            CodexArrowButton(
                text = "➡",
                enabled = hasNext,
                tag = "MonsterCodexNext",
                onClick = onNext,
            )
        }
        Spacer(Modifier.height(16.dp))
        Text(current.nameEn, modifier = Modifier.testTag("MonsterCodexName"), fontSize = 30.sp, fontWeight = FontWeight.Bold, color = Color(0xFF1D3557))
        Text(
            "「${current.kindZh}」",
            modifier = Modifier
                .clip(RoundedCornerShape(12.dp))
                .background(Color(0xFFEAF2F8))
                .padding(horizontal = 12.dp, vertical = 4.dp)
                .testTag("MonsterCodexKind"),
            fontSize = 18.sp,
            color = Color(0xFF457B9D),
        )
        Text("${catalog.index + 1} / ${catalog.entries.size}", modifier = Modifier.testTag("MonsterCodexPosition"), fontSize = 14.sp, color = Color(0xFF888888))
        Text(
            current.descriptionZh,
            modifier = Modifier
                .fillMaxWidth(0.7f)
                .testTag("MonsterCodexDescription"),
            color = Color(0xFF333333),
            fontSize = 18.sp,
            lineHeight = 28.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun CodexArrowButton(text: String, enabled: Boolean, tag: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier
            .size(56.dp)
            .defaultMinSize(minWidth = 56.dp, minHeight = 56.dp)
            .testTag(tag),
        shape = CircleShape,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (enabled) Color(0xFFFCEAEA) else Color(0xFFEEEEEE),
            contentColor = if (enabled) Color(0xFFE63946) else Color(0xFF999999),
            disabledContainerColor = Color(0xFFEEEEEE),
            disabledContentColor = Color(0xFF999999),
        ),
    ) {
        Text(text, fontSize = 28.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
fun TodayPlanScreen(plan: TodayPlan, onReport: () -> Unit, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize().background(Color(0xFFFFF7E6)).padding(horizontal = 40.dp, vertical = 20.dp).testTag("TodayPlanScreen")) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text("今日计划", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
            Spacer(Modifier.weight(1f))
            Button(onClick = onReport, modifier = Modifier.testTag("TodayPlanReportButton"), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050))) { Text("学习报告") }
            Spacer(Modifier.width(8.dp))
            OutlinedButton(onClick = onBack) { Text("返回") }
        }
        PlanBucket("复习", plan.review.map { it.word }, "TodayPlanReviewBucket")
        PlanBucket("学习中", plan.learning.map { it.word }, "TodayPlanLearningBucket")
        PlanBucket("新单词", plan.newWords.map { it.word }, "TodayPlanNewBucket")
    }
}

@Composable
fun LearningReportScreen(report: LearningReport, onBack: () -> Unit) {
    LazyColumn(Modifier.fillMaxSize().background(Color.White).padding(horizontal = 40.dp, vertical = 20.dp).testTag("LearningReportScreen")) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text("学习报告", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onBack) { Text("返回") }
            }
            Text("单词 ${report.totalSeenWords}/${report.totalWords}", modifier = Modifier.padding(top = 10.dp).testTag("LearningReportTotalWords"), fontWeight = FontWeight.Bold)
            Text("正确率 ${report.accuracyPercent}%", modifier = Modifier.testTag("LearningReportAccuracy"), color = Color(0xFF6A5843))
        }
        items(report.packRows) { row ->
            Card(Modifier.fillMaxWidth().padding(vertical = 6.dp).testTag("LearningReportPackRow_${row.packId}"), colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF7E6))) {
                Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(row.nameEn, Modifier.weight(1f), fontWeight = FontWeight.Black)
                    Text("${row.seenWords}/${row.totalWords} · ${row.accuracyPercent}%")
                }
            }
        }
    }
}

@Composable
private fun PlanBucket(title: String, words: List<String>, tag: String) {
    Card(Modifier.fillMaxWidth().padding(vertical = 8.dp).testTag(tag), colors = CardDefaults.cardColors(containerColor = Color.White)) {
        Column(Modifier.padding(14.dp)) {
            Text(title, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
            Text(if (words.isEmpty()) "暂无" else words.joinToString(" / "), color = Color(0xFF6A5843))
        }
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
