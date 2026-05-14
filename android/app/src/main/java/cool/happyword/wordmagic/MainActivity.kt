@file:Suppress("OVERRIDE_DEPRECATION")

package cool.happyword.wordmagic

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
import cool.happyword.wordmagic.ui.CenteredCircleTextButton
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

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        @Suppress("DEPRECATION")
        window.setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN, WindowManager.LayoutParams.FLAG_FULLSCREEN)
        setContent {
            WordMagicGameApp()
        }
    }
}

private enum class AppRoute {
    Home,
    Battle,
    Result,
    Config,
    ParentPin,
    ParentAdmin,
    LessonDraftReview,
    PackManager,
    Wishlist,
    RedemptionHistory,
    MonsterCodex,
    TodayPlan,
    LearningReport,
    ScanBinding,
    BoundDeviceInfo,
    DevMenu,
    BypassSecret,
}

private data class PackUi(
    val id: String,
    val nameZh: String,
    val nameEn: String,
    val story: String,
    val monsterRes: Int,
)

private val packs = listOf(
    PackUi("fruit-forest", "水果森林", "Fruit Forest", "藤蔓和果香里的第一场魔法单词冒险。", R.raw.character_slime),
    PackUi("school-castle", "校园城堡", "School Castle", "在书本城堡里挑战会拼写的怪物。", R.raw.character_zombie),
    PackUi("home-cottage", "家庭小屋", "Home Cottage", "把熟悉的家庭物品变成轻松复习。", R.raw.character_dragon),
    PackUi("animal-safari", "动物远征", "Animal Safari", "跟动物朋友一起找回单词记忆。", R.raw.character_slime),
    PackUi("ocean-realm", "海洋王国", "Ocean Realm", "在蓝色海底完成今日练习。", R.raw.character_zombie),
)
private val homePackOrder = listOf("school-castle", "ocean-realm", "home-cottage", "fruit-forest", "animal-safari")
private val homePacks = homePackOrder.mapNotNull { id -> packs.firstOrNull { it.id == id } }
private const val DEFAULT_BATTLE_TIMER_SECONDS = 300
private const val BATTLE_FEEDBACK_MS = 650L
private const val PROJECTILE_IMPACT_MS = 320L
private const val GIFTBOX_TRIGGER_DELAY_MS = 60L
private const val GIFTBOX_MODAL_TOTAL_MS = 3_180L
private const val WISH_REDEEMED_ACK_MS = 1_500L

@Composable
fun WordMagicGameApp() {
    val context = LocalContext.current
    var route by remember { mutableStateOf(AppRoute.Home) }
    val repositories = remember { AndroidLocalProgressRepositories(context.applicationContext) }
    val cloudRepositories = remember { AndroidCloudRepositories(context.applicationContext) }
    val debugRoutingRepository = remember { AndroidDebugRoutingRepository(context.applicationContext) }
    val devMenuViewModel = remember { DevMenuViewModel() }
    val appScope = rememberCoroutineScope()
    val cloudCoordinator = remember { CloudSyncCoordinator() }
    val isDebuggable = remember { (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0 }
    val showDeveloperTools = BuildGate.showDeveloperTools(isDebuggable)
    val homeVersionLabel = remember(showDeveloperTools) {
        if (showDeveloperTools) BuildInfo.homeVersionLabel(context) else ""
    }
    var cloudCredentials by remember { mutableStateOf(cloudRepositories.loadCredentials()) }
    var globalPacks by remember { mutableStateOf(cloudRepositories.loadGlobalPacks()) }
    var familyPacks by remember { mutableStateOf(cloudRepositories.loadFamilyPacks()) }
    var cloudSyncStatus by remember { mutableStateOf(cloudRepositories.loadSyncStatus()) }
    var learningSyncStatus by remember { mutableStateOf(cloudRepositories.loadLearningSyncStatus()) }
    var learningSyncToast by remember { mutableStateOf("") }
    var learningSyncBusy by remember { mutableStateOf(false) }
    var bindingError by remember { mutableStateOf("") }
    var pendingCloudUnbind by remember { mutableStateOf(false) }
    var backendRouteState by remember { mutableStateOf(BuildGate.coerceBackendRouteForBuild(isDebuggable, debugRoutingRepository.loadRouteState())) }
    val bindingClient = remember {
        DeviceBindingClient(
            baseUrlProvider = { BackendURLProvider().resolve(backendRouteState) },
            extraHeadersProvider = {
                BackendHeaderProvider().headers(
                    backendRouteState,
                    debugRoutingRepository.bypassSecretStore.load(),
                )
            },
        )
    }
    val childProfileClient = remember {
        ChildProfileClient(
            baseUrlProvider = { BackendURLProvider().resolve(backendRouteState) },
            extraHeadersProvider = {
                BackendHeaderProvider().headers(
                    backendRouteState,
                    debugRoutingRepository.bypassSecretStore.load(),
                )
            },
        )
    }
    val wordStatsSyncClient = remember {
        WordStatsSyncClient(
            baseUrlProvider = { BackendURLProvider().resolve(backendRouteState) },
            extraHeadersProvider = {
                BackendHeaderProvider().headers(
                    backendRouteState,
                    debugRoutingRepository.bypassSecretStore.load(),
                )
            },
        )
    }
    var previewTargets by remember { mutableStateOf(devMenuViewModel.fallbackManifest()) }
    var previewManifestBusy by remember { mutableStateOf(false) }
    var backendApplying by remember { mutableStateOf(false) }
    var pendingPreviewAfterSecret by remember { mutableStateOf<cool.happyword.wordmagic.core.PreviewTarget?>(null) }
    var probeStatus by remember { mutableStateOf("尚未探测") }
    val packLibrary = remember(globalPacks, familyPacks) { PackLibrary.merge(BuiltinPacks.all, globalPacks, familyPacks) }
    var selection by remember { mutableStateOf(repositories.loadSelection().prune(packLibrary)) }
    var selectedPackId by remember { mutableStateOf("fruit-forest") }
    val activePacks = packLibrary.activePacks(selection.activePackIds).ifEmpty { BuiltinPacks.defaultActiveOrder.mapNotNull(packLibrary::findPack) }
    val selectedPack = packLibrary.findPack(selectedPackId) ?: activePacks.first()
    var config by remember { mutableStateOf(GameConfig()) }
    var engine by remember { mutableStateOf(BattleEngine(config = config)) }
    var battleState by remember { mutableStateOf<BattleState?>(null) }
    var battleRunId by remember { mutableIntStateOf(0) }
    var battleTimeLeft by remember { mutableIntStateOf(DEFAULT_BATTLE_TIMER_SECONDS) }
    var result by remember { mutableStateOf<SessionResult?>(null) }
    var coinAccount by remember { mutableStateOf(repositories.loadCoinAccount()) }
    var learningRecorder by remember { mutableStateOf(repositories.loadLearningRecorder()) }
    var wishlist by remember { mutableStateOf(repositories.loadWishlist()) }
    var redemptionHistory by remember { mutableStateOf(repositories.loadRedemptionHistory()) }
    var localProgressMessage by remember { mutableStateOf("") }
    var monsterCatalog by remember { mutableStateOf(MonsterCatalog.default()) }
    var pendingRedemptionWishId by remember { mutableStateOf<String?>(null) }
    var wishlistGiftBoxVisible by remember { mutableStateOf(false) }
    var wishlistGiftBoxTrigger by remember { mutableIntStateOf(0) }
    var recentlyRedeemedWishId by remember { mutableStateOf<String?>(null) }
    var parentPin by remember { mutableStateOf("") }
    var devMenuRoutePreset by remember { mutableStateOf<String?>(null) }

    fun resetForBackendSwitch() {
        cloudRepositories.resetForBackendSwitch()
        cloudCredentials = null
        globalPacks = emptyList()
        familyPacks = emptyList()
        cloudSyncStatus = cloudRepositories.loadSyncStatus()
        learningSyncStatus = cloudRepositories.loadLearningSyncStatus()
        learningSyncToast = ""
    }

    fun applyBackendRoute(targetState: BackendRouteState, bypassSecret: String = "") {
        if (backendApplying) return
        appScope.launch {
            backendApplying = true
            try {
                if (targetState.env == BackendEnv.Preview) {
                    probeStatus = "Probing ${devMenuViewModel.routingSummary(targetState).substringAfter(": ")}/api/v1/health..."
                    val probeResult = devMenuViewModel.probeHealth(targetState, bypassSecret)
                    probeStatus = probeResult.message
                    if (!probeResult.ok) {
                        route = AppRoute.DevMenu
                        Toast.makeText(context, "Cannot reach /api/v1/health - see status at bottom", Toast.LENGTH_SHORT).show()
                        return@launch
                    }
                    debugRoutingRepository.bypassSecretStore.save(bypassSecret)
                }
                resetForBackendSwitch()
                debugRoutingRepository.saveRouteState(targetState)
                backendRouteState = targetState
                Toast.makeText(context, "Environment updated. Re-bind parent account if needed.", Toast.LENGTH_SHORT).show()
                route = AppRoute.Home
            } finally {
                backendApplying = false
            }
        }
    }

    ApplyOrientation(route)
    LaunchedEffect(route, devMenuRoutePreset) {
        if (route != AppRoute.DevMenu) return@LaunchedEffect
        val preset = devMenuRoutePreset ?: return@LaunchedEffect
        devMenuRoutePreset = null
        if (!preset.equals(DevMenuRouteParams.PRESET_ENV_PREVIEW, ignoreCase = true)) return@LaunchedEffect
        previewManifestBusy = true
        try {
            previewTargets = devMenuViewModel.refreshManifest(previewTargets, force = true)
        } finally {
            previewManifestBusy = false
        }
    }
    LaunchedEffect(route, battleRunId) {
        if (route == AppRoute.Battle) {
            var remaining = battleTimeLeft
            while (remaining > 0 && (battleState?.status ?: BattleStatus.Playing) == BattleStatus.Playing) {
                withContext(Dispatchers.Default) {
                    Thread.sleep(1_000)
                }
                remaining = (remaining - 1).coerceAtLeast(0)
                battleTimeLeft = remaining
            }
            if (remaining <= 0 && (battleState?.status ?: BattleStatus.Playing) == BattleStatus.Playing) {
                val timedOut = (battleState ?: engine.initialState()).copy(playerHp = 0, status = BattleStatus.Lost)
                battleState = timedOut
                result = engine.resultFor(timedOut)
                route = AppRoute.Result
            }
        }
    }

    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Color(0xFFD94141),
            secondary = Color(0xFFFFB400),
            surface = Color(0xFFFFFBF4),
            background = Color(0xFFFFF6E7),
        ),
    ) {
        Surface(modifier = Modifier.fillMaxSize(), color = Color(0xFFFFF6E7)) {
            when (route) {
                AppRoute.Home -> HomeScreen(
                    activePacks = activePacks,
                    selectedPack = selectedPack,
                    coins = coinAccount.balance,
                    cloudCredentials = cloudCredentials,
                    showDeveloperTools = showDeveloperTools,
                    homeVersionLabel = homeVersionLabel,
                    onDeveloperVersionTripleTap = {
                        if (showDeveloperTools) {
                            devMenuRoutePreset = DevMenuRouteParams.PRESET_ENV_PREVIEW
                            route = AppRoute.DevMenu
                        }
                    },
                    onSelectPack = { selectedPackId = it.id },
                    onBoundChild = {
                        route = if (cloudCredentials == null) AppRoute.ScanBinding else AppRoute.BoundDeviceInfo
                    },
                    onStart = {
                        val sessionConfig = config.copy(timerSeconds = DEFAULT_BATTLE_TIMER_SECONDS)
                        battleRunId += 1
                        battleTimeLeft = DEFAULT_BATTLE_TIMER_SECONDS
                        engine = BattleEngine(config = sessionConfig, words = selectedPack.words)
                        battleState = engine.initialState()
                        route = AppRoute.Battle
                    },
                    onPackManager = { route = AppRoute.PackManager },
                    onWishlist = { route = AppRoute.Wishlist },
                    onMonsterCodex = { route = AppRoute.MonsterCodex },
                    onTodayPlan = { route = AppRoute.TodayPlan },
                    onConfig = { route = AppRoute.Config },
                )
                AppRoute.Battle -> BattleScreen(
                    runId = battleRunId,
                    state = battleState ?: engine.initialState().also { battleState = it },
                    pack = selectedPack,
                    config = config,
                    timeLeft = battleTimeLeft,
                    onAnswer = { answer ->
                        val outcome = engine.submitAnswerWithOutcome(battleState ?: engine.initialState(), answer)
                        selectedPack.words.firstOrNull { it.word == outcome.correctAnswer }?.let { answeredWord ->
                            learningRecorder.recordAnswer(
                                packId = selectedPack.id,
                                wordId = answeredWord.id,
                                correct = outcome.correct,
                                answeredAtMs = System.currentTimeMillis(),
                            )
                            repositories.saveLearningRecorder(learningRecorder)
                        }
                        val next = outcome.nextState
                        battleState = next
                        outcome
                    },
                    onBattleFinished = { finishedState ->
                        val sessionResult = engine.resultFor(finishedState).copy(packId = selectedPack.id)
                        val credited = coinAccount.creditBattleReward(sessionResult.stars, LocalDate.now().toString())
                        val sessionRecord = BattleSessionRecord(
                            packId = selectedPack.id,
                            won = sessionResult.won,
                            stars = sessionResult.stars,
                            correctCount = sessionResult.correctCount,
                            wrongCount = sessionResult.wrongCount,
                            defeatedMonsters = sessionResult.defeatedMonsters,
                            completedAtMs = System.currentTimeMillis(),
                        )
                        learningRecorder.recordSession(sessionRecord)
                        repositories.saveLearningRecorder(learningRecorder)
                        cloudCoordinator.syncStats(learningRecorder.statsSnapshot(), System.currentTimeMillis())
                        if (sessionRecord.perfect) {
                            val rotation = selection.recordPerfectRun(selectedPack.id, packLibrary)
                            selection = rotation.selection
                            repositories.saveSelection(selection)
                            selectedPackId = selection.activePackIds.firstOrNull() ?: selectedPack.id
                        }
                        coinAccount = credited.account
                        repositories.saveCoinAccount(coinAccount)
                        result = sessionResult.copy(coinDelta = credited.delta)
                        route = AppRoute.Result
                    },
                    onExit = { route = AppRoute.Home },
                )
                AppRoute.Result -> ResultScreen(
                    result = result ?: SessionResult(false, 0, 0, 0, 0, 0, 0),
                    coins = coinAccount.balance,
                    onHome = { route = AppRoute.Home },
                )
                AppRoute.Config -> ConfigScreen(
                    initialConfig = config,
                    activePackCount = selection.activePackIds.size,
                    maxActivePacks = PackSelectionStore.MAX_ACTIVE,
                    parentPinSet = parentPin.isNotEmpty(),
                    cloudBound = cloudCredentials != null,
                    cloudChildNickname = cloudCredentials?.childNickname.orEmpty().ifBlank { "宝贝" },
                    learningSyncBusy = learningSyncBusy,
                    learningSyncStatus = learningSyncStatus,
                    learningSyncToast = learningSyncToast,
                    onSave = { next ->
                        config = next
                        route = AppRoute.Home
                    },
                    onCancel = { route = AppRoute.Home },
                    onParentAdmin = { route = AppRoute.ParentPin },
                    onParentPinSetup = { route = AppRoute.ParentPin },
                    onCloudBinding = { route = if (cloudCredentials == null) AppRoute.ScanBinding else AppRoute.BoundDeviceInfo },
                    onPackManager = { route = AppRoute.PackManager },
                    onLearningSync = {
                        if (learningSyncBusy) return@ConfigScreen
                        val credentials = cloudCredentials
                        if (credentials == null) {
                            learningSyncToast = "未绑定家长账号，请先在“家长账户”中绑定"
                            return@ConfigScreen
                        }
                        appScope.launch {
                            learningSyncBusy = true
                            try {
                                val result = wordStatsSyncClient.sync(
                                    deviceToken = credentials.deviceToken,
                                    stats = learningRecorder.statsSnapshot(),
                                    syncedThroughMs = cloudRepositories.loadLearningSyncCheckpointMs(),
                                )
                                if (result.serverNowMs > 0) {
                                    cloudRepositories.saveLearningSyncCheckpointMs(result.serverNowMs)
                                }
                                learningSyncStatus = formatLearningSyncStatus(result)
                                learningSyncToast = formatLearningSyncToast(result)
                                cloudRepositories.saveLearningSyncStatus(learningSyncStatus)
                            } finally {
                                learningSyncBusy = false
                            }
                        }
                    },
                )
                AppRoute.ParentPin -> ParentPinScreen(
                    hasPin = parentPin.isNotEmpty(),
                    onBack = {
                        if (pendingRedemptionWishId != null) {
                            pendingRedemptionWishId = null
                            route = AppRoute.Wishlist
                        } else if (pendingCloudUnbind) {
                            pendingCloudUnbind = false
                            route = AppRoute.BoundDeviceInfo
                        } else {
                            route = AppRoute.Config
                        }
                    },
                    onSubmit = { value ->
                        val pinAccepted = if (parentPin.isEmpty()) {
                            parentPin = value
                            true
                        } else if (value == parentPin) {
                            true
                        } else {
                            false
                        }
                        if (pinAccepted && pendingRedemptionWishId != null) {
                            val redeemedWishId = pendingRedemptionWishId.orEmpty()
                            val redeemed = redemptionHistory.redeem(
                                account = coinAccount,
                                wishlist = wishlist,
                                wishId = redeemedWishId,
                                redeemedAtMs = System.currentTimeMillis(),
                                parentApproved = true,
                            )
                            coinAccount = redeemed.account
                            redemptionHistory = redeemed.history
                            localProgressMessage = redeemed.message
                            pendingRedemptionWishId = null
                            repositories.saveCoinAccount(coinAccount)
                            repositories.saveRedemptionHistory(redemptionHistory)
                            if (redeemed.accepted) {
                                wishlistGiftBoxTrigger = 0
                                wishlistGiftBoxVisible = true
                                recentlyRedeemedWishId = redeemedWishId
                                appScope.launch {
                                    delay(GIFTBOX_TRIGGER_DELAY_MS)
                                    wishlistGiftBoxTrigger += 1
                                    delay(GIFTBOX_MODAL_TOTAL_MS - GIFTBOX_TRIGGER_DELAY_MS)
                                    wishlistGiftBoxVisible = false
                                    delay(WISH_REDEEMED_ACK_MS)
                                    if (recentlyRedeemedWishId == redeemedWishId) {
                                        recentlyRedeemedWishId = null
                                    }
                                }
                            }
                            route = AppRoute.Wishlist
                        } else if (pinAccepted && pendingCloudUnbind) {
                            pendingCloudUnbind = false
                            cloudRepositories.clearCredentials()
                            cloudCredentials = null
                            cloudSyncStatus = "已解除绑定，本地进度保留"
                            cloudRepositories.saveSyncStatus(cloudSyncStatus)
                            route = AppRoute.Config
                        } else if (pinAccepted) {
                            route = AppRoute.ParentAdmin
                        }
                    },
                )
                AppRoute.ParentAdmin -> ParentAdminScreen(
                    onBack = { route = AppRoute.Config },
                    onReview = { route = AppRoute.LessonDraftReview },
                )
                AppRoute.LessonDraftReview -> LessonDraftReviewScreen(
                    onBack = { route = AppRoute.ParentAdmin },
                )
                AppRoute.PackManager -> PackManagerScreen(
                    packs = packLibrary.allPacks(),
                    selection = selection,
                    message = localProgressMessage,
                    onToggleActive = { pack ->
                        val mutation = if (pack.id in selection.activePackIds) {
                            selection.deactivate(pack.id)
                        } else {
                            selection.activate(pack.id)
                        }
                        selection = mutation.selection
                        if (selectedPackId !in selection.activePackIds && selection.activePackIds.isNotEmpty()) {
                            selectedPackId = selection.activePackIds.first()
                        }
                        localProgressMessage = mutation.message
                        repositories.saveSelection(selection)
                    },
                    onTogglePin = { pack ->
                        val mutation = selection.togglePin(pack.id)
                        selection = mutation.selection
                        localProgressMessage = mutation.message
                        repositories.saveSelection(selection)
                    },
                    onSync = {
                        val syncResult = cloudCoordinator.syncPacks(cloudCredentials)
                        globalPacks = syncResult.globalPacks.ifEmpty { globalPacks }
                        familyPacks = syncResult.familyPacks.ifEmpty { familyPacks }
                        cloudRepositories.saveGlobalPacks(globalPacks)
                        cloudRepositories.saveFamilyPacks(familyPacks)
                        cloudSyncStatus = syncResult.statusMessage
                        localProgressMessage = syncResult.statusMessage
                        cloudRepositories.saveSyncStatus(cloudSyncStatus)
                    },
                    onBack = { route = AppRoute.Home },
                )
                AppRoute.Wishlist -> WishlistScreen(
                    coinAccount = coinAccount,
                    wishlist = wishlist,
                    message = localProgressMessage,
                    giftBoxVisible = wishlistGiftBoxVisible,
                    giftBoxTrigger = wishlistGiftBoxTrigger,
                    recentlyRedeemedWishId = recentlyRedeemedWishId,
                    onRedeem = { wish ->
                        pendingRedemptionWishId = wish.id
                        route = AppRoute.ParentPin
                    },
                    onHistory = { route = AppRoute.RedemptionHistory },
                    onAddCustom = {
                        if (parentPin.length != 6) {
                            Toast.makeText(
                                context,
                                "请先在设置页面配置家长密码（6 位数字），再使用此功能。",
                                Toast.LENGTH_SHORT,
                            ).show()
                        } else {
                            Toast.makeText(
                                context,
                                "自定义愿望功能即将在 Android 版推出。",
                                Toast.LENGTH_SHORT,
                            ).show()
                        }
                    },
                    onBack = { route = AppRoute.Home },
                )
                AppRoute.RedemptionHistory -> RedemptionHistoryScreen(
                    history = redemptionHistory,
                    onBack = { route = AppRoute.Wishlist },
                )
                AppRoute.MonsterCodex -> MonsterCodexScreen(
                    catalog = monsterCatalog,
                    onPrevious = { monsterCatalog = monsterCatalog.previous() },
                    onNext = { monsterCatalog = monsterCatalog.next() },
                    onBack = { route = AppRoute.Home },
                )
                AppRoute.TodayPlan -> TodayPlanScreen(
                    plan = TodayPlanService().buildUi(
                        library = packLibrary,
                        activeIds = selection.activePackIds,
                        stats = learningRecorder.statsSnapshot(),
                        regionDisplayName = selectedPack.nameZh,
                        nowMs = System.currentTimeMillis(),
                    ),
                    onReport = { route = AppRoute.LearningReport },
                    onBack = { route = AppRoute.Home },
                )
                AppRoute.LearningReport -> LearningReportScreen(
                    report = LearningReportBuilder().build(packLibrary, selection.activePackIds, learningRecorder.statsSnapshot()),
                    onBack = { route = AppRoute.TodayPlan },
                )
                AppRoute.ScanBinding -> ScanBindingScreen(
                    deviceId = cloudRepositories.deviceIdProvider.getOrCreate(),
                    error = bindingError,
                    onRedeem = { code ->
                        if (bindingError == "正在绑定...") return@ScanBindingScreen
                        appScope.launch {
                            bindingError = "正在绑定..."
                            when (val result = bindingClient.redeemShortCode(code, cloudRepositories.deviceIdProvider.getOrCreate())) {
                                is BindingResult.Success -> {
                                    cloudRepositories.saveCredentials(result.credentials)
                                    cloudCredentials = result.credentials
                                    bindingError = ""
                                    val syncResult = cloudCoordinator.syncPacks(cloudCredentials)
                                    globalPacks = syncResult.globalPacks.ifEmpty { globalPacks }
                                    familyPacks = syncResult.familyPacks.ifEmpty { familyPacks }
                                    cloudRepositories.saveGlobalPacks(globalPacks)
                                    cloudRepositories.saveFamilyPacks(familyPacks)
                                    cloudSyncStatus = syncResult.statusMessage
                                    cloudRepositories.saveSyncStatus(cloudSyncStatus)
                                    route = AppRoute.BoundDeviceInfo
                                }
                                is BindingResult.Failure -> bindingError = result.message
                            }
                        }
                    },
                    onBack = { route = AppRoute.Config },
                )
                AppRoute.BoundDeviceInfo -> BoundDeviceInfoScreen(
                    credentials = cloudCredentials,
                    syncStatus = cloudSyncStatus,
                    onEditProfile = { nickname, avatarEmoji ->
                        val current = cloudCredentials
                            ?: return@BoundDeviceInfoScreen "当前未绑定，请先扫码"
                        try {
                            val updated = childProfileClient.updateProfile(
                                current.deviceToken,
                                nickname,
                                avatarEmoji,
                            )
                            val next = current.copy(
                                childNickname = updated.nickname,
                                avatarEmoji = updated.avatarEmoji.ifBlank { avatarEmoji },
                                familyLabel = updated.familyId.ifBlank { current.familyLabel },
                            )
                            cloudRepositories.saveCredentials(next)
                            cloudCredentials = next
                            null
                        } catch (err: ChildProfileException) {
                            childProfileErrorMessage(err)
                        }
                    },
                    onUnbind = {
                        pendingCloudUnbind = true
                        route = AppRoute.ParentPin
                    },
                    onBack = { route = AppRoute.Config },
                )
                AppRoute.DevMenu -> DevMenuScreen(
                    state = backendRouteState,
                    previews = previewTargets,
                    routingSummary = devMenuViewModel.routingSummary(backendRouteState),
                    probeStatus = probeStatus,
                    manifestBusy = previewManifestBusy,
                    applying = backendApplying,
                    onSelectEnv = { env ->
                        applyBackendRoute(BackendRouteState(env = env))
                    },
                    onRefreshManifest = {
                        if (!previewManifestBusy) {
                            appScope.launch {
                                previewManifestBusy = true
                                try {
                                    previewTargets = devMenuViewModel.refreshManifest(previewTargets, force = true)
                                } finally {
                                    previewManifestBusy = false
                                }
                            }
                        }
                    },
                    onSelectPreview = { preview ->
                        val secret = debugRoutingRepository.bypassSecretStore.load()
                        if (secret.isBlank()) {
                            pendingPreviewAfterSecret = preview
                            route = AppRoute.BypassSecret
                        } else {
                            applyBackendRoute(devMenuViewModel.selectPreview(backendRouteState, preview), secret)
                        }
                    },
                    onProbe = { probeStatus = devMenuViewModel.probe(backendRouteState) },
                    onBypassSecret = { route = AppRoute.BypassSecret },
                    onClear = {
                        backendRouteState = BackendRouteState()
                        debugRoutingRepository.clearRouteState()
                    },
                    onBack = { route = AppRoute.Home },
                )
                AppRoute.BypassSecret -> BypassSecretScreen(
                    initialSecret = debugRoutingRepository.bypassSecretStore.load(),
                    onSave = { secret ->
                        debugRoutingRepository.bypassSecretStore.save(secret)
                        val pendingPreview = pendingPreviewAfterSecret
                        if (pendingPreview != null) {
                            pendingPreviewAfterSecret = null
                            applyBackendRoute(devMenuViewModel.selectPreview(backendRouteState, pendingPreview), secret)
                        } else {
                            route = AppRoute.DevMenu
                        }
                    },
                    onClear = {
                        debugRoutingRepository.bypassSecretStore.clear()
                        pendingPreviewAfterSecret = null
                        route = AppRoute.DevMenu
                    },
                    onCancel = {
                        pendingPreviewAfterSecret = null
                        route = AppRoute.DevMenu
                    },
                )
            }
        }
    }
}

@Composable
private fun ApplyOrientation(route: AppRoute) {
    val activity = LocalContext.current as? Activity
    DisposableEffect(route) {
        activity?.requestedOrientation = when (route) {
            AppRoute.ParentPin,
            AppRoute.ParentAdmin,
            AppRoute.LessonDraftReview -> ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
            else -> ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
        }
        onDispose {}
    }
}

private fun childProfileErrorMessage(err: ChildProfileException): String = when (err.code) {
    "INVALID_NICKNAME" -> "名字不能为空"
    "BINDING_NOT_FOUND" -> "当前后端未找到绑定记录"
    "BINDING_REVOKED" -> "绑定已被撤销，请重新扫码配对"
    "NETWORK" -> "网络错误，请稍后重试"
    "NOT_BOUND" -> "当前未绑定，请先扫码"
    else -> if (err.status > 0) "保存失败 (HTTP ${err.status})" else "保存失败，请稍后重试"
}

@Composable
private fun HomeScreen(
    activePacks: List<WordPack>,
    selectedPack: WordPack,
    coins: Int,
    cloudCredentials: cool.happyword.wordmagic.core.CloudCredentials?,
    showDeveloperTools: Boolean,
    homeVersionLabel: String,
    onDeveloperVersionTripleTap: () -> Unit,
    onSelectPack: (WordPack) -> Unit,
    onBoundChild: () -> Unit,
    onStart: () -> Unit,
    onPackManager: () -> Unit,
    onWishlist: () -> Unit,
    onMonsterCodex: () -> Unit,
    onTodayPlan: () -> Unit,
    onConfig: () -> Unit,
) {
    var reviewLockedToastVisible by remember { mutableStateOf(false) }
    val versionTripleTap = remember { VersionTripleTap() }

    LaunchedEffect(reviewLockedToastVisible) {
        if (reviewLockedToastVisible) {
            delay(1_800)
            reviewLockedToastVisible = false
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .testTag("HomeScreen"),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .fillMaxHeight()
                .padding(horizontal = 44.dp)
                .padding(top = 72.dp, bottom = 10.dp),
        ) {
            Text(
                "Small Magician Word Adventure",
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFF303030),
            )
            Spacer(Modifier.height(8.dp))

            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .border(1.dp, colorFromSceneHex(selectedPack.scene.bgAccent, Color(0xFFFFD2A6)), RoundedCornerShape(28.dp))
                    .testTag("AdventureCard"),
                shape = RoundedCornerShape(28.dp),
                colors = CardDefaults.cardColors(
                    containerColor = colorFromSceneHex(selectedPack.scene.bgPrimary, Color(0xFFFFF7E6)),
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
            ) {
                Column(modifier = Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(selectedPack.nameEn, modifier = Modifier.testTag("AdventureCardTitle"), fontSize = 26.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
                        Spacer(Modifier.weight(1f))
                        SmallPill("今日")
                    }
                    LazyRow(
                        horizontalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterHorizontally),
                        modifier = Modifier.fillMaxWidth().testTag("PackChipRow"),
                    ) {
                        items(activePacks) { pack ->
                            val selected = pack.id == selectedPack.id
                            OutlinedButton(
                                onClick = { onSelectPack(pack) },
                                colors = ButtonDefaults.outlinedButtonColors(
                                    containerColor = if (selected) Color(0xFFFF0050) else Color.White,
                                    contentColor = if (selected) Color.White else Color(0xFF4F3424),
                                ),
                                modifier = Modifier.height(42.dp).testTag("RegionChip_${pack.id}"),
                                contentPadding = PaddingValues(horizontal = 18.dp, vertical = 0.dp),
                            ) {
                                Text(pack.nameEn, fontSize = 15.sp, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        SmallPill("常规")
                        SmallPill("拼写")
                        SmallPill("复习")
                        SmallPill("精英")
                        SmallPill("首领")
                    }
                    Text("今天的冒险包含 5 关卡，含拼写、复习与首领关", fontSize = 18.sp, color = Color(0xFF6A5843), modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center)
                    Button(
                        onClick = onStart,
                        modifier = Modifier.fillMaxWidth().height(46.dp).testTag("HomeStartButton"),
                        shape = RoundedCornerShape(18.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFFF0050)),
                        contentPadding = PaddingValues(vertical = 0.dp),
                    ) { Text("开始今日冒险", fontSize = 20.sp, fontWeight = FontWeight.Bold) }
                }
            }
        }

        if (showDeveloperTools && homeVersionLabel.isNotEmpty()) {
            Text(
                homeVersionLabel,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 8.dp)
                    .fillMaxWidth(0.55f)
                    .testTag("HomeVersionLabel")
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                    ) {
                        if (versionTripleTap.onTap(System.currentTimeMillis())) {
                            onDeveloperVersionTripleTap()
                        }
                    },
                fontSize = 11.sp,
                color = Color(0xFF999999),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }

        Row(
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 16.dp, end = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (cloudCredentials != null) {
                HomeBadge(
                    text = "${cloudCredentials.avatarEmoji.ifBlank { "🦄" }} ${cloudCredentials.childNickname.ifBlank { "宝贝" }}",
                    modifier = Modifier
                        .testTag("HomeBoundChildBadge")
                        .clickable(onClick = onBoundChild),
                    textColor = Color(0xFF0369A1),
                    backgroundColor = Color(0xFFE0F2FE),
                    fontSize = 14.sp,
                    horizontalPadding = 10.dp,
                )
            }
            HomeBadge(
                text = "✨ $coins",
                modifier = Modifier.testTag("HomeCoinBalance"),
                textColor = Color(0xFFFFB400),
                backgroundColor = Color(0xFFFFF6E5),
                fontSize = 16.sp,
                horizontalPadding = 12.dp,
            )
            IconCircle(R.drawable.icon_review, "复习", Modifier.testTag("HomeReviewButton"), backgroundColor = Color(0xFFFCEAEA), onClick = { reviewLockedToastVisible = true })
            IconCircle(R.drawable.icon_codex, "图鉴", Modifier.testTag("HomeCodexButton"), backgroundColor = Color(0xFFFCEAEA), onClick = onMonsterCodex)
            EmojiCircle("📋", "今日计划", Modifier.testTag("HomePlanButton"), backgroundColor = Color(0xFFFCEAEA), onClick = onTodayPlan)
            IconCircle(R.drawable.icon_wishlist, "愿望", Modifier.testTag("HomeWishlistButton"), backgroundColor = Color(0xFFFCEAEA), onClick = onWishlist)
            IconCircle(R.drawable.icon_gear, "设置", Modifier.testTag("HomeConfigButton"), backgroundColor = Color(0xFFEAF2F8), onClick = onConfig)
        }

        if (reviewLockedToastVisible) {
            Text(
                "先答错几题再来复习吧",
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 96.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color(0xCC3A3A3A))
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .testTag("HomeReviewLockedToast"),
                fontSize = 14.sp,
                color = Color.White,
            )
        }
    }
}

@Composable
private fun BattleScreen(
    runId: Int,
    state: BattleState,
    pack: WordPack,
    config: GameConfig,
    timeLeft: Int,
    onAnswer: (String) -> BattleAnswerOutcome,
    onBattleFinished: (BattleState) -> Unit,
    onExit: () -> Unit,
) {
    val context = LocalContext.current
    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    var activeOutcome by remember(runId) { mutableStateOf<BattleAnswerOutcome?>(null) }
    var ttsReady by remember { mutableStateOf(false) }
    var ttsEngine by remember { mutableStateOf<TextToSpeech?>(null) }
    var ttsPlayer by remember { mutableStateOf<MediaPlayer?>(null) }
    var ttsRequestId by remember { mutableIntStateOf(0) }
    var pendingSpeech by remember { mutableStateOf<String?>(null) }
    val speakWord: (String) -> Unit = { word ->
        val cleanWord = word.trim()
        if (cleanWord.isNotEmpty()) {
            val engine = ttsEngine
            if (ttsReady && engine != null) {
                ttsRequestId += 1
                val utteranceId = "battle-tts-$ttsRequestId"
                val outputFile = File(context.cacheDir, "$utteranceId.wav")
                engine.stop()
                val result = engine.synthesizeToFile(cleanWord, null, outputFile, utteranceId)
                if (result == TextToSpeech.ERROR) {
                    Log.w("WordMagicTTS", "synthesizeToFile failed to start for word=$cleanWord")
                }
            } else {
                pendingSpeech = cleanWord
            }
        }
    }

    DisposableEffect(context.applicationContext) {
        val holder = arrayOfNulls<TextToSpeech>(1)
        val engine = TextToSpeech(context.applicationContext) { status ->
            mainHandler.post {
                val initializedEngine = holder[0] ?: return@post
                if (status == TextToSpeech.SUCCESS) {
                    val languageStatus = initializedEngine.setLanguage(Locale.US)
                    val languageReady = languageStatus != TextToSpeech.LANG_MISSING_DATA &&
                        languageStatus != TextToSpeech.LANG_NOT_SUPPORTED
                    initializedEngine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) = Unit

                        override fun onDone(utteranceId: String?) {
                            if (utteranceId == null) return
                            val outputFile = File(context.cacheDir, "$utteranceId.wav")
                            mainHandler.post {
                                if (outputFile.exists()) {
                                    ttsPlayer?.stop()
                                    ttsPlayer?.release()
                                    ttsPlayer = MediaPlayer().apply {
                                        setDataSource(outputFile.absolutePath)
                                        setOnCompletionListener { completed ->
                                            completed.release()
                                            if (ttsPlayer === completed) {
                                                ttsPlayer = null
                                            }
                                            outputFile.delete()
                                        }
                                        setOnErrorListener { failed, _, _ ->
                                            failed.release()
                                            if (ttsPlayer === failed) {
                                                ttsPlayer = null
                                            }
                                            outputFile.delete()
                                            true
                                        }
                                        prepare()
                                        start()
                                    }
                                }
                            }
                        }

                        @Suppress("DEPRECATION")
                        override fun onError(utteranceId: String?) {
                            Log.w("WordMagicTTS", "TTS synthesis error utteranceId=$utteranceId")
                        }

                        override fun onError(utteranceId: String?, errorCode: Int) {
                            Log.w("WordMagicTTS", "TTS synthesis error utteranceId=$utteranceId code=$errorCode")
                        }
                    })
                    ttsEngine = initializedEngine
                    ttsReady = languageReady
                } else {
                    Log.w("WordMagicTTS", "TextToSpeech init failed status=$status")
                    ttsReady = false
                }
            }
        }
        holder[0] = engine
        onDispose {
            ttsPlayer?.stop()
            ttsPlayer?.release()
            engine.stop()
            engine.shutdown()
        }
    }
    LaunchedEffect(ttsReady, pendingSpeech) {
        val word = pendingSpeech
        if (ttsReady && word != null) {
            pendingSpeech = null
            speakWord(word)
        }
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
            playBattleSound(context, if (outcome.comboTriggered) R.raw.hit_crit else R.raw.hit_normal)
            if (outcome.monsterDefeated && !outcome.battleEnded) {
                delay(120)
                playBattleSound(context, R.raw.monster_defeat)
            }
        } else {
            playBattleSound(context, R.raw.answer_wrong)
            delay(PROJECTILE_IMPACT_MS)
            playBattleSound(context, R.raw.player_hurt)
        }
        val remainingFeedback = BATTLE_FEEDBACK_MS - PROJECTILE_IMPACT_MS
        if (remainingFeedback > 0) {
            delay(remainingFeedback)
        }
        val finishedState = outcome.nextState
        activeOutcome = null
        if (finishedState.status != BattleStatus.Playing) {
            onBattleFinished(finishedState)
        }
    }
    LaunchedEffect(runId, state.question.correctAnswer, config.autoPronunciation, ttsReady, activeOutcome) {
        if (config.autoPronunciation && ttsReady && activeOutcome == null && state.status == BattleStatus.Playing) {
            delay(250)
            speakWord(state.question.correctAnswer)
        }
    }

    val displayQuestion = if (activeOutcome?.advancedStep == true) state.question else activeOutcome?.question ?: state.question
    val feedbackLocked = activeOutcome != null

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFF9FAFC))
            .padding(horizontal = 24.dp, vertical = 14.dp)
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
                OutlinedButton(onClick = onExit, enabled = !feedbackLocked) { Text("Back") }
            }
            Spacer(Modifier.height(18.dp))
            Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
                Row(modifier = Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(30.dp)) {
                    CharacterPanel(
                        title = "Small Magician",
                        hp = state.playerHp,
                        maxHp = config.playerHp,
                        image = R.raw.character_magican,
                        fightImage = R.raw.character_magican_fight,
                        hurtImage = R.raw.character_magican_beaten,
                        modifier = Modifier.weight(0.86f),
                        panelColor = Color(0xFFDCEEFF),
                        borderColor = Color(0xFFA8CCF0),
                        isCasting = activeOutcome?.correct == true,
                        isCritCasting = activeOutcome?.comboTriggered == true,
                        isHurt = activeOutcome?.playerDamaged == true,
                    )
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
                    CharacterPanel(
                        title = "Word Monster",
                        hp = state.monsterHp,
                        maxHp = config.monsterHp,
                        image = monsterResourceForPack(pack.id),
                        modifier = Modifier.weight(0.86f),
                        panelColor = Color(0xFFF7D2D2),
                        borderColor = Color(0xFFEAA0A0),
                        isHurt = activeOutcome?.correct == true && activeOutcome?.comboTriggered != true,
                        isZoomHit = activeOutcome?.comboTriggered == true,
                    )
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
        CritBurstOverlay(outcome = activeOutcome, modifier = Modifier.fillMaxSize().zIndex(4f))
    }
}

@Composable
private fun BattleQuestionPrompt(question: Question) {
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
            QuestionKind.FillLetter, QuestionKind.FillLetterMedium -> {
                Text(question.prompt, color = Color(0xFF6A5843), fontSize = 18.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(6.dp))
                Text(
                    if (question.kind == QuestionKind.FillLetter) question.letterTemplate else question.letterTemplateBase,
                    fontSize = 42.sp,
                    fontWeight = FontWeight.Black,
                    color = Color(0xFF1C3655),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun BattleAnswerArea(
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
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, option ->
            val buttonColor = answerButtonColor(option, outcome)
            Button(
                onClick = { onSelect(option) },
                enabled = !feedbackLocked,
                modifier = Modifier
                    .weight(1f)
                    .height(58.dp)
                    .testTag("BattleAnswer_$index"),
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
private fun SpellAnswerArea(question: Question, feedbackLocked: Boolean, onComplete: (String) -> Unit) {
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
                Button(
                    onClick = {
                        if (feedbackLocked || used || completed || wrongPoolIndex >= 0) return@Button
                        val nextSlot = slots.indexOfFirst { it.isBlank() }
                        if (nextSlot < 0) return@Button
                        val expected = question.spellLetters.getOrNull(nextSlot)
                        if (letter != expected) {
                            wrongPoolIndex = index
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
                        .testTag("BattleSpellPool_$index"),
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

private fun answerOptions(question: Question): List<String> {
    return when (question.kind) {
        QuestionKind.Choice -> question.options
        QuestionKind.FillLetter -> question.letterOptions
        QuestionKind.FillLetterMedium -> question.letterOptionsSteps.getOrElse(question.currentStep) { emptyList() }
        QuestionKind.Spell -> question.spellPool
    }
}

@Composable
private fun BattleFeedbackText(outcome: BattleAnswerOutcome) {
    val text = when {
        outcome.advancedStep -> "Good! Next letter"
        outcome.comboTriggered -> "Combo 3! Magic Burst x2"
        outcome.correct -> "Hit! -${outcome.damage}"
        else -> "Correct: ${correctOptionForOutcome(outcome)}"
    }
    val color = when {
        outcome.comboTriggered -> Color(0xFFC27A00)
        outcome.correct -> Color(0xFF147C42)
        else -> Color(0xFFD23A3A)
    }
    Text(text, color = color, fontSize = 17.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
}

private fun answerButtonColor(option: String, outcome: BattleAnswerOutcome?): Color {
    if (outcome == null) return Color(0xFF8253A8)
    val correctOption = correctOptionForOutcome(outcome)
    return when {
        option == outcome.selectedAnswer && outcome.correct -> Color(0xFF16A765)
        option == outcome.selectedAnswer && !outcome.correct -> Color(0xFFE04444)
        option == correctOption && !outcome.correct -> Color(0xFF16A765)
        else -> Color(0xFFB7A1C8)
    }
}

private fun correctOptionForOutcome(outcome: BattleAnswerOutcome): String {
    return when (outcome.question.kind) {
        QuestionKind.Choice -> outcome.correctAnswer
        QuestionKind.FillLetter -> outcome.question.letterAnswer
        QuestionKind.FillLetterMedium -> outcome.question.letterAnswers.getOrElse(outcome.question.currentStep) { outcome.correctAnswer }
        QuestionKind.Spell -> outcome.correctAnswer
    }
}

@Composable
private fun BattleProjectileOverlay(outcome: BattleAnswerOutcome?, modifier: Modifier = Modifier) {
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
private fun CritBurstOverlay(outcome: BattleAnswerOutcome?, modifier: Modifier = Modifier) {
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

private fun playBattleSound(context: android.content.Context, @RawRes sound: Int) {
    runCatching {
        val player = MediaPlayer.create(context.applicationContext, sound) ?: return
        player.setOnCompletionListener { completed -> completed.release() }
        player.start()
    }
}

private fun formatCountdown(totalSeconds: Int): String {
    val safeSeconds = totalSeconds.coerceAtLeast(0)
    val minutes = safeSeconds / 60
    val seconds = safeSeconds % 60
    return "$minutes:${seconds.toString().padStart(2, '0')}"
}

private fun resolveBattleTimerSeconds(config: GameConfig): Int {
    return if (config.timerSeconds in setOf(3, 30, 180, DEFAULT_BATTLE_TIMER_SECONDS, 600)) {
        config.timerSeconds
    } else {
        DEFAULT_BATTLE_TIMER_SECONDS
    }
}

@RawRes
private fun monsterResourceForPack(packId: String): Int {
    return when (packId) {
        "school-castle", "ocean-realm" -> R.raw.character_zombie
        "home-cottage" -> R.raw.character_dragon
        else -> R.raw.character_slime
    }
}

@Composable
private fun ResultScreen(result: SessionResult, coins: Int, onHome: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFFF3DC))
            .padding(24.dp)
            .testTag("ResultScreen"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(if (result.won) "冒险胜利" else "继续加油", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = Color(0xFF3B2418))
        Text("★".repeat(result.stars).ifEmpty { "☆" }, fontSize = 40.sp, color = Color(0xFFFFB400))
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard("击败怪物", "${result.defeatedMonsters}")
            StatCard("正确率", "${result.accuracyPercent}%")
            StatCard("学习单词", "${result.learnedWordCount}")
            StatCard("魔法币", "+${result.coinDelta} / $coins")
        }
        Spacer(Modifier.height(22.dp))
        Button(onClick = onHome, modifier = Modifier.width(240.dp).height(54.dp).testTag("ResultHomeButton")) {
            Text("回到首页", fontSize = 18.sp)
        }
    }
}

private fun formatLearningSyncStatus(result: WordStatsSyncResult): String {
    if (result.serverNowMs <= 0L) return "上次同步时间未知"
    val formatted = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(result.serverNowMs))
    return "上次成功同步 $formatted"
}

private fun formatLearningSyncToast(result: WordStatsSyncResult): String = when (result.status) {
    WordStatsSyncStatus.Unbound -> "未绑定家长账号，请先在“家长账户”中绑定"
    WordStatsSyncStatus.NoChanges -> "没有新的学习记录"
    WordStatsSyncStatus.Pushed -> "已上传 ${result.pushed} 条学习记录"
    WordStatsSyncStatus.Pulled -> "已合并 ${result.pulled} 条服务器记录"
    WordStatsSyncStatus.PushedAndPulled -> "已上传 ${result.pushed} 条 / 合并 ${result.pulled} 条服务器记录"
    WordStatsSyncStatus.NetworkError -> "同步失败：网络异常，请稍后重试"
}

private val HarmonyBattleHpRange = 1..10
private val HarmonyMonsterCountRange = 1..10

private fun harmonyTimerChipBase(seconds: Int): String =
    if (seconds < 60) "${seconds}s" else "${seconds / 60}m"

private fun harmonyTimerChipLabel(seconds: Int, selectedSeconds: Int): String {
    val base = harmonyTimerChipBase(seconds)
    return if (seconds == selectedSeconds) "\u2713$base" else base
}

private fun harmonyCustomTimerChipLabel(timerSeconds: Int): String {
    val custom = timerSeconds !in GameConfig.timerPresets
    return if (custom) "\u2713自定义 (${harmonyTimerChipBase(timerSeconds)})" else "自定义"
}

@Composable
private fun HarmonyConfigStepperRow(
    label: String,
    value: Int,
    testTagPrefix: String,
    range: IntRange,
    onValueChange: (Int) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
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

@Composable
private fun ConfigScreen(
    initialConfig: GameConfig,
    activePackCount: Int,
    maxActivePacks: Int,
    parentPinSet: Boolean,
    cloudBound: Boolean,
    cloudChildNickname: String,
    learningSyncBusy: Boolean,
    learningSyncStatus: String,
    learningSyncToast: String,
    onSave: (GameConfig) -> Unit,
    onCancel: () -> Unit,
    onParentAdmin: () -> Unit,
    onParentPinSetup: () -> Unit,
    onCloudBinding: () -> Unit,
    onPackManager: () -> Unit,
    onLearningSync: () -> Unit,
) {
    var draft by remember(initialConfig) { mutableStateOf(initialConfig) }
    var showCustomTimerDialog by remember { mutableStateOf(false) }
    var customTimerText by remember { mutableStateOf("") }
    var customTimerError by remember { mutableStateOf("") }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(horizontal = 40.dp, vertical = 16.dp)
            .verticalScroll(rememberScrollState())
            .testTag("ConfigScreen"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            "游戏设置",
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
                value = draft.playerHp,
                testTagPrefix = "ConfigPlayerHp",
                range = HarmonyBattleHpRange,
                onValueChange = { draft = draft.copy(playerHp = it) },
            )
            HarmonyConfigStepperRow(
                label = "怪物血量",
                value = draft.monsterHp,
                testTagPrefix = "ConfigMonsterHp",
                range = HarmonyBattleHpRange,
                onValueChange = { draft = draft.copy(monsterHp = it) },
            )
            HarmonyConfigStepperRow(
                label = "怪物数量",
                value = draft.monsterCount,
                testTagPrefix = "ConfigMonsterCount",
                range = HarmonyMonsterCountRange,
                onValueChange = { draft = draft.copy(monsterCount = it) },
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("倒计时", fontSize = 18.sp, modifier = Modifier.width(120.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                GameConfig.timerPresets.forEach { sec ->
                    val selected = draft.timerSeconds == sec
                    Button(
                        onClick = { draft = draft.copy(timerSeconds = sec) },
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
                        Text(harmonyTimerChipLabel(sec, draft.timerSeconds), fontSize = 16.sp)
                    }
                }
                val customSelected = draft.timerSeconds !in GameConfig.timerPresets
                Button(
                    onClick = {
                        customTimerText = "${draft.timerSeconds}"
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
                    Text(harmonyCustomTimerChipLabel(draft.timerSeconds), fontSize = 16.sp)
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("发音播放", fontSize = 18.sp, modifier = Modifier.width(120.dp))
            Button(
                onClick = { draft = draft.copy(autoPronunciation = !draft.autoPronunciation) },
                modifier = Modifier
                    .width(140.dp)
                    .height(40.dp)
                    .testTag("ConfigAutoSpeakToggle"),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (draft.autoPronunciation) Color(0xFFFFF4D0) else Color(0xFFF0F0F0),
                    contentColor = if (draft.autoPronunciation) Color(0xFFB8860B) else Color(0xFF666666),
                ),
                shape = RoundedCornerShape(8.dp),
                border = if (draft.autoPronunciation) BorderStroke(2.dp, Color(0xFFFFB400)) else null,
            ) {
                Text(
                    if (draft.autoPronunciation) "\u2713 自动朗读" else "自动朗读",
                    fontSize = 16.sp,
                )
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
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
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("家长密码", fontSize = 18.sp, modifier = Modifier.width(120.dp))
            Button(
                onClick = onParentPinSetup,
                modifier = Modifier
                    .width(220.dp)
                    .height(40.dp)
                    .testTag("ConfigParentPinButton"),
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (parentPinSet) Color(0xFFFFF4D0) else Color(0xFFEAF2F8),
                    contentColor = if (parentPinSet) Color(0xFFB8860B) else Color(0xFF457B9D),
                ),
                shape = RoundedCornerShape(8.dp),
                border = if (parentPinSet) BorderStroke(2.dp, Color(0xFFFFB400)) else null,
            ) {
                Text(
                    if (parentPinSet) "修改 (•••••• 已设置)" else "设置",
                    fontSize = 15.sp,
                )
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("家长账户", fontSize = 18.sp, modifier = Modifier.width(120.dp))
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
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 8.dp)
                    .testTag("ConfigCloudSyncRow"),
                verticalAlignment = Alignment.CenterVertically,
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
                        .padding(start = 120.dp, bottom = 4.dp)
                        .testTag("ConfigCloudSyncStatus"),
                )
            }
            if (learningSyncToast.isNotBlank()) {
                Text(
                    learningSyncToast,
                    color = Color(0xFFFF0050),
                    fontSize = 14.sp,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 120.dp, bottom = 8.dp)
                        .testTag("ConfigCloudSyncToast"),
                )
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
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
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Button(
                onClick = onCancel,
                modifier = Modifier
                    .width(160.dp)
                    .height(48.dp)
                    .testTag("ConfigCancelButton"),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFFBDBDBD),
                    contentColor = Color.White,
                ),
            ) {
                Text("取消", fontSize = 16.sp)
            }
            Spacer(Modifier.width(16.dp))
            Button(
                onClick = { onSave(draft) },
                modifier = Modifier
                    .width(160.dp)
                    .height(48.dp)
                    .testTag("ConfigSaveButton"),
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF2ECC71),
                    contentColor = Color.White,
                ),
            ) {
                Text("保存", fontSize = 16.sp)
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
                            draft = draft.copy(timerSeconds = v.seconds)
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
private fun ParentPinScreen(hasPin: Boolean, onBack: () -> Unit, onSubmit: (String) -> Unit) {
    var pin by remember { mutableStateOf("") }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFFF6E7))
            .padding(24.dp)
            .testTag("ParentPinScreen"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(if (hasPin) "验证家长密码" else "设置家长密码", fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(16.dp))
        OutlinedTextField(
            value = pin,
            onValueChange = {
                val nextPin = it.filter(Char::isDigit).take(6)
                pin = nextPin
                if (ParentPinStore.isValidPin(nextPin)) {
                    onSubmit(nextPin)
                }
            },
            label = { Text("6 位数字密码") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            modifier = Modifier.testTag("ParentPinInput"),
        )
        Spacer(Modifier.height(12.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = onBack) { Text("返回") }
            Button(
                onClick = { if (ParentPinStore.isValidPin(pin)) onSubmit(pin) },
                enabled = ParentPinStore.isValidPin(pin),
                modifier = Modifier.testTag("ParentPinSubmit"),
            ) {
                Text(if (hasPin) "验证并进入" else "保存并进入")
            }
        }
    }
}

@Composable
private fun ParentAdminScreen(onBack: () -> Unit, onReview: () -> Unit) {
    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(20.dp)
            .testTag("ParentAdminScreen"),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("家长管理后台", fontSize = 28.sp, fontWeight = FontWeight.Black, color = Color(0xFF2E2F33))
                Spacer(Modifier.weight(1f))
                OutlinedButton(onClick = onBack) { Text("返回") }
            }
            Text("服务器：本地模拟数据", color = Color(0xFF666B74), fontSize = 16.sp)
        }
        item {
            SettingCard("学习概览") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    StatCard("今日完成", "1 局")
                    StatCard("正确率", "92%")
                    StatCard("待审核", "2")
                }
            }
        }
        item {
            SettingCard("课本图片导入") {
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = onReview, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF213E66))) { Text("📷 拍照导入") }
                    Button(onClick = onReview, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4E88A8))) { Text("🖼 从相册选择") }
                }
            }
        }
        item {
            SettingCard("待审核草稿") {
                DraftRow("水果课本第一页", "apple / banana / pear", onReview)
                DraftRow("家庭物品复习", "chair / desk / lamp", onReview)
            }
        }
        item {
            SettingCard("发布新词包") {
                Text("确认草稿后，可发布给孩子设备同步。")
                Spacer(Modifier.height(8.dp))
                Button(onClick = {}, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF213E66))) { Text("发布新版本词包") }
            }
        }
    }
}

@Composable
private fun LessonDraftReviewScreen(onBack: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFFF6E7))
            .padding(18.dp)
            .testTag("LessonDraftReviewScreen"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("草稿审核", fontSize = 26.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = onBack) { Text("返回") }
        }
        Spacer(Modifier.height(12.dp))
        SettingCard("主题标签") { Text("水果森林 · 课本导入") }
        SettingCard("候选单词") {
            listOf("apple 苹果", "banana 香蕉", "pear 梨").forEach { row ->
                Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(row, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.weight(1f))
                    OutlinedButton(onClick = {}) { Text("保留") }
                    Spacer(Modifier.width(6.dp))
                    OutlinedButton(onClick = {}) { Text("编辑") }
                }
            }
        }
        Spacer(Modifier.weight(1f))
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            OutlinedButton(onClick = onBack, modifier = Modifier.weight(1f)) { Text("全部拒绝") }
            Button(onClick = onBack, modifier = Modifier.weight(1f)) { Text("全部确认") }
        }
    }
}

@Composable
private fun CharacterPanel(
    title: String,
    hp: Int,
    maxHp: Int,
    @RawRes image: Int,
    @RawRes fightImage: Int? = null,
    @RawRes hurtImage: Int? = null,
    modifier: Modifier = Modifier,
    panelColor: Color,
    borderColor: Color,
    isCasting: Boolean = false,
    isCritCasting: Boolean = false,
    isHurt: Boolean = false,
    isZoomHit: Boolean = false,
) {
    val bodyScale by animateFloatAsState(
        targetValue = when {
            isZoomHit -> 1.12f
            isHurt -> 0.92f
            isCritCasting -> 1.1f
            else -> 1f
        },
        animationSpec = tween(durationMillis = 260, easing = FastOutSlowInEasing),
        label = "characterScale",
    )
    val bodyTranslation by animateFloatAsState(
        targetValue = when {
            isCasting -> 14f
            isHurt -> -10f
            else -> 0f
        },
        animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing),
        label = "characterTranslation",
    )
    val bodyRotation by animateFloatAsState(
        targetValue = if (isCritCasting) -5f else 0f,
        animationSpec = tween(durationMillis = 220, easing = FastOutSlowInEasing),
        label = "characterRotation",
    )
    val flashAlpha by animateFloatAsState(
        targetValue = if (isHurt || isZoomHit) 0.28f else 0f,
        animationSpec = tween(durationMillis = 260),
        label = "characterFlash",
    )
    val displayedImage = when {
        isHurt && hurtImage != null -> hurtImage
        (isCasting || isCritCasting) && fightImage != null -> fightImage
        else -> image
    }
    Card(
        modifier = modifier.fillMaxHeight().border(1.dp, borderColor, RoundedCornerShape(18.dp)),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = panelColor),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.fillMaxSize().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(title, fontWeight = FontWeight.Bold, color = Color(0xFF1C3655), fontSize = 22.sp)
            Spacer(Modifier.height(10.dp))
            Box(modifier = Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                if (isCritCasting) {
                    Box(
                        modifier = Modifier
                            .fillMaxHeight(0.96f)
                            .aspectRatio(1f)
                            .clip(CircleShape)
                            .background(Color(0x44FFD24A)),
                    )
                }
                SvgRawImage(
                    displayedImage,
                    modifier = Modifier
                        .fillMaxHeight(0.88f)
                        .aspectRatio(1f)
                        .graphicsLayer {
                            scaleX = bodyScale
                            scaleY = bodyScale
                            translationX = bodyTranslation
                            rotationZ = bodyRotation
                        },
                )
                Box(
                    modifier = Modifier
                        .matchParentSize()
                        .clip(RoundedCornerShape(14.dp))
                        .background(if (isZoomHit) Color(0xFFFFD24A).copy(alpha = flashAlpha) else Color.Red.copy(alpha = flashAlpha)),
                )
            }
            Spacer(Modifier.height(8.dp))
            Text("HP $hp / $maxHp", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color(0xFF1C3655))
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { hp.toFloat() / maxHp.toFloat() },
                modifier = Modifier.fillMaxWidth().height(10.dp).clip(RoundedCornerShape(99.dp)),
                color = Color(0xFF34D17A),
                trackColor = Color(0xFFE6E6E6),
            )
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

@Composable
private fun IconCircle(
    @DrawableRes icon: Int,
    label: String,
    modifier: Modifier = Modifier,
    backgroundColor: Color = Color(0xFFFCEAEA),
    onClick: (() -> Unit)? = null,
) {
    val clickableModifier = if (onClick == null) Modifier else Modifier.clickable(onClick = onClick)
    Box(
        modifier = modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(backgroundColor)
            .then(clickableModifier),
        contentAlignment = Alignment.Center,
    ) {
        Image(painter = painterResource(icon), contentDescription = label, modifier = Modifier.size(32.dp))
    }
}

@Composable
private fun EmojiCircle(
    emoji: String,
    label: String,
    modifier: Modifier = Modifier,
    backgroundColor: Color = Color(0xFFFCEAEA),
    onClick: (() -> Unit)? = null,
) {
    val clickableModifier = if (onClick == null) Modifier else Modifier.clickable(onClick = onClick)
    Box(
        modifier = modifier
            .size(56.dp)
            .clip(CircleShape)
            .background(backgroundColor)
            .semantics { contentDescription = label }
            .then(clickableModifier),
        contentAlignment = Alignment.Center,
    ) {
        Text(emoji, style = circleGlyphTextStyle(28.sp))
    }
}

@Composable
private fun HomeBadge(
    text: String,
    modifier: Modifier = Modifier,
    textColor: Color,
    backgroundColor: Color,
    fontSize: androidx.compose.ui.unit.TextUnit,
    horizontalPadding: androidx.compose.ui.unit.Dp,
) {
    Text(
        text = text,
        modifier = modifier
            .clip(RoundedCornerShape(99.dp))
            .background(backgroundColor)
            .padding(horizontal = horizontalPadding, vertical = 6.dp),
        color = textColor,
        fontSize = fontSize,
        fontWeight = FontWeight.Bold,
    )
}

@Composable
private fun Badge(text: String) {
    Text(
        text = text,
        modifier = Modifier.clip(RoundedCornerShape(99.dp)).background(Color.White).padding(horizontal = 12.dp, vertical = 5.dp),
        color = Color(0xFF6A442B),
        fontWeight = FontWeight.Bold,
    )
}

@Composable
private fun SmallPill(text: String) {
    Text(
        text = text,
        modifier = Modifier.clip(RoundedCornerShape(99.dp)).background(Color(0xFFFFE7B4)).padding(horizontal = 9.dp, vertical = 4.dp),
        color = Color(0xFF7A4A00),
        fontSize = 12.sp,
    )
}

private fun colorFromSceneHex(hex: String, fallback: Color): Color {
    val cleaned = hex.trim().removePrefix("#")
    if (cleaned.length != 6) return fallback
    val value = cleaned.toLongOrNull(16) ?: return fallback
    return Color(0xFF000000 or value)
}

@Composable
private fun StatCard(label: String, value: String) {
    Card(shape = RoundedCornerShape(18.dp), colors = CardDefaults.cardColors(containerColor = Color.White), elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)) {
        Column(modifier = Modifier.padding(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color(0xFF213E66))
            Text(label, fontSize = 12.sp, color = Color(0xFF666B74), textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun StepperRow(label: String, value: Int, testTagPrefix: String, onValueChange: (Int) -> Unit) {
    SettingCard(label) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CenteredCircleTextButton(
                text = "-",
                onClick = { onValueChange(value - 1) },
                modifier = Modifier.testTag("${testTagPrefix}Decrement"),
                size = 44.dp,
                fontSize = 22.sp,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF213E66),
                    contentColor = Color.White,
                ),
            )
            Text("$value", modifier = Modifier.width(72.dp).testTag("${testTagPrefix}Value"), textAlign = TextAlign.Center, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            CenteredCircleTextButton(
                text = "+",
                onClick = { onValueChange(value + 1) },
                modifier = Modifier.testTag("${testTagPrefix}Increment"),
                size = 44.dp,
                fontSize = 22.sp,
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color(0xFF213E66),
                    contentColor = Color.White,
                ),
            )
        }
    }
}

@Composable
private fun SettingCard(title: String, content: @Composable () -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFFF5F7FA)),
        elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(title, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = Color(0xFF2E2F33))
            Spacer(Modifier.height(8.dp))
            content()
        }
    }
}

@Composable
private fun DraftRow(title: String, words: String, onReview: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold)
            Text(words, color = Color(0xFF666B74), fontSize = 13.sp)
        }
        Button(onClick = onReview, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4E88A8))) { Text("审核") }
    }
}
