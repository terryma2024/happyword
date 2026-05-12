package cool.happyword.wordmagic.ui

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.annotation.RawRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
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
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(horizontal = 38.dp, vertical = 18.dp)
            .testTag("PackManagerScreen"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text("我的词包", modifier = Modifier.testTag("PackManagerTitle"), fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
                Spacer(Modifier.width(14.dp))
                Text("${selection.activePackIds.size}/5", modifier = Modifier.testTag("PackManagerActiveCount"), color = Color(0xFF6A5843), fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onSync, modifier = Modifier.testTag("PackManagerSyncButton")) { Text("同步") }
                Spacer(Modifier.width(8.dp))
                OutlinedButton(onClick = onBack, modifier = Modifier.testTag("PackManagerBack")) { Text("返回") }
            }
            if (message.isNotBlank()) {
                Text(message, color = Color(0xFFD94141), modifier = Modifier.padding(top = 6.dp).testTag("PackManagerLimitMessage"))
            } else {
                Text("本地词包已就绪", color = Color(0xFF777777), modifier = Modifier.padding(top = 6.dp).testTag("PackManagerStatus"))
            }
        }
        items(packs) { pack ->
            Card(
                colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF7E6)),
                shape = RoundedCornerShape(18.dp),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
                modifier = Modifier.border(1.dp, Color(0xFFFFD2A6), RoundedCornerShape(18.dp)),
            ) {
                Row(Modifier.fillMaxWidth().padding(14.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(pack.nameEn, modifier = Modifier.testTag("PackLabel_${pack.id}"), fontSize = 20.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
                        Text("${pack.nameZh} · ${sourceLabel(pack.source.name)} · ${pack.scene.storyZh}", modifier = Modifier.testTag("PackSourceTag_${pack.id}"), color = Color(0xFF6A5843))
                    }
                    Switch(
                        checked = pack.id in selection.activePackIds,
                        onCheckedChange = { onToggleActive(pack) },
                        modifier = Modifier.testTag("PackToggle_${pack.id}"),
                    )
                    if (pack.id in selection.activePackIds) {
                        Spacer(Modifier.width(8.dp))
                        OutlinedButton(onClick = { onTogglePin(pack) }, modifier = Modifier.testTag("PackPin_${pack.id}")) {
                            Text(if (pack.id in selection.pinnedPackIds) "已固定" else "固定")
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun WishlistScreen(
    coinAccount: CoinAccount,
    wishlist: WishlistState,
    message: String,
    onRedeem: (WishItem) -> Unit,
    onHistory: () -> Unit,
    onBack: () -> Unit,
) {
    LazyColumn(Modifier.fillMaxSize().background(Color(0xFFFFF6E7)).padding(horizontal = 40.dp, vertical = 20.dp).testTag("WishlistScreen")) {
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
                    Button(onClick = { onRedeem(wish) }, modifier = Modifier.testTag("WishRedeem_${wish.id}"), colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050))) {
                        Text("兑换")
                    }
                }
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
