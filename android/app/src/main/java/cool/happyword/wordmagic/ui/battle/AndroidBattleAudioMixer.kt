package cool.happyword.wordmagic.ui.battle

import android.content.Context
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.util.Log
import androidx.annotation.RawRes
import cool.happyword.wordmagic.R
import cool.happyword.wordmagic.core.BattleAudioMixerPolicy
import cool.happyword.wordmagic.core.GameConfig
import java.io.File
import java.util.Locale

data class AndroidBattleAudioSnapshot(
    val musicPlaying: Boolean = false,
    val voiceActive: Boolean = false,
    val musicVolume: Float = 0.0f,
    val lastEvent: String = "idle",
)

class AndroidBattleAudioMixer(
    context: Context,
    private val policy: BattleAudioMixerPolicy = BattleAudioMixerPolicy(),
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
    private var activeUtteranceId: String = ""
    private var activeVoiceFile: File? = null
    private var voiceActive: Boolean = false
    private var currentMusicVolume: Float = 0.0f
    private var lastEvent: String = "idle"

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
        val cleanWord = word.trim()
        if (disposed || cleanWord.isEmpty()) return
        val engine = ttsEngine
        if (!ttsReady || engine == null) {
            pendingSpeech = cleanWord
            ensureTts()
            return
        }
        beginVoice()
        requestId += 1
        val utteranceId = "battle-tts-$requestId"
        activeUtteranceId = utteranceId
        val outputFile = File(appContext.cacheDir, "$utteranceId.wav")
        activeVoiceFile = outputFile
        runCatching { engine.stop() }
        val result = engine.synthesizeToFile(cleanWord, null, outputFile, utteranceId)
        if (result == TextToSpeech.ERROR) {
            Log.w("WordMagicTTS", "synthesizeToFile failed to start for word=$cleanWord")
            finishVoice(utteranceId)
        } else {
            lastEvent = "voice_synthesize"
        }
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
        releaseVoicePlayer()
        finishVoice(activeUtteranceId)
        stopMusic()
        runCatching {
            ttsEngine?.stop()
            ttsEngine?.shutdown()
        }
        ttsEngine = null
        ttsReady = false
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
                    val languageStatus = initializedEngine.setLanguage(Locale.US)
                    ttsReady = languageStatus != TextToSpeech.LANG_MISSING_DATA &&
                        languageStatus != TextToSpeech.LANG_NOT_SUPPORTED
                    initializedEngine.setOnUtteranceProgressListener(ttsListener())
                    ttsEngine = initializedEngine
                    val pending = pendingSpeech
                    if (ttsReady && pending != null) {
                        pendingSpeech = null
                        speakWord(pending)
                    }
                } else {
                    ttsReady = false
                    Log.w("WordMagicTTS", "TextToSpeech init failed status=$status")
                }
            }
        }
        holder[0] = engine
        ttsEngine = engine
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
                    playVoiceFile(outputFile, utteranceId)
                }
            }

            @Suppress("OVERRIDE_DEPRECATION")
            override fun onError(utteranceId: String?) {
                Log.w("WordMagicTTS", "TTS synthesis error utteranceId=$utteranceId")
                mainHandler.post { finishVoice(utteranceId.orEmpty()) }
            }

            override fun onError(utteranceId: String?, errorCode: Int) {
                Log.w("WordMagicTTS", "TTS synthesis error utteranceId=$utteranceId code=$errorCode")
                mainHandler.post { finishVoice(utteranceId.orEmpty()) }
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
