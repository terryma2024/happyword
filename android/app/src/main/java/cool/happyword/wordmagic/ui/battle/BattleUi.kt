package cool.happyword.wordmagic.ui.battle

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.content.pm.ActivityInfo
import android.content.res.Resources
import android.graphics.Bitmap
import android.graphics.Canvas
import android.media.MediaPlayer
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import android.view.WindowManager
import android.widget.Toast
import androidx.annotation.DrawableRes
import androidx.annotation.RawRes
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.caverock.androidsvg.SVG
import cool.happyword.wordmagic.app.BuildGate
import cool.happyword.wordmagic.app.BuildInfo
import cool.happyword.wordmagic.core.BattleSessionRecord
import cool.happyword.wordmagic.core.BattleAnswerOutcome
import cool.happyword.wordmagic.core.BattleEngine
import cool.happyword.wordmagic.core.BattleState
import cool.happyword.wordmagic.core.BattleStatus
import cool.happyword.wordmagic.core.BackendEnv
import cool.happyword.wordmagic.core.BackendHeaderProvider
import cool.happyword.wordmagic.core.BackendRouteState
import cool.happyword.wordmagic.core.BackendURLProvider
import cool.happyword.wordmagic.core.BindingResult
import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.ChildProfileClient
import cool.happyword.wordmagic.core.ChildProfileException
import cool.happyword.wordmagic.core.CloudSyncCoordinator
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.DevMenuRouteParams
import cool.happyword.wordmagic.core.DevMenuViewModel
import cool.happyword.wordmagic.core.VersionTripleTap
import cool.happyword.wordmagic.core.DeviceBindingClient
import cool.happyword.wordmagic.core.BattleQuestionTypePolicy
import cool.happyword.wordmagic.core.CustomWishRules
import cool.happyword.wordmagic.core.GameConfig
import cool.happyword.wordmagic.core.LearningRecorder
import cool.happyword.wordmagic.core.LearningReportBuilder
import cool.happyword.wordmagic.core.MonsterCatalog
import cool.happyword.wordmagic.core.MonsterEntry
import cool.happyword.wordmagic.core.PackLibrary
import cool.happyword.wordmagic.core.PackSelectionStore
import cool.happyword.wordmagic.core.ParentPinStore
import cool.happyword.wordmagic.core.Question
import cool.happyword.wordmagic.core.QuestionKind
import cool.happyword.wordmagic.core.RedemptionHistoryStore
import cool.happyword.wordmagic.core.SessionResult
import cool.happyword.wordmagic.core.TodayPlanService
import cool.happyword.wordmagic.core.WishlistState
import cool.happyword.wordmagic.core.WordPack
import cool.happyword.wordmagic.core.tryAddCustomWish
import cool.happyword.wordmagic.core.removeCustomWish
import cool.happyword.wordmagic.ui.CenteredCircleTextButton
import cool.happyword.wordmagic.ui.HarmonyPageTopBackButton
import cool.happyword.wordmagic.ui.circleGlyphTextStyle
import cool.happyword.wordmagic.core.WordStatsSyncClient
import cool.happyword.wordmagic.core.WordStatsSyncResult
import cool.happyword.wordmagic.core.WordStatsSyncStatus
import cool.happyword.wordmagic.data.AndroidCloudRepositories
import cool.happyword.wordmagic.data.AndroidDebugRoutingRepository
import cool.happyword.wordmagic.data.AndroidLocalProgressRepositories
import cool.happyword.wordmagic.ui.BypassSecretScreen
import cool.happyword.wordmagic.ui.BoundDeviceInfoScreen
import cool.happyword.wordmagic.ui.DevMenuScreen
import cool.happyword.wordmagic.ui.LearningReportScreen
import cool.happyword.wordmagic.ui.MonsterCodexScreen
import cool.happyword.wordmagic.ui.PageChromeInsets
import cool.happyword.wordmagic.ui.PackManagerScreen
import cool.happyword.wordmagic.ui.RedemptionHistoryScreen
import cool.happyword.wordmagic.ui.ScanBindingScreen
import cool.happyword.wordmagic.ui.TodayPlanScreen
import cool.happyword.wordmagic.ui.WishlistScreen
import java.io.File
import java.text.SimpleDateFormat
import java.time.LocalDate
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.ui.navigation.BATTLE_FEEDBACK_MS
import cool.happyword.wordmagic.ui.navigation.PROJECTILE_IMPACT_MS
import cool.happyword.wordmagic.ui.navigation.DEFAULT_BATTLE_TIMER_SECONDS
import cool.happyword.wordmagic.ui.components.Badge
import cool.happyword.wordmagic.ui.components.CharacterPanel
import cool.happyword.wordmagic.ui.components.MessageBubble
import cool.happyword.wordmagic.ui.circleGlyphTextStyle

object BattleBossIntroLayoutSpec {
    const val bubbleXRatio: Float = 0.56f
    const val bubbleYRatio: Float = 0.10f
    const val bubbleWidthDp: Float = 224f
    const val bubbleHeightDp: Float = 96f
    const val bubbleZIndex: Float = 4f
    const val levelTagZIndex: Float = 1f
    const val levelTagStartGapDp: Float = 8f
    const val levelTagCornerRadiusDp: Float = 14f
}

@Composable
@Suppress("UNUSED_PARAMETER")
internal fun BattleScreen(
    runId: Int,
    state: BattleState,
    pack: WordPack,
    config: GameConfig,
    timeLeft: Int,
    onAnswer: (String) -> BattleAnswerOutcome,
    onSpellWrongTap: () -> BattleAnswerOutcome,
    onBattleFinished: (BattleState) -> Unit,
    onEscape: () -> Unit,
) {
    val context = LocalContext.current
    var activeOutcome by remember(runId) { mutableStateOf<BattleAnswerOutcome?>(null) }
    var introBubbleCatalogIndex by remember(runId) { mutableStateOf<Int?>(null) }
    var introShownCatalogIndices by remember(runId) { mutableStateOf(emptySet<Int>()) }
    var playerFloaters by remember(runId) { mutableStateOf(emptyList<FloaterPending>()) }
    var monsterFloaters by remember(runId) { mutableStateOf(emptyList<FloaterPending>()) }
    var nextFloaterKey by remember(runId) { mutableIntStateOf(0) }
    val battleAudioMixer = remember(runId) { AndroidBattleAudioMixer(context.applicationContext) }
    val speakWord: (String) -> Unit = { word ->
        battleAudioMixer.speakWord(word)
    }

    DisposableEffect(battleAudioMixer) {
        battleAudioMixer.enter(config)
        onDispose {
            battleAudioMixer.dispose()
        }
    }
    LaunchedEffect(battleAudioMixer, config) {
        battleAudioMixer.updateConfig(config)
    }
    LaunchedEffect(activeOutcome) {
        val outcome = activeOutcome ?: return@LaunchedEffect
        if (outcome.advancedStep) {
            delay(180)
            activeOutcome = null
            return@LaunchedEffect
        }
        if (outcome.correct) {
            delay(PROJECTILE_IMPACT_MS)
            val pushed = pushBattleFloater(monsterFloaters, nextFloaterKey, outcome.damage)
            monsterFloaters = pushed.first
            nextFloaterKey = pushed.second
            battleAudioMixer.playSfx(if (outcome.comboTriggered) R.raw.hit_crit else R.raw.hit_normal)
            if (outcome.monsterDefeated && !outcome.battleEnded) {
                delay(120)
                battleAudioMixer.playSfx(R.raw.monster_defeat)
            }
        } else {
            battleAudioMixer.playSfx(R.raw.answer_wrong)
            delay(PROJECTILE_IMPACT_MS)
            if (outcome.playerDamaged) {
                val pushed = pushBattleFloater(playerFloaters, nextFloaterKey, outcome.damage)
                playerFloaters = pushed.first
                nextFloaterKey = pushed.second
            }
            battleAudioMixer.playSfx(R.raw.player_hurt)
        }
        val remainingFeedback = BATTLE_FEEDBACK_MS - PROJECTILE_IMPACT_MS
        if (remainingFeedback > 0) {
            delay(remainingFeedback)
        }
        val finishedState = outcome.nextState
        activeOutcome = null
        if (finishedState.status != BattleStatus.Playing) {
            if (finishedState.status == BattleStatus.Won) {
                battleAudioMixer.playVictory()
            } else {
                battleAudioMixer.playDefeat()
            }
            onBattleFinished(finishedState)
        }
    }
    LaunchedEffect(runId, state.monsterCatalogIndex, activeOutcome == null) {
        if (activeOutcome != null || state.status != BattleStatus.Playing) return@LaunchedEffect
        if (state.monsterCatalogIndex in introShownCatalogIndices) {
            introBubbleCatalogIndex = null
            return@LaunchedEffect
        }
        introShownCatalogIndices = introShownCatalogIndices + state.monsterCatalogIndex
        introBubbleCatalogIndex = state.monsterCatalogIndex
        delay(1_200)
        if (introBubbleCatalogIndex == state.monsterCatalogIndex) {
            introBubbleCatalogIndex = null
        }
    }
    LaunchedEffect(runId, state.question.correctAnswer, state.question.kind, config.autoPronunciation, activeOutcome) {
        if (
            config.autoPronunciation &&
            activeOutcome == null &&
            state.status == BattleStatus.Playing &&
            state.question.kind != QuestionKind.SentenceCloze
        ) {
            delay(250)
            speakWord(state.question.correctAnswer)
        }
    }

    val displayQuestion = if (activeOutcome?.advancedStep == true) state.question else activeOutcome?.question ?: state.question
    val feedbackLocked = activeOutcome != null
    val monsterCatalog = remember { MonsterCatalog.default() }
    val currentMonster = remember(state.monsterCatalogIndex) {
        monsterCatalog.entries[Math.floorMod(state.monsterCatalogIndex - 1, monsterCatalog.entries.size)]
    }

    BoxWithConstraints(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF9FAFC))
            .padding(horizontal = PageChromeInsets.homeAlignedHorizontal, vertical = 14.dp)
            .testTag("BattleScreen"),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Badge("Combo ${state.combo}")
                Spacer(Modifier.weight(1f))
                Text("Battle", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color(0xFF1C3655))
                Spacer(Modifier.weight(1f))
                Badge("Time ${formatCountdown(timeLeft)}")
                Spacer(Modifier.width(8.dp))
                OutlinedButton(
                    onClick = onEscape,
                    enabled = !feedbackLocked,
                    modifier = Modifier.testTag("BattleEscapeButton"),
                ) {
                    Text("Escape")
                }
            }
            Spacer(Modifier.height(18.dp))
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(30.dp)) {
                    Box(modifier = Modifier.weight(0.86f)) {
                        CharacterPanel(
                            title = "Small Magician",
                            hp = state.playerHp,
                            maxHp = config.playerHp,
                            image = R.raw.character_magican,
                            fightImage = R.raw.character_magican_fight,
                            hurtImage = R.raw.character_magican_beaten,
                            modifier = Modifier.fillMaxSize(),
                            panelColor = Color(0xFFDCEEFF),
                            borderColor = Color(0xFFA8CCF0),
                            isCasting = activeOutcome?.correct == true,
                            isCritCasting = activeOutcome?.comboTriggered == true,
                            isHurt = activeOutcome?.playerDamaged == true,
                        )
                        DamageFloaterStack(
                            floaters = playerFloaters,
                            side = BattleFloaterSide.Player,
                            modifier = Modifier
                                .align(Alignment.TopCenter)
                                .offset(y = (-10).dp),
                            onDispose = { key -> playerFloaters = playerFloaters.filter { it.id != key } },
                        )
                    }
                    Box(
                        modifier = Modifier
                            .weight(1.58f)
                            .fillMaxHeight(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.Center,
                        ) {
                            Text("Question", color = Color(0xFF4B86B4), fontSize = 20.sp)
                            Spacer(Modifier.height(12.dp))
                            BattleQuestionPrompt(displayQuestion)
                            if (displayQuestion.kind == QuestionKind.Spell) {
                                Spacer(Modifier.height(8.dp))
                                SpellAnswerArea(
                                    question = displayQuestion,
                                    feedbackLocked = feedbackLocked,
                                    onWrongLetterTap = {
                                        if (activeOutcome == null) {
                                            activeOutcome = onSpellWrongTap()
                                        }
                                    },
                                    onComplete = { option ->
                                        if (activeOutcome == null) {
                                            activeOutcome = onAnswer(option)
                                        }
                                    },
                                )
                            }
                            Spacer(Modifier.height(12.dp))
                            activeOutcome?.let { outcome ->
                                BattleFeedbackText(outcome)
                                Spacer(Modifier.height(8.dp))
                            }
                            Box(
                                modifier = Modifier
                                    .size(58.dp)
                                    .clip(CircleShape)
                                    .background(Color(0xFFEFF8FC))
                                    .clickable(enabled = !feedbackLocked) { speakWord(state.question.correctAnswer) }
                                    .testTag("BattleSpeakerButton"),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text("🔊", style = circleGlyphTextStyle(30.sp))
                            }
                            Spacer(Modifier.height(18.dp))
                            Text("Monster ${state.monsterIndex} / ${config.monsterCount}", color = Color(0xFF777777), fontSize = 18.sp)
                        }
                    }
                    Box(modifier = Modifier.weight(0.86f)) {
                        CharacterPanel(
                            title = currentMonster.nameEn,
                            hp = state.monsterHp,
                            maxHp = config.monsterHp,
                            image = monsterResourceForEntry(currentMonster, context.packageName, context.resources),
                            modifier = Modifier.fillMaxSize(),
                            panelColor = Color(0xFFF7D2D2),
                            borderColor = Color(0xFFEAA0A0),
                            titleModifier = Modifier.testTag("BattleMonsterName"),
                            titleAccessory = {
                                BattleMonsterLevelTag(currentMonster.battleLevelLabel)
                            },
                            isHurt = activeOutcome?.correct == true && activeOutcome?.comboTriggered != true,
                            isZoomHit = activeOutcome?.comboTriggered == true,
                        )
                        DamageFloaterStack(
                            floaters = monsterFloaters,
                            side = BattleFloaterSide.Monster,
                            modifier = Modifier
                                .align(Alignment.TopCenter)
                                .offset(y = (-12).dp),
                            onDispose = { key -> monsterFloaters = monsterFloaters.filter { it.id != key } },
                        )
                        if (state.currentMonsterBonus) {
                            Text(
                                "Bonus",
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .clip(RoundedCornerShape(14.dp))
                                    .background(Color(0xFFFFB400))
                                    .padding(horizontal = 8.dp, vertical = 4.dp)
                                    .testTag("MonsterBonusStar_${state.monsterIndex}"),
                                color = Color.White,
                                fontSize = 12.sp,
                                fontWeight = FontWeight.Bold,
                            )
                        }
                    }
                }
                BattleProjectileOverlay(outcome = activeOutcome, modifier = Modifier.fillMaxSize().zIndex(2f))
            }
            Spacer(Modifier.height(10.dp))
            BattleAnswerArea(
                question = displayQuestion,
                feedbackLocked = feedbackLocked,
                outcome = activeOutcome,
                onSelect = { option ->
                    if (activeOutcome == null) {
                        activeOutcome = onAnswer(option)
                    }
                },
            )
        }
        if (introBubbleCatalogIndex == state.monsterCatalogIndex && activeOutcome == null) {
            BossIntroBubble(
                monster = currentMonster,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .offset(
                        x = maxWidth * BattleBossIntroLayoutSpec.bubbleXRatio,
                        y = maxHeight * BattleBossIntroLayoutSpec.bubbleYRatio,
                    )
                    .zIndex(BattleBossIntroLayoutSpec.bubbleZIndex),
            )
        }
        CritBurstOverlay(outcome = activeOutcome, modifier = Modifier.fillMaxSize().zIndex(4f))
    }
}

@Composable
private fun BattleMonsterLevelTag(label: String) {
    Text(
        label,
        modifier = Modifier
            .clip(RoundedCornerShape(BattleBossIntroLayoutSpec.levelTagCornerRadiusDp.dp))
            .background(Color(0xFF008EB1))
            .padding(horizontal = 8.dp, vertical = 3.dp)
            .zIndex(BattleBossIntroLayoutSpec.levelTagZIndex)
            .testTag("BattleMonsterLevelLabel"),
        color = Color.White,
        fontSize = 12.sp,
        fontWeight = FontWeight.Black,
    )
}

@Composable
private fun BossIntroBubble(monster: MonsterEntry, modifier: Modifier = Modifier) {
    MessageBubble(
        modifier = modifier.testTag("BattleBossIntroBubble"),
        width = BattleBossIntroLayoutSpec.bubbleWidthDp.dp,
        height = BattleBossIntroLayoutSpec.bubbleHeightDp.dp,
        radius = 18.dp,
        borderWidth = 1.dp,
        fillColor = Color(0xFFFFFDF6),
        strokeColor = Color(0xFFE7D7B6),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Text(
                monster.nameEn,
                modifier = Modifier.testTag("BattleBossIntroName"),
                color = Color(0xFF69451B),
                fontSize = 14.sp,
                fontWeight = FontWeight.Black,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                monster.dialogue.introLine.en,
                modifier = Modifier.testTag("BattleBossIntroLineEn"),
                color = Color(0xFF233D63),
                fontSize = 15.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                monster.dialogue.introLine.zh,
                modifier = Modifier.testTag("BattleBossIntroLineZh"),
                color = Color(0xFF7A653D),
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
internal fun BattleQuestionPrompt(question: Question) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        when (question.kind) {
            QuestionKind.Choice, QuestionKind.Spell -> {
                Text(
                    question.prompt,
                    fontSize = 42.sp,
                    fontWeight = FontWeight.Black,
                    color = Color(0xFF1C3655),
                    textAlign = TextAlign.Center,
                )
            }
            QuestionKind.SentenceCloze -> {
                Text(
                    question.sentenceTemplate,
                    modifier = Modifier.testTag("BattleSentenceClozePrompt"),
                    fontSize = 34.sp,
                    lineHeight = 44.sp,
                    fontWeight = FontWeight.Black,
                    color = Color(0xFF1C3655),
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(8.dp))
                Text(
                    question.sentenceZh,
                    modifier = Modifier.testTag("BattleSentenceClozeZh"),
                    color = Color(0xFF6A5843),
                    fontSize = 18.sp,
                    fontWeight = FontWeight.Bold,
                    textAlign = TextAlign.Center,
                )
            }
            QuestionKind.FillLetter, QuestionKind.FillLetterMedium -> {
                Text(question.prompt, color = Color(0xFF6A5843), fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(6.dp))
                LetterTemplateRow(
                    template = if (question.kind == QuestionKind.FillLetter) question.letterTemplate else question.letterTemplateBase,
                    missingIndex = letterMissingIndex(question),
                    pendingIndex = letterPendingIndex(question),
                )
            }
        }
    }
}

@Composable
private fun LetterTemplateRow(template: String, missingIndex: Int, pendingIndex: Int) {
    val slots = LetterTemplateLayout.slots(template, missingIndex, pendingIndex)
    val metrics = LetterTemplateLayout.metricsForGlyphCount(slots.size)
    Row(
        horizontalArrangement = Arrangement.spacedBy(metrics.gap.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .testTag("BattleLetterTemplate"),
    ) {
        slots.forEach { slot ->
            LetterTemplateSlotView(slot = slot, metrics = metrics)
        }
    }
}

@Composable
private fun LetterTemplateSlotView(slot: LetterTemplateSlot, metrics: LetterTemplateMetrics) {
    Box(
        modifier = Modifier
            .width(metrics.width.dp)
            .height(metrics.height.dp)
            .testTag("BattleLetterSlot_${slot.originalIndex}"),
        contentAlignment = Alignment.Center,
    ) {
        when {
            slot.glyph == " " -> Unit
            slot.isMissing -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xFFFCEAEA), RoundedCornerShape(6.dp)),
                )
                Text(
                    "_",
                    modifier = Modifier.testTag("BattleLetterSlotText_${slot.originalIndex}"),
                    fontSize = metrics.placeholderFontSize.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFFE63946),
                    textAlign = TextAlign.Center,
                )
            }
            slot.isPending -> {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(0xFFF1F3F5), RoundedCornerShape(6.dp)),
                )
                Text(
                    if (slot.glyph == "_") "_" else slot.glyph,
                    modifier = Modifier.testTag("BattleLetterSlotText_${slot.originalIndex}"),
                    fontSize = metrics.placeholderFontSize.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFFA3A3A3),
                    textAlign = TextAlign.Center,
                )
            }
            else -> {
                Text(
                    slot.glyph,
                    modifier = Modifier.testTag("BattleLetterSlotText_${slot.originalIndex}"),
                    fontSize = metrics.filledFontSize.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color(0xFF1D3557),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

private fun letterMissingIndex(question: Question): Int {
    return when (question.kind) {
        QuestionKind.FillLetter -> question.missingIndex
        QuestionKind.FillLetterMedium -> question.missingIndices.getOrElse(question.currentStep) { -1 }
        else -> -1
    }
}

private fun letterPendingIndex(question: Question): Int {
    if (question.kind != QuestionKind.FillLetterMedium) return -1
    val pendingStep = if (question.currentStep == 0) 1 else 0
    return question.missingIndices.getOrElse(pendingStep) { -1 }
}

@Composable
internal fun BattleAnswerArea(
    question: Question,
    feedbackLocked: Boolean,
    outcome: BattleAnswerOutcome?,
    onSelect: (String) -> Unit,
) {
    if (question.kind == QuestionKind.Spell) {
        Spacer(
            modifier = Modifier
                .fillMaxWidth()
                .height(20.dp)
                .testTag("BattleOptionsRow_SpellPlaceholder"),
        )
        return
    }
    val options = answerOptions(question)
    val rowTag = if (question.kind == QuestionKind.SentenceCloze) {
        "BattleOptionsRow_SentenceCloze"
    } else {
        "BattleOptionsRow"
    }
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth().testTag(rowTag)) {
        options.forEachIndexed { index, option ->
            val buttonColor = answerButtonColor(option, outcome)
            val buttonTag = if (question.kind == QuestionKind.SentenceCloze) {
                "BattleSentenceClozeOption_$index"
            } else {
                "BattleAnswer_$index"
            }
            Button(
                onClick = { onSelect(option) },
                enabled = !feedbackLocked,
                modifier = Modifier
                    .weight(1f)
                    .height(58.dp)
                    .testTag(buttonTag),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = buttonColor,
                    disabledContainerColor = buttonColor,
                    disabledContentColor = Color.White,
                ),
            ) {
                Text(option, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
internal fun SpellAnswerArea(
    question: Question,
    feedbackLocked: Boolean,
    onWrongLetterTap: () -> Unit,
    onComplete: (String) -> Unit,
) {
    var slots by remember(question.wordId, question.correctAnswer) {
        mutableStateOf(question.spellLetters.mapIndexed { index, letter ->
            if (question.spellRevealedMask.getOrElse(index) { false }) letter else ""
        })
    }
    var consumed by remember(question.wordId, question.correctAnswer) {
        mutableStateOf(List(question.spellPool.size) { false })
    }
    var wrongPoolIndex by remember(question.wordId, question.correctAnswer) { mutableIntStateOf(-1) }
    var completed by remember(question.wordId, question.correctAnswer) { mutableStateOf(false) }
    LaunchedEffect(wrongPoolIndex) {
        if (wrongPoolIndex >= 0) {
            delay(220)
            wrongPoolIndex = -1
        }
    }
    LaunchedEffect(completed) {
        if (completed) {
            delay(200)
            onComplete(question.correctAnswer)
        }
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .testTag("BattleSpellArea"),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            slots.forEachIndexed { index, value ->
                Box(
                    modifier = Modifier
                        .width(36.dp)
                        .height(48.dp)
                        .clip(RoundedCornerShape(6.dp))
                        .background(if (value.isNotBlank()) Color.White else Color(0xFFFCEAEA))
                        .border(1.dp, Color(0xFFD9D9D9), RoundedCornerShape(6.dp))
                        .testTag("BattleSpellSlot_$index"),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        value.ifBlank { "_" },
                        modifier = Modifier.testTag("BattleSpellSlotText_$index"),
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Black,
                        color = if (value.isNotBlank()) Color(0xFF1D3557) else Color(0xFFE63946),
                    )
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            question.spellPool.forEachIndexed { index, letter ->
                val used = consumed.getOrElse(index) { false }
                val wrong = wrongPoolIndex == index
                val nextSlot = slots.indexOfFirst { it.isBlank() }
                val expected = question.spellLetters.getOrNull(nextSlot)
                Button(
                    onClick = {
                        if (feedbackLocked || used || completed || wrongPoolIndex >= 0) return@Button
                        if (nextSlot < 0) return@Button
                        if (letter != expected) {
                            wrongPoolIndex = index
                            onWrongLetterTap()
                            return@Button
                        }
                        val nextSlots = slots.toMutableList().also { it[nextSlot] = letter }
                        slots = nextSlots
                        consumed = consumed.toMutableList().also { it[index] = true }
                        if (nextSlots.joinToString("") == question.spellLetters.joinToString("")) {
                            completed = true
                        }
                    },
                    enabled = !feedbackLocked && !used && !completed,
                    modifier = Modifier
                        .width(44.dp)
                        .height(52.dp)
                        .testTag("BattleSpellPool_$index")
                        .semantics {
                            contentDescription = if (!used && !completed && letter == expected) {
                                "BattleSpellCorrectPool"
                            } else {
                                "BattleSpellPool_$index"
                            }
                        },
                    shape = CircleShape,
                    contentPadding = PaddingValues(0.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = when {
                            used -> Color(0xFFE0E0E0)
                            wrong -> Color(0xFFFCEAEA)
                            else -> Color(0xFFFFF8E7)
                        },
                        disabledContainerColor = if (used) Color(0xFFE0E0E0) else Color(0xFFFFF8E7),
                        disabledContentColor = Color(0xFFA3A3A3),
                    ),
                ) {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            letter,
                            style = circleGlyphTextStyle(20.sp, FontWeight.Bold),
                            color = when {
                                used -> Color(0xFFA3A3A3)
                                wrong -> Color(0xFFE63946)
                                else -> Color(0xFF1D3557)
                            },
                        )
                    }
                }
            }
        }
    }
}

internal fun answerOptions(question: Question): List<String> {
    return when (question.kind) {
        QuestionKind.Choice -> question.options
        QuestionKind.SentenceCloze -> question.options
        QuestionKind.FillLetter -> question.letterOptions
        QuestionKind.FillLetterMedium -> question.letterOptionsSteps.getOrElse(question.currentStep) { emptyList() }
        QuestionKind.Spell -> question.spellPool
    }
}

@Composable
internal fun BattleFeedbackText(outcome: BattleAnswerOutcome) {
    val text = when {
        outcome.advancedStep -> "Good! Next letter"
        outcome.comboTriggered -> "Combo 3! Magic Burst x2"
        outcome.correct -> "Correct!"
        else -> "Correct: ${correctOptionForOutcome(outcome)}"
    }
    val color = when {
        outcome.comboTriggered -> Color(0xFFC27A00)
        outcome.correct -> Color(0xFF147C42)
        else -> Color(0xFFD23A3A)
    }
    Text(text, color = color, fontSize = 17.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
}

internal fun answerButtonColor(option: String, outcome: BattleAnswerOutcome?): Color {
    if (outcome == null) return Color(0xFF8253A8)
    val correctOption = correctOptionForOutcome(outcome)
    return when {
        option == outcome.selectedAnswer && outcome.correct -> Color(0xFF16A765)
        option == outcome.selectedAnswer && !outcome.correct -> Color(0xFFE04444)
        option == correctOption && !outcome.correct -> Color(0xFF16A765)
        else -> Color(0xFFB7A1C8)
    }
}

internal fun correctOptionForOutcome(outcome: BattleAnswerOutcome): String {
    return when (outcome.question.kind) {
        QuestionKind.Choice -> outcome.correctAnswer
        QuestionKind.SentenceCloze -> outcome.correctAnswer
        QuestionKind.FillLetter -> outcome.question.letterAnswer
        QuestionKind.FillLetterMedium -> outcome.question.letterAnswers.getOrElse(outcome.question.currentStep) { outcome.correctAnswer }
        QuestionKind.Spell -> outcome.correctAnswer
    }
}

@Composable
internal fun BattleProjectileOverlay(outcome: BattleAnswerOutcome?, modifier: Modifier = Modifier) {
    if (outcome == null) return
    if (outcome.advancedStep) return
    val travel = remember(outcome) { Animatable(0f) }
    LaunchedEffect(outcome) {
        travel.snapTo(0f)
        travel.animateTo(1f, animationSpec = tween(durationMillis = 520, easing = FastOutSlowInEasing))
    }
    BoxWithConstraints(modifier = modifier) {
        val maxWidthPx = constraints.maxWidth.toFloat()
        val maxHeightPx = constraints.maxHeight.toFloat()
        val progress = travel.value
        val startX = if (outcome.correct) maxWidthPx * 0.18f else maxWidthPx * 0.78f
        val endX = if (outcome.correct) maxWidthPx * 0.78f else maxWidthPx * 0.18f
        val x = startX + (endX - startX) * progress
        val y = maxHeightPx * 0.44f
        val projectileColor = when {
            outcome.comboTriggered -> Color(0xFFFFC83D)
            outcome.correct -> Color(0xFF46C7FF)
            else -> Color(0xFFFF7A7A)
        }
        val projectileWidth = if (outcome.comboTriggered) 122.dp else 104.dp
        val projectileHeight = if (outcome.comboTriggered) 48.dp else 40.dp
        Box(
            modifier = Modifier
                .offset { IntOffset(x.roundToInt() - 56, y.roundToInt() - 22) }
                .size(width = projectileWidth, height = projectileHeight)
                .clip(RoundedCornerShape(99.dp))
                .background(projectileColor.copy(alpha = 0.92f))
                .border(2.dp, Color.White.copy(alpha = 0.8f), RoundedCornerShape(99.dp))
                .graphicsLayer {
                    scaleX = if (outcome.comboTriggered) 1.12f else 1f
                    scaleY = if (outcome.comboTriggered) 1.12f else 1f
                    shadowElevation = 12f
                },
            contentAlignment = Alignment.Center,
        ) {
            Text(outcome.correctAnswer, color = Color.White, fontWeight = FontWeight.Black, fontSize = 16.sp)
        }
    }
}

@Composable
internal fun CritBurstOverlay(outcome: BattleAnswerOutcome?, modifier: Modifier = Modifier) {
    if (outcome?.comboTriggered != true) return
    val burst = remember(outcome) { Animatable(0f) }
    LaunchedEffect(outcome) {
        burst.snapTo(0f)
        burst.animateTo(1f, animationSpec = tween(durationMillis = BATTLE_FEEDBACK_MS.toInt(), easing = LinearEasing))
    }
    val progress = burst.value
    Box(
        modifier = modifier
            .background(Color(0xFFFFD34A).copy(alpha = (0.24f * (1f - progress)).coerceAtLeast(0f))),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .size((120 + 260 * progress).dp)
                .clip(CircleShape)
                .border(5.dp, Color(0xFFFFC400).copy(alpha = 1f - progress), CircleShape),
        )
        Box(
            modifier = Modifier
                .size((60 + 190 * progress).dp)
                .clip(CircleShape)
                .border(3.dp, Color.White.copy(alpha = 0.85f - progress * 0.7f), CircleShape),
        )
        Text(
            "-${outcome.damage}!",
            modifier = Modifier.graphicsLayer {
                translationY = -80f * progress
                alpha = 1f - progress * 0.25f
                scaleX = 1f + progress * 0.28f
                scaleY = 1f + progress * 0.28f
            },
            color = Color(0xFFFF0050),
            fontSize = 58.sp,
            fontWeight = FontWeight.Black,
        )
    }
}

internal fun playBattleSound(context: android.content.Context, @RawRes sound: Int) {
    runCatching {
        val player = MediaPlayer.create(context.applicationContext, sound) ?: return
        player.setOnCompletionListener { completed -> completed.release() }
        player.start()
    }
}

internal fun formatCountdown(totalSeconds: Int): String {
    val safeSeconds = totalSeconds.coerceAtLeast(0)
    val minutes = safeSeconds / 60
    val seconds = safeSeconds % 60
    return "$minutes:${seconds.toString().padStart(2, '0')}"
}

internal fun resolveBattleTimerSeconds(config: GameConfig): Int {
    return if (config.timerSeconds in setOf(3, 30, 180, DEFAULT_BATTLE_TIMER_SECONDS, 600)) {
        config.timerSeconds
    } else {
        DEFAULT_BATTLE_TIMER_SECONDS
    }
}

@RawRes
internal fun monsterResourceForPack(packId: String): Int {
    return when (packId) {
        "school-castle", "ocean-realm" -> R.raw.character_zombie
        "home-cottage" -> R.raw.character_dragon
        else -> R.raw.character_slime
    }
}

@RawRes
internal fun monsterResourceForEntry(monster: MonsterEntry, packageName: String, resources: Resources): Int {
    val resolved = resources.getIdentifier(monster.rawResourceName, "raw", packageName)
    return if (resolved != 0) resolved else monsterResourceForPack("")
}
