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
import androidx.annotation.DrawableRes
import androidx.annotation.RawRes
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import com.caverock.androidsvg.SVG
import cool.happyword.wordmagic.app.BuildGate
import cool.happyword.wordmagic.core.BattleSessionRecord
import cool.happyword.wordmagic.core.BattleAnswerOutcome
import cool.happyword.wordmagic.core.BattleEngine
import cool.happyword.wordmagic.core.BattleState
import cool.happyword.wordmagic.core.BattleStatus
import cool.happyword.wordmagic.core.BackendEnv
import cool.happyword.wordmagic.core.BackendRouteState
import cool.happyword.wordmagic.core.BindingResult
import cool.happyword.wordmagic.core.BuiltinPacks
import cool.happyword.wordmagic.core.CloudSyncCoordinator
import cool.happyword.wordmagic.core.CoinAccount
import cool.happyword.wordmagic.core.DevMenuViewModel
import cool.happyword.wordmagic.core.FixtureDeviceBindingClient
import cool.happyword.wordmagic.core.GameConfig
import cool.happyword.wordmagic.core.LearningRecorder
import cool.happyword.wordmagic.core.LearningReportBuilder
import cool.happyword.wordmagic.core.MonsterCatalog
import cool.happyword.wordmagic.core.PackLibrary
import cool.happyword.wordmagic.core.ParentPinStore
import cool.happyword.wordmagic.core.Question
import cool.happyword.wordmagic.core.QuestionKind
import cool.happyword.wordmagic.core.RedemptionHistoryStore
import cool.happyword.wordmagic.core.SessionResult
import cool.happyword.wordmagic.core.TodayPlanService
import cool.happyword.wordmagic.core.WishlistState
import cool.happyword.wordmagic.core.WordPack
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
import java.time.LocalDate
import java.util.Locale
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
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

@Composable
fun WordMagicGameApp() {
    val context = LocalContext.current
    var route by remember { mutableStateOf(AppRoute.Home) }
    val repositories = remember { AndroidLocalProgressRepositories(context.applicationContext) }
    val cloudRepositories = remember { AndroidCloudRepositories(context.applicationContext) }
    val debugRoutingRepository = remember { AndroidDebugRoutingRepository(context.applicationContext) }
    val devMenuViewModel = remember { DevMenuViewModel() }
    val cloudCoordinator = remember { CloudSyncCoordinator() }
    val bindingClient = remember { FixtureDeviceBindingClient() }
    var cloudCredentials by remember { mutableStateOf(cloudRepositories.loadCredentials()) }
    var globalPacks by remember { mutableStateOf(cloudRepositories.loadGlobalPacks()) }
    var familyPacks by remember { mutableStateOf(cloudRepositories.loadFamilyPacks()) }
    var cloudSyncStatus by remember { mutableStateOf(cloudRepositories.loadSyncStatus()) }
    var bindingError by remember { mutableStateOf("") }
    var pendingCloudUnbind by remember { mutableStateOf(false) }
    var backendRouteState by remember { mutableStateOf(debugRoutingRepository.loadRouteState()) }
    var previewTargets by remember { mutableStateOf(emptyList<cool.happyword.wordmagic.core.PreviewTarget>()) }
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
    var parentPin by remember { mutableStateOf("") }

    ApplyOrientation(route)
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
                    onSelectPack = { selectedPackId = it.id },
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
                    config = config,
                    parentPinSet = parentPin.isNotEmpty(),
                    cloudBound = cloudCredentials != null,
                    showDeveloper = BuildGate.showDeveloperTools((context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0),
                    onConfigChange = { config = it },
                    onBack = { route = AppRoute.Home },
                    onParentAdmin = { route = AppRoute.ParentPin },
                    onCloudBinding = { route = if (cloudCredentials == null) AppRoute.ScanBinding else AppRoute.BoundDeviceInfo },
                    onDeveloper = { route = AppRoute.DevMenu },
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
                            val redeemed = redemptionHistory.redeem(
                                account = coinAccount,
                                wishlist = wishlist,
                                wishId = pendingRedemptionWishId.orEmpty(),
                                redeemedAtMs = System.currentTimeMillis(),
                                parentApproved = true,
                            )
                            coinAccount = redeemed.account
                            redemptionHistory = redeemed.history
                            localProgressMessage = redeemed.message
                            pendingRedemptionWishId = null
                            repositories.saveCoinAccount(coinAccount)
                            repositories.saveRedemptionHistory(redemptionHistory)
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
                    onRedeem = { wish ->
                        pendingRedemptionWishId = wish.id
                        route = AppRoute.ParentPin
                    },
                    onHistory = { route = AppRoute.RedemptionHistory },
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
                    plan = TodayPlanService().build(packLibrary, selection.activePackIds, learningRecorder.statsSnapshot()),
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
                    },
                    onBack = { route = AppRoute.Config },
                )
                AppRoute.BoundDeviceInfo -> BoundDeviceInfoScreen(
                    credentials = cloudCredentials,
                    syncStatus = cloudSyncStatus,
                    onManualSync = {
                        val syncResult = cloudCoordinator.syncPacks(cloudCredentials)
                        globalPacks = syncResult.globalPacks.ifEmpty { globalPacks }
                        familyPacks = syncResult.familyPacks.ifEmpty { familyPacks }
                        cloudRepositories.saveGlobalPacks(globalPacks)
                        cloudRepositories.saveFamilyPacks(familyPacks)
                        cloudSyncStatus = syncResult.statusMessage
                        cloudRepositories.saveSyncStatus(cloudSyncStatus)
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
                    onSelectEnv = { env ->
                        backendRouteState = BackendRouteState(env = env)
                        debugRoutingRepository.saveRouteState(backendRouteState)
                    },
                    onRefreshManifest = { previewTargets = devMenuViewModel.refreshManifest(previewTargets) },
                    onSelectPreview = { preview ->
                        backendRouteState = devMenuViewModel.selectPreview(backendRouteState, preview)
                        debugRoutingRepository.saveRouteState(backendRouteState)
                    },
                    onProbe = { probeStatus = devMenuViewModel.probe(backendRouteState) },
                    onBypassSecret = { route = AppRoute.BypassSecret },
                    onClear = {
                        backendRouteState = BackendRouteState()
                        debugRoutingRepository.clearRouteState()
                    },
                    onBack = { route = AppRoute.Config },
                )
                AppRoute.BypassSecret -> BypassSecretScreen(
                    initialSecret = debugRoutingRepository.bypassSecretStore.load(),
                    onSave = { secret ->
                        debugRoutingRepository.bypassSecretStore.save(secret)
                        route = AppRoute.DevMenu
                    },
                    onClear = {
                        debugRoutingRepository.bypassSecretStore.clear()
                        route = AppRoute.DevMenu
                    },
                    onCancel = { route = AppRoute.DevMenu },
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

@Composable
private fun HomeScreen(
    activePacks: List<WordPack>,
    selectedPack: WordPack,
    coins: Int,
    onSelectPack: (WordPack) -> Unit,
    onStart: () -> Unit,
    onPackManager: () -> Unit,
    onWishlist: () -> Unit,
    onMonsterCodex: () -> Unit,
    onTodayPlan: () -> Unit,
    onConfig: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.White)
            .padding(horizontal = 44.dp, vertical = 10.dp)
            .testTag("HomeScreen"),
    ) {
        Box(modifier = Modifier.fillMaxWidth().height(54.dp)) {
            Text(
                "v0.1.0",
                modifier = Modifier.align(Alignment.TopStart).padding(top = 4.dp),
                fontSize = 16.sp,
                color = Color(0xFF9A9A9A),
            )
            Row(
                modifier = Modifier.align(Alignment.CenterEnd),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Badge("🦁 小明测试82941")
                Spacer(Modifier.width(8.dp))
                Badge("✨ $coins")
                Spacer(Modifier.width(12.dp))
                IconCircle(R.drawable.icon_review, "复习", Modifier.testTag("HomeTodayPlanButton"), onClick = onTodayPlan)
                IconCircle(R.drawable.icon_codex, "图鉴", Modifier.testTag("HomeCodexButton"), onClick = onMonsterCodex)
                IconCircle(R.drawable.icon_scroll, "计划", Modifier.testTag("HomePackManagerButton"), onClick = onPackManager)
                IconCircle(R.drawable.icon_wishlist, "愿望", Modifier.testTag("HomeWishlistButton"), onClick = onWishlist)
                IconCircle(R.drawable.icon_gear, "设置", Modifier.testTag("HomeConfigButton"), onClick = onConfig)
            }
        }

        Spacer(Modifier.height(4.dp))
        Text(
            "Small Magician Word Adventure",
            modifier = Modifier.fillMaxWidth(),
            textAlign = TextAlign.Center,
            fontSize = 34.sp,
            fontWeight = FontWeight.Black,
            color = Color(0xFF303030),
        )
        Spacer(Modifier.height(8.dp))

        Card(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .border(1.dp, Color(0xFFFFD2A6), RoundedCornerShape(28.dp))
                .testTag("AdventureCard"),
            shape = RoundedCornerShape(28.dp),
            colors = CardDefaults.cardColors(containerColor = Color(0xFFFFF7E6)),
            elevation = CardDefaults.cardElevation(defaultElevation = 0.dp),
        ) {
            Column(modifier = Modifier.fillMaxSize().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(selectedPack.nameEn, modifier = Modifier.testTag("AdventureCardTitle"), fontSize = 26.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
                    Spacer(Modifier.weight(1f))
                    SmallPill("今日")
                }
                LazyRow(horizontalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxWidth().testTag("PackChipRow")) {
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
                            Text(questionKindLabel(displayQuestion), color = Color(0xFF4B86B4), fontSize = 20.sp)
                            Spacer(Modifier.height(12.dp))
                            BattleQuestionPrompt(displayQuestion)
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
                                Text("🔊", fontSize = 30.sp)
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
        if (question.kind != QuestionKind.Choice) {
            Text(question.prompt, color = Color(0xFF6A5843), fontSize = 18.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
        }
        val promptText = when (question.kind) {
            QuestionKind.Choice -> question.prompt
            QuestionKind.FillLetter -> question.letterTemplate
            QuestionKind.FillLetterMedium -> question.letterTemplateBase
            QuestionKind.Spell -> question.spellLetters.mapIndexed { index, letter ->
                if (question.spellRevealedMask.getOrElse(index) { false }) letter else "_"
            }.joinToString(" ")
        }
        Text(promptText, fontSize = 42.sp, fontWeight = FontWeight.Black, color = Color(0xFF1C3655), textAlign = TextAlign.Center)
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
        SpellAnswerArea(question = question, feedbackLocked = feedbackLocked, onComplete = onSelect)
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
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            slots.forEachIndexed { index, value ->
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(RoundedCornerShape(12.dp))
                        .background(if (value.isNotBlank()) Color(0xFFFFE2A8) else Color(0xFFF2F2F2))
                        .border(1.dp, Color(0xFFD8C3A0), RoundedCornerShape(12.dp))
                        .testTag("BattleSpellSlot_$index"),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(value.ifBlank { "_" }, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color(0xFF3B2418))
                }
            }
        }
        Spacer(Modifier.height(10.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            question.spellPool.forEachIndexed { index, letter ->
                val used = consumed.getOrElse(index) { false }
                Button(
                    onClick = {
                        if (feedbackLocked || used) return@Button
                        val nextSlot = slots.indexOfFirst { it.isBlank() }
                        if (nextSlot < 0) return@Button
                        val expected = question.spellLetters.getOrNull(nextSlot)
                        if (letter != expected) return@Button
                        slots = slots.toMutableList().also { it[nextSlot] = letter }
                        consumed = consumed.toMutableList().also { it[index] = true }
                        if (slots.toMutableList().also { it[nextSlot] = letter }.joinToString("") == question.spellLetters.joinToString("")) {
                            onComplete(question.correctAnswer)
                        }
                    },
                    enabled = !feedbackLocked && !used,
                    modifier = Modifier
                        .weight(1f)
                        .height(52.dp)
                        .testTag("BattleSpellPool_$index"),
                    shape = RoundedCornerShape(16.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (used) Color(0xFFB7A1C8) else Color(0xFF8253A8),
                        disabledContainerColor = Color(0xFFB7A1C8),
                        disabledContentColor = Color.White,
                    ),
                ) {
                    Text(letter, fontSize = 20.sp, fontWeight = FontWeight.Bold)
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

private fun questionKindLabel(question: Question): String {
    return when (question.kind) {
        QuestionKind.Choice -> "Question"
        QuestionKind.FillLetter -> "Missing Letter"
        QuestionKind.FillLetterMedium -> "Two Missing Letters"
        QuestionKind.Spell -> "Spell"
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

@Composable
private fun ConfigScreen(
    config: GameConfig,
    parentPinSet: Boolean,
    cloudBound: Boolean,
    showDeveloper: Boolean,
    onConfigChange: (GameConfig) -> Unit,
    onBack: () -> Unit,
    onParentAdmin: () -> Unit,
    onCloudBinding: () -> Unit,
    onDeveloper: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFFFFF6E7))
            .padding(16.dp)
            .verticalScroll(rememberScrollState())
            .testTag("ConfigScreen"),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("设置", fontSize = 28.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = onBack) { Text("返回首页") }
        }
        Spacer(Modifier.height(12.dp))
        StepperRow("玩家血量", config.playerHp, "ConfigPlayerHp") { onConfigChange(config.copy(playerHp = it.coerceIn(1, 20))) }
        StepperRow("怪物血量", config.monsterHp, "ConfigMonsterHp") { onConfigChange(config.copy(monsterHp = it.coerceIn(1, 20))) }
        StepperRow("怪物数量", config.monsterCount, "ConfigMonsterCount") { onConfigChange(config.copy(monsterCount = it.coerceIn(1, 20))) }
        SettingCard("倒计时") {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GameConfig.timerPresets.forEach { value ->
                    OutlinedButton(onClick = { onConfigChange(config.copy(timerSeconds = value)) }) {
                        Text(if (value >= 60) "${value / 60}分钟" else "${value}秒")
                    }
                }
                OutlinedButton(onClick = { onConfigChange(config.copy(timerSeconds = 3)) }) { Text("自定义 3秒") }
            }
        }
        SettingCard("发音播放") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (config.autoPronunciation) "自动播放已开启" else "自动播放已关闭")
                Spacer(Modifier.weight(1f))
                Switch(checked = config.autoPronunciation, onCheckedChange = { onConfigChange(config.copy(autoPronunciation = it)) })
            }
        }
        SettingCard("家长管理") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (parentPinSet) "家长密码已设置" else "需要先设置 6 位家长密码")
                Spacer(Modifier.weight(1f))
                Button(onClick = onParentAdmin, modifier = Modifier.testTag("ConfigParentAdminButton")) {
                    Text("进入家长后台")
                }
            }
        }
        SettingCard("设备绑定") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(if (cloudBound) "已绑定家长账号" else "未绑定，仍可离线游玩")
                Spacer(Modifier.weight(1f))
                Button(onClick = onCloudBinding, modifier = Modifier.testTag("ConfigCloudBindingButton")) {
                    Text(if (cloudBound) "查看绑定" else "绑定家长账号")
                }
            }
        }
        SettingCard("我的词包") {
            Text("词包管理已接入首页计划按钮，可管理启用、固定与同步。")
        }
        if (showDeveloper) {
            SettingCard("开发者") {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("ConfigDeveloperRow").clickable(onClick = onDeveloper)) {
                    Text("后端环境与 Preview 调试")
                    Spacer(Modifier.weight(1f))
                    Button(onClick = onDeveloper) { Text("打开") }
                }
            }
        }
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
private fun IconCircle(@DrawableRes icon: Int, label: String, modifier: Modifier = Modifier, onClick: (() -> Unit)? = null) {
    val clickableModifier = if (onClick == null) Modifier else Modifier.clickable(onClick = onClick)
    Box(
        modifier = modifier
            .padding(horizontal = 4.dp)
            .size(42.dp)
            .clip(CircleShape)
            .background(Color.White)
            .border(1.dp, Color(0xFFFFD2A6), CircleShape)
            .then(clickableModifier),
        contentAlignment = Alignment.Center,
    ) {
        Image(painter = painterResource(icon), contentDescription = label, modifier = Modifier.size(26.dp))
    }
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
            OutlinedButton(onClick = { onValueChange(value - 1) }, modifier = Modifier.testTag("${testTagPrefix}Decrement")) { Text("-") }
            Text("$value", modifier = Modifier.width(72.dp).testTag("${testTagPrefix}Value"), textAlign = TextAlign.Center, fontSize = 22.sp, fontWeight = FontWeight.Bold)
            OutlinedButton(onClick = { onValueChange(value + 1) }, modifier = Modifier.testTag("${testTagPrefix}Increment")) { Text("+") }
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
