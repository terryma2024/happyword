package cool.happyword.wordmagic.core

data class BattleAudioMixerPolicy(
    val masterVolume: Float = 1.0f,
    val musicVolume: Float = 0.32f,
    val musicLoweredVolumeWhileVoice: Float = 0.50f,
    val sfxDuringVoiceVolume: Float = 0.35f,
    val resumeMusicAfterVoice: Boolean = false,
    val voiceSynthesisStartDelayMs: Long = 800L,
    val voiceSynthesisTimeoutMs: Long = 3500L,
    val maxVoiceSynthesisStartRetries: Int = 1,
) {
    fun musicVolumeForVoice(musicPlaying: Boolean): Float =
        if (musicPlaying) musicLoweredVolumeWhileVoice else 0.0f

    fun musicVolumeAfterVoice(musicPlaying: Boolean): Float =
        if (musicPlaying) musicVolume else 0.0f

    fun shouldResumeMusicAfterVoice(): Boolean = resumeMusicAfterVoice

    fun sfxVolume(voiceActive: Boolean, actionSfxEnabled: Boolean): Float {
        if (!actionSfxEnabled) return 0.0f
        return if (voiceActive) sfxDuringVoiceVolume else masterVolume
    }
}
