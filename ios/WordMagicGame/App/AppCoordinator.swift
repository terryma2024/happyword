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
    case childProfile
    case devMenu
    case bypassSecret
}

/// HarmonyOS `DevMenuRouteParams.presetEnv` parity (e.g. home version triple-tap → DevMenu).
enum DevMenuRouteParams {
    static let presetPreview = "preview"
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
    @Published var toastMessage: String?

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
    let packLayerClient: any PackLayerClienting
    let packLayerStore: FileBackedPackLayerStore
    let wordStatsSyncClient: any WordStatsSyncClienting
    let wordStatsSyncStateStore: WordStatsSyncStateStore
    let unbindClient: any DeviceUnbindClienting
    let childProfileClient: any ChildProfileClienting
    let developerMenuViewModel: DeveloperMenuViewModel

    private var globalPackCache: PackLayerCache?
    private var familyPackCache: PackLayerCache?
    private let battleRandomSeed: UInt64?
    private var toastToken = UUID()
    private var pendingDeveloperMenuCard: DeveloperMenuCard?
    /// Consumed once when `DevMenuView` appears. Matches Harmony `presetEnv` route param.
    private var devMenuRoutePreset: String?

    var packs: [Pack] {
        packLibrary.allPacks()
    }

    var activePacks: [Pack] {
        packLibrary.activePacks(ids: packSelectionStore.activePackIds)
    }

    var showsChildProfileShortcut: Bool {
        cloudCredentialsStore.credentials != nil
    }

    init(
        configStore: GameConfigStore = GameConfigStore(),
        pronunciationService: PronunciationSpeaking = SystemPronunciationService(),
        cloudCredentialsStore: CloudCredentialsStore = CloudCredentialsStore(),
        deviceIdProvider: DeviceIdProvider = DeviceIdProvider(),
        bindingClient: any DeviceBindingClienting = CloudClientFactory.bindingClient(),
        packLayerClient: any PackLayerClienting = CloudClientFactory.packLayerClient(),
        packLayerStore: FileBackedPackLayerStore = FileBackedPackLayerStore(),
        wordStatsSyncClient: any WordStatsSyncClienting = CloudClientFactory.wordStatsSyncClient(),
        wordStatsSyncStateStore: WordStatsSyncStateStore = WordStatsSyncStateStore(),
        unbindClient: any DeviceUnbindClienting = CloudClientFactory.unbindClient(),
        childProfileClient: any ChildProfileClienting = CloudClientFactory.childProfileClient(),
        developerMenuViewModel: DeveloperMenuViewModel = DeveloperMenuViewModel(),
        battleRandomSeed: UInt64? = nil
    ) {
        self.configStore = configStore
        self.pronunciationService = pronunciationService
        self.cloudCredentialsStore = cloudCredentialsStore
        self.deviceIdProvider = deviceIdProvider
        self.bindingClient = bindingClient
        self.packLayerClient = packLayerClient
        self.packLayerStore = packLayerStore
        self.wordStatsSyncClient = wordStatsSyncClient
        self.wordStatsSyncStateStore = wordStatsSyncStateStore
        self.unbindClient = unbindClient
        self.childProfileClient = childProfileClient
        self.developerMenuViewModel = developerMenuViewModel
        self.battleRandomSeed = battleRandomSeed
        packSelectionStore = PackSelectionStore(defaultIds: Pack.builtin.map(\.id))
        selectedPack = Pack.builtin[0]
        pronunciationService.prepare()
        loadCachedPackLayers()
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
        Task { await syncPacksFromCloud() }
    }

    func activateDeveloperMenuCard(_ card: DeveloperMenuCard) async {
        if card.environment == .preview, developerMenuViewModel.bypassSecret.isEmpty {
            pendingDeveloperMenuCard = card
            developerMenuViewModel.statusMessage = "请先保存 bypass secret"
            route = .bypassSecret
            return
        }
        let bindingBeforeSwitch = cloudCredentialsStore.credentials
        let result = await developerMenuViewModel.activate(card)
        guard result.didApply else { return }
        let shouldPromptRebind = bindingNeedsRebindAfterEnvironmentActivation(bindingBeforeSwitch)
        if shouldPromptRebind {
            clearLocalBindingForEnvironmentSwitch()
        }
        route = .home
        if shouldPromptRebind {
            showToast("已切换环境，请重新绑定家长账号")
        } else if let message = result.toastMessage {
            showToast(message)
        }
    }

    func showToast(_ message: String, duration: TimeInterval = 2.0) {
        toastToken = UUID()
        let token = toastToken
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if toastToken == token {
                toastMessage = nil
            }
        }
    }

    func syncPacksFromCloud() async {
        guard let credentials = cloudCredentialsStore.credentials else {
            packManagerMessage = "请先绑定家长账号"
            return
        }
        do {
            globalPackCache = try await packLayerClient.fetchGlobal(cached: globalPackCache)
            familyPackCache = try await packLayerClient.fetchFamily(
                deviceToken: credentials.deviceToken,
                cached: familyPackCache
            )
            try packLayerStore.save(globalPackCache, layer: .global)
            try packLayerStore.save(familyPackCache, layer: .family)
            rebuildPackLibraryFromCaches()
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
        let enabledTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(configStore.config.enabledQuestionTypes)
        guard BattleQuestionTypePolicy.anyWordSupportsQuestionTypes(selectedPack.words, typeIds: enabledTypes) else {
            showToast("当前词包没有支持所选题型的单词")
            return
        }
        let questionSource = PlanQuestionSource(
            plan: BattleQuestionPlan.from(pack: selectedPack, enabledQuestionTypes: enabledTypes),
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
            let answeredWordId = engine.state.currentQuestion?.wordId
            let outcome = try engine.submitAnswer(option)
            if let answeredWordId, !outcome.advancedStep {
                learningRecorder.record(wordId: answeredWordId, correct: outcome.correct)
            }
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
            let answeredWordId = engine.state.currentQuestion?.wordId
            let outcome = try engine.submitAnswer(option)
            if let answeredWordId, !outcome.advancedStep {
                learningRecorder.record(wordId: answeredWordId, correct: outcome.correct)
            }
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
        Task { await syncWordStatsIfPossible(showStatus: false) }
    }

    private func makeBattleRandomSeed() -> UInt64 {
        if let battleRandomSeed {
            return battleRandomSeed
        }
        return UInt64(Date().timeIntervalSince1970 * 1000)
    }

    func saveConfig(_ config: GameConfig) {
        configStore.save(config)
        route = .home
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

    func openChildProfile() {
        bindingMessage = ""
        route = .childProfile
    }

    func openDeveloperMenu(presetEnv: String? = nil) {
        guard DeveloperToolsPolicy.isDeveloperToolsVisible() else { return }
        if let trimmed = presetEnv?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
            devMenuRoutePreset = trimmed
        } else {
            devMenuRoutePreset = nil
        }
        route = .devMenu
    }

    /// Returns and clears the pending `presetEnv` value for `DevMenuView` (single consume).
    func takeDevMenuRoutePreset() -> String? {
        let value = devMenuRoutePreset
        devMenuRoutePreset = nil
        return value
    }

    func openBypassSecret() {
        guard DeveloperToolsPolicy.isDeveloperToolsVisible() else { return }
        pendingDeveloperMenuCard = nil
        route = .bypassSecret
    }

    func cancelBypassSecret() {
        pendingDeveloperMenuCard = nil
        route = .devMenu
    }

    func saveBypassSecretAndContinue(_ secret: String) async {
        developerMenuViewModel.saveBypassSecret(secret)
        guard !developerMenuViewModel.bypassSecret.isEmpty else {
            route = .bypassSecret
            return
        }
        guard let card = pendingDeveloperMenuCard else {
            route = .devMenu
            return
        }
        pendingDeveloperMenuCard = nil
        route = .devMenu
        await activateDeveloperMenuCard(card)
    }

    func currentChildNickname() -> String {
        cloudCredentialsStore.credentials?.nickname ?? "孩子档案"
    }

    func currentChildAvatarEmoji() -> String {
        cloudCredentialsStore.credentials?.avatarEmoji ?? "🧒"
    }

    func currentDeviceIdSuffix() -> String {
        String(deviceIdProvider.deviceId().suffix(4))
    }

    func currentDeviceIdSourceLabel() -> String {
        deviceIdProvider.sourceLabel()
    }

    func currentBindingTimeText() -> String {
        guard let pairedAt = cloudCredentialsStore.credentials?.pairedAt else {
            return "—"
        }
        return DateFormatter.localizedString(from: pairedAt, dateStyle: .short, timeStyle: .medium)
    }

    func updateChildNickname(_ nickname: String) async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            bindingMessage = "请输入孩子名字"
            return
        }
        guard var credentials = cloudCredentialsStore.credentials else {
            bindingMessage = "请先绑定家长账号"
            return
        }
        credentials.nickname = trimmed
        cloudCredentialsStore.save(credentials)
        bindingMessage = "已保存孩子名字"
        objectWillChange.send()
        do {
            let response = try await childProfileClient.update(
                nickname: trimmed,
                avatarEmoji: credentials.avatarEmoji,
                deviceToken: credentials.deviceToken
            )
            var updatedCredentials = credentials
            updatedCredentials.nickname = response.nickname
            updatedCredentials.avatarEmoji = response.avatarEmoji
            cloudCredentialsStore.save(updatedCredentials)
            route = .home
        } catch {
            bindingMessage = "已保存孩子名字，云端稍后重试"
        }
    }

    func bind(pairingInput: String) async {
        let trimmed = pairingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            bindingMessage = "请输入短码或二维码链接"
            return
        }
        do {
            let response = try await bindingClient.redeem(pairingInput: trimmed, deviceId: deviceIdProvider.deviceId())
            cloudCredentialsStore.save(response, apiBaseURL: developerMenuViewModel.effectiveBaseURL)
            bindingMessage = "绑定成功：\(response.nickname)"
        } catch {
            bindingMessage = "短码无效，请重新输入"
        }
    }

    func bind(shortCode: String) async {
        await bind(pairingInput: shortCode)
    }

    func finishBinding() {
        bindingMessage = ""
        route = .config
    }

    func unbind(pin: String) {
        Task { await confirmUnbind(pin: pin) }
    }

    func confirmUnbind(pin: String) async {
        guard pin == configStore.config.parentPin else {
            bindingMessage = "PIN 不正确"
            return
        }
        if let credentials = cloudCredentialsStore.credentials {
            do {
                try await unbindClient.unbind(deviceToken: credentials.deviceToken)
            } catch {
                bindingMessage = "解绑失败，请稍后再试"
                return
            }
        }
        cloudCredentialsStore.clear()
        globalPackCache = nil
        familyPackCache = nil
        try? packLayerStore.clear()
        packLibrary = PackLibrary()
        packManagerMessage = ""
        bindingMessage = ""
        route = .config
    }

    func syncWordStatsExplicitly() async {
        await syncWordStatsIfPossible(showStatus: true)
    }

    func syncWordStatsIfPossible(showStatus: Bool) async {
        guard let credentials = cloudCredentialsStore.credentials else {
            if showStatus {
                packManagerMessage = "请先绑定家长账号"
                showToast("请先绑定家长账号")
            }
            return
        }
        let payload = WordStatsSyncPayload.from(
            recorder: learningRecorder,
            syncedThroughMs: wordStatsSyncStateStore.syncedThroughMs
        )
        guard !payload.items.isEmpty || wordStatsSyncStateStore.needsRetry else {
            if showStatus {
                packManagerMessage = "暂无学习数据需要同步"
                showToast("暂无学习数据需要同步")
            }
            return
        }
        do {
            let response = try await wordStatsSyncClient.sync(payload: payload, deviceToken: credentials.deviceToken)
            wordStatsSyncStateStore.markSuccess(serverNowMs: response.serverNowMs)
            if showStatus {
                packManagerMessage = "学习数据已同步"
                showToast("学习记录已同步")
            }
        } catch {
            wordStatsSyncStateStore.markFailure()
            if showStatus {
                packManagerMessage = "学习数据同步失败"
                showToast("学习记录同步失败")
            }
        }
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
        } else if arguments.contains("-UITestRouteRedemptionHistory") {
            route = .redemptionHistory
        } else if arguments.contains("-UITestRouteTodayPlan") {
            route = .todayPlan
        } else if arguments.contains("-UITestRouteLearningReport") {
            openLearningReport()
        } else if arguments.contains("-UITestRouteScanBinding") {
            route = .scanBinding
        } else if arguments.contains("-UITestRouteBoundDeviceInfo") {
            route = .boundDeviceInfo
        } else if arguments.contains("-UITestRouteChildProfile") {
            route = .childProfile
        } else if arguments.contains("-UITestRouteDevMenu"), DeveloperToolsPolicy.isDeveloperToolsVisible() {
            route = .devMenu
        } else if arguments.contains("-UITestRouteBypassSecret"), DeveloperToolsPolicy.isDeveloperToolsVisible() {
            route = .bypassSecret
        }
    }

    private func loadCachedPackLayers() {
        globalPackCache = try? packLayerStore.load(layer: .global)
        familyPackCache = try? packLayerStore.load(layer: .family)
        rebuildPackLibraryFromCaches()
    }

    private func rebuildPackLibraryFromCaches() {
        packLibrary = PackLibrary(
            builtin: Pack.builtin,
            global: globalPackCache?.packs ?? [],
            family: familyPackCache?.packs ?? []
        )
    }

    private func clearLocalBindingForEnvironmentSwitch() {
        cloudCredentialsStore.clear()
        globalPackCache = nil
        familyPackCache = nil
        try? packLayerStore.clear()
        rebuildPackLibraryFromCaches()
        packManagerMessage = ""
        bindingMessage = "请重新绑定家长账号"
    }

    private func bindingNeedsRebindAfterEnvironmentActivation(_ credentials: CloudCredentials?) -> Bool {
        guard let credentials else { return false }
        guard let apiBaseURL = credentials.apiBaseURL else { return true }
        return normalizedBaseURL(apiBaseURL) != normalizedBaseURL(developerMenuViewModel.effectiveBaseURL)
    }

    private func normalizedBaseURL(_ url: URL) -> String {
        normalizedBaseURL(url.absoluteString)
    }

    private func normalizedBaseURL(_ url: String) -> String {
        var value = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private func applyLaunchSeeds() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-UITestClearBinding") {
            cloudCredentialsStore.clear()
        }
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
}
