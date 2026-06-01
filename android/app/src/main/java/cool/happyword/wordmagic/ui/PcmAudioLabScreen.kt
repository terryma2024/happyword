package cool.happyword.wordmagic.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.BattleAudioMixerPolicy
import cool.happyword.wordmagic.core.GameConfig
import cool.happyword.wordmagic.ui.battle.AndroidBattleAudioMixer
import kotlin.math.roundToInt

private val labWords = listOf("apple", "dragon", "magic", "school")
private val sfxVoicePolicies = listOf("full", "lower", "suppress", "delay")

@Composable
fun PcmAudioLabScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val mixer = remember { AndroidBattleAudioMixer(context.applicationContext) }
    var status by remember { mutableStateOf(mixer.snapshot()) }
    var statusText by remember { mutableStateOf("Ready. PCM voice should mix over BGM without stopping it.") }
    var selectedWord by remember { mutableStateOf("apple") }
    var musicEnabled by remember { mutableStateOf(true) }
    var sfxEnabled by remember { mutableStateOf(true) }
    var voiceEnabled by remember { mutableStateOf(true) }
    var resumeAfterVoice by remember { mutableStateOf(false) }
    var masterVolume by remember { mutableFloatStateOf(1.0f) }
    var musicVolume by remember { mutableFloatStateOf(0.32f) }
    var musicLoweredVolume by remember { mutableFloatStateOf(0.50f) }
    var sfxVoiceVolume by remember { mutableFloatStateOf(0.35f) }
    var selectedPolicy by remember { mutableStateOf("lower") }

    fun currentPolicy(): BattleAudioMixerPolicy =
        BattleAudioMixerPolicy(
            masterVolume = masterVolume,
            musicVolume = musicVolume,
            musicLoweredVolumeWhileVoice = musicLoweredVolume,
            sfxDuringVoiceVolume = sfxVoiceVolume,
            resumeMusicAfterVoice = resumeAfterVoice,
        )

    fun currentConfig(): GameConfig =
        GameConfig(playBgm = musicEnabled, actionSfx = sfxEnabled)

    fun refreshStatus() {
        status = mixer.snapshot()
    }

    fun applyMixerState() {
        mixer.updatePolicy(currentPolicy())
        mixer.updateConfig(currentConfig())
        refreshStatus()
    }

    fun run(statusMessage: String, action: () -> Unit) {
        action()
        statusText = statusMessage
        refreshStatus()
    }

    fun speak(word: String) {
        if (!voiceEnabled) {
            statusText = "Voice is off."
            refreshStatus()
            return
        }
        mixer.speakWord(word)
    }

    DisposableEffect(mixer) {
        mixer.enter(currentConfig())
        mixer.updatePolicy(currentPolicy())
        onDispose {
            mixer.dispose()
        }
    }
    LaunchedEffect(musicEnabled, sfxEnabled, resumeAfterVoice, masterVolume, musicVolume, musicLoweredVolume, sfxVoiceVolume) {
        applyMixerState()
    }

    Column(
        Modifier
            .fillMaxSize()
            .background(Color.White)
            .verticalScroll(rememberScrollState())
            .topChromeSafeInsets()
            .padding(start = 22.dp, top = 12.dp, end = 22.dp, bottom = 24.dp)
            .testTag("PcmAudioLabScreen"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        HeaderRow(onBack)
        MixPanel(
            musicEnabled = musicEnabled,
            sfxEnabled = sfxEnabled,
            voiceEnabled = voiceEnabled,
            resumeAfterVoice = resumeAfterVoice,
            masterVolume = masterVolume,
            musicVolume = musicVolume,
            musicLoweredVolume = musicLoweredVolume,
            sfxVoiceVolume = sfxVoiceVolume,
            onToggleMusic = { musicEnabled = !musicEnabled },
            onToggleSfx = { sfxEnabled = !sfxEnabled },
            onToggleVoice = { voiceEnabled = !voiceEnabled },
            onToggleResume = { resumeAfterVoice = !resumeAfterVoice },
            onAdjustMaster = { masterVolume = clamp01(masterVolume + it) },
            onAdjustMusic = { musicVolume = clamp01(musicVolume + it) },
            onAdjustDuck = { musicLoweredVolume = clamp01(musicLoweredVolume + it) },
            onAdjustSfxVoice = { sfxVoiceVolume = clamp01(sfxVoiceVolume + it) },
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            TransportPanel(
                modifier = Modifier.weight(1f),
                onStartBgm = { run("BGM loop requested.") { mixer.startMusic() } },
                onStopBgm = { run("BGM stopped.") { mixer.stopMusic() } },
                onNormal = { run("Played normal attack SFX.") { mixer.playSfx(R.raw.hit_normal) } },
                onCombo = {
                    run("Played combo SFX with temporary BGM duck.") {
                        mixer.playSfx(R.raw.hit_crit)
                    }
                },
                onWrong = { run("Played wrong-answer SFX.") { mixer.playSfx(R.raw.answer_wrong) } },
                onHurt = { run("Played critical player-hurt SFX.") { mixer.playSfx(R.raw.player_hurt) } },
                onVictory = { run("Played victory SFX.") { mixer.playVictory() } },
                onDefeat = { run("Played defeat SFX.") { mixer.playDefeat() } },
            )
            VoicePanel(
                modifier = Modifier.weight(1f),
                selectedWord = selectedWord,
                onSelectWord = {
                    selectedWord = it
                    statusText = "Selected word: $it."
                    refreshStatus()
                },
                onSpeak = { run("Speaking $selectedWord.") { speak(selectedWord) } },
                onSpeakOverBgm = {
                    run("BGM plus voice for $selectedWord.") {
                        mixer.startMusic()
                        speak(selectedWord)
                    }
                },
                onComboOverBgm = {
                    run("Combo attack over BGM.") {
                        mixer.startMusic()
                        mixer.playSfx(R.raw.hit_crit)
                    }
                },
                onSfxDuringVoice = {
                    run("Voice, BGM, non-critical SFX, combo SFX, and critical SFX fired together.") {
                        mixer.startMusic()
                        speak(selectedWord)
                        mixer.playSfx(R.raw.hit_normal)
                        mixer.playSfx(R.raw.hit_crit)
                        mixer.playSfx(R.raw.player_hurt)
                    }
                },
                onWrongSequence = {
                    run("Wrong answer plus player hurt sequence.") {
                        mixer.playSfx(R.raw.answer_wrong)
                        mixer.playSfx(R.raw.player_hurt)
                    }
                },
                onWinSequence = {
                    run("Played victory over current BGM.") {
                        mixer.playSfx(R.raw.monster_defeat)
                        mixer.playVictory()
                    }
                },
            )
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
            PolicyPanel(
                modifier = Modifier.weight(1f),
                selectedPolicy = selectedPolicy,
                onSelectPolicy = {
                    selectedPolicy = it
                    statusText = "SFX during voice policy: $it."
                    refreshStatus()
                },
            )
            StatusPanel(
                modifier = Modifier.weight(1f),
                statusText = statusText,
                musicPlaying = status.musicPlaying,
                voiceActive = status.voiceActive,
                musicVolume = status.musicVolume,
                lastEvent = status.lastEvent,
            )
        }
    }
}

@Composable
private fun HeaderRow(onBack: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Button(
            onClick = onBack,
            modifier = Modifier
                .height(32.dp)
                .testTag("PcmAudioLabBackButton"),
            shape = RoundedCornerShape(16.dp),
            colors = ButtonDefaults.outlinedButtonColors(
                containerColor = Color.White,
                contentColor = Color(0xFF1D3557),
            ),
        ) {
            Text("Back", fontSize = 13.sp)
        }
        Text(
            "PcmAudioLab",
            modifier = Modifier
                .weight(1f)
                .testTag("PcmAudioLabTitle"),
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = Color(0xFF1D3557),
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(32.dp).weight(0.12f))
    }
}

@Composable
private fun MixPanel(
    musicEnabled: Boolean,
    sfxEnabled: Boolean,
    voiceEnabled: Boolean,
    resumeAfterVoice: Boolean,
    masterVolume: Float,
    musicVolume: Float,
    musicLoweredVolume: Float,
    sfxVoiceVolume: Float,
    onToggleMusic: () -> Unit,
    onToggleSfx: () -> Unit,
    onToggleVoice: () -> Unit,
    onToggleResume: () -> Unit,
    onAdjustMaster: (Float) -> Unit,
    onAdjustMusic: (Float) -> Unit,
    onAdjustDuck: (Float) -> Unit,
    onAdjustSfxVoice: (Float) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.fillMaxWidth()) {
        SectionTitle("Mix")
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            CompactToggle("BGM", musicEnabled, "AudioLabToggleMusic", onToggleMusic, Modifier.weight(1f))
            CompactToggle("SFX", sfxEnabled, "AudioLabToggleSfx", onToggleSfx, Modifier.weight(1f))
            CompactToggle("Voice", voiceEnabled, "AudioLabToggleVoice", onToggleVoice, Modifier.weight(1f))
            CompactToggle("Resume", resumeAfterVoice, "AudioLabToggleResume", onToggleResume, Modifier.weight(1f))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            StepperRow("Master", percent(masterVolume), "AudioLabMasterMinus", "AudioLabMasterPlus", { onAdjustMaster(-0.05f) }, { onAdjustMaster(0.05f) }, Modifier.weight(1f))
            StepperRow("BGM", percent(musicVolume), "AudioLabMusicMinus", "AudioLabMusicPlus", { onAdjustMusic(-0.05f) }, { onAdjustMusic(0.05f) }, Modifier.weight(1f))
            StepperRow("BGM duck", percent(musicLoweredVolume), "AudioLabDuckMinus", "AudioLabDuckPlus", { onAdjustDuck(-0.02f) }, { onAdjustDuck(0.02f) }, Modifier.weight(1f))
            StepperRow("SFX voice", percent(sfxVoiceVolume), "AudioLabSfxVoiceMinus", "AudioLabSfxVoicePlus", { onAdjustSfxVoice(-0.05f) }, { onAdjustSfxVoice(0.05f) }, Modifier.weight(1f))
        }
    }
}

@Composable
private fun TransportPanel(
    modifier: Modifier,
    onStartBgm: () -> Unit,
    onStopBgm: () -> Unit,
    onNormal: () -> Unit,
    onCombo: () -> Unit,
    onWrong: () -> Unit,
    onHurt: () -> Unit,
    onVictory: () -> Unit,
    onDefeat: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp), modifier = modifier) {
        SectionTitle("Transport")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            LabButton("Start BGM", "PcmAudioLabStartBgmButton", onStartBgm, Modifier.weight(1f))
            LabButton("Stop BGM", "PcmAudioLabStopBgmButton", onStopBgm, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            LabButton("Normal hit", "PcmAudioLabNormalHitButton", onNormal, Modifier.weight(1f))
            LabButton("Combo hit", "AudioLabComboHit", onCombo, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            LabButton("Wrong", "AudioLabWrong", onWrong, Modifier.weight(1f))
            LabButton("Hurt", "AudioLabHurt", onHurt, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            LabButton("Victory", "AudioLabVictory", onVictory, Modifier.weight(1f))
            LabButton("Defeat", "AudioLabDefeat", onDefeat, Modifier.weight(1f))
        }
    }
}

@Composable
private fun VoicePanel(
    modifier: Modifier,
    selectedWord: String,
    onSelectWord: (String) -> Unit,
    onSpeak: () -> Unit,
    onSpeakOverBgm: () -> Unit,
    onComboOverBgm: () -> Unit,
    onSfxDuringVoice: () -> Unit,
    onWrongSequence: () -> Unit,
    onWinSequence: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(5.dp), modifier = modifier) {
        SectionTitle("PCM Voice")
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            labWords.forEach { word ->
                ChipButton(word, selectedWord == word, "AudioLabWord_$word", { onSelectWord(word) }, Modifier.weight(1f))
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            LabButton("Speak", "AudioLabSpeak", onSpeak, Modifier.weight(1f))
            LabButton("Speak over BGM", "PcmAudioLabSpeakOverBgmButton", onSpeakOverBgm, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            LabButton("Combo over BGM", "AudioLabComboOverMusic", onComboOverBgm, Modifier.weight(1f))
            LabButton("SFX during voice", "AudioLabSfxDuringVoice", onSfxDuringVoice, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.fillMaxWidth()) {
            LabButton("Wrong sequence", "AudioLabWrongSequence", onWrongSequence, Modifier.weight(1f))
            LabButton("Win sequence", "PcmAudioLabWinSequenceButton", onWinSequence, Modifier.weight(1f))
        }
    }
}

@Composable
private fun PolicyPanel(modifier: Modifier, selectedPolicy: String, onSelectPolicy: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = modifier) {
        SectionTitle("SFX During Voice")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            sfxVoicePolicies.forEach { policy ->
                ChipButton(policy, selectedPolicy == policy, "AudioLabPolicy_$policy", { onSelectPolicy(policy) }, Modifier.weight(1f))
            }
        }
        Text(
            "Try Speak over BGM, then SFX during voice. Critical hurt/victory/defeat cues still play under suppress and delay policies.",
            fontSize = 12.sp,
            lineHeight = 18.sp,
            color = Color(0xFF536B78),
        )
    }
}

@Composable
private fun StatusPanel(
    modifier: Modifier,
    statusText: String,
    musicPlaying: Boolean,
    voiceActive: Boolean,
    musicVolume: Float,
    lastEvent: String,
) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = modifier) {
        SectionTitle("Status")
        Text(
            statusText,
            modifier = Modifier.testTag("PcmAudioLabStatus"),
            fontSize = 13.sp,
            lineHeight = 19.sp,
            color = Color(0xFF334B5A),
        )
        Text(
            "music=${if (musicPlaying) "playing" else "idle"} voice=${if (voiceActive) "active" else "idle"} volume=${percent(musicVolume)} timers=0",
            fontSize = 12.sp,
            color = Color(0xFF536B78),
        )
        Text(
            "last=${if (lastEvent.isNotEmpty()) lastEvent else "none"} delayed=none resume=0",
            fontSize = 12.sp,
            color = Color(0xFF536B78),
        )
    }
}

@Composable
private fun SectionTitle(title: String) {
    Text(
        title,
        fontSize = 14.sp,
        fontWeight = FontWeight.Bold,
        color = Color(0xFF18324A),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun LabButton(label: String, tag: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    CompactLabSurface(
        modifier = modifier.height(26.dp).testTag(tag),
        label = label,
        background = Color(0xFFEAF4F8),
        contentColor = Color(0xFF123047),
        fontWeight = FontWeight.Bold,
        onClick = onClick,
    )
}

@Composable
private fun ChipButton(label: String, selected: Boolean, tag: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    CompactLabSurface(
        modifier = modifier.height(24.dp).testTag(tag),
        label = label,
        background = if (selected) Color(0xFF276C7D) else Color(0xFFEEF3F4),
        contentColor = if (selected) Color.White else Color(0xFF315166),
        fontWeight = if (selected) FontWeight.Bold else FontWeight.Normal,
        onClick = onClick,
    )
}

@Composable
private fun CompactToggle(label: String, value: Boolean, tag: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    CompactLabSurface(
        modifier = modifier.height(26.dp).testTag(tag),
        label = "$label  ${if (value) "on" else "off"}",
        background = if (value) Color(0xFF007B86) else Color(0xFFEAF0F2),
        contentColor = if (value) Color.White else Color(0xFF536B78),
        fontWeight = FontWeight.Bold,
        radius = 13,
        onClick = onClick,
    )
}

@Composable
private fun StepperRow(
    label: String,
    value: String,
    minusTag: String,
    plusTag: String,
    onMinus: () -> Unit,
    onPlus: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(modifier = modifier, horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 11.sp, color = Color(0xFF334B5A), modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
        StepButton("-", minusTag, onMinus)
        Text(value, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = Color(0xFF123047), textAlign = TextAlign.Center, modifier = Modifier.weight(0.55f))
        StepButton("+", plusTag, onPlus)
    }
}

@Composable
private fun StepButton(label: String, tag: String, onClick: () -> Unit) {
    CompactLabSurface(
        modifier = Modifier.height(24.dp).testTag(tag),
        label = label,
        background = Color(0xFFEAF4F8),
        contentColor = Color(0xFF123047),
        fontSize = 14,
        fontWeight = FontWeight.Bold,
        radius = 12,
        onClick = onClick,
    )
}

@Composable
private fun CompactLabSurface(
    modifier: Modifier,
    label: String,
    background: Color,
    contentColor: Color,
    fontSize: Int = 11,
    fontWeight: FontWeight = FontWeight.Normal,
    radius: Int = 7,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(radius.dp))
            .background(background)
            .clickable(onClick = onClick)
            .padding(horizontal = 6.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label,
            fontSize = fontSize.sp,
            fontWeight = fontWeight,
            color = contentColor,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

private fun clamp01(value: Float): Float = value.coerceIn(0.0f, 1.0f)

private fun percent(value: Float): String = "${(value * 100).roundToInt()}%"
