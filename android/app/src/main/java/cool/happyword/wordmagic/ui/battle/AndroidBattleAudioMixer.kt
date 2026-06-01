package cool.happyword.wordmagic.ui.battle

import android.content.Context
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import android.widget.Toast
import androidx.annotation.RawRes
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.BattleAudioMixerPolicy
import cool.happyword.wordmagic.core.BattleTtsVoiceCandidate
import cool.happyword.wordmagic.core.BattleTtsVoiceSelector
import cool.happyword.wordmagic.core.GameConfig
import java.io.File

data class AndroidBattleAudioSnapshot(
    val musicPlaying: Boolean = false,
    val voiceActive: Boolean = false,
    val musicVolume: Float = 0.0f,
    val lastEvent: String = "idle",
)

class AndroidBattleAudioMixer(
    context: Context,
    private var policy: BattleAudioMixerPolicy = BattleAudioMixerPolicy(),
    private val mainHandler: Handler = Handler(Looper.getMainLooper()),
) {
    private val appContext = context.applicationContext
    private var config: GameConfig = GameConfig()
    private var musicPlayer: MediaPlayer? = null
    private var voicePlayer: MediaPlayer? = null
    private var ttsEngine: TextToSpeech? = null
    private var ttsReady: Boolean = false
    private var disposed: Boolean = false
    private var requestId: Int = 0
    private var pendingSpeech: String? = null
    private var pendingSpeechRetryCount: Int = 0
    private var activeUtteranceId: String = ""
    private var activeVoiceFile: File? = null
    private var activeVoiceWord: String = ""
    private var activeVoiceRetryCount: Int = 0
    private var voiceActive: Boolean = false
    private var currentMusicVolume: Float = 0.0f
    private var lastEvent: String = "idle"
    private var ttsStableAtMs: Long = 0L
    private var currentTtsVoiceName: String? = null
    private val unavailableTtsVoiceNames = mutableSetOf<String>()

    fun enter(initialConfig: GameConfig) {
        disposed = false
        updateConfig(initialConfig)
        ensureTts()
    }

    fun updateConfig(nextConfig: GameConfig) {
        config = nextConfig
        if (config.playBgm) {
            startMusic()
        } else {
            stopMusic()
        }
    }

    fun updatePolicy(nextPolicy: BattleAudioMixerPolicy) {
        policy = nextPolicy
        if (isMusicPlaying()) {
            setMusicVolume(
                if (voiceActive) {
                    policy.musicVolumeForVoice(musicPlaying = true)
                } else {
                    policy.musicVolumeAfterVoice(musicPlaying = true)
                },
            )
        }
    }

    fun startMusic() {
        if (disposed || !config.playBgm) return
        val existing = musicPlayer
        if (existing != null) {
            setMusicVolume(policy.musicVolume)
            runCatching {
                if (!existing.isPlaying) existing.start()
            }
            lastEvent = "music_start"
            return
        }
        runCatching {
            val player = MediaPlayer.create(appContext, R.raw.bgm_battle_loop) ?: return
            musicPlayer = player
            player.isLooping = true
            setMusicVolume(policy.musicVolume)
            player.start()
            lastEvent = "music_start"
        }.onFailure {
            Log.w("WordMagicAudio", "BGM start failed", it)
        }
    }

    fun stopMusic() {
        val player = musicPlayer
        musicPlayer = null
        currentMusicVolume = 0.0f
        runCatching {
            player?.stop()
            player?.release()
        }
        lastEvent = "music_stop"
    }

    fun speakWord(word: String) {
        speakWord(word, retryCount = 0)
    }

    private fun speakWord(word: String, retryCount: Int) {
        val cleanWord = word.trim()
        if (disposed || cleanWord.isEmpty()) return
        if (!ttsReady || ttsEngine == null) {
            pendingSpeech = cleanWord
            pendingSpeechRetryCount = retryCount
            ensureTts()
            return
        }
        beginVoice()
        requestId += 1
        val utteranceId = "battle-tts-$requestId"
        activeUtteranceId = utteranceId
        activeVoiceWord = cleanWord
        activeVoiceRetryCount = retryCount
        val outputFile = File(appContext.cacheDir, "$utteranceId.wav")
        activeVoiceFile = outputFile
        val delayMs = (ttsStableAtMs - SystemClock.elapsedRealtime()).coerceAtLeast(0L)
        mainHandler.postDelayed({
            startVoiceSynthesis(cleanWord, utteranceId, outputFile, retryCount)
        }, delayMs)
        lastEvent = if (delayMs > 0) "voice_wait_tts" else "voice_synthesize_queued"
    }

    private fun startVoiceSynthesis(
        cleanWord: String,
        utteranceId: String,
        outputFile: File,
        retryCount: Int,
    ) {
        if (disposed || utteranceId != activeUtteranceId) return
        val engine = ttsEngine
        if (!ttsReady || engine == null) {
            retryVoiceSynthesis(cleanWord, utteranceId, retryCount, "tts_not_ready")
            return
        }
        val result = engine.synthesizeToFile(cleanWord, null, outputFile, utteranceId)
        if (result == TextToSpeech.ERROR) {
            Log.w("WordMagicTTS", "synthesizeToFile failed to start for word=$cleanWord")
            retryVoiceSynthesis(cleanWord, utteranceId, retryCount, "synthesize_start_failed")
        } else {
            Log.i("WordMagicTTS", "TTS synthesis started utteranceId=$utteranceId word=$cleanWord")
            lastEvent = "voice_synthesize"
            mainHandler.postDelayed({
                if (!disposed && utteranceId == activeUtteranceId && voiceActive) {
                    Log.w("WordMagicTTS", "TTS synthesis timed out utteranceId=$utteranceId")
                    retryVoiceSynthesis(cleanWord, utteranceId, retryCount, "synthesize_timeout")
                }
            }, policy.voiceSynthesisTimeoutMs)
        }
    }

    private fun retryVoiceSynthesis(cleanWord: String, utteranceId: String, retryCount: Int, reason: String) {
        finishVoice(utteranceId)
        markCurrentTtsVoiceUnavailable(reason)
        resetTtsEngine(reason)
        if (retryCount >= policy.maxVoiceSynthesisStartRetries) {
            reportTtsUnavailable(reason)
            return
        }
        pendingSpeech = cleanWord
        pendingSpeechRetryCount = retryCount + 1
        ensureTts()
    }

    fun playSfx(@RawRes sound: Int) {
        val volume = policy.sfxVolume(voiceActive = voiceActive, actionSfxEnabled = config.actionSfx)
        if (disposed || volume <= 0.0f) return
        runCatching {
            val player = MediaPlayer.create(appContext, sound) ?: return
            val effectiveVolume = (volume * policy.masterVolume).coerceIn(0.0f, 1.0f)
            player.setVolume(effectiveVolume, effectiveVolume)
            player.setOnCompletionListener { completed -> completed.release() }
            player.setOnErrorListener { failed, _, _ ->
                failed.release()
                true
            }
            player.start()
            lastEvent = if (voiceActive) "sfx_lowered" else "sfx_play"
        }.onFailure {
            Log.w("WordMagicAudio", "SFX playback failed sound=$sound", it)
        }
    }

    fun playVictory() {
        playSfx(R.raw.victory)
    }

    fun playDefeat() {
        playSfx(R.raw.defeat)
    }

    fun snapshot(): AndroidBattleAudioSnapshot =
        AndroidBattleAudioSnapshot(
            musicPlaying = isMusicPlaying(),
            voiceActive = voiceActive,
            musicVolume = currentMusicVolume,
            lastEvent = lastEvent,
        )

    fun dispose() {
        disposed = true
        pendingSpeech = null
        pendingSpeechRetryCount = 0
        activeVoiceWord = ""
        activeVoiceRetryCount = 0
        releaseVoicePlayer()
        finishVoice(activeUtteranceId)
        stopMusic()
        runCatching {
            ttsEngine?.stop()
            ttsEngine?.shutdown()
        }
        ttsEngine = null
        ttsReady = false
        currentTtsVoiceName = null
        lastEvent = "disposed"
    }

    private fun ensureTts() {
        if (ttsEngine != null || disposed) return
        val holder = arrayOfNulls<TextToSpeech>(1)
        val engine = TextToSpeech(appContext) { status ->
            mainHandler.post {
                val initializedEngine = holder[0] ?: return@post
                if (disposed) {
                    initializedEngine.shutdown()
                    return@post
                }
                if (status == TextToSpeech.SUCCESS) {
                    ttsReady = configureTtsVoice(initializedEngine)
                    initializedEngine.setOnUtteranceProgressListener(ttsListener())
                    ttsEngine = initializedEngine
                    ttsStableAtMs = SystemClock.elapsedRealtime() + policy.voiceSynthesisStartDelayMs
                    val pending = pendingSpeech
                    val pendingRetryCount = pendingSpeechRetryCount
                    if (!ttsReady) {
                        ttsEngine = null
                        pendingSpeech = null
                        pendingSpeechRetryCount = 0
                        initializedEngine.shutdown()
                        if (pending != null) {
                            reportTtsUnavailable("no_tts_voice")
                        }
                        return@post
                    }
                    if (ttsReady && pending != null) {
                        pendingSpeech = null
                        pendingSpeechRetryCount = 0
                        mainHandler.postDelayed({
                            speakWord(pending, pendingRetryCount)
                        }, policy.voiceSynthesisStartDelayMs)
                    }
                } else {
                    ttsReady = false
                    ttsEngine = null
                    Log.w("WordMagicTTS", "TextToSpeech init failed status=$status")
                    if (pendingSpeech != null) {
                        pendingSpeech = null
                        pendingSpeechRetryCount = 0
                        reportTtsUnavailable("tts_init_failed")
                    }
                }
            }
        }
        holder[0] = engine
        ttsEngine = engine
    }

    private fun configureTtsVoice(engine: TextToSpeech): Boolean {
        val voices = runCatching { engine.voices.orEmpty() }
            .onFailure { Log.w("WordMagicTTS", "Unable to inspect TTS voices", it) }
            .getOrDefault(emptySet())
        if (voices.isEmpty()) {
            Log.w("WordMagicTTS", "No TTS voices available")
            return false
        }

        val candidates = voices.map { voice ->
            val locale = voice.locale
            BattleTtsVoiceCandidate(
                name = voice.name,
                language = locale.language,
                country = locale.country,
                networkConnectionRequired = voice.isNetworkConnectionRequired,
            )
        }
        var selectedCandidate = BattleTtsVoiceSelector.choose(
            candidates = candidates,
            unavailableVoiceNames = unavailableTtsVoiceNames,
        )
        while (selectedCandidate != null) {
            val selectedVoice = voices.firstOrNull { it.name == selectedCandidate.name }
            if (selectedVoice == null) {
                Log.w("WordMagicTTS", "Selected TTS voice disappeared name=${selectedCandidate.name}")
                unavailableTtsVoiceNames += selectedCandidate.name
                selectedCandidate = BattleTtsVoiceSelector.choose(candidates, unavailableTtsVoiceNames)
                continue
            }

            val result = engine.setVoice(selectedVoice)
            val ready = result != TextToSpeech.ERROR
            if (ready) {
                currentTtsVoiceName = selectedVoice.name
                Log.i(
                    "WordMagicTTS",
                    "Selected TTS voice=${selectedVoice.name} locale=${selectedVoice.locale} " +
                        "network=${selectedVoice.isNetworkConnectionRequired}",
                )
                return true
            }

            Log.w("WordMagicTTS", "setVoice failed for ${selectedVoice.name}")
            unavailableTtsVoiceNames += selectedVoice.name
            selectedCandidate = BattleTtsVoiceSelector.choose(candidates, unavailableTtsVoiceNames)
        }

        Log.w(
            "WordMagicTTS",
            "No English TTS voice available after fallback. voices=${voices.joinToString { it.name }}",
        )
        return false
    }

    private fun markCurrentTtsVoiceUnavailable(reason: String) {
        val failedVoiceName = currentTtsVoiceName ?: return
        unavailableTtsVoiceNames += failedVoiceName
        Log.w("WordMagicTTS", "Marked TTS voice unavailable voice=$failedVoiceName reason=$reason")
    }

    private fun reportTtsUnavailable(reason: String) {
        lastEvent = "tts_unavailable"
        Log.w("WordMagicTTS", "TTS unavailable reason=$reason")
        if (!disposed) {
            Toast.makeText(appContext, "TTS unavailable", Toast.LENGTH_SHORT).show()
        }
    }

    private fun resetTtsEngine(reason: String) {
        Log.w("WordMagicTTS", "Resetting TTS engine after $reason")
        val engine = ttsEngine
        ttsEngine = null
        ttsReady = false
        currentTtsVoiceName = null
        ttsStableAtMs = 0L
        runCatching {
            engine?.stop()
            engine?.shutdown()
        }
    }

    private fun ttsListener(): UtteranceProgressListener =
        object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) = Unit

            override fun onDone(utteranceId: String?) {
                if (utteranceId == null) return
                val outputFile = File(appContext.cacheDir, "$utteranceId.wav")
                mainHandler.post {
                    if (disposed || utteranceId != activeUtteranceId) {
                        outputFile.delete()
                        return@post
                    }
                    if (!outputFile.exists()) {
                        finishVoice(utteranceId)
                        return@post
                    }
                    Log.i("WordMagicTTS", "TTS synthesis done utteranceId=$utteranceId bytes=${outputFile.length()}")
                    playVoiceFile(outputFile, utteranceId)
                }
            }

            @Suppress("OVERRIDE_DEPRECATION")
            override fun onError(utteranceId: String?) {
                Log.w("WordMagicTTS", "TTS synthesis error utteranceId=$utteranceId")
                mainHandler.post {
                    val failedUtteranceId = utteranceId.orEmpty()
                    val failedWord = activeVoiceWord
                    val failedRetryCount = activeVoiceRetryCount
                    if (failedUtteranceId == activeUtteranceId && failedWord.isNotEmpty()) {
                        retryVoiceSynthesis(
                            failedWord,
                            failedUtteranceId,
                            failedRetryCount,
                            "tts_synthesis_error",
                        )
                    } else {
                        finishVoice(failedUtteranceId)
                    }
                }
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                Log.w("WordMagicTTS", "TTS synthesis error utteranceId=$utteranceId code=$errorCode")
                mainHandler.post {
                    val failedUtteranceId = utteranceId.orEmpty()
                    val failedWord = activeVoiceWord
                    val failedRetryCount = activeVoiceRetryCount
                    if (failedUtteranceId == activeUtteranceId && failedWord.isNotEmpty()) {
                        retryVoiceSynthesis(
                            failedWord,
                            failedUtteranceId,
                            failedRetryCount,
                            "tts_synthesis_error_$errorCode",
                        )
                    } else {
                        finishVoice(failedUtteranceId)
                    }
                }
            }
        }

    private fun playVoiceFile(outputFile: File, utteranceId: String) {
        runCatching {
            voicePlayer?.stop()
            voicePlayer?.release()
            voicePlayer = MediaPlayer().apply {
                setDataSource(outputFile.absolutePath)
                setOnCompletionListener { completed ->
                    completed.release()
                    if (voicePlayer === completed) {
                        voicePlayer = null
                    }
                    outputFile.delete()
                    finishVoice(utteranceId)
                }
                setOnErrorListener { failed, _, _ ->
                    failed.release()
                    if (voicePlayer === failed) {
                        voicePlayer = null
                    }
                    outputFile.delete()
                    finishVoice(utteranceId)
                    true
                }
                prepare()
                start()
            }
            Log.i("WordMagicTTS", "Voice playback started utteranceId=$utteranceId")
            lastEvent = "voice_play"
        }.onFailure {
            Log.w("WordMagicTTS", "Voice playback failed utteranceId=$utteranceId", it)
            outputFile.delete()
            finishVoice(utteranceId)
        }
    }

    private fun beginVoice() {
        releaseVoicePlayer()
        activeVoiceFile?.delete()
        voiceActive = true
        if (isMusicPlaying()) {
            setMusicVolume(policy.musicVolumeForVoice(musicPlaying = true))
        }
        lastEvent = "voice_start"
    }

    private fun finishVoice(utteranceId: String) {
        if (utteranceId.isNotEmpty() && utteranceId != activeUtteranceId) return
        voiceActive = false
        activeUtteranceId = ""
        activeVoiceWord = ""
        activeVoiceRetryCount = 0
        activeVoiceFile?.delete()
        activeVoiceFile = null
        if (isMusicPlaying()) {
            setMusicVolume(policy.musicVolumeAfterVoice(musicPlaying = true))
        }
        if (policy.shouldResumeMusicAfterVoice()) {
            startMusic()
        }
        lastEvent = "voice_end"
    }

    private fun releaseVoicePlayer() {
        val player = voicePlayer
        voicePlayer = null
        runCatching {
            player?.stop()
        }
        runCatching {
            player?.release()
        }
    }

    private fun setMusicVolume(volume: Float) {
        val effectiveVolume = (volume * policy.masterVolume).coerceIn(0.0f, 1.0f)
        currentMusicVolume = effectiveVolume
        runCatching {
            musicPlayer?.setVolume(effectiveVolume, effectiveVolume)
        }
    }

    private fun isMusicPlaying(): Boolean =
        runCatching { musicPlayer?.isPlaying == true }.getOrDefault(false)
}
