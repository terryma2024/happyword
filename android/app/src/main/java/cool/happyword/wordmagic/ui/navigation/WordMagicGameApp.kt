package cool.happyword.wordmagic.ui.navigation

import android.app.Activity
import android.content.Context
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
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
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
import cool.happyword.wordmagic.core.SystemBrowser
import cool.happyword.wordmagic.core.BindingResult
import cool.happyword.wordmagic.core.CloudCredentials
import cool.happyword.wordmagic.core.bindingFailureReasonFromMessage
import cool.happyword.wordmagic.core.extractTokenFromQrPayload
import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.ChildProfileClient
import cool.happyword.wordmagic.core.ChildProfileException
import cool.happyword.wordmagic.core.CloudSyncCoordinator
import cool.happyword.wordmagic.core.CompliancePolicy
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.DevMenuRouteParams
import cool.happyword.wordmagic.core.DevMenuViewModel
import cool.happyword.wordmagic.core.VersionTripleTap
import cool.happyword.wordmagic.core.DeviceBindingClient
import cool.happyword.wordmagic.core.FixtureDeviceBindingClient
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
import cool.happyword.wordmagic.ui.decodeQrPayloadFromUri
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
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

import cool.happyword.wordmagic.ui.navigation.AppRoute
import cool.happyword.wordmagic.ui.navigation.ApplyOrientation
import cool.happyword.wordmagic.ui.navigation.DEFAULT_BATTLE_TIMER_SECONDS
import cool.happyword.wordmagic.ui.navigation.GIFTBOX_MODAL_TOTAL_MS
import cool.happyword.wordmagic.ui.navigation.GIFTBOX_TRIGGER_DELAY_MS
import cool.happyword.wordmagic.ui.navigation.WISH_REDEEMED_ACK_MS
import cool.happyword.wordmagic.ui.navigation.childProfileErrorMessage
import cool.happyword.wordmagic.ui.home.HomeScreen
import cool.happyword.wordmagic.ui.battle.BattleScreen
import cool.happyword.wordmagic.ui.result.ResultScreen
import cool.happyword.wordmagic.ui.result.formatLearningSyncStatus
import cool.happyword.wordmagic.ui.result.formatLearningSyncToast
import cool.happyword.wordmagic.ui.config.ConfigScreen
import cool.happyword.wordmagic.ui.config.AddCustomWishPinDialog
import cool.happyword.wordmagic.ui.config.AddCustomWishFormDialog
import cool.happyword.wordmagic.ui.config.RemoveCustomWishPinDialog
import cool.happyword.wordmagic.ui.parent.ParentPinScreen
import cool.happyword.wordmagic.ui.parent.ParentAdminScreen
import cool.happyword.wordmagic.ui.parent.LessonDraftReviewScreen

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
    val compliancePrefs = remember {
        context.applicationContext.getSharedPreferences(CompliancePolicy.PREFS_NAME, Context.MODE_PRIVATE)
    }
    var privacyConsentAccepted by remember {
        mutableStateOf(
            isDebuggable ||
                compliancePrefs.getBoolean(CompliancePolicy.PRIVACY_CONSENT_KEY, false),
        )
    }
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
    var scanBindingBusy by remember { mutableStateOf(false) }
    var scanBindingFailureReason by remember { mutableStateOf("") }
    var scanBindingSuccessNickname by remember { mutableStateOf<String?>(null) }
    var pendingCloudUnbind by remember { mutableStateOf(false) }
    var pendingPostBindPinSetup by remember { mutableStateOf(false) }
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
    val fixtureBindingClient = remember { FixtureDeviceBindingClient() }
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
    var addCustomWishPinVisible by remember { mutableStateOf(false) }
    var addCustomWishFormVisible by remember { mutableStateOf(false) }
    var addCustomWishPinInput by remember { mutableStateOf("") }
    var addCustomWishName by remember { mutableStateOf("") }
    var addCustomWishCost by remember { mutableStateOf("") }
    var addCustomWishEmoji by remember { mutableStateOf("") }
    var addCustomWishFormError by remember { mutableStateOf("") }
    var removeCustomWishPinVisible by remember { mutableStateOf(false) }
    var removeCustomWishPinInput by remember { mutableStateOf("") }
    var pendingRemoveCustomWishId by remember { mutableStateOf<String?>(null) }
    var parentPin by remember { mutableStateOf("") }
    var devMenuRoutePreset by remember { mutableStateOf<String?>(null) }

    fun applyBindingSuccess(credentials: CloudCredentials) {
        cloudRepositories.saveCredentials(credentials)
        cloudCredentials = credentials
        val syncResult = cloudCoordinator.syncPacks(cloudCredentials)
        globalPacks = syncResult.globalPacks.ifEmpty { globalPacks }
        familyPacks = syncResult.familyPacks.ifEmpty { familyPacks }
        cloudRepositories.saveGlobalPacks(globalPacks)
        cloudRepositories.saveFamilyPacks(familyPacks)
        cloudSyncStatus = syncResult.statusMessage
        cloudRepositories.saveSyncStatus(cloudSyncStatus)
        scanBindingSuccessNickname = credentials.childNickname.ifBlank { "宝贝" }
        scanBindingFailureReason = ""
        if (parentPin.length == 6) {
            route = AppRoute.BoundDeviceInfo
        } else {
            pendingPostBindPinSetup = true
            route = AppRoute.ParentPin
        }
    }

    fun redeemBindingShortCode(code: String) {
        if (scanBindingBusy) return
        appScope.launch {
            scanBindingBusy = true
            scanBindingFailureReason = ""
            val deviceId = cloudRepositories.deviceIdProvider.getOrCreate()
            val result = if (isDebuggable) {
                fixtureBindingClient.redeemShortCode(code, deviceId)
            } else {
                bindingClient.redeemShortCode(code, deviceId)
            }
            when (result) {
                is BindingResult.Success -> applyBindingSuccess(result.credentials)
                is BindingResult.Failure -> scanBindingFailureReason = bindingFailureReasonFromMessage(result.message)
            }
            scanBindingBusy = false
        }
    }

    fun redeemBindingToken(token: String) {
        if (scanBindingBusy) return
        appScope.launch {
            scanBindingBusy = true
            scanBindingFailureReason = ""
            val deviceId = cloudRepositories.deviceIdProvider.getOrCreate()
            val result = if (isDebuggable) {
                fixtureBindingClient.redeemToken(token, deviceId)
            } else {
                bindingClient.redeemToken(token, deviceId)
            }
            when (result) {
                is BindingResult.Success -> applyBindingSuccess(result.credentials)
                is BindingResult.Failure -> scanBindingFailureReason = bindingFailureReasonFromMessage(result.message)
            }
            scanBindingBusy = false
        }
    }

    val qrScanLauncher = rememberLauncherForActivityResult(ScanContract()) { result ->
        val payload = result.contents.orEmpty()
        if (payload.isBlank()) return@rememberLauncherForActivityResult
        val token = extractTokenFromQrPayload(payload)
        if (token.length < 4) {
            scanBindingFailureReason = "TOKEN_INVALID"
            return@rememberLauncherForActivityResult
        }
        redeemBindingToken(token)
    }
    val galleryQrLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.GetContent(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        appScope.launch {
            scanBindingFailureReason = ""
            val payload = decodeQrPayloadFromUri(context, uri)
            if (payload.isNullOrBlank()) {
                scanBindingFailureReason = "TOKEN_INVALID"
            } else {
                val token = extractTokenFromQrPayload(payload)
                if (token.length < 4) {
                    scanBindingFailureReason = "TOKEN_INVALID"
                } else {
                    redeemBindingToken(token)
                }
            }
        }
    }

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
                    probeStatus = "Probing ${devMenuViewModel.routingSummary(targetState).substringAfter(": ")}/api/v1/public/health..."
                    val probeResult = devMenuViewModel.probeHealth(targetState, bypassSecret)
                    probeStatus = probeResult.message
                    if (!probeResult.ok) {
                        route = AppRoute.DevMenu
                        Toast.makeText(context, "Cannot reach /api/v1/public/health - see status at bottom", Toast.LENGTH_SHORT).show()
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

    fun finishBattleSession(finishedState: BattleState) {
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
    LaunchedEffect(route) {
        if (route != AppRoute.Wishlist) {
            addCustomWishPinVisible = false
            addCustomWishFormVisible = false
            removeCustomWishPinVisible = false
            removeCustomWishPinInput = ""
            pendingRemoveCustomWishId = null
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
                    onSpellWrongTap = {
                        val current = battleState ?: engine.initialState()
                        val outcome = engine.spellLetterPenaltyOutcome(current)
                        battleState = outcome.nextState
                        outcome
                    },
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
                    onBattleFinished = ::finishBattleSession,
                    onEscape = {
                        val current = battleState ?: engine.initialState()
                        val escaped = current.copy(status = BattleStatus.Lost)
                        battleState = escaped
                        finishBattleSession(escaped)
                    },
                )
                AppRoute.Result -> ResultScreen(
                    result = result ?: SessionResult(false, 0, 0, 0, 0, 0, 0),
                    coins = coinAccount.balance,
                    onHome = { route = AppRoute.Home },
                )
                AppRoute.Config -> ConfigScreen(
                    config = config,
                    activePackCount = selection.activePackIds.size,
                    maxActivePacks = PackSelectionStore.MAX_ACTIVE,
                    parentPinReady = parentPin.length == 6,
                    cloudBound = cloudCredentials != null,
                    cloudChildNickname = cloudCredentials?.childNickname.orEmpty().ifBlank { "宝贝" },
                    learningSyncBusy = learningSyncBusy,
                    learningSyncStatus = learningSyncStatus,
                    learningSyncToast = learningSyncToast,
                    onConfigChange = { next ->
                        config = next
                        engine = BattleEngine(config = config)
                    },
                    onBack = { route = AppRoute.Home },
                    onParentAdmin = { route = AppRoute.ParentPin },
                    onParentPinSetup = { route = AppRoute.ParentPin },
                    onCloudBinding = {
                        scanBindingFailureReason = ""
                        scanBindingSuccessNickname = null
                        route = if (cloudCredentials == null) AppRoute.ScanBinding else AppRoute.BoundDeviceInfo
                    },
                    onPackManager = { route = AppRoute.PackManager },
                    onReportChannel = {
                        try {
                            SystemBrowser.openUrl(context, CompliancePolicy.REPORT_CHANNEL_URL)
                        } catch (err: Exception) {
                            Toast.makeText(context, "问题反馈暂时无法打开，请稍后重试", Toast.LENGTH_SHORT).show()
                        }
                    },
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
                                    familyId = credentials.familyLabel,
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
                    hasPin = parentPin.length == 6,
                    onBack = {
                        when {
                            pendingRedemptionWishId != null -> {
                                pendingRedemptionWishId = null
                                route = AppRoute.Wishlist
                            }
                            pendingCloudUnbind -> {
                                pendingCloudUnbind = false
                                route = AppRoute.BoundDeviceInfo
                            }
                            pendingPostBindPinSetup -> {
                                pendingPostBindPinSetup = false
                                route = AppRoute.BoundDeviceInfo
                            }
                            else -> route = AppRoute.Config
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
                        } else if (pinAccepted && pendingPostBindPinSetup) {
                            pendingPostBindPinSetup = false
                            route = AppRoute.BoundDeviceInfo
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
                AppRoute.Wishlist -> {
                    Box(Modifier.fillMaxSize()) {
                        WishlistScreen(
                            coinAccount = coinAccount,
                            wishlist = wishlist,
                            message = localProgressMessage,
                            giftBoxVisible = wishlistGiftBoxVisible,
                            giftBoxTrigger = wishlistGiftBoxTrigger,
                            recentlyRedeemedWishId = recentlyRedeemedWishId,
                            showAddCustomEntry = parentPin.length == 6,
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
                                    removeCustomWishPinVisible = false
                                    removeCustomWishPinInput = ""
                                    pendingRemoveCustomWishId = null
                                    addCustomWishPinInput = ""
                                    addCustomWishPinVisible = true
                                }
                            },
                            onRequestRemoveCustom = { wish ->
                                if (parentPin.length != 6) {
                                    Toast.makeText(
                                        context,
                                        "请先在设置页面配置家长密码（6 位数字），再使用此功能。",
                                        Toast.LENGTH_SHORT,
                                    ).show()
                                } else if (!wish.custom) {
                                    // Defensive: only parent-created rows are removable.
                                } else {
                                    addCustomWishPinVisible = false
                                    addCustomWishFormVisible = false
                                    pendingRemoveCustomWishId = wish.id
                                    removeCustomWishPinInput = ""
                                    removeCustomWishPinVisible = true
                                }
                            },
                            onBack = { route = AppRoute.Home },
                        )
                        AddCustomWishPinDialog(
                            visible = addCustomWishPinVisible,
                            pinInput = addCustomWishPinInput,
                            onPinChange = { v -> addCustomWishPinInput = v.filter { it.isDigit() }.take(6) },
                            onDismiss = {
                                addCustomWishPinVisible = false
                                addCustomWishPinInput = ""
                            },
                            onConfirm = {
                                if (!ParentPinStore.isValidPin(addCustomWishPinInput)) {
                                    return@AddCustomWishPinDialog
                                }
                                if (addCustomWishPinInput != parentPin) {
                                    Toast.makeText(context, "密码不正确", Toast.LENGTH_SHORT).show()
                                    return@AddCustomWishPinDialog
                                }
                                addCustomWishPinVisible = false
                                addCustomWishPinInput = ""
                                addCustomWishName = ""
                                addCustomWishCost = ""
                                addCustomWishEmoji = ""
                                addCustomWishFormError = ""
                                addCustomWishFormVisible = true
                            },
                        )
                        RemoveCustomWishPinDialog(
                            visible = removeCustomWishPinVisible,
                            pinInput = removeCustomWishPinInput,
                            onPinChange = { v -> removeCustomWishPinInput = v.filter { it.isDigit() }.take(6) },
                            onDismiss = {
                                removeCustomWishPinVisible = false
                                removeCustomWishPinInput = ""
                                pendingRemoveCustomWishId = null
                            },
                            onConfirm = {
                                if (!ParentPinStore.isValidPin(removeCustomWishPinInput)) {
                                    return@RemoveCustomWishPinDialog
                                }
                                if (removeCustomWishPinInput != parentPin) {
                                    Toast.makeText(context, "密码不正确", Toast.LENGTH_SHORT).show()
                                    return@RemoveCustomWishPinDialog
                                }
                                val id = pendingRemoveCustomWishId
                                removeCustomWishPinVisible = false
                                removeCustomWishPinInput = ""
                                pendingRemoveCustomWishId = null
                                if (id != null) {
                                    val next = wishlist.removeCustomWish(id)
                                    if (next !== wishlist) {
                                        wishlist = next
                                        repositories.saveWishlist(wishlist)
                                        localProgressMessage = ""
                                        Toast.makeText(context, "已删除愿望", Toast.LENGTH_SHORT).show()
                                    }
                                }
                            },
                        )
                        AddCustomWishFormDialog(
                            visible = addCustomWishFormVisible,
                            name = addCustomWishName,
                            costRaw = addCustomWishCost,
                            emoji = addCustomWishEmoji,
                            error = addCustomWishFormError,
                            onNameChange = {
                                addCustomWishName = it.take(CustomWishRules.NAME_MAX_CHARS)
                                addCustomWishFormError = ""
                            },
                            onCostChange = {
                                addCustomWishCost = it.filter { c -> c.isDigit() }.take(4)
                                addCustomWishFormError = ""
                            },
                            onEmojiChange = {
                                addCustomWishEmoji = it.take(4)
                                addCustomWishFormError = ""
                            },
                            onDismiss = { addCustomWishFormVisible = false },
                            onSubmit = {
                                val (next, err) = wishlist.tryAddCustomWish(
                                    addCustomWishName,
                                    addCustomWishCost,
                                    addCustomWishEmoji,
                                    System.currentTimeMillis(),
                                )
                                if (err != null) {
                                    addCustomWishFormError = err
                                } else {
                                    wishlist = next
                                    repositories.saveWishlist(wishlist)
                                    addCustomWishFormVisible = false
                                    addCustomWishFormError = ""
                                    localProgressMessage = ""
                                    Toast.makeText(context, "已添加愿望", Toast.LENGTH_SHORT).show()
                                }
                            },
                        )
                    }
                }
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
                    report = LearningReportBuilder().build(
                        packLibrary,
                        selection.activePackIds,
                        learningRecorder.statsSnapshot(),
                        System.currentTimeMillis(),
                    ),
                    onBack = { route = AppRoute.TodayPlan },
                )
                AppRoute.ScanBinding -> {
                    val scanBindingContext = LocalContext.current
                    val backendUrlProvider = remember { BackendURLProvider() }
                    ScanBindingScreen(
                        busy = scanBindingBusy,
                        failureReason = scanBindingFailureReason,
                        boundChildNickname = scanBindingSuccessNickname,
                        onOpenScanner = {
                            scanBindingFailureReason = ""
                            val options = ScanOptions().apply {
                                setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                                setPrompt("请扫描家长端「添加设备」页面显示的二维码")
                                setBeepEnabled(false)
                                setOrientationLocked(false)
                            }
                            qrScanLauncher.launch(options)
                        },
                        onPickGallery = {
                            scanBindingFailureReason = ""
                            galleryQrLauncher.launch("image/*")
                        },
                        onRedeemShortCode = ::redeemBindingShortCode,
                        onOpenParentLogin = {
                            val url = backendUrlProvider.parentFamilyLoginPageUrl(backendRouteState)
                            try {
                                SystemBrowser.openUrl(scanBindingContext, url)
                            } catch (err: Exception) {
                                Toast.makeText(scanBindingContext, "Could not open browser", Toast.LENGTH_SHORT).show()
                            }
                        },
                        onBack = {
                            scanBindingFailureReason = ""
                            scanBindingSuccessNickname = null
                            route = AppRoute.Config
                        },
                        onSuccessBack = {
                            scanBindingSuccessNickname = null
                            route = AppRoute.Config
                        },
                    )
                }
                AppRoute.BoundDeviceInfo -> BoundDeviceInfoScreen(
                    credentials = cloudCredentials,
                    syncStatus = cloudSyncStatus,
                    onEditProfile = { nickname, avatarEmoji ->
                        val current = cloudCredentials
                            ?: return@BoundDeviceInfoScreen "当前未绑定，请先扫码"
                        try {
                            val updated = childProfileClient.updateProfile(
                                current.deviceToken,
                                current.familyLabel,
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
            if (!privacyConsentAccepted) {
                PrivacyConsentDialog(
                    onOpenTerms = {
                        SystemBrowser.openUrl(context, CompliancePolicy.TERMS_OF_SERVICE_URL)
                    },
                    onOpenPrivacy = {
                        SystemBrowser.openUrl(context, CompliancePolicy.PRIVACY_POLICY_URL)
                    },
                    onAgree = {
                        compliancePrefs.edit()
                            .putBoolean(CompliancePolicy.PRIVACY_CONSENT_KEY, true)
                            .apply()
                        privacyConsentAccepted = true
                    },
                )
            }
        }
    }
}

@Composable
private fun PrivacyConsentDialog(
    onOpenTerms: () -> Unit,
    onOpenPrivacy: () -> Unit,
    onAgree: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = {},
        title = {
            Text(
                "请阅读并同意隐私政策",
                fontWeight = FontWeight.Bold,
                modifier = Modifier.testTag("PrivacyConsentTitle"),
            )
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "魔法背单词会在家长绑定、学习同步、课本图片导入和愿望兑换时处理必要信息。继续使用前，请阅读《用户协议》和《隐私政策》。",
                    color = Color(0xFF374151),
                    modifier = Modifier.testTag("PrivacyConsentBody"),
                )
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TextButton(
                        onClick = onOpenTerms,
                        modifier = Modifier.testTag("PrivacyConsentTermsButton"),
                    ) { Text("用户协议") }
                    TextButton(
                        onClick = onOpenPrivacy,
                        modifier = Modifier.testTag("PrivacyConsentPolicyButton"),
                    ) { Text("隐私政策") }
                }
            }
        },
        confirmButton = {
            Button(
                onClick = onAgree,
                modifier = Modifier.testTag("PrivacyConsentAgreeButton"),
            ) {
                Text("同意并继续")
            }
        },
        shape = RoundedCornerShape(28.dp),
        containerColor = Color(0xFFFFFEFB),
        tonalElevation = 10.dp,
        modifier = Modifier
            .testTag("PrivacyConsentDialog")
            .border(2.dp, Color(0xFFFFD28A), RoundedCornerShape(28.dp)),
    )
}
