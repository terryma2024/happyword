import AVFoundation
import Foundation

@MainActor
protocol PronunciationSpeaking: AnyObject {
    var isAvailable: Bool { get }

    func prepare()
    func speak(_ word: String)
    func dispose()
}

@MainActor
protocol BattleVoiceLane: AnyObject {
    var isAvailable: Bool { get }

    func prepare()
    func speak(_ word: String, completion: (() -> Void)?)
    func dispose()
}

@MainActor
protocol BattleMusicLane: AnyObject {
    var isPlaying: Bool { get }

    func startLoop(volume: Double)
    func setVolume(_ volume: Double)
    func stop()
    func dispose()
}

@MainActor
protocol BattleSfxLane: AnyObject {
    func play(_ cue: BattleSfxCue, volume: Double)
    func dispose()
}

enum BattleSfxCue: String, Equatable {
    case normalHit = "normal_hit"
    case comboHit = "combo_hit"
    case wrong = "wrong"
    case hurt = "hurt"
    case monsterDefeat = "monster_defeat"
    case victory = "victory"
    case defeat = "defeat"
}

enum BattleAudioMixPolicy {
    static let masterVolume = 1.0
    static let musicVolume = 0.32
    static let musicLoweredVolumeWhileVoice = 0.50
    static let sfxVolume = 1.0
    static let sfxDuringVoiceVolume = 0.35
    static let resumeMusicAfterVoice = false
}

enum BattleSfxDuringVoicePolicy: String, CaseIterable, Equatable {
    case full
    case lower
    case suppress
    case delay
}

struct BattleAudioMixSettings: Equatable {
    var masterVolume = BattleAudioMixPolicy.masterVolume
    var musicVolume = BattleAudioMixPolicy.musicVolume
    var musicLoweredVolumeWhileVoice = BattleAudioMixPolicy.musicLoweredVolumeWhileVoice
    var sfxVolume = BattleAudioMixPolicy.sfxVolume
    var sfxDuringVoiceVolume = BattleAudioMixPolicy.sfxDuringVoiceVolume
    var resumeMusicAfterVoice = BattleAudioMixPolicy.resumeMusicAfterVoice
    var voiceEnabled = true
    var sfxEnabled = true
    var sfxDuringVoicePolicy = BattleSfxDuringVoicePolicy.lower
}

@MainActor
protocol BattleAudioMixing: AnyObject {
    var isAvailable: Bool { get }

    func prepare()
    func updateSettings(_ settings: BattleAudioMixSettings)
    func startBattle(config: GameConfig)
    func stopBattle()
    func speak(_ word: String)
    func playSfx(_ cue: BattleSfxCue)
    func dispose()
}

func shouldAutoSpeak(
    autoSpeakEnabled: Bool,
    ttsAvailable: Bool,
    isRevealing: Bool,
    questionKind: QuestionKind? = nil
) -> Bool {
    autoSpeakEnabled && ttsAvailable && !isRevealing && questionKind != .sentenceCloze
}

func shouldAutoSpeakAfterAnswerFeedback(_ outcome: AnswerOutcome) -> Bool {
    !outcome.advancedStep
}

@MainActor
final class SystemPronunciationService: NSObject, PronunciationSpeaking, BattleVoiceLane {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isAvailable = true
    private var completion: (() -> Void)?

    func prepare() {
        isAvailable = true
        configureAudioSessionForMixing()
    }

    func speak(_ word: String) {
        speak(word, completion: nil)
    }

    func speak(_ word: String, completion: (() -> Void)?) {
        guard isAvailable else { return }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        self.completion = completion
        synthesizer.delegate = self
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func dispose() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        completion = nil
    }
}

extension SystemPronunciationService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
        Task { @MainActor in
            let callback = completion
            completion = nil
            callback?()
        }
    }

    nonisolated func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
        Task { @MainActor in
            let callback = completion
            completion = nil
            callback?()
        }
    }
}

@MainActor
final class PcmBattleAudioMixer: BattleAudioMixing {
    private let musicLane: BattleMusicLane
    private let voice: BattleVoiceLane
    private let sfxLane: BattleSfxLane
    private var config = GameConfig.default
    private var voiceActive = false
    private var settings = BattleAudioMixSettings()
    private var delayedSfx: [BattleSfxCue] = []

    var isAvailable: Bool {
        voice.isAvailable
    }

    init(
        musicLane: BattleMusicLane = BundleAudioMusicLane(),
        voice: BattleVoiceLane = PcmSpeechVoiceLane(),
        sfxLane: BattleSfxLane = BundleAudioSfxLane()
    ) {
        self.musicLane = musicLane
        self.voice = voice
        self.sfxLane = sfxLane
    }

    func prepare() {
        voice.prepare()
    }

    func updateSettings(_ settings: BattleAudioMixSettings) {
        self.settings = settings
        if musicLane.isPlaying {
            musicLane.setVolume(effectiveMusicVolume(voiceActive ? settings.musicLoweredVolumeWhileVoice : settings.musicVolume))
        }
    }

    func startBattle(config: GameConfig) {
        self.config = config
        voiceActive = false
        delayedSfx.removeAll()
        if config.playBgm {
            musicLane.startLoop(volume: effectiveMusicVolume(settings.musicVolume))
        }
    }

    func stopBattle() {
        musicLane.stop()
        voiceActive = false
        delayedSfx.removeAll()
    }

    func speak(_ word: String) {
        guard settings.voiceEnabled, voice.isAvailable else { return }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        voiceActive = true
        if musicLane.isPlaying {
            musicLane.setVolume(effectiveMusicVolume(settings.musicLoweredVolumeWhileVoice))
        }
        voice.speak(trimmed) { [weak self] in
            guard let self else { return }
            voiceActive = false
            if musicLane.isPlaying {
                musicLane.setVolume(effectiveMusicVolume(settings.musicVolume))
            }
            flushDelayedSfx()
        }
    }

    func playSfx(_ cue: BattleSfxCue) {
        guard config.actionSfx, settings.sfxEnabled else { return }
        guard voiceActive else {
            sfxLane.play(cue, volume: effectiveSfxVolume(settings.sfxVolume))
            return
        }

        switch settings.sfxDuringVoicePolicy {
        case .full:
            sfxLane.play(cue, volume: effectiveSfxVolume(settings.sfxVolume))
        case .lower:
            sfxLane.play(cue, volume: effectiveSfxVolume(settings.sfxDuringVoiceVolume))
        case .suppress:
            if cue.isCriticalDuringVoice {
                sfxLane.play(cue, volume: effectiveSfxVolume(settings.sfxDuringVoiceVolume))
            }
        case .delay:
            if cue.isCriticalDuringVoice {
                sfxLane.play(cue, volume: effectiveSfxVolume(settings.sfxDuringVoiceVolume))
            } else {
                delayedSfx.append(cue)
            }
        }
    }

    func dispose() {
        stopBattle()
        voice.dispose()
        musicLane.dispose()
        sfxLane.dispose()
    }

    private func flushDelayedSfx() {
        let cues = delayedSfx
        delayedSfx.removeAll()
        cues.forEach { sfxLane.play($0, volume: effectiveSfxVolume(settings.sfxVolume)) }
    }

    private func effectiveMusicVolume(_ volume: Double) -> Double {
        volume * settings.masterVolume
    }

    private func effectiveSfxVolume(_ volume: Double) -> Double {
        volume * settings.masterVolume
    }
}

private extension BattleSfxCue {
    var isCriticalDuringVoice: Bool {
        switch self {
        case .hurt, .victory, .defeat:
            return true
        case .normalHit, .comboHit, .wrong, .monsterDefeat:
            return false
        }
    }
}

@MainActor
final class PcmSpeechVoiceLane: NSObject, BattleVoiceLane {
    private let synthesizer = AVSpeechSynthesizer()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private(set) var isAvailable = true
    private var isPrepared = false
    private var activeGeneration = UUID()
    private var completion: (() -> Void)?
    private var pendingBuffers = 0
    private var sawEndBuffer = false

    func prepare() {
        isAvailable = true
        configureAudioSessionForMixing()
    }

    func speak(_ word: String, completion: (() -> Void)?) {
        guard isAvailable else { return }
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        activeGeneration = UUID()
        let generation = activeGeneration
        self.completion = completion
        pendingBuffers = 0
        sawEndBuffer = false
        player.stop()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US") ?? AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1.0

        synthesizer.write(utterance) { [weak self] buffer in
            Task { @MainActor in
                guard let self, generation == self.activeGeneration else { return }
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else {
                    self.finishSpeech(generation: generation)
                    return
                }
                guard pcmBuffer.frameLength > 0 else {
                    self.sawEndBuffer = true
                    self.finishSpeechIfReady(generation: generation)
                    return
                }
                self.schedule(buffer: pcmBuffer, generation: generation)
            }
        }
    }

    func dispose() {
        activeGeneration = UUID()
        player.stop()
        engine.stop()
        if isPrepared {
            engine.detach(player)
            isPrepared = false
        }
        completion = nil
        pendingBuffers = 0
        sawEndBuffer = false
    }

    private func schedule(buffer: AVAudioPCMBuffer, generation: UUID) {
        prepareIfNeeded(format: buffer.format)
        startEngineIfNeeded()
        pendingBuffers += 1
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.activeGeneration else { return }
                self.pendingBuffers = max(0, self.pendingBuffers - 1)
                self.finishSpeechIfReady(generation: generation)
            }
        }
        if !player.isPlaying {
            player.play()
        }
    }

    private func finishSpeechIfReady(generation: UUID) {
        guard sawEndBuffer, pendingBuffers == 0 else { return }
        finishSpeech(generation: generation)
    }

    private func finishSpeech(generation: UUID) {
        guard generation == activeGeneration else { return }
        let callback = completion
        completion = nil
        callback?()
    }

    private func prepareIfNeeded(format: AVAudioFormat) {
        guard !isPrepared else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isPrepared = true
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }
}

@MainActor
final class PronunciationVoiceLaneAdapter: BattleVoiceLane {
    private let speaker: PronunciationSpeaking

    var isAvailable: Bool {
        speaker.isAvailable
    }

    init(_ speaker: PronunciationSpeaking) {
        self.speaker = speaker
    }

    func prepare() {
        speaker.prepare()
    }

    func speak(_ word: String, completion: (() -> Void)?) {
        speaker.speak(word)
        completion?()
    }

    func dispose() {
        speaker.dispose()
    }
}

@MainActor
final class BundleAudioMusicLane: NSObject, BattleMusicLane, AVAudioPlayerDelegate {
    static let defaultResourceName = "bgm_battle_loop"
    static let defaultResourceExtension = "caf"

    private let resourceName: String
    private let resourceExtension: String
    private let bundle: Bundle
    private var player: AVAudioPlayer?
    private(set) var isPlaying = false

    init(
        resourceName: String = BundleAudioMusicLane.defaultResourceName,
        resourceExtension: String = BundleAudioMusicLane.defaultResourceExtension,
        bundle: Bundle = .main
    ) {
        self.resourceName = resourceName
        self.resourceExtension = resourceExtension
        self.bundle = bundle
    }

    func startLoop(volume: Double) {
        configureAudioSessionForMixing()
        let audioPlayer: AVAudioPlayer
        if let existing = player {
            audioPlayer = existing
        } else {
            guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
                  let loaded = try? AVAudioPlayer(contentsOf: url)
            else {
                isPlaying = false
                return
            }
            loaded.delegate = self
            loaded.numberOfLoops = -1
            loaded.prepareToPlay()
            player = loaded
            audioPlayer = loaded
        }

        audioPlayer.currentTime = 0
        audioPlayer.volume = Float(volume)
        isPlaying = audioPlayer.play()
    }

    func setVolume(_ volume: Double) {
        player?.volume = Float(volume)
    }

    func stop() {
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
    }

    func dispose() {
        stop()
        player = nil
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_: AVAudioPlayer, error _: Error?) {
        Task { @MainActor in
            self.isPlaying = false
        }
    }
}

@MainActor
final class GeneratedMusicLane: BattleMusicLane {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isPrepared = false
    private(set) var isPlaying = false

    func startLoop(volume: Double) {
        configureAudioSessionForMixing()
        guard let buffer = Self.makeToneBuffer(frequency: 196, seconds: 1.2, amplitude: 0.24) else { return }
        prepareIfNeeded(format: buffer.format)
        player.stop()
        player.volume = Float(volume)
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        startEngineIfNeeded()
        player.play()
        isPlaying = true
    }

    func setVolume(_ volume: Double) {
        player.volume = Float(volume)
    }

    func stop() {
        player.stop()
        isPlaying = false
    }

    func dispose() {
        stop()
        engine.stop()
        if isPrepared {
            engine.detach(player)
            isPrepared = false
        }
    }

    private func prepareIfNeeded(format: AVAudioFormat) {
        guard !isPrepared else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isPrepared = true
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    fileprivate static func makeToneBuffer(frequency: Double, seconds: Double, amplitude: Float) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate * seconds))
        else {
            return nil
        }
        buffer.frameLength = buffer.frameCapacity
        guard let channel = buffer.floatChannelData?[0] else { return nil }
        for frame in 0..<Int(buffer.frameLength) {
            let t = Double(frame) / sampleRate
            let wave = sin(2.0 * .pi * frequency * t) + 0.45 * sin(2.0 * .pi * frequency * 1.5 * t)
            channel[frame] = amplitude * Float(wave)
        }
        return buffer
    }
}

@MainActor
final class BundleAudioSfxLane: BattleSfxLane {
    static let resourceExtension = "caf"

    private let bundle: Bundle
    private var activePlayers: [AVAudioPlayer] = []

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func play(_ cue: BattleSfxCue, volume: Double) {
        configureAudioSessionForMixing()
        activePlayers = activePlayers.filter(\.isPlaying)
        guard let url = bundle.url(
            forResource: Self.resourceName(for: cue),
            withExtension: Self.resourceExtension
        ),
            let player = try? AVAudioPlayer(contentsOf: url)
        else {
            return
        }
        player.volume = Float(volume)
        player.numberOfLoops = 0
        player.prepareToPlay()
        if player.play() {
            activePlayers.append(player)
        }
    }

    func dispose() {
        activePlayers.forEach { $0.stop() }
        activePlayers.removeAll()
    }

    static func resourceName(for cue: BattleSfxCue) -> String {
        switch cue {
        case .normalHit:
            return "hit_normal"
        case .comboHit:
            return "hit_crit"
        case .wrong:
            return "answer_wrong"
        case .hurt:
            return "player_hurt"
        case .monsterDefeat:
            return "monster_defeat"
        case .victory:
            return "victory"
        case .defeat:
            return "defeat"
        }
    }
}

@MainActor
final class GeneratedSfxLane: BattleSfxLane {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isPrepared = false

    func play(_ cue: BattleSfxCue, volume: Double) {
        configureAudioSessionForMixing()
        let frequency: Double
        switch cue {
        case .normalHit:
            frequency = 520
        case .comboHit:
            frequency = 740
        case .wrong:
            frequency = 180
        case .hurt:
            frequency = 240
        case .monsterDefeat:
            frequency = 660
        case .victory:
            frequency = 880
        case .defeat:
            frequency = 150
        }
        guard let buffer = GeneratedMusicLane.makeToneBuffer(frequency: frequency, seconds: 0.18, amplitude: 0.45) else { return }
        prepareIfNeeded(format: buffer.format)
        player.volume = Float(volume)
        player.scheduleBuffer(buffer)
        startEngineIfNeeded()
        player.play()
    }

    func dispose() {
        player.stop()
        engine.stop()
        if isPrepared {
            engine.detach(player)
            isPrepared = false
        }
    }

    private func prepareIfNeeded(format: AVAudioFormat) {
        guard !isPrepared else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        isPrepared = true
    }

    private func startEngineIfNeeded() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }
}

private func configureAudioSessionForMixing() {
#if os(iOS)
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
    try? session.setActive(true)
#endif
}
