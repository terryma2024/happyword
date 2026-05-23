package cool.happyword.wordmagic.ui.result

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

import cool.happyword.wordmagic.ui.components.StatCard

@Composable
internal fun ResultScreen(result: SessionResult, coins: Int, onHome: () -> Unit) {
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
        if (result.bonusKillCount > 0) {
            Spacer(Modifier.height(10.dp))
            Text(
                "Bonus 怪物 ×${result.bonusKillCount} → +${(result.coinDelta - result.stars).coerceAtLeast(0)} ✨",
                modifier = Modifier
                    .clip(RoundedCornerShape(18.dp))
                    .background(Color.White)
                    .padding(horizontal = 14.dp, vertical = 7.dp)
                    .testTag("BattleResultBonusCoinRow"),
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = Color(0xFFD84545),
            )
        }
        Spacer(Modifier.height(22.dp))
        Button(onClick = onHome, modifier = Modifier.width(240.dp).height(54.dp).testTag("ResultHomeButton")) {
            Text("回到首页", fontSize = 18.sp)
        }
    }
}

internal fun formatLearningSyncStatus(result: WordStatsSyncResult): String {
    if (result.serverNowMs <= 0L) return "上次同步时间未知"
    val formatted = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.getDefault()).format(Date(result.serverNowMs))
    return "上次成功同步 $formatted"
}

internal fun formatLearningSyncToast(result: WordStatsSyncResult): String = when (result.status) {
    WordStatsSyncStatus.Unbound -> "未绑定家长账号，请先在“家长账户”中绑定"
    WordStatsSyncStatus.NoChanges -> "没有新的学习记录"
    WordStatsSyncStatus.Pushed -> "已上传 ${result.pushed} 条学习记录"
    WordStatsSyncStatus.Pulled -> "已合并 ${result.pulled} 条服务器记录"
    WordStatsSyncStatus.PushedAndPulled -> "已上传 ${result.pushed} 条 / 合并 ${result.pulled} 条服务器记录"
    WordStatsSyncStatus.NetworkError -> "同步失败：网络异常，请稍后重试"
}
