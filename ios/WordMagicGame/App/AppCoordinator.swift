import Foundation
import SwiftUI

enum AppRoute: Equatable {
    case home
    case battle
    case result
    case config
    case pinSetup
    case pinGate
    case parentAdmin
    case lessonReview
    case monsterCodex
    case packManager
    case wishlist
    case redemptionHistory
    case todayPlan
    case learningReport
    case scanBinding
    case boundDeviceInfo
}

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var route: AppRoute = .home
    @Published var selectedPack: Pack
    @Published var battleEngine: BattleEngine?
    @Published var lastResult: SessionResult?
    @Published var pinMessage: String = ""
    @Published var parentAdminMessage: String = ""
    @Published var reviewStore = LessonDraftReviewStore(draft: .fixtureReviewedDraft)
    @Published var packSelectionStore: PackSelectionStore
    @Published var packManagerMessage = ""
    @Published var learningReport: LearningReport?
    @Published var bindingMessage = ""
    @Published var packLibrary = PackLibrary()

    let configStore: GameConfigStore
    let coinAccount = CoinAccount()
    let parentClient: ParentApiClient = MockParentApiClient()
    let wishlistStore = WishlistStore()
    let redemptionHistoryStore = RedemptionHistoryStore()
    let learningRecorder = LearningRecorder()
    let pronunciationService: PronunciationSpeaking
    let cloudCredentialsStore: CloudCredentialsStore
    let deviceIdProvider: DeviceIdProvider
    let bindingClient: any DeviceBindingClienting

    private var globalPackCache: PackLayerCache?
    private var familyPackCache: PackLayerCache?
    private let battleRandomSeed: UInt64?

    var packs: [Pack] {
        packLibrary.allPacks()
    }

    var activePacks: [Pack] {
        packLibrary.activePacks(ids: packSelectionStore.activePackIds)
    }

    init(
        configStore: GameConfigStore = GameConfigStore(),
        pronunciationService: PronunciationSpeaking = SystemPronunciationService(),
        cloudCredentialsStore: CloudCredentialsStore = CloudCredentialsStore(),
        deviceIdProvider: DeviceIdProvider = DeviceIdProvider(),
        bindingClient: any DeviceBindingClienting = MockDeviceBindingClient(),
        battleRandomSeed: UInt64? = nil
    ) {
        self.configStore = configStore
        self.pronunciationService = pronunciationService
        self.cloudCredentialsStore = cloudCredentialsStore
        self.deviceIdProvider = deviceIdProvider
        self.bindingClient = bindingClient
        self.battleRandomSeed = battleRandomSeed
        packSelectionStore = PackSelectionStore(defaultIds: Pack.builtin.map(\.id))
        selectedPack = Pack.builtin[0]
        pronunciationService.prepare()
        applyLaunchSeeds()
        applyLaunchRouteOverride()
    }

    func selectPack(_ pack: Pack) {
        selectedPack = pack
    }

    func togglePackActive(_ pack: Pack) {
        if packSelectionStore.toggleActive(pack.id) {
            if !packSelectionStore.activePackIds.contains(selectedPack.id),
               let first = activePacks.first {
                selectedPack = first
            }
            packManagerMessage = "已激活 \(packSelectionStore.activePackIds.count) / \(PackSelectionStore.maxActivePacks)"
        } else {
            packManagerMessage = "最多只能激活 \(PackSelectionStore.maxActivePacks) 个词包"
        }
    }

    func togglePackPin(_ pack: Pack) {
        guard packSelectionStore.togglePin(pack.id) else { return }
        packManagerMessage = packSelectionStore.pinnedPackIds.contains(pack.id) ? "已固定 \(pack.title)" : "已取消固定 \(pack.title)"
    }

    func syncPacks() {
        guard cloudCredentialsStore.credentials != nil else {
            packManagerMessage = "请先绑定家长账号"
            return
        }
        do {
            let client = PackSyncClient()
            let globalResponse = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: DemoPackLayerFixtures.global)
            let familyResponse = try JSONDecoder.snakeCase.decode(PackLayerFixture.self, from: DemoPackLayerFixtures.family)
            globalPackCache = try client.apply(
                status: globalResponse.status,
                etag: globalResponse.headers.eTag,
                body: globalResponse.body,
                source: .global,
                cached: globalPackCache
            )
            familyPackCache = try client.apply(
                status: familyResponse.status,
                etag: familyResponse.headers.eTag,
                body: familyResponse.body,
                source: .family,
                cached: familyPackCache
            )
            packLibrary = PackLibrary(
                builtin: Pack.builtin,
                global: globalPackCache?.packs ?? [],
                family: familyPackCache?.packs ?? []
            )
            packManagerMessage = "已同步官方/家庭词包"
        } catch PackSyncError.bindingGone {
            cloudCredentialsStore.clear()
            packManagerMessage = "绑定已失效，请重新绑定"
        } catch {
            packManagerMessage = "同步失败，请稍后再试"
        }
    }

    func startBattle() {
        pronunciationService.prepare()
        let repository = WordRepository(words: selectedPack.words)
        let questionSource = PlanQuestionSource(
            plan: BattleQuestionPlan.from(pack: selectedPack),
            repository: repository,
            randomSeed: makeBattleRandomSeed()
        )
        let engine = BattleEngine(questionSource: questionSource, config: configStore.config)
        questionSource.setMonsterIndexProvider { engine.state.monsterIndex }
        engine.start()
        battleEngine = engine
        route = .battle
    }

    func autoSpeakCurrentBattleAnswer(isRevealing: Bool) {
        guard shouldAutoSpeak(
            autoSpeakEnabled: configStore.config.autoSpeak,
            ttsAvailable: pronunciationService.isAvailable,
            isRevealing: isRevealing
        ) else { return }
        speakCurrentBattleAnswer()
    }

    func speakCurrentBattleAnswer() {
        guard let word = battleEngine?.state.currentQuestion?.answer else { return }
        pronunciationService.speak(word)
    }

    func disposeBattlePronunciation() {
        pronunciationService.dispose()
    }

    func submitBattleOption(_ option: String) {
        guard let engine = battleEngine else { return }
        do {
            let outcome = try engine.submitAnswer(option)
            if outcome.battleEnded {
                finishBattle()
            } else {
                objectWillChange.send()
            }
        } catch {
            finishBattle()
        }
    }

    func submitBattleOptionForAnimation(_ option: String) -> AnswerOutcome? {
        guard let engine = battleEngine else { return nil }
        do {
            let outcome = try engine.submitAnswer(option)
            objectWillChange.send()
            return outcome
        } catch {
            finishBattle()
            return nil
        }
    }

    func tickBattleCountdown() {
        guard let engine = battleEngine else { return }
        let outcome = engine.tick(deltaSeconds: 1)
        if outcome.battleEnded {
            finishBattle()
        } else {
            objectWillChange.send()
        }
    }

    func finishBattle() {
        guard let engine = battleEngine,
              var result = try? engine.buildSessionResult() else { return }
        result.coinsEarned = result.stars
        result.coinsTotal = coinAccount.earn(result.stars)
        lastResult = result
        route = .result
    }

    private func makeBattleRandomSeed() -> UInt64 {
        if let battleRandomSeed {
            return battleRandomSeed
        }
        return UInt64(Date().timeIntervalSince1970 * 1000)
    }

    func saveConfig(_ config: GameConfig) {
        configStore.save(config)
        route = .config
    }

    func saveParentPin(_ pin: String, confirmation: String) {
        guard GameConfig.isValidPin(pin), pin == confirmation else {
            pinMessage = "PIN 需要是两次一致的 6 位数字"
            return
        }
        var config = configStore.config
        config.parentPin = pin
        configStore.save(config)
        pinMessage = "PIN 已保存"
        route = .config
    }

    func openParentAdmin() {
        pinMessage = ""
        if configStore.config.parentPin.isEmpty {
            route = .pinSetup
        } else {
            route = .pinGate
        }
    }

    func verifyParentPin(_ pin: String) {
        guard pin == configStore.config.parentPin else {
            pinMessage = "PIN 不正确"
            return
        }
        route = .parentAdmin
    }

    func openLessonReview(draft: LessonDraft = .fixtureReviewedDraft) {
        reviewStore = LessonDraftReviewStore(draft: draft)
        route = .lessonReview
    }

    func openMonsterCodex() {
        route = .monsterCodex
    }

    func openWishlist() {
        route = .wishlist
    }

    func openTodayPlan() {
        route = .todayPlan
    }

    func openLearningReport() {
        learningReport = LearningReportBuilder().build(
            library: packLibrary,
            activePackIds: packSelectionStore.activePackIds,
            recorder: learningRecorder
        )
        route = .learningReport
    }

    func openBinding() {
        bindingMessage = ""
        route = .scanBinding
    }

    func openBoundDeviceInfo() {
        bindingMessage = ""
        route = .boundDeviceInfo
    }

    func bind(shortCode: String) async {
        let trimmed = shortCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6 else {
            bindingMessage = "请输入 6 位短码"
            return
        }
        do {
            let response = try await bindingClient.redeem(shortCode: trimmed, deviceId: deviceIdProvider.deviceId())
            cloudCredentialsStore.save(response)
            bindingMessage = "绑定成功：\(response.nickname)"
        } catch {
            bindingMessage = "短码无效，请重新输入"
        }
    }

    func finishBinding() {
        bindingMessage = ""
        route = .config
    }

    func unbind(pin: String) {
        guard pin == configStore.config.parentPin else {
            bindingMessage = "PIN 不正确"
            return
        }
        cloudCredentialsStore.clear()
        globalPackCache = nil
        familyPackCache = nil
        packLibrary = PackLibrary()
        packManagerMessage = ""
        bindingMessage = ""
        route = .config
    }

    func approveLessonReview() {
        parentAdminMessage = "已发布词包 v7，包含 \(reviewStore.approvePayload().words.count) 个单词"
        route = .parentAdmin
    }

    private func applyLaunchRouteOverride() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestRouteBattle") {
            startBattle()
        } else if arguments.contains("-UITestRouteResult") {
            lastResult = SessionResult(
                status: .won,
                defeatedMonsters: 5,
                monstersTotal: 5,
                totalAnswers: 15,
                correctAnswers: 15,
                correctRate: 1,
                learnedWordCount: 5,
                stars: 3,
                coinsEarned: 3,
                coinsTotal: 3
            )
            route = .result
        } else if arguments.contains("-UITestRouteConfig") {
            route = .config
        } else if arguments.contains("-UITestRoutePinSetup") {
            route = .pinSetup
        } else if arguments.contains("-UITestRouteParentAdmin") {
            route = .parentAdmin
        } else if arguments.contains("-UITestRouteLessonReview") {
            route = .lessonReview
        } else if arguments.contains("-UITestRouteMonsterCodex") {
            route = .monsterCodex
        } else if arguments.contains("-UITestRoutePackManager") {
            route = .packManager
        } else if arguments.contains("-UITestRouteWishlist") {
            route = .wishlist
        } else if arguments.contains("-UITestRouteTodayPlan") {
            route = .todayPlan
        } else if arguments.contains("-UITestRouteLearningReport") {
            openLearningReport()
        } else if arguments.contains("-UITestRouteScanBinding") {
            route = .scanBinding
        } else if arguments.contains("-UITestRouteBoundDeviceInfo") {
            route = .boundDeviceInfo
        }
    }

    private func applyLaunchSeeds() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestSeedCoins") {
            _ = coinAccount.earn(20)
        }
        if arguments.contains("-UITestSeedParentPin") {
            var config = configStore.config
            config.parentPin = "123456"
            configStore.save(config)
        }
        if arguments.contains("-UITestSeedBoundDevice") {
            cloudCredentialsStore.save(.demoBinding)
        }
        if arguments.contains("-UITestResetState") {
            packSelectionStore = PackSelectionStore(defaultIds: Pack.builtin.map(\.id))
            selectedPack = Pack.builtin[0]
        }
        if arguments.contains("-UITestRouteTodayPlan") || arguments.contains("-UITestRouteLearningReport") {
            learningRecorder.record(wordId: "fruit-apple", correct: true, at: Date(timeIntervalSinceNow: -86_400 * 3))
            learningRecorder.record(wordId: "home-door", correct: false, at: Date())
        }
    }
}

enum AppTheme {
    static let ink = Color(red: 0.13, green: 0.15, blue: 0.19)
    static let red = Color(red: 0.84, green: 0.18, blue: 0.18)
    static let gold = Color(red: 0.95, green: 0.68, blue: 0.22)
    static let mint = Color(red: 0.18, green: 0.58, blue: 0.49)
    static let blue = Color(red: 0.08, green: 0.35, blue: 0.94)
    static let navy = Color(red: 0.10, green: 0.19, blue: 0.32)
    static let purple = Color(red: 0.47, green: 0.29, blue: 0.64)
    static let cream = Color(red: 1.00, green: 0.96, blue: 0.84)
    static let paleBlue = Color(red: 0.86, green: 0.93, blue: 0.98)
    static let palePink = Color(red: 0.98, green: 0.82, blue: 0.82)
    static let page = Color(red: 0.98, green: 0.99, blue: 1.00)
    static let background = LinearGradient(
        colors: [
            Color(red: 0.99, green: 1.00, blue: 1.00),
            Color(red: 0.95, green: 0.98, blue: 1.00),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
