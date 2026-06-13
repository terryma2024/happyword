@testable import WordMagicGame
import XCTest

@MainActor
final class PronunciationServiceTests: XCTestCase {
    func testShouldAutoSpeakMatchesHarmonyGate() {
        XCTAssertTrue(shouldAutoSpeak(autoSpeakEnabled: true, ttsAvailable: true, isRevealing: false, questionKind: .choice))
        XCTAssertFalse(shouldAutoSpeak(autoSpeakEnabled: false, ttsAvailable: true, isRevealing: false, questionKind: .choice))
        XCTAssertFalse(shouldAutoSpeak(autoSpeakEnabled: true, ttsAvailable: false, isRevealing: false, questionKind: .choice))
        XCTAssertFalse(shouldAutoSpeak(autoSpeakEnabled: true, ttsAvailable: true, isRevealing: true, questionKind: .choice))
        XCTAssertFalse(shouldAutoSpeak(autoSpeakEnabled: true, ttsAvailable: true, isRevealing: false, questionKind: .sentenceCloze))
    }

    func testShouldAutoSpeakAfterAnswerFeedbackSuppressesFillLetterMediumStepAdvance() {
        XCTAssertFalse(shouldAutoSpeakAfterAnswerFeedback(AnswerOutcome(correct: true, damage: 0, advancedStep: true)))
        XCTAssertTrue(shouldAutoSpeakAfterAnswerFeedback(AnswerOutcome(correct: true, damage: 1, advancedStep: false)))
        XCTAssertTrue(shouldAutoSpeakAfterAnswerFeedback(AnswerOutcome(correct: false, damage: 1, advancedStep: false)))
    }

    func testAutoSpeakCurrentBattleAnswerUsesEnglishAnswerWhenAllowed() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)

        coordinator.startBattle()
        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)

        XCTAssertEqual(speaker.spokenWords.first, coordinator.battleEngine?.state.currentQuestion?.answer)
    }

    func testAutoSpeakCurrentBattleAnswerRespectsConfigAndRevealState() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)
        var config = coordinator.configStore.config
        config.autoSpeak = false
        coordinator.configStore.save(config)

        coordinator.startBattle()
        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)
        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: true)

        XCTAssertTrue(speaker.spokenWords.isEmpty)
    }

    func testManualSpeakCurrentBattleAnswerIgnoresAutoSpeakConfig() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)
        var config = coordinator.configStore.config
        config.autoSpeak = false
        coordinator.configStore.save(config)

        coordinator.startBattle()
        coordinator.speakCurrentBattleAnswer()

        XCTAssertEqual(speaker.spokenWords.first, coordinator.battleEngine?.state.currentQuestion?.answer)
    }

    func testBattleSpeakTextReturnsFullSentenceForCloze() {
        let q = Question(promptZh: "p", answer: "cat", options: ["cat", "dog", "sun"], wordId: "w",
                         kind: .sentenceCloze, sentenceTemplate: "The ____ sat on the mat", sentenceZh: "z")
        XCTAssertEqual(q.battleSpeakText, "The cat sat on the mat")
    }
    func testBattleSpeakTextReturnsWordForChoice() {
        let q = Question.choice(wordId: "w", promptZh: "p", answer: "cat", options: ["cat", "dog", "sun"])
        XCTAssertEqual(q.battleSpeakText, "cat")
    }
    func testBattleSpeakTextFallsBackToWordWhenTemplateEmpty() {
        let q = Question(promptZh: "p", answer: "cat", options: ["cat", "dog", "sun"], wordId: "w",
                         kind: .sentenceCloze, sentenceTemplate: "", sentenceZh: "z")
        XCTAssertEqual(q.battleSpeakText, "cat")
    }

    func testSentenceClozeDoesNotAutoSpeakButManualSpeakerStillWorks() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)
        coordinator.battleEngine = BattleEngine(questionSource: FixedQuestionSource.single(Self.sentenceClozeQuestion), config: coordinator.configStore.config)
        coordinator.battleEngine?.start()

        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)
        XCTAssertTrue(speaker.spokenWords.isEmpty)

        coordinator.speakCurrentBattleAnswer()
        XCTAssertEqual(speaker.spokenWords, ["I eat an apple."])
    }

    func testAutoSpeakAfterAnswerUsesNextQuestionAnswer() {
        let speaker = RecordingPronunciationService()
        let coordinator = makeCoordinator(pronunciationService: speaker)

        coordinator.startBattle()
        let firstAnswer = coordinator.battleEngine?.state.currentQuestion?.answer
        _ = coordinator.submitBattleOptionForAnimation(firstAnswer ?? "")
        coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)

        XCTAssertEqual(speaker.spokenWords.first, coordinator.battleEngine?.state.currentQuestion?.answer)
    }

    func testBattleAudioMixerStartsBgmOnlyWhenConfiguredAndUsesFrozenVolumes() {
        let music = RecordingMusicLane()
        let voice = RecordingPronunciationService()
        let sfx = RecordingSfxLane()
        let mixer = PcmBattleAudioMixer(musicLane: music, voice: voice, sfxLane: sfx)

        mixer.startBattle(config: GameConfig(playBgm: false))
        XCTAssertTrue(music.events.isEmpty)

        mixer.startBattle(config: GameConfig(playBgm: true))

        XCTAssertEqual(music.events, ["start:0.32"])
        XCTAssertEqual(BattleAudioMixPolicy.musicVolume, 0.32, accuracy: 0.001)
        XCTAssertEqual(BattleAudioMixPolicy.musicLoweredVolumeWhileVoice, 0.50, accuracy: 0.001)
        XCTAssertEqual(BattleAudioMixPolicy.sfxDuringVoiceVolume, 0.35, accuracy: 0.001)
        XCTAssertFalse(BattleAudioMixPolicy.resumeMusicAfterVoice)
    }

    func testDefaultMusicLaneUsesHarmonyBgmBundleResource() {
        XCTAssertEqual(BundleAudioMusicLane.defaultResourceName, "bgm_battle_loop")
        XCTAssertEqual(BundleAudioMusicLane.defaultResourceExtension, "caf")
    }

    func testDefaultSfxLaneUsesHarmonyCueBundleResources() {
        XCTAssertEqual(BundleAudioSfxLane.resourceName(for: .normalHit), "hit_normal")
        XCTAssertEqual(BundleAudioSfxLane.resourceName(for: .comboHit), "hit_crit")
        XCTAssertEqual(BundleAudioSfxLane.resourceName(for: .wrong), "answer_wrong")
        XCTAssertEqual(BundleAudioSfxLane.resourceName(for: .hurt), "player_hurt")
        XCTAssertEqual(BundleAudioSfxLane.resourceName(for: .monsterDefeat), "monster_defeat")
        XCTAssertEqual(BundleAudioSfxLane.resourceName(for: .victory), "victory")
        XCTAssertEqual(BundleAudioSfxLane.resourceName(for: .defeat), "defeat")
        XCTAssertEqual(BundleAudioSfxLane.resourceExtension, "caf")
    }

    func testPcmAudioLabControllerMirrorsHarmonyControls() {
        let mixer = RecordingBattleAudioMixer()
        let lab = PcmAudioLabController(mixer: mixer)

        XCTAssertEqual(lab.selectedWord, "apple")
        XCTAssertTrue(lab.musicEnabled)
        XCTAssertTrue(lab.sfxEnabled)
        XCTAssertTrue(lab.voiceEnabled)
        XCTAssertFalse(lab.resumeMusicAfterVoice)
        XCTAssertEqual(lab.masterVolume, 1.0, accuracy: 0.001)
        XCTAssertEqual(lab.musicVolume, 0.32, accuracy: 0.001)
        XCTAssertEqual(lab.musicLoweredVolume, 0.50, accuracy: 0.001)
        XCTAssertEqual(lab.sfxDuringVoiceVolume, 0.35, accuracy: 0.001)
        XCTAssertEqual(lab.sfxDuringVoicePolicy, .lower)

        lab.selectWord("dragon")
        lab.adjustMusic(-0.05)
        lab.setPolicy(.delay)
        lab.toggleSfx()
        lab.startBgm()
        lab.speak()
        lab.comboOverBgm()
        lab.wrongSequence()
        lab.winSequence()

        XCTAssertEqual(lab.selectedWord, "dragon")
        XCTAssertEqual(lab.musicVolume, 0.27, accuracy: 0.001)
        XCTAssertEqual(lab.sfxDuringVoicePolicy, .delay)
        XCTAssertFalse(lab.sfxEnabled)
        XCTAssertEqual(mixer.settings.last?.sfxEnabled, false)
        XCTAssertEqual(mixer.startedConfigs.last?.playBgm, true)
        XCTAssertEqual(mixer.spokenWords, ["dragon"])
        XCTAssertTrue(mixer.sfxCues.contains(.comboHit))
        XCTAssertTrue(mixer.sfxCues.contains(.wrong))
        XCTAssertTrue(mixer.sfxCues.contains(.hurt))
        XCTAssertTrue(mixer.sfxCues.contains(.victory))
    }

    func testBattleAudioMixerLowersBgmDuringVoiceWithoutStopResume() {
        let music = RecordingMusicLane()
        let voice = RecordingPronunciationService()
        let sfx = RecordingSfxLane()
        let mixer = PcmBattleAudioMixer(musicLane: music, voice: voice, sfxLane: sfx)

        mixer.startBattle(config: GameConfig(playBgm: true))
        mixer.speak("apple")

        XCTAssertEqual(voice.spokenWords, ["apple"])
        XCTAssertEqual(music.events, ["start:0.32", "volume:0.50"])
        XCTAssertFalse(music.events.contains("stop"))
        XCTAssertFalse(music.events.contains("resume"))

        voice.finishCurrentSpeech()

        XCTAssertEqual(music.events, ["start:0.32", "volume:0.50", "volume:0.32"])
    }

    func testBattleAudioMixerSuppressesSfxWhenDisabledAndLowersSfxDuringVoice() {
        let music = RecordingMusicLane()
        let voice = RecordingPronunciationService()
        let sfx = RecordingSfxLane()
        let mixer = PcmBattleAudioMixer(musicLane: music, voice: voice, sfxLane: sfx)

        mixer.startBattle(config: GameConfig(actionSfx: false))
        mixer.playSfx(.normalHit)
        XCTAssertTrue(sfx.events.isEmpty)

        mixer.startBattle(config: GameConfig(playBgm: true, actionSfx: true))
        mixer.speak("dragon")
        mixer.playSfx(.victory)

        XCTAssertEqual(sfx.events, ["victory:0.35"])
        XCTAssertFalse(music.events.contains("stop"))
    }

    private func makeCoordinator(pronunciationService: PronunciationSpeaking) -> AppCoordinator {
        let defaults = UserDefaults(suiteName: "PronunciationServiceTests-\(UUID().uuidString)")!
        return AppCoordinator(configStore: GameConfigStore(defaults: defaults), pronunciationService: pronunciationService)
    }

    private final class RecordingPronunciationService: PronunciationSpeaking, BattleVoiceLane {
        var isAvailable = true
        private(set) var spokenWords: [String] = []
        private(set) var prepareCount = 0
        private(set) var disposeCount = 0
        private var completion: (() -> Void)?

        func prepare() {
            prepareCount += 1
        }

        func speak(_ word: String) {
            speak(word, completion: nil)
        }

        func speak(_ word: String, completion: (() -> Void)?) {
            guard isAvailable else { return }
            let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            spokenWords.append(trimmed)
            self.completion = completion
        }

        func finishCurrentSpeech() {
            let callback = completion
            completion = nil
            callback?()
        }

        func dispose() {
            disposeCount += 1
        }
    }

    private final class RecordingMusicLane: BattleMusicLane {
        private(set) var isPlaying = false
        private(set) var events: [String] = []

        func startLoop(volume: Double) {
            isPlaying = true
            events.append("start:\(Self.format(volume))")
        }

        func setVolume(_ volume: Double) {
            events.append("volume:\(Self.format(volume))")
        }

        func stop() {
            isPlaying = false
            events.append("stop")
        }

        func dispose() {
            isPlaying = false
            events.append("dispose")
        }

        private static func format(_ value: Double) -> String {
            String(format: "%.2f", value)
        }
    }

    private final class RecordingSfxLane: BattleSfxLane {
        private(set) var events: [String] = []

        func play(_ cue: BattleSfxCue, volume: Double) {
            events.append("\(cue.rawValue):\(String(format: "%.2f", volume))")
        }

        func dispose() {
            events.append("dispose")
        }
    }

    private final class RecordingBattleAudioMixer: BattleAudioMixing {
        var isAvailable = true
        private(set) var preparedCount = 0
        private(set) var settings: [BattleAudioMixSettings] = []
        private(set) var startedConfigs: [GameConfig] = []
        private(set) var stoppedCount = 0
        private(set) var spokenWords: [String] = []
        private(set) var sfxCues: [BattleSfxCue] = []
        private(set) var disposedCount = 0

        func prepare() {
            preparedCount += 1
        }

        func updateSettings(_ settings: BattleAudioMixSettings) {
            self.settings.append(settings)
        }

        func startBattle(config: GameConfig) {
            startedConfigs.append(config)
        }

        func stopBattle() {
            stoppedCount += 1
        }

        func speak(_ word: String) {
            spokenWords.append(word)
        }

        func playSfx(_ cue: BattleSfxCue) {
            sfxCues.append(cue)
        }

        func dispose() {
            disposedCount += 1
        }
    }

    private static var sentenceClozeQuestion: Question {
        var question = Question(
            promptZh: "苹果",
            answer: "apple",
            options: ["apple", "banana", "orange"],
            wordId: "fruit-apple",
            kind: .sentenceCloze
        )
        question.sentenceTemplate = "I eat an ____."
        question.sentenceZh = "我吃一个苹果。"
        return question
    }
}
