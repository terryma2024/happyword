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
    case checkInCalendar
    case scanBinding
    case boundDeviceInfo
    case childProfile
    case devMenu
    case bypassSecret
    case messageBubbleLab
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
    @Published var packManagerToastId = ""
    @Published var learningReport: LearningReport?
    @Published var bindingMessage = ""
    /// After first successful cloud bind, steer the parent to PIN setup once (Harmony parity).
    @Published var pendingPostBindPinSetup: Bool = false
    @Published var packLibrary = PackLibrary()
    @Published var toastMessage: String?

    let configStore: GameConfigStore
    let coinAccount = CoinAccount()
    let checkInStore: CheckInStore
    let parentClient: any ParentApiClient
    let parentAdminUsesLocalMock: Bool
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
    let checkInSyncClient: any CheckInSyncClienting
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
    private let reviewWindowSize = 12

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
        checkInStore: CheckInStore = CheckInStore(),
        checkInSyncClient: any CheckInSyncClienting = CloudClientFactory.checkInSyncClient(),
        unbindClient: any DeviceUnbindClienting = CloudClientFactory.unbindClient(),
        childProfileClient: any ChildProfileClienting = CloudClientFactory.childProfileClient(),
        parentClient: (any ParentApiClient)? = nil,
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
        self.checkInStore = checkInStore
        self.checkInSyncClient = checkInSyncClient
        self.unbindClient = unbindClient
        self.childProfileClient = childProfileClient
        self.parentClient = parentClient ?? CloudClientFactory.parentApiClient(cloudCredentialsStore: cloudCredentialsStore)
        parentAdminUsesLocalMock = parentClient == nil && (
            CloudClientFactory.shouldUseLocalMocks(arguments: ProcessInfo.processInfo.arguments)
                || ProcessInfo.processInfo.arguments.contains("-UITestRouteParentAdmin")
                || ProcessInfo.processInfo.arguments.contains("-UITestRouteLessonReview")
        )
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
        let change = packSelectionStore.toggleActive(pack.id)
        switch change.result {
        case .activated, .deactivated:
            packManagerToastId = ""
            if !packSelectionStore.activePackIds.contains(selectedPack.id),
               let first = activePacks.first {
                selectedPack = first
            }
            packManagerMessage = "已激活 \(packSelectionStore.activePackIds.count) / \(PackSelectionStore.maxActivePacks)"
        case .activatedAutoClosed:
            packManagerToastId = "PackManagerAutoRotateToast"
            if !packSelectionStore.activePackIds.contains(selectedPack.id),
               let first = activePacks.first {
                selectedPack = first
            }
            let closedTitle = packLibrary.pack(id: change.autoClosedId)?.title ?? change.autoClosedId
            packManagerMessage = "已关闭 \(closedTitle) 以激活 \(pack.title)"
        case .refusedAllPinned:
            packManagerToastId = "PackManagerCapRefuseToast"
            packManagerMessage = "请先取消固定一个词包"
        }
        objectWillChange.send()
    }

    func togglePackPin(_ pack: Pack) {
        guard packSelectionStore.togglePin(pack.id) else { return }
        packManagerToastId = ""
        packManagerMessage = packSelectionStore.pinnedPackIds.contains(pack.id) ? "已固定 \(pack.title)" : "已取消固定 \(pack.title)"
        objectWillChange.send()
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
                familyId: credentials.familyId,
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
        let battlePlan = BattleQuestionPlan.from(pack: selectedPack, enabledQuestionTypes: enabledTypes)
        let questionSource = PlanQuestionSource(
            plan: battlePlan,
            repository: repository,
            randomSeed: makeBattleRandomSeed(),
            enabledQuestionTypes: enabledTypes,
        )
        let engine = BattleEngine(
            questionSource: questionSource,
            config: configStore.config,
            monsterCatalogIndex: { questionSource.catalogIndexForMonster($0) }
        )
        questionSource.setMonsterIndexProvider { engine.state.monsterIndex }
        engine.start()
        battleEngine = engine
        route = .battle
    }

    func startReviewBattle() {
        let reviewIds = learningRecorder.recentWrongIds(limit: reviewWindowSize)
        guard !reviewIds.isEmpty else {
            showToast("先答错几题再来复习吧")
            return
        }
        let allWords = packLibrary.allPacks().flatMap(\.words)
        let knownIds = Set(allWords.map(\.id))
        let focusedIds = reviewIds.filter { knownIds.contains($0) }
        guard !focusedIds.isEmpty else {
            showToast("先答错几题再来复习吧")
            return
        }
        let enabledTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(configStore.config.enabledQuestionTypes)
        guard BattleQuestionTypePolicy.anyWordSupportsQuestionTypes(
            allWords.filter { focusedIds.contains($0.id) },
            typeIds: enabledTypes
        ) else {
            showToast("当前词包没有支持所选题型的单词")
            return
        }

        pronunciationService.prepare()
        let repository = WordRepository(words: allWords)
        let reviewPlan = BattleQuestionPlan(
            wordIds: focusedIds,
            monsterSlots: BattleQuestionTypePolicy.buildMonsterSlots(enabledTypeIds: enabledTypes)
        )
        let questionSource = PlanQuestionSource(
            plan: reviewPlan,
            repository: repository,
            randomSeed: makeBattleRandomSeed(),
            enabledQuestionTypes: enabledTypes,
        )
        var reviewConfig = configStore.config
        reviewConfig.monstersTotal = 3
        reviewConfig.startingSeconds = 120
        let engine = BattleEngine(
            questionSource: questionSource,
            config: reviewConfig,
            monsterCatalogIndex: { questionSource.catalogIndexForMonster($0) }
        )
        questionSource.setMonsterIndexProvider { engine.state.monsterIndex }
        engine.start()
        battleEngine = engine
        route = .battle
    }

    func autoSpeakCurrentBattleAnswer(isRevealing: Bool) {
        guard shouldAutoSpeak(
            autoSpeakEnabled: configStore.config.autoSpeak,
            ttsAvailable: pronunciationService.isAvailable,
            isRevealing: isRevealing,
            questionKind: battleEngine?.state.currentQuestion?.kind
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

    func escapeBattle() {
        guard let engine = battleEngine else { return }
        engine.escapeBattle()
        finishBattle()
    }

    func finishBattle() {
        guard let engine = battleEngine,
              var result = try? engine.buildSessionResult() else { return }
        result.coinsTotal = coinAccount.earn(result.coinsEarned)
        if result.status == .won {
            let checkIn = checkInStore.recordWin(coins: coinAccount)
            result.checkInRecorded = checkIn.changed
            result.checkInCurrentStreak = checkIn.currentStreak
            result.checkInBonusCoins = checkIn.bonusCoins
            result.checkInBonusDayKey = checkIn.bonusDayKey
            result.coinsTotal = coinAccount.balance
            syncCheckInsBestEffort()
        }
        lastResult = result
        route = .result
        Task { await syncWordStatsIfPossible(showStatus: false) }
    }

    private func makeBattleRandomSeed() -> UInt64 {
        if let battleRandomSeed {
            return battleRandomSeed
        }
        if let seedArgument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-UITestBattleSeed=") }),
           let seed = UInt64(seedArgument.replacingOccurrences(of: "-UITestBattleSeed=", with: "")) {
            return seed
        }
        return UInt64(Date().timeIntervalSince1970 * 1000)
    }

    func saveConfig(_ config: GameConfig) {
        configStore.save(config)
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
        if pendingPostBindPinSetup {
            pendingPostBindPinSetup = false
            route = .boundDeviceInfo
        } else {
            route = .config
        }
    }

    func cancelParentPinSetup() {
        if pendingPostBindPinSetup {
            pendingPostBindPinSetup = false
            route = .boundDeviceInfo
        } else {
            route = .config
        }
    }

    func openParentAdmin() {
        pinMessage = ""
        if GameConfig.isValidPin(configStore.config.parentPin) {
            route = .pinGate
        } else {
            route = .pinSetup
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

    func openCheckInCalendar() {
        route = .checkInCalendar
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

    func openMessageBubbleLab() {
        guard DeveloperToolsPolicy.isDeveloperToolsVisible() else { return }
        route = .messageBubbleLab
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
        cloudCredentialsStore.credentials?.nickname ?? "学习档案"
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

    func parentAccountSettingsURL(for credentials: CloudCredentials) -> URL {
        let baseURL = credentials.apiBaseURL.flatMap(URL.init(string:)) ?? developerMenuViewModel.effectiveBaseURL
        return baseURL
            .appendingPathComponent("family")
            .appendingPathComponent(credentials.familyId)
            .appendingPathComponent("account")
    }

    func updateChildNickname(_ nickname: String) async {
        await updateChildProfile(nickname: nickname, avatarEmoji: cloudCredentialsStore.credentials?.avatarEmoji ?? "🦄")
        if bindingMessage.hasPrefix("已保存") {
            route = .home
        }
    }

    func updateChildProfile(nickname: String, avatarEmoji: String) async {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            bindingMessage = "请输入学习者名字"
            return
        }
        guard var credentials = cloudCredentialsStore.credentials else {
            bindingMessage = "请先绑定家长账号"
            return
        }
        credentials.nickname = trimmed
        let trimmedAvatar = avatarEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        credentials.avatarEmoji = trimmedAvatar.isEmpty ? "🦄" : trimmedAvatar
        cloudCredentialsStore.save(credentials)
        bindingMessage = "已保存学习者名字"
        objectWillChange.send()
        do {
            let response = try await childProfileClient.update(
                nickname: trimmed,
                avatarEmoji: credentials.avatarEmoji,
                familyId: credentials.familyId,
                deviceToken: credentials.deviceToken
            )
            var updatedCredentials = credentials
            updatedCredentials.nickname = response.nickname
            updatedCredentials.avatarEmoji = response.avatarEmoji
            cloudCredentialsStore.save(updatedCredentials)
        } catch {
            bindingMessage = "已保存学习者名字，云端稍后重试"
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
            guard cloudCredentialsStore.save(response, apiBaseURL: developerMenuViewModel.effectiveBaseURL) else {
                bindingMessage = "绑定保存失败，请重试"
                toastMessage = nil
                route = .scanBinding
                return
            }
            showToast("绑定成功：\(response.nickname)")
            bindingMessage = ""
            if GameConfig.isValidPin(configStore.config.parentPin) {
                route = .boundDeviceInfo
            } else {
                pendingPostBindPinSetup = true
                pinMessage = ""
                route = .pinSetup
            }
        } catch {
            bindingMessage = "短码无效，请重新输入"
        }
    }

    func bind(shortCode: String) async {
        await bind(pairingInput: shortCode)
    }

    func finishBinding() {
        bindingMessage = ""
        if GameConfig.isValidPin(configStore.config.parentPin) {
            route = .boundDeviceInfo
        } else {
            pendingPostBindPinSetup = true
            pinMessage = ""
            route = .pinSetup
        }
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
                try await unbindClient.unbind(familyId: credentials.familyId, deviceToken: credentials.deviceToken)
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
        packManagerToastId = ""
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
            let response = try await wordStatsSyncClient.sync(
                payload: payload,
                familyId: credentials.familyId,
                deviceToken: credentials.deviceToken
            )
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

    func syncCheckInsBestEffort() {
        Task { await syncCheckInsIfPossible() }
    }

    func syncCheckInsIfPossible() async {
        guard let credentials = cloudCredentialsStore.credentials else { return }
        do {
            let response = try await checkInSyncClient.sync(
                payload: CheckInSyncPayload.from(snapshot: checkInStore.snapshot),
                familyId: credentials.familyId,
                deviceToken: credentials.deviceToken
            )
            checkInStore.applyCloudMerge(
                checkedDayKeys: response.checkedDayKeys,
                weeklyBonusDayKeys: response.weeklyBonusDayKeys,
                serverNowMs: response.serverNowMs
            )
        } catch {
            checkInStore.markPendingSync()
        }
    }

    func importLessonImage(_ image: PickedLessonImage) async throws -> LessonDraft {
        try await parentClient.importLessonImage(image)
    }

    func approveLessonReview() async {
        let draftId = reviewStore.draft.id
        let payload = reviewStore.editedExtractedPayload()
        guard !payload.words.isEmpty else {
            parentAdminMessage = "请至少保留一个单词"
            return
        }
        do {
            _ = try await parentClient.patchLessonDraft(id: draftId, payload: payload)
            let summary = try await parentClient.approveLessonDraft(id: draftId)
            parentAdminMessage = "复核完成，已加入词表（\(summary.createdWords.count) 个词）"
            route = .parentAdmin
        } catch {
            parentAdminMessage = "审核失败，请稍后重试"
        }
    }

    func rejectLessonReview() async {
        do {
            try await parentClient.rejectLessonDraft(id: reviewStore.draft.id)
            parentAdminMessage = "已丢弃草稿"
            route = .parentAdmin
        } catch {
            parentAdminMessage = "拒绝失败，请稍后重试"
        }
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
        } else if arguments.contains("-UITestRouteLearningReportEmpty") {
            learningReport = LearningReportBuilder().build(
                library: packLibrary,
                activePackIds: packSelectionStore.activePackIds,
                recorder: learningRecorder
            )
            route = .learningReport
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
        } else if arguments.contains("-UITestRouteMessageBubbleLab"), DeveloperToolsPolicy.isDeveloperToolsVisible() {
            route = .messageBubbleLab
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
        packManagerToastId = ""
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
        if arguments.contains("-UITestQuestionTypesChoiceOnly") {
            saveUITestQuestionTypes([QuestionKind.choice.rawValue])
        } else if arguments.contains("-UITestQuestionTypesFillLetterOnly") {
            saveUITestQuestionTypes([QuestionKind.fillLetter.rawValue])
        } else if arguments.contains("-UITestQuestionTypesSpellOnly") || arguments.contains("-UITestBattleSpellOnly") {
            saveUITestQuestionTypes([QuestionKind.spell.rawValue])
        } else if arguments.contains("-UITestQuestionTypesSentenceClozeOnly") {
            saveUITestQuestionTypes([QuestionKind.sentenceCloze.rawValue])
        }
        if arguments.contains("-UITestQuickBattle") {
            saveUITestQuickBattleConfig()
        }
        if arguments.contains("-UITestSeedBoundDevice") {
            cloudCredentialsStore.save(.demoBinding)
        }
        if arguments.contains("-UITestResetState") {
            packSelectionStore = PackSelectionStore(defaultIds: Pack.builtin.map(\.id))
            selectedPack = Pack.builtin[0]
        }
        if arguments.contains("-UITestBattleBossFirst") {
            selectedPack.scene.monsterPlan = [MonsterPlanSlot(kind: .boss, catalogIndex: 4)]
        }
        if arguments.contains("-UITestRouteTodayPlan") || arguments.contains("-UITestRouteLearningReport") {
            learningRecorder.record(wordId: "fruit-apple", correct: true, at: Date(timeIntervalSinceNow: -86_400 * 3))
            learningRecorder.record(wordId: "home-door", correct: false, at: Date())
        }
    }

    private func saveUITestQuestionTypes(_ types: [String]) {
        var config = configStore.config
        config.enabledQuestionTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(types)
        configStore.save(config)
    }

    private func saveUITestQuickBattleConfig() {
        var config = configStore.config
        config.monsterMaxHp = 1
        config.monstersTotal = 2
        configStore.save(config)
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
    /// Standard horizontal gutter for full-screen flows (pt).
    static let pageHorizontalPadding: CGFloat = 24
    static let portraitPageTopPadding: CGFloat = 4
    static let portraitPageBottomPadding: CGFloat = 16
}
