package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class BattleAudioMixerPolicyTest {
    @Test
    fun defaultPolicyMatchesHarmonyPcmBattleMixing() {
        val policy = BattleAudioMixerPolicy()

        assertEquals(1.0f, policy.masterVolume, 0.001f)
        assertEquals(0.32f, policy.musicVolume, 0.001f)
        assertEquals(0.50f, policy.musicLoweredVolumeWhileVoice, 0.001f)
        assertEquals(0.35f, policy.sfxDuringVoiceVolume, 0.001f)
        assertFalse(policy.resumeMusicAfterVoice)
        assertEquals(800L, policy.voiceSynthesisStartDelayMs)
        assertEquals(3500L, policy.voiceSynthesisTimeoutMs)
        assertEquals(1, policy.maxVoiceSynthesisStartRetries)
    }

    @Test
    fun speakLowersAndRestoresMusicWithoutResumeSemantics() {
        val policy = BattleAudioMixerPolicy()

        assertEquals(0.50f, policy.musicVolumeForVoice(musicPlaying = true), 0.001f)
        assertEquals(0.32f, policy.musicVolumeAfterVoice(musicPlaying = true), 0.001f)
        assertEquals(0.0f, policy.musicVolumeForVoice(musicPlaying = false), 0.001f)
        assertFalse(policy.shouldResumeMusicAfterVoice())
    }

    @Test
    fun sfxDuringVoiceUsesLowerVolumeAndDisabledSfxSuppressesPlayback() {
        val policy = BattleAudioMixerPolicy()

        assertEquals(1.0f, policy.sfxVolume(voiceActive = false, actionSfxEnabled = true), 0.001f)
        assertEquals(0.35f, policy.sfxVolume(voiceActive = true, actionSfxEnabled = true), 0.001f)
        assertEquals(0.0f, policy.sfxVolume(voiceActive = true, actionSfxEnabled = false), 0.001f)
    }
}
