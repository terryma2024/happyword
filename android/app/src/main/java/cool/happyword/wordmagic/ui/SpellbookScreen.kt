package cool.happyword.wordmagic.ui

import androidx.annotation.DrawableRes
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.SpellbookCardState
import cool.happyword.wordmagic.core.SpellbookRewardSnapshot
import cool.happyword.wordmagic.core.SpellbookService
import cool.happyword.wordmagic.core.WordEntry
import cool.happyword.wordmagic.core.WordLearningStat
import cool.happyword.wordmagic.core.WordPack

@Composable
internal fun SpellbookScreen(
    packs: List<WordPack>,
    stats: List<WordLearningStat>,
    rewards: SpellbookRewardSnapshot,
    coinAccount: CoinAccount,
    coverCacheVersion: Int = 0,
    onClaimReward: (WordPack) -> Unit,
    onBack: () -> Unit,
) {
    var selected by remember { mutableStateOf<SpellbookWordSelection?>(null) }
    var lockedTipVisible by remember { mutableStateOf(false) }
    val statsByPack = remember(stats) {
        stats.groupBy { it.packId }.mapValues { (_, rows) -> rows.associateBy { it.wordId } }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFFF6E7))
            .padding(horizontal = 28.dp, vertical = 18.dp)
            .testTag("SpellbookPage"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            HarmonyPageTopBackButton(modifier = Modifier.testTag("SpellbookBackButton"), onClick = onBack)
            Text(
                "魔法书图鉴",
                modifier = Modifier.testTag("SpellbookTitle"),
                fontSize = 28.sp,
                fontWeight = FontWeight.Black,
                color = Color(0xFF2F2A27),
            )
            Spacer(Modifier.weight(1f))
            Text(
                "✨ ${coinAccount.balance}",
                modifier = Modifier
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color(0xFFFFF6E5))
                    .padding(horizontal = 12.dp, vertical = 7.dp),
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFFFFB400),
            )
        }

        if (lockedTipVisible) {
            Text(
                "先在冒险或复习里遇见这个单词，就能点亮它。",
                modifier = Modifier
                    .padding(top = 10.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color(0xFFFFE8BC))
                    .padding(horizontal = 14.dp, vertical = 8.dp)
                    .testTag("SpellbookLockedTip"),
                color = Color(0xFF6D3B05),
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(top = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(packs, key = { it.id }) { pack ->
                PackSpellbookCard(
                    pack = pack,
                    statsByWordId = statsByPack[pack.id].orEmpty(),
                    rewards = rewards,
                    coverCacheVersion = coverCacheVersion,
                    onClaimReward = { onClaimReward(pack) },
                    onLocked = { lockedTipVisible = true },
                    onWord = { selected = it },
                )
            }
        }
    }

    selected?.let { selection ->
        AlertDialog(
            onDismissRequest = { selected = null },
            confirmButton = {
                TextButton(modifier = Modifier.testTag("SpellbookWordDetailClose"), onClick = { selected = null }) {
                    Text("关闭")
                }
            },
            title = {
                Text(
                    selection.word.word,
                    modifier = Modifier.testTag("SpellbookWordDetailTitle"),
                    fontWeight = FontWeight.Black,
                    fontSize = 28.sp,
                )
            },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(selection.word.meaning, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    Text(
                        if (selection.state == SpellbookCardState.Mastered) "已精通" else "已点亮",
                        modifier = Modifier.testTag("SpellbookWordDetailState"),
                        color = if (selection.state == SpellbookCardState.Mastered) Color(0xFF16803A) else Color(0xFF2563EB),
                        fontWeight = FontWeight.Bold,
                    )
                    selection.word.example?.let {
                        Text(it.en, color = Color(0xFF332C26), fontWeight = FontWeight.SemiBold)
                        Text(it.zh, color = Color(0xFF6B625B), fontWeight = FontWeight.SemiBold)
                    }
                }
            },
            modifier = Modifier.testTag("SpellbookWordDetailSheet"),
        )
    }
}

@Composable
private fun PackSpellbookCard(
    pack: WordPack,
    statsByWordId: Map<String, WordLearningStat>,
    rewards: SpellbookRewardSnapshot,
    coverCacheVersion: Int,
    onClaimReward: () -> Unit,
    onLocked: () -> Unit,
    onWord: (SpellbookWordSelection) -> Unit,
) {
    val progress = SpellbookService.progress(pack.words, statsByWordId)
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.86f)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                SpellbookCover(pack = pack, cacheVersion = coverCacheVersion, modifier = Modifier.testTag("SpellbookPackCover_${pack.id}"))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(pack.nameEn, fontSize = 20.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        "${progress.masteredCount}/${progress.totalCount} 已精通",
                        modifier = Modifier.testTag("SpellbookPackProgress_${pack.id}"),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color(0xFF746A62),
                    )
                }
                if (rewards.isClaimed(pack.id)) {
                    Text(
                        "已领取",
                        modifier = Modifier
                            .clip(RoundedCornerShape(16.dp))
                            .background(Color(0xFFE8F8EE))
                            .padding(horizontal = 12.dp, vertical = 8.dp)
                            .testTag("SpellbookPackRewardClaimed_${pack.id}"),
                        color = Color(0xFF16803A),
                        fontWeight = FontWeight.Black,
                    )
                } else {
                    Button(
                        modifier = Modifier.testTag("SpellbookPackRewardButton_${pack.id}"),
                        enabled = progress.isComplete,
                        onClick = onClaimReward,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050), disabledContainerColor = Color(0xFFB8B1AC)),
                    ) { Text("+50", fontWeight = FontWeight.Black) }
                }
            }

            pack.words.chunked(SPELLBOOK_WORDS_PER_ROW).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                    row.forEach { word ->
                        val state = SpellbookService.cardState(word, statsByWordId[word.id])
                        WordSpellbookCard(
                            modifier = Modifier.weight(1f),
                            packId = pack.id,
                            word = word,
                            state = state,
                            onLocked = onLocked,
                            onWord = { onWord(SpellbookWordSelection(pack, word, state)) },
                        )
                    }
                    repeat(SPELLBOOK_WORDS_PER_ROW - row.size) {
                        Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

private const val SPELLBOOK_WORDS_PER_ROW = 8

@Composable
private fun WordSpellbookCard(
    modifier: Modifier,
    packId: String,
    word: WordEntry,
    state: SpellbookCardState,
    onLocked: () -> Unit,
    onWord: () -> Unit,
) {
    val stateTag = when (state) {
        SpellbookCardState.Locked -> "SpellbookCardLocked_${packId}_${word.id}"
        SpellbookCardState.Seen -> "SpellbookCardSeen_${packId}_${word.id}"
        SpellbookCardState.Mastered -> "SpellbookCardMastered_${packId}_${word.id}"
    }
    Column(
        modifier = modifier
            .height(76.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(
                when (state) {
                    SpellbookCardState.Locked -> Color(0xFFE8E3DE)
                    SpellbookCardState.Seen -> Color(0xFFE0F2FE)
                    SpellbookCardState.Mastered -> Color(0xFFE8F8EE)
                },
            )
            .clickable { if (state == SpellbookCardState.Locked) onLocked() else onWord() }
            .padding(8.dp)
            .testTag("SpellbookCard_${packId}_${word.id}"),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            if (state == SpellbookCardState.Locked) "?" else word.word,
            fontSize = 16.sp,
            fontWeight = FontWeight.Black,
            color = if (state == SpellbookCardState.Locked) Color(0xFF8A817A) else Color(0xFF2F2A27),
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            when (state) {
                SpellbookCardState.Locked -> "未点亮"
                SpellbookCardState.Seen -> "已点亮"
                SpellbookCardState.Mastered -> "已精通"
            },
            modifier = Modifier.testTag(stateTag),
            fontSize = 11.sp,
            fontWeight = FontWeight.Bold,
            color = if (state == SpellbookCardState.Mastered) Color(0xFF16803A) else Color(0xFF746A62),
        )
    }
}

@Composable
private fun SpellbookCover(pack: WordPack, cacheVersion: Int, modifier: Modifier = Modifier) {
    SpellbookCoverImage(
        pack = pack,
        cacheVersion = cacheVersion,
        contentDescription = pack.id,
        modifier = modifier
            .size(72.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White.copy(alpha = 0.62f))
            .padding(4.dp),
        contentScale = ContentScale.Fit,
    )
}

internal data class SpellbookWordSelection(
    val pack: WordPack,
    val word: WordEntry,
    val state: SpellbookCardState,
)

@DrawableRes
internal fun spellbookCoverDrawableId(packId: String): Int = when (packId) {
    "fruit-forest" -> R.drawable.spellbook_cover_fruit_forest
    "school-castle" -> R.drawable.spellbook_cover_school_castle
    "home-cottage" -> R.drawable.spellbook_cover_home_cottage
    "animal-safari" -> R.drawable.spellbook_cover_animal_safari
    "ocean-realm" -> R.drawable.spellbook_cover_ocean_realm
    else -> R.drawable.spellbook_cover_default
}
