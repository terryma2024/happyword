package cool.happyword.wordmagic.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.GameConfig
import cool.happyword.wordmagic.ui.battle.AndroidBattleAudioMixer

@Composable
fun PcmAudioLabScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val mixer = remember { AndroidBattleAudioMixer(context.applicationContext) }
    var status by remember { mutableStateOf(mixer.snapshot()) }
    val labConfig = remember { GameConfig(playBgm = true, actionSfx = true) }

    DisposableEffect(mixer) {
        mixer.enter(labConfig)
        onDispose {
            mixer.dispose()
        }
    }

    fun refreshStatus() {
        status = mixer.snapshot()
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(Color.White)
            .verticalScroll(rememberScrollState())
            .topChromeSafeInsets()
            .padding(
                start = PageChromeInsets.bodyHorizontal,
                top = PageChromeInsets.bodyTop,
                end = PageChromeInsets.bodyHorizontal,
                bottom = PageChromeInsets.bodyBottom,
            )
            .testTag("PcmAudioLabScreen"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            HarmonyPageTopBackButton(
                onClick = onBack,
                modifier = Modifier.testTag("PcmAudioLabBackButton"),
            )
            Text(
                "PcmAudioLab",
                modifier = Modifier
                    .padding(start = 16.dp)
                    .testTag("PcmAudioLabTitle"),
                fontSize = 24.sp,
                fontWeight = FontWeight.Black,
                color = Color(0xFF0B3958),
            )
        }
        Spacer(Modifier.height(20.dp))
        LabButton("Start BGM", "PcmAudioLabStartBgmButton") {
            mixer.startMusic()
            refreshStatus()
        }
        LabButton("Stop BGM", "PcmAudioLabStopBgmButton") {
            mixer.stopMusic()
            refreshStatus()
        }
        LabButton("Speak over BGM", "PcmAudioLabSpeakOverBgmButton") {
            mixer.speakWord("apple")
            refreshStatus()
        }
        LabButton("Normal hit", "PcmAudioLabNormalHitButton") {
            mixer.playSfx(R.raw.hit_normal)
            refreshStatus()
        }
        LabButton("Win sequence", "PcmAudioLabWinSequenceButton") {
            mixer.playSfx(R.raw.monster_defeat)
            mixer.playVictory()
            refreshStatus()
        }
        Text(
            "Status music=${status.musicPlaying} voice=${status.voiceActive} volume=${(status.musicVolume * 100).toInt()}% event=${status.lastEvent}",
            modifier = Modifier
                .padding(top = 18.dp)
                .testTag("PcmAudioLabStatus"),
            fontSize = 14.sp,
            color = Color(0xFF45616F),
        )
    }
}

@Composable
private fun LabButton(label: String, tag: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .padding(bottom = 8.dp)
            .testTag(tag),
        shape = RoundedCornerShape(8.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color(0xFFE0F2FE),
            contentColor = Color(0xFF0369A1),
        ),
    ) {
        Text(label, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    }
}
