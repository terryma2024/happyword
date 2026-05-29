package cool.happyword.wordmagic.ui.home

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
import androidx.compose.foundation.layout.sizeIn
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
import cool.happyword.wordmagic.core.DailyHomeStatus
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

import cool.happyword.wordmagic.ui.components.HomeBadge
import cool.happyword.wordmagic.ui.components.IconCircle
import cool.happyword.wordmagic.ui.components.EmojiCircle
import cool.happyword.wordmagic.ui.components.colorFromSceneHex
import cool.happyword.wordmagic.R

internal object HomeDailyStatusBadgeStyle {
    const val backgroundArgb: Int = 0xFFF2DFC9.toInt()
    const val textArgb: Int = 0xFF8C877F.toInt()
    const val fontSizeSp: Int = 16
    const val horizontalPaddingDp: Int = 22
    const val verticalPaddingDp: Int = 8
    const val cornerRadiusDp: Int = 22
}

internal object HomeReviewCountBadgeStyle {
    const val backgroundArgb: Int = 0xFFE63946.toInt()
    const val minSizeDp: Int = 20
    const val cornerRadiusDp: Int = 10
    const val fontSizeSp: Int = 12
    const val horizontalPaddingDp: Int = 6
    const val topEndOffsetXDp: Int = 8
    const val topEndOffsetYDp: Int = 2
}

internal object HomeAdventureCardLayoutStyle {
    const val pageBottomPaddingDp: Int = 28
    const val cardBottomPaddingDp: Int = 24
    const val storyTopPaddingDp: Int = 16
    const val storyMaxLines: Int = 2
    const val buttonTopGapMinDp: Int = 14
}

internal fun adventureCardStoryLine(pack: WordPack): String {
    val story = pack.scene.storyEn.trim()
    if (story.isNotEmpty()) return story
    val low = pack.words.count { it.difficulty <= 2 }
    val mid = pack.words.count { it.difficulty == 3 }
    val high = pack.words.count { it.difficulty >= 4 }
    val buckets = buildList {
        if (low > 0) add("${low} 个低难度")
        if (mid > 0) add("${mid} 个中难度")
        if (high > 0) add("${high} 个高难度")
    }
    val prefix = "本词包 ${pack.words.size} 个单词"
    return if (buckets.isEmpty()) prefix else "$prefix，其中 ${buckets.joinToString("，")}"
}

@Composable
internal fun HomeScreen(
    activePacks: List<WordPack>,
    selectedPack: WordPack,
    coins: Int,
    cloudCredentials: cool.happyword.wordmagic.core.CloudCredentials?,
    showDeveloperTools: Boolean,
    homeVersionLabel: String,
    dailyStatus: DailyHomeStatus,
    onDeveloperVersionTripleTap: () -> Unit,
    onSelectPack: (WordPack) -> Unit,
    onBoundChild: () -> Unit,
    onStart: () -> Unit,
    onReview: () -> Boolean,
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
                .padding(top = 72.dp, bottom = HomeAdventureCardLayoutStyle.pageBottomPaddingDp.dp),
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
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .padding(
                            start = 16.dp,
                            top = 16.dp,
                            end = 16.dp,
                            bottom = HomeAdventureCardLayoutStyle.cardBottomPaddingDp.dp,
                        ),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            selectedPack.nameEn,
                            modifier = Modifier.weight(1f).testTag("AdventureCardTitle"),
                            fontSize = 26.sp,
                            fontWeight = FontWeight.Black,
                            color = Color(0xFF3B2418),
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = dailyStatus.label,
                            modifier = Modifier
                                .clip(RoundedCornerShape(HomeDailyStatusBadgeStyle.cornerRadiusDp.dp))
                                .background(Color(HomeDailyStatusBadgeStyle.backgroundArgb))
                                .padding(
                                    horizontal = HomeDailyStatusBadgeStyle.horizontalPaddingDp.dp,
                                    vertical = HomeDailyStatusBadgeStyle.verticalPaddingDp.dp,
                                )
                                .testTag("AdventureCardDailyStatusBadge")
                                .semantics { contentDescription = dailyStatus.label },
                            color = Color(HomeDailyStatusBadgeStyle.textArgb),
                            fontSize = HomeDailyStatusBadgeStyle.fontSizeSp.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
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
                    Text(
                        adventureCardStoryLine(selectedPack),
                        fontSize = 18.sp,
                        color = Color(0xFF6A5843),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = HomeAdventureCardLayoutStyle.storyTopPaddingDp.dp)
                            .testTag("AdventureCardStoryLine")
                            .semantics { contentDescription = adventureCardStoryLine(selectedPack) },
                        textAlign = TextAlign.Center,
                        maxLines = HomeAdventureCardLayoutStyle.storyMaxLines,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Spacer(
                        Modifier
                            .height(HomeAdventureCardLayoutStyle.buttonTopGapMinDp.dp)
                            .weight(1f),
                    )
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
            Box(
                modifier = Modifier.size(58.dp),
                contentAlignment = Alignment.Center,
            ) {
                IconCircle(R.drawable.icon_review, "复习", Modifier.testTag("HomeReviewButton"), backgroundColor = Color(0xFFFCEAEA), onClick = {
                    if (!onReview()) {
                        reviewLockedToastVisible = true
                    }
                })
                if (dailyStatus.showReviewCountBadge) {
                    Text(
                        text = dailyStatus.remainingReviewCount.toString(),
                        modifier = Modifier
                            .align(Alignment.TopEnd)
                            .offset(
                                x = HomeReviewCountBadgeStyle.topEndOffsetXDp.dp,
                                y = (-HomeReviewCountBadgeStyle.topEndOffsetYDp).dp,
                            )
                            .clip(RoundedCornerShape(HomeReviewCountBadgeStyle.cornerRadiusDp.dp))
                            .background(Color(HomeReviewCountBadgeStyle.backgroundArgb))
                            .padding(horizontal = HomeReviewCountBadgeStyle.horizontalPaddingDp.dp)
                            .sizeIn(minWidth = HomeReviewCountBadgeStyle.minSizeDp.dp, minHeight = HomeReviewCountBadgeStyle.minSizeDp.dp)
                            .testTag("HomeReviewCountBadge"),
                        color = Color.White,
                        fontSize = HomeReviewCountBadgeStyle.fontSizeSp.sp,
                        fontWeight = FontWeight.Black,
                        textAlign = TextAlign.Center,
                    )
                }
            }
            IconCircle(R.drawable.icon_codex, "图鉴", Modifier.testTag("HomeCodexButton"), backgroundColor = Color(0xFFFCEAEA), onClick = onMonsterCodex)
            EmojiCircle("📋", "今日计划", Modifier.testTag("HomePlanButton"), backgroundColor = Color(0xFFFCEAEA), onClick = onTodayPlan)
            IconCircle(R.drawable.icon_wishlist, "愿望", Modifier.testTag("HomeWishlistButton"), backgroundColor = Color(0xFFFCEAEA), onClick = onWishlist)
            IconCircle(R.drawable.icon_gear, "设置", Modifier.testTag("HomeConfigButton"), backgroundColor = Color(0xFFEAF2F8), onClick = onConfig)
        }

        if (reviewLockedToastVisible) {
            Text(
                "今天没有需要复习的单词",
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 96.dp)
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color(0xE63A3A3A))
                    .padding(horizontal = 16.dp, vertical = 8.dp)
                    .testTag("HomeReviewEmptyToast"),
                fontSize = 14.sp,
                color = Color.White,
            )
        }
    }
}
