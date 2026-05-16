package cool.happyword.wordmagic.ui.config

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.content.pm.ActivityInfo
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

import cool.happyword.wordmagic.ui.components.SettingCard
import cool.happyword.wordmagic.ui.components.StepperRow
import cool.happyword.wordmagic.ui.components.DraftRow

internal val HarmonyBattleHpRange = 1..10
internal val HarmonyMonsterCountRange = 1..10

internal fun harmonyTimerChipBase(seconds: Int): String =
    if (seconds < 60) "${seconds}s" else "${seconds / 60}m"

internal fun harmonyTimerChipLabel(seconds: Int, selectedSeconds: Int): String {
    val base = harmonyTimerChipBase(seconds)
    return if (seconds == selectedSeconds) "\u2713$base" else base
}

internal fun harmonyCustomTimerChipLabel(timerSeconds: Int): String {
    val custom = timerSeconds !in GameConfig.timerPresets
    return if (custom) "\u2713自定义 (${harmonyTimerChipBase(timerSeconds)})" else "自定义"
}

@Composable
internal fun ConfigCenteredFormRow(
    modifier: Modifier = Modifier,
    bottomPadding: Dp = 12.dp,
    verticalAlignment: Alignment.Vertical = Alignment.CenterVertically,
    content: @Composable RowScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(bottom = bottomPadding),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = verticalAlignment, content = content)
    }
}

@Composable
internal fun HarmonyConfigStepperRow(
    label: String,
    value: Int,
    testTagPrefix: String,
    range: IntRange,
    onValueChange: (Int) -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp),
        contentAlignment = Alignment.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(label, fontSize = 18.sp, modifier = Modifier.width(120.dp))
            CenteredCircleTextButton(
                text = "-",
                onClick = { onValueChange((value - 1).coerceAtLeast(range.first)) },
                modifier = Modifier.testTag("${testTagPrefix}Decrement"),
                size = 44.dp,
                enabled = value > range.first,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF213E66),
                    contentColor = Color.White,
                    disabledContainerColor = Color(0xFFE8E8E8),
                    disabledContentColor = Color(0xFFB0B0B0),
                ),
            )
            Text(
                "$value",
                fontSize = 22.sp,
                modifier = Modifier
                    .width(48.dp)
                    .testTag("${testTagPrefix}Value"),
                textAlign = TextAlign.Center,
            )
            CenteredCircleTextButton(
                text = "+",
                onClick = { onValueChange((value + 1).coerceAtMost(range.last)) },
                modifier = Modifier.testTag("${testTagPrefix}Increment"),
                size = 44.dp,
                enabled = value < range.last,
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF213E66),
                    contentColor = Color.White,
                    disabledContainerColor = Color(0xFFE8E8E8),
                    disabledContentColor = Color(0xFFB0B0B0),
                ),
            )
        }
    }
}

@Composable
internal fun ConfigScreen(
    config: GameConfig,
    activePackCount: Int,
    maxActivePacks: Int,
    parentPinReady: Boolean,
    cloudBound: Boolean,
    cloudChildNickname: String,
    learningSyncBusy: Boolean,
    learningSyncStatus: String,
    learningSyncToast: String,
    onConfigChange: (GameConfig) -> Unit,
    onBack: () -> Unit,
    onParentAdmin: () -> Unit,
    onParentPinSetup: () -> Unit,
    onCloudBinding: () -> Unit,
    onPackManager: () -> Unit,
    onLearningSync: () -> Unit,
) {
    var showCustomTimerDialog by remember { mutableStateOf(false) }
    var customTimerText by remember { mutableStateOf("") }
    var customTimerError by remember { mutableStateOf("") }
    var questionTypeHint by remember { mutableStateOf("") }

    val safeTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(config.enabledQuestionTypes)
    fun isTypeOn(id: String) = safeTypes.contains(id)
    fun chipLabel(typeId: String, selected: Boolean): String {
        val base = BattleQuestionTypePolicy.displayLabel(typeId)
        return if (selected) "\u2713 $base" else base
    }
    fun toggleQuestionType(typeId: String) {
        val current = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(config.enabledQuestionTypes).toMutableList()
        if (current.contains(typeId)) {
            if (current.size <= 1) {
                questionTypeHint = "至少保留一种题型"
                return
            }
            current.remove(typeId)
            questionTypeHint = ""
        } else {
            current.add(typeId)
            questionTypeHint = ""
        }
        onConfigChange(
            config.copy(
                enabledQuestionTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(current),
            ),
        )
    }

    val ordered = BattleQuestionTypePolicy.defaultOrderedTypeIds
    val row0 = ordered.take(2)
    val row1 = ordered.drop(2)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .testTag("ConfigScreen"),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = PageChromeInsets.bodyHorizontal,
                    vertical = PageChromeInsets.bodyTop,
                ),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier.testTag("ConfigBackButton"),
            )
            Spacer(Modifier.weight(1f))
        }
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(
                    start = PageChromeInsets.bodyHorizontal,
                    top = PageChromeInsets.bodyTop,
                    end = PageChromeInsets.bodyHorizontal,
                    bottom = PageChromeInsets.bodyBottom,
                ),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                "游戏配置",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 12.dp),
                textAlign = TextAlign.Center,
            )
            Column(modifier = Modifier.fillMaxWidth()) {
                HarmonyConfigStepperRow(
                    label = "玩家血量",
                    value = config.playerHp,
                    testTagPrefix = "ConfigPlayerHp",
                    range = HarmonyBattleHpRange,
                    onValueChange = { onConfigChange(config.copy(playerHp = it)) },
                )
                HarmonyConfigStepperRow(
                    label = "怪物血量",
                    value = config.monsterHp,
                    testTagPrefix = "ConfigMonsterHp",
                    range = HarmonyBattleHpRange,
                    onValueChange = { onConfigChange(config.copy(monsterHp = it)) },
                )
                HarmonyConfigStepperRow(
                    label = "怪物数量",
                    value = config.monsterCount,
                    testTagPrefix = "ConfigMonsterCount",
                    range = HarmonyMonsterCountRange,
                    onValueChange = { onConfigChange(config.copy(monsterCount = it)) },
                )
            }
            ConfigCenteredFormRow {
                Text("倒计时", fontSize = 18.sp, modifier = Modifier.width(120.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    GameConfig.timerPresets.forEach { sec ->
                        val selected = config.timerSeconds == sec
                        Button(
                            onClick = { onConfigChange(config.copy(timerSeconds = sec)) },
                            modifier = Modifier
                                .height(40.dp)
                                .testTag("ConfigTimer${sec}s"),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (selected) Color(0xFFFFB400) else Color(0xFFEAF2F8),
                                contentColor = if (selected) Color.White else Color(0xFF457B9D),
                            ),
                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                            shape = RoundedCornerShape(50),
                        ) {
                            Text(harmonyTimerChipLabel(sec, config.timerSeconds), fontSize = 16.sp)
                        }
                    }
                    val customSelected = config.timerSeconds !in GameConfig.timerPresets
                    Button(
                        onClick = {
                            customTimerText = "${config.timerSeconds}"
                            customTimerError = ""
                            showCustomTimerDialog = true
                        },
                        modifier = Modifier
                            .height(40.dp)
                            .testTag("ConfigTimerCustom"),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (customSelected) Color(0xFFFFB400) else Color(0xFFEAF2F8),
                            contentColor = if (customSelected) Color.White else Color(0xFF457B9D),
                        ),
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                        shape = RoundedCornerShape(50),
                    ) {
                        Text(harmonyCustomTimerChipLabel(config.timerSeconds), fontSize = 16.sp)
                    }
                }
            }
            ConfigCenteredFormRow {
                Text("发音播放", fontSize = 18.sp, modifier = Modifier.width(120.dp))
                Button(
                    onClick = { onConfigChange(config.copy(autoPronunciation = !config.autoPronunciation)) },
                    modifier = Modifier
                        .width(140.dp)
                        .height(40.dp)
                        .testTag("ConfigAutoSpeakToggle"),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (config.autoPronunciation) Color(0xFFFFF4D0) else Color(0xFFF0F0F0),
                        contentColor = if (config.autoPronunciation) Color(0xFFB8860B) else Color(0xFF666666),
                    ),
                    shape = RoundedCornerShape(8.dp),
                    border = if (config.autoPronunciation) BorderStroke(2.dp, Color(0xFFFFB400)) else null,
                ) {
                    Text(
                        if (config.autoPronunciation) "\u2713 自动朗读" else "自动朗读",
                        fontSize = 16.sp,
                    )
                }
            }
            ConfigCenteredFormRow(bottomPadding = 4.dp, verticalAlignment = Alignment.Top) {
                Text("题型选择", fontSize = 18.sp, modifier = Modifier.width(120.dp))
                Column {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row0.forEach { typeId ->
                            val selected = isTypeOn(typeId)
                            Button(
                                onClick = { toggleQuestionType(typeId) },
                                modifier = Modifier
                                    .height(40.dp)
                                    .testTag("ConfigQuestionType_$typeId"),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = if (selected) Color(0xFFFFF4D0) else Color(0xFFF0F0F0),
                                    contentColor = if (selected) Color(0xFFB8860B) else Color(0xFF666666),
                                ),
                                shape = RoundedCornerShape(8.dp),
                                border = if (selected) BorderStroke(2.dp, Color(0xFFFFB400)) else null,
                                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                            ) {
                                Text(chipLabel(typeId, selected), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier.padding(top = 8.dp),
                    ) {
                        row1.forEach { typeId ->
                            val selected = isTypeOn(typeId)
                            Button(
                                onClick = { toggleQuestionType(typeId) },
                                modifier = Modifier
                                    .height(40.dp)
                                    .testTag("ConfigQuestionType_$typeId"),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = if (selected) Color(0xFFFFF4D0) else Color(0xFFF0F0F0),
                                    contentColor = if (selected) Color(0xFFB8860B) else Color(0xFF666666),
                                ),
                                shape = RoundedCornerShape(8.dp),
                                border = if (selected) BorderStroke(2.dp, Color(0xFFFFB400)) else null,
                                contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                            ) {
                                Text(chipLabel(typeId, selected), fontSize = 14.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
            if (questionTypeHint.isNotEmpty()) {
                Text(
                    questionTypeHint,
                    color = Color(0xFFB45309),
                    fontSize = 12.sp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 8.dp)
                        .testTag("ConfigQuestionTypeLastEnabledHint"),
                    textAlign = TextAlign.Center,
                )
            }
            ConfigCenteredFormRow {
                Text("我的词包", fontSize = 18.sp, modifier = Modifier.width(120.dp))
                Row(
                    modifier = Modifier
                        .width(220.dp)
                        .height(40.dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(Color(0xFFEAF2F8))
                        .clickable { onPackManager() }
                        .padding(horizontal = 12.dp)
                        .testTag("ConfigPackManagerButton"),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "已激活 $activePackCount / $maxActivePacks",
                        fontSize = 15.sp,
                        color = Color(0xFF1F2937),
                        modifier = Modifier
                            .weight(1f)
                            .testTag("ConfigPackPickerStatus"),
                    )
                    Text("管理 ›", fontSize = 15.sp, color = Color(0xFF457B9D))
                }
            }
            Text(
                "家长配置",
                fontSize = 24.sp,
                fontWeight = FontWeight.Bold,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp, bottom = 12.dp)
                    .testTag("ConfigSectionParentTitle"),
                textAlign = TextAlign.Center,
            )
            ConfigCenteredFormRow {
                Text("家长账号", fontSize = 18.sp, modifier = Modifier.width(120.dp))
                if (cloudBound) {
                    Button(
                        onClick = onCloudBinding,
                        modifier = Modifier
                            .width(220.dp)
                            .height(40.dp)
                            .testTag("ConfigCloudBindingButton"),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFE0F2FE),
                            contentColor = Color(0xFF0369A1),
                        ),
                        shape = RoundedCornerShape(8.dp),
                        border = BorderStroke(2.dp, Color(0xFF0EA5E9)),
                    ) {
                        Text(
                            "孩子档案：$cloudChildNickname",
                            fontSize = 15.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                } else {
                    Button(
                        onClick = onCloudBinding,
                        modifier = Modifier
                            .width(220.dp)
                            .height(40.dp)
                            .testTag("ConfigCloudBindingButton"),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = Color(0xFFFFF4D0),
                            contentColor = Color(0xFFB8860B),
                        ),
                        shape = RoundedCornerShape(8.dp),
                        border = BorderStroke(2.dp, Color(0xFFFFB400)),
                    ) {
                        Text("绑定家长账号", fontSize = 15.sp)
                    }
                }
            }
            if (cloudBound) {
                ConfigCenteredFormRow {
                    Text("家长密码", fontSize = 18.sp, modifier = Modifier.width(120.dp))
                    Button(
                        onClick = onParentPinSetup,
                        modifier = Modifier
                            .width(220.dp)
                            .height(40.dp)
                            .testTag("ConfigParentPinButton"),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = if (parentPinReady) Color(0xFFFFF4D0) else Color(0xFFEAF2F8),
                            contentColor = if (parentPinReady) Color(0xFFB8860B) else Color(0xFF457B9D),
                        ),
                        shape = RoundedCornerShape(8.dp),
                        border = if (parentPinReady) BorderStroke(2.dp, Color(0xFFFFB400)) else null,
                    ) {
                        Text(
                            if (parentPinReady) "修改 (•••••• 已设置)" else "设置",
                            fontSize = 15.sp,
                        )
                    }
                }
                ConfigCenteredFormRow(
                    modifier = Modifier.testTag("ConfigCloudSyncRow"),
                    bottomPadding = 8.dp,
                ) {
                    Text("学习记录", fontSize = 18.sp, modifier = Modifier.width(120.dp))
                    OutlinedButton(
                        onClick = onLearningSync,
                        enabled = !learningSyncBusy,
                        modifier = Modifier
                            .width(220.dp)
                            .height(40.dp)
                            .testTag("ConfigCloudSyncButton"),
                        colors = ButtonDefaults.outlinedButtonColors(
                            containerColor = Color(0xFFE0F2FE),
                            contentColor = Color(0xFF0369A1),
                        ),
                        border = BorderStroke(2.dp, Color(0xFF0EA5E9)),
                    ) {
                        Text(if (learningSyncBusy) "同步中…" else "立即同步学习记录", fontSize = 15.sp)
                    }
                }
                if (learningSyncStatus.isNotBlank()) {
                    Text(
                        learningSyncStatus,
                        color = Color(0xFF0369A1),
                        fontSize = 14.sp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 4.dp)
                            .testTag("ConfigCloudSyncStatus"),
                        textAlign = TextAlign.Center,
                    )
                }
                if (learningSyncToast.isNotBlank()) {
                    Text(
                        learningSyncToast,
                        color = Color(0xFFFF0050),
                        fontSize = 14.sp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 8.dp)
                            .testTag("ConfigCloudSyncToast"),
                        textAlign = TextAlign.Center,
                    )
                }
                if (parentPinReady) {
                    ConfigCenteredFormRow {
                        Text("管理后台", fontSize = 18.sp, modifier = Modifier.width(120.dp))
                        Button(
                            onClick = onParentAdmin,
                            modifier = Modifier
                                .width(220.dp)
                                .height(40.dp)
                                .testTag("ConfigParentAdminButton"),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color(0xFFFFF4D0),
                                contentColor = Color(0xFFB8860B),
                            ),
                            shape = RoundedCornerShape(8.dp),
                            border = BorderStroke(2.dp, Color(0xFFFFB400)),
                        ) {
                            Text("家长管理后台", fontSize = 15.sp)
                        }
                    }
                }
            }
        }
    }

    if (showCustomTimerDialog) {
        AlertDialog(
            onDismissRequest = { showCustomTimerDialog = false },
            title = {
                Text(
                    "自定义倒计时",
                    modifier = Modifier.testTag("CustomTimerDialogTitle"),
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Medium,
                    color = Color(0xFF1D3557),
                )
            },
            text = {
                Column {
                    Text(
                        "请输入倒计时秒数（${GameConfig.TIMER_CUSTOM_MIN} - ${GameConfig.TIMER_CUSTOM_MAX}）",
                        fontSize = 14.sp,
                        color = Color(0xFF6B7280),
                        modifier = Modifier.testTag("CustomTimerDialogHint"),
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = customTimerText,
                        onValueChange = { raw ->
                            customTimerText = raw.filter { it.isDigit() }.take(4)
                            customTimerError = ""
                        },
                        placeholder = { Text("秒", color = Color(0xFFBBBBBB)) },
                        modifier = Modifier.testTag("CustomTimerDialogInput"),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                        singleLine = true,
                    )
                    if (customTimerError.isNotEmpty()) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            customTimerError,
                            color = Color(0xFFE63946),
                            fontSize = 13.sp,
                            modifier = Modifier.testTag("CustomTimerDialogError"),
                        )
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val v = GameConfig.validateCustomTimerInput(customTimerText)
                        if (!v.ok) {
                            customTimerError = v.message
                        } else {
                            onConfigChange(config.copy(timerSeconds = v.seconds))
                            showCustomTimerDialog = false
                        }
                    },
                    modifier = Modifier.testTag("CustomTimerDialogConfirmButton"),
                ) {
                    Text("确定", color = Color(0xFFE63946), fontWeight = FontWeight.Bold)
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showCustomTimerDialog = false },
                    modifier = Modifier.testTag("CustomTimerDialogCancelButton"),
                ) { Text("取消") }
            },
        )
    }
}

@Composable
internal fun AddCustomWishPinDialog(
    visible: Boolean,
    pinInput: String,
    onPinChange: (String) -> Unit,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    if (!visible) {
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("请输入家长密码以添加自定义愿望") },
        text = {
            OutlinedTextField(
                value = pinInput,
                onValueChange = onPinChange,
                label = { Text("6 位数字密码") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("AddCustomWishPinInput"),
            )
        },
        confirmButton = {
            TextButton(
                onClick = onConfirm,
                modifier = Modifier.testTag("AddCustomWishPinConfirm"),
            ) { Text("继续") }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                modifier = Modifier.testTag("AddCustomWishPinCancel"),
            ) { Text("取消") }
        },
    )
}

@Composable
internal fun RemoveCustomWishPinDialog(
    visible: Boolean,
    pinInput: String,
    onPinChange: (String) -> Unit,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    if (!visible) {
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("请输入家长密码以删除该愿望") },
        text = {
            OutlinedTextField(
                value = pinInput,
                onValueChange = onPinChange,
                label = { Text("6 位数字密码") },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                singleLine = true,
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("RemoveCustomWishPinInput"),
            )
        },
        confirmButton = {
            TextButton(
                onClick = onConfirm,
                modifier = Modifier.testTag("RemoveCustomWishPinConfirm"),
            ) { Text("继续") }
        },
        dismissButton = {
            TextButton(
                onClick = onDismiss,
                modifier = Modifier.testTag("RemoveCustomWishPinCancel"),
            ) { Text("取消") }
        },
    )
}

@Composable
internal fun AddCustomWishFormDialog(
    visible: Boolean,
    name: String,
    costRaw: String,
    emoji: String,
    error: String,
    onNameChange: (String) -> Unit,
    onCostChange: (String) -> Unit,
    onEmojiChange: (String) -> Unit,
    onDismiss: () -> Unit,
    onSubmit: () -> Unit,
) {
    if (!visible) {
        return
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("添加魔法愿望") },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text("愿望名称", fontSize = 14.sp, color = Color(0xFF888888))
                OutlinedTextField(
                    value = name,
                    onValueChange = onNameChange,
                    label = { Text("1-${CustomWishRules.NAME_MAX_CHARS} 字") },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("AddCustomWishNameInput"),
                )
                Text("需要的魔法币数量", fontSize = 14.sp, color = Color(0xFF888888))
                OutlinedTextField(
                    value = costRaw,
                    onValueChange = onCostChange,
                    label = { Text("${CustomWishRules.COST_MIN}-${CustomWishRules.COST_MAX}") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("AddCustomWishCostInput"),
                )
                Text("表情图标 (留空使用 ⭐)", fontSize = 14.sp, color = Color(0xFF888888))
                OutlinedTextField(
                    value = emoji,
                    onValueChange = onEmojiChange,
                    label = { Text("emoji") },
                    singleLine = true,
                    modifier = Modifier
                        .fillMaxWidth()
                        .testTag("AddCustomWishEmojiInput"),
                )
                if (error.isNotEmpty()) {
                    Text(
                        error,
                        fontSize = 13.sp,
                        color = Color(0xFFE63946),
                        modifier = Modifier.testTag("AddCustomWishError"),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = onSubmit,
                modifier = Modifier.testTag("AddCustomWishSubmitButton"),
            ) { Text("添加") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
    )
}

