package cool.happyword.wordmagic.ui.components

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

import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.ui.CenteredCircleTextButton
import cool.happyword.wordmagic.ui.circleGlyphTextStyle

@Composable
internal fun CharacterPanel(
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
internal fun SvgRawImage(@RawRes rawRes: Int, modifier: Modifier = Modifier) {
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
internal fun IconCircle(
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
internal fun EmojiCircle(
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
internal fun HomeBadge(
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
internal fun Badge(text: String) {
    Text(
        text = text,
        modifier = Modifier.clip(RoundedCornerShape(99.dp)).background(Color.White).padding(horizontal = 12.dp, vertical = 5.dp),
        color = Color(0xFF6A442B),
        fontWeight = FontWeight.Bold,
    )
}

@Composable
internal fun SmallPill(text: String) {
    Text(
        text = text,
        modifier = Modifier.clip(RoundedCornerShape(99.dp)).background(Color(0xFFFFE7B4)).padding(horizontal = 9.dp, vertical = 4.dp),
        color = Color(0xFF7A4A00),
        fontSize = 12.sp,
    )
}

internal fun colorFromSceneHex(hex: String, fallback: Color): Color {
    val cleaned = hex.trim().removePrefix("#")
    if (cleaned.length != 6) return fallback
    val value = cleaned.toLongOrNull(16) ?: return fallback
    return Color(0xFF000000 or value)
}

@Composable
internal fun StatCard(label: String, value: String) {
    Card(shape = RoundedCornerShape(18.dp), colors = CardDefaults.cardColors(containerColor = Color.White), elevation = CardDefaults.cardElevation(defaultElevation = 0.dp)) {
        Column(modifier = Modifier.padding(14.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color(0xFF213E66))
            Text(label, fontSize = 12.sp, color = Color(0xFF666B74), textAlign = TextAlign.Center)
        }
    }
}

@Composable
internal fun StepperRow(label: String, value: Int, testTagPrefix: String, onValueChange: (Int) -> Unit) {
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
internal fun SettingCard(title: String, content: @Composable () -> Unit) {
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
internal fun DraftRow(title: String, words: String, onReview: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(title, fontWeight = FontWeight.Bold)
            Text(words, color = Color(0xFF666B74), fontSize = 13.sp)
        }
        Button(onClick = onReview, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF4E88A8))) { Text("审核") }
    }
}
