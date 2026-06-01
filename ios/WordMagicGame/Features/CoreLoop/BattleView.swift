import SwiftUI

enum BattleBossIntroLayoutSpec {
    static let positionXRatio: CGFloat = 0.65
    static let positionYRatio: CGFloat = 0.20
}

struct LetterTemplateSlot: Equatable {
    var glyph: String
    var originalIndex: Int
    var isMissing: Bool
    var isPending: Bool
}

struct LetterTemplateMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat
    var gap: CGFloat
    var filledFontSize: CGFloat
    var placeholderFontSize: CGFloat
}

enum LetterTemplateLayout {
    static func slots(from template: String, missingIndex: Int, pendingIndex: Int = -1) -> [LetterTemplateSlot] {
        let chars = Array(template)
        var output: [LetterTemplateSlot] = []
        var index = 0

        while index < chars.count {
            let char = chars[index]
            if char != " " {
                output.append(LetterTemplateSlot(
                    glyph: String(char),
                    originalIndex: index,
                    isMissing: index == missingIndex,
                    isPending: index == pendingIndex
                ))
                index += 1
                continue
            }

            var run = 0
            while index + run < chars.count, chars[index + run] == " " {
                run += 1
            }
            output.append(LetterTemplateSlot(
                glyph: " ",
                originalIndex: index,
                isMissing: index == missingIndex,
                isPending: index == pendingIndex
            ))
            index += run
        }

        return output
    }

    static func metrics(forGlyphCount count: Int) -> LetterTemplateMetrics {
        if count <= 6 {
            return LetterTemplateMetrics(width: 16, height: 44, gap: 3, filledFontSize: 30, placeholderFontSize: 26)
        } else if count <= 9 {
            return LetterTemplateMetrics(width: 16, height: 40, gap: 2, filledFontSize: 25, placeholderFontSize: 22)
        } else if count <= 12 {
            return LetterTemplateMetrics(width: 16, height: 36, gap: 2, filledFontSize: 22, placeholderFontSize: 20)
        } else {
            return LetterTemplateMetrics(width: 16, height: 32, gap: 2, filledFontSize: 19, placeholderFontSize: 17)
        }
    }
}

struct BattleView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var engine: BattleEngine
    @State private var feedbackQuestion: Question?
    @State private var feedbackOptions: [String] = []
    @State private var selectedOption: String?
    @State private var optionFeedback: OptionFeedback = .idle
    @State private var feedbackText = "Choose the right spell"
    @State private var feedbackColor = Color.secondary
    @State private var activeProjectile: BattleProjectile?
    @State private var critOverlay = CritOverlayState()
    @State private var playerPose: FighterPose = .idle
    @State private var playerScale = 1.0
    @State private var playerOffsetX = 0.0
    @State private var playerRotation = 0.0
    @State private var playerGlowOpacity = 0.0
    @State private var playerHurtOpacity = 0.0
    @State private var monsterScale = 1.0
    @State private var monsterOffsetX = 0.0
    @State private var monsterHurtOpacity = 0.0
    @State private var feedbackSerial = 0
    @State private var pendingBattleEnd = false
    @State private var spellSlots: [String] = []
    @State private var spellConsumedIndices: Set<Int> = []
    @State private var spellShakingPoolIndex: Int?
    @State private var playerFloaters: [FloaterPending] = []
    @State private var monsterFloaters: [FloaterPending] = []
    @State private var nextFloaterKey = 0
    @State private var bossIntro: BossIntroOverlayState?
    @State private var shownBossIntroCatalogIndices: Set<Int> = []
    @State private var lastBossIntroMonsterIndex = 0

    private let maxFloatersPerSide = 4
    private let floaterStackOffset: CGFloat = 6
    private let battleImpactDelayNs: UInt64 = 340_000_000
    private let battleHorizontalPadding: CGFloat = 6
    private let battleColumnSpacing: CGFloat = 18
    private let battleFighterCardWidth: CGFloat = 168

    private var state: BattleState {
        engine.state
    }

    private var displayedQuestion: Question? {
        feedbackQuestion ?? state.currentQuestion
    }

    private var displayedOptions: [String] {
        if feedbackQuestion != nil {
            return feedbackOptions
        }
        guard let question = state.currentQuestion else { return [] }
        return options(for: question)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 10) {
                    topStatus

                    HStack(spacing: battleColumnSpacing) {
                        fighterCard(
                            imageName: playerImageName,
                            title: "Magician",
                            subtitle: "Player",
                            hp: state.playerHp,
                            maxHp: state.playerMaxHp,
                            tint: AppTheme.paleBlue,
                            scale: playerScale,
                            offsetX: playerOffsetX,
                            rotation: playerRotation,
                            glowOpacity: playerGlowOpacity,
                            hurtOpacity: playerHurtOpacity,
                            floaters: playerFloaters,
                            floaterSide: .player,
                            levelBadge: nil
                        )
                        .accessibilityIdentifier("PlayerArea")

                        questionPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)

                        fighterCard(
                            imageName: currentMonsterArt.imageName,
                            title: currentMonsterArt.name,
                            subtitle: "Monster \(state.monsterIndex) / \(state.monstersTotal)",
                            hp: state.monsterHp,
                            maxHp: state.monsterMaxHp,
                            tint: AppTheme.palePink,
                            scale: monsterScale,
                            offsetX: monsterOffsetX,
                            rotation: 0,
                            glowOpacity: 0,
                            hurtOpacity: monsterHurtOpacity,
                            floaters: monsterFloaters,
                            floaterSide: .monster,
                            levelBadge: currentMonsterLevel.battleLabel
                        )
                        .accessibilityIdentifier("MonsterArea")
                        .overlay(alignment: .topTrailing) {
                            if state.currentMonsterBonus {
                                Text("Bonus")
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(AppTheme.gold, in: Capsule())
                                    .accessibilityIdentifier("MonsterBonusStar_\(state.monsterIndex)")
                            }
                        }
                    }
                    .frame(height: max(170, proxy.size.height - 132))

                    answerRow
                }
                .padding(.horizontal, battleHorizontalPadding)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .frame(width: proxy.size.width, height: proxy.size.height)

                MagicProjectileOverlay(projectile: activeProjectile)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                CritSpectacleOverlay(state: critOverlay)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                bossIntroBubble(proxy: proxy)
                Text(currentMonsterLevel.battleLabel)
                    .font(.caption2)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .position(x: proxy.size.width - 8, y: 8)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityIdentifier("BattleMonsterLevelLabel")
                    .accessibilityLabel(currentMonsterLevel.battleLabel)
            }
        }
        .background(AppTheme.page)
        .onAppear {
            resetSpellProgress(for: state.currentQuestion)
            presentBossIntroIfNeeded()
            coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)
        }
        .onChange(of: state.currentQuestion?.wordId) { _, _ in
            let question = state.currentQuestion
            resetSpellProgress(for: question)
        }
        .onChange(of: state.monsterIndex) { _, _ in
            presentBossIntroIfNeeded()
        }
        .onChange(of: state.currentMonsterCatalogIndex) { _, _ in
            presentBossIntroIfNeeded()
        }
        .onDisappear {
            coordinator.disposeBattlePronunciation()
        }
        .task {
            await runCountdown()
        }
        .task(id: feedbackSerial) {
            await clearFeedbackAfterDelay()
        }
    }

    private var topStatus: some View {
        HStack {
            Text("Combo: \(state.comboCount)")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("BattleComboLabel")
            Spacer()
            Text("Battle")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("BattleTitle")
            Spacer()
            Text("Countdown \(formatTime(state.remainingSeconds))")
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("BattleTimerLabel")
            Button("Escape") {
                coordinator.escapeBattle()
            }
            .buttonStyle(.bordered)
            .disabled(feedbackQuestion != nil)
            .accessibilityIdentifier("BattleEscapeButton")
        }
    }

    private var questionPanel: some View {
        VStack(spacing: 10) {
            Text("Question")
                .font(.title2.weight(.medium))
                .foregroundStyle(Color(red: 0.23, green: 0.45, blue: 0.61))
            questionContent
            Button {
                coordinator.speakCurrentBattleAnswer()
            } label: {
                Text("🔊")
                    .font(.system(size: 28))
                    .frame(width: 58, height: 58)
                    .background(AppTheme.paleBlue, in: Circle())
            }
            .accessibilityLabel("Pronounce")
            .accessibilityIdentifier("BattleSpeakerButton")
            Text(feedbackText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(feedbackColor)
                .accessibilityIdentifier("BattleFeedback")
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var questionContent: some View {
        if let question = displayedQuestion {
            switch question.kind {
            case .choice:
                Text(question.promptZh)
                    .font(.system(size: 42, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.navy)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("BattlePrompt")
            case .fillLetter:
                spellingTemplate(
                    prompt: question.promptZh,
                    template: question.letterTemplate,
                    missingIndex: question.missingIndex,
                    pendingIndex: -1
                )
            case .fillLetterMedium:
                spellingTemplate(
                    prompt: question.promptZh,
                    template: question.letterTemplateBase,
                    missingIndex: letterMissingIndex(for: question),
                    pendingIndex: letterPendingIndex(for: question)
                )
            case .spell:
                VStack(spacing: 8) {
                    Text(question.promptZh)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                        .accessibilityIdentifier("BattlePrompt")
                    HStack(spacing: 7) {
                        ForEach(Array(currentSpellSlots(for: question).enumerated()), id: \.offset) { index, letter in
                            Text(letter.isEmpty ? "_" : letter)
                                .font(.system(size: 25, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppTheme.navy)
                                .frame(width: 30, height: 38)
                                .background(letter.isEmpty ? Color.white.opacity(0.7) : AppTheme.gold.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityIdentifier("BattleSpellSlot_\(index)")
                        }
                    }
                    .accessibilityIdentifier("BattleSpellSlots")
                }
            case .sentenceCloze:
                VStack(spacing: 8) {
                    Text(question.sentenceTemplate)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.navy)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("BattleSentenceClozePrompt")
                    Text(question.sentenceZh)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.38, green: 0.43, blue: 0.50))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("BattleSentenceClozeZh")
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Text("")
                .accessibilityIdentifier("BattlePrompt")
        }
    }

    private func spellingTemplate(prompt: String, template: String, missingIndex: Int, pendingIndex: Int) -> some View {
        VStack(spacing: 8) {
            Text(prompt)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("BattlePrompt")
            letterTemplateRow(template: template, missingIndex: missingIndex, pendingIndex: pendingIndex)
        }
    }

    private func letterTemplateRow(template: String, missingIndex: Int, pendingIndex: Int) -> some View {
        let slots = LetterTemplateLayout.slots(from: template, missingIndex: missingIndex, pendingIndex: pendingIndex)
        let metrics = LetterTemplateLayout.metrics(forGlyphCount: slots.count)
        return HStack(spacing: metrics.gap) {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                letterTemplateSlot(slot, metrics: metrics)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("BattleLetterTemplate")
    }

    @ViewBuilder
    private func letterTemplateSlot(_ slot: LetterTemplateSlot, metrics: LetterTemplateMetrics) -> some View {
        ZStack {
            if slot.glyph == " " {
                Color.clear
            } else if slot.isMissing {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.99, green: 0.92, blue: 0.92))
                Text("_")
                    .font(.system(size: metrics.placeholderFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.90, green: 0.22, blue: 0.27))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("BattleLetterSlotText_\(slot.originalIndex)")
            } else if slot.isPending {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(red: 0.95, green: 0.95, blue: 0.96))
                Text(slot.glyph == "_" ? "_" : slot.glyph)
                    .font(.system(size: metrics.placeholderFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.64, green: 0.64, blue: 0.64))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("BattleLetterSlotText_\(slot.originalIndex)")
            } else {
                Text(slot.glyph)
                    .font(.system(size: metrics.filledFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.11, green: 0.21, blue: 0.34))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("BattleLetterSlotText_\(slot.originalIndex)")
            }
        }
        .frame(width: metrics.width, height: metrics.height)
    }

    private func letterMissingIndex(for question: Question) -> Int {
        guard question.missingIndices.indices.contains(question.currentStep) else { return -1 }
        return question.missingIndices[question.currentStep]
    }

    private func letterPendingIndex(for question: Question) -> Int {
        let pendingStep = question.currentStep == 0 ? 1 : 0
        guard question.missingIndices.indices.contains(pendingStep) else { return -1 }
        return question.missingIndices[pendingStep]
    }

    private var answerRow: some View {
        HStack(spacing: 18) {
            ForEach(Array(answerButtons.enumerated()), id: \.offset) { index, option in
                Button {
                    handleAnswerButtonTap(option, index: index)
                } label: {
                    Text(option)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(tint(for: option))
                .disabled(isAnswerButtonDisabled(option: option, index: index))
                .accessibilityLabel(accessibilityLabel(for: option, index: index))
                .accessibilityIdentifier(accessibilityIdentifier(for: option, index: index))
            }
        }
        .accessibilityIdentifier(optionsRowIdentifier)
    }

    private var optionsRowIdentifier: String {
        if displayedQuestion?.kind == .sentenceCloze {
            return "BattleOptionsRow_SentenceCloze"
        }
        return "BattleOptionsRow"
    }

    private var answerButtons: [String] {
        guard feedbackQuestion == nil,
              let question = displayedQuestion,
              question.kind == .spell
        else {
            return displayedOptions
        }
        return question.spellPool
    }

    private func accessibilityLabel(for option: String, index: Int) -> String {
        if isExposedCorrectOption(option, index: index) {
            return "BattleCorrectOption"
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestExposeCorrectAnswer") {
            return "BattleIncorrectOption"
        }
        return option
    }

    private func accessibilityIdentifier(for option: String, index: Int) -> String {
        if isExposedCorrectOption(option, index: index) {
            return "BattleCorrectOption"
        }
        if ProcessInfo.processInfo.arguments.contains("-UITestExposeCorrectAnswer") {
            return "BattleIncorrectOption"
        }
        if displayedQuestion?.kind == .sentenceCloze {
            return "BattleSentenceClozeOption_\(index)"
        }
        return "BattleOption\(String(UnicodeScalar(65 + index)!))"
    }

    private func isExposedCorrectOption(_ option: String, index: Int?) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("-UITestExposeCorrectAnswer"),
              let question = displayedQuestion
        else { return false }

        switch question.kind {
        case .choice:
            return option == question.answer
        case .sentenceCloze:
            return option == question.answer
        case .fillLetter:
            return option == question.letterAnswer
        case .fillLetterMedium:
            return question.letterAnswers.indices.contains(question.currentStep)
                && option == question.letterAnswers[question.currentStep]
        case .spell:
            let slots = currentSpellSlots(for: question)
            guard let index,
                  !spellConsumedIndices.contains(index),
                  let nextIndex = slots.firstIndex(where: \.isEmpty),
                  question.spellLetters.indices.contains(nextIndex),
                  option == question.spellLetters[nextIndex]
            else { return false }
            return question.spellPool.indices.first {
                !spellConsumedIndices.contains($0) && question.spellPool[$0] == option
            } == index
        }
    }

    private func options(for question: Question) -> [String] {
        switch question.kind {
        case .choice:
            return question.options
        case .sentenceCloze:
            return question.options
        case .fillLetter:
            return question.letterOptions
        case .fillLetterMedium:
            guard question.letterOptionsSteps.indices.contains(question.currentStep) else { return [] }
            return question.letterOptionsSteps[question.currentStep]
        case .spell:
            return [question.answer]
        }
    }

    private func isAnswerButtonDisabled(option _: String, index: Int) -> Bool {
        if feedbackQuestion != nil {
            return true
        }
        guard displayedQuestion?.kind == .spell else {
            return false
        }
        if spellShakingPoolIndex != nil {
            return true
        }
        return spellConsumedIndices.contains(index)
    }

    private func handleAnswerButtonTap(_ option: String, index: Int) {
        guard let question = displayedQuestion else { return }
        if question.kind == .spell {
            handleSpellLetterTap(option, poolIndex: index, question: question)
        } else {
            handleOptionTap(option)
        }
    }

    private func handleSpellLetterTap(_ letter: String, poolIndex: Int, question: Question) {
        guard feedbackQuestion == nil,
              spellShakingPoolIndex == nil,
              !spellConsumedIndices.contains(poolIndex),
              poolIndex >= 0,
              poolIndex < question.spellPool.count,
              let nextIndex = spellSlots.firstIndex(where: \.isEmpty),
              question.spellLetters.indices.contains(nextIndex)
        else { return }

        let tapped = question.spellPool[poolIndex]
        let expected = question.spellLetters[nextIndex]

        if tapped == expected {
            spellSlots[nextIndex] = tapped
            spellConsumedIndices.insert(poolIndex)
            if !spellSlots.contains("") {
                handleOptionTap(question.answer)
            }
        } else {
            let damage = engine.applySpellLetterPenalty()
            guard damage > 0 else { return }

            spellShakingPoolIndex = poolIndex
            feedbackQuestion = question
            feedbackOptions = question.spellPool
            selectedOption = letter
            optionFeedback = .wrong

            let event = BattleAnimationEvent.spellWrongTapPenalty(damage: damage)
            feedbackText = event.feedbackText
            feedbackColor = AppTheme.red
            pendingBattleEnd = engine.state.status == .lost
            feedbackSerial += 1
            triggerAnimation(event)

            Task {
                try? await Task.sleep(nanoseconds: 220_000_000)
                await MainActor.run {
                    spellShakingPoolIndex = nil
                }
            }
        }
    }

    private func resetSpellProgress(for question: Question?) {
        guard let question, question.kind == .spell else {
            spellSlots = []
            spellConsumedIndices = []
            return
        }
        spellSlots = question.spellLetters.enumerated().map { index, letter in
            question.spellRevealedMask.indices.contains(index) && question.spellRevealedMask[index] ? letter : ""
        }
        spellConsumedIndices = []
    }

    private func currentSpellSlots(for question: Question) -> [String] {
        if spellSlots.count == question.spellLetters.count {
            return spellSlots
        }
        return question.spellLetters.enumerated().map { index, letter in
            question.spellRevealedMask.indices.contains(index) && question.spellRevealedMask[index] ? letter : ""
        }
    }

    private func fighterCard(
        imageName: String,
        title: String,
        subtitle: String,
        hp: Int,
        maxHp: Int,
        tint: Color,
        scale: Double,
        offsetX: Double,
        rotation: Double,
        glowOpacity: Double,
        hurtOpacity: Double,
        floaters: [FloaterPending],
        floaterSide: BattleFloaterSide,
        levelBadge: String?
    ) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(AppTheme.gold.opacity(glowOpacity))
                        .frame(width: 112, height: 112)
                        .blur(radius: 1)
                        .accessibilityIdentifier("CritCastGlow")
                    Image(imageName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 88)
                    Circle()
                        .fill(Color(red: 0.90, green: 0.22, blue: 0.28).opacity(hurtOpacity))
                        .frame(width: 112, height: 92)
                        .accessibilityIdentifier(title == "Magician" ? "PlayerHurtOverlay" : "MonsterHurtOverlay")
                }
                .scaleEffect(scale)
                .offset(x: offsetX)
                .rotationEffect(.degrees(rotation))

                damageFloaterStack(floaters: floaters, side: floaterSide)
                    .offset(y: floaterSide == .player ? -10 : -12)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 7) {
                Text(title)
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(AppTheme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                if let levelBadge {
                    Text(levelBadge)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppTheme.navy, in: Capsule())
                }
            }
            Text(subtitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("HP \(hp) / \(maxHp)")
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(title == "Magician" ? "PlayerHpLabel" : "MonsterHpLabel")
            ProgressView(value: Double(hp), total: Double(max(maxHp, 1)))
                .tint(Color(red: 0.15, green: 0.80, blue: 0.42))
                .scaleEffect(x: 1, y: 1.8, anchor: .center)
        }
        .frame(width: battleFighterCardWidth)
        .padding(14)
        .background(tint, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(tint.opacity(0.7), lineWidth: 1.5)
        }
    }

    private var playerImageName: String {
        switch playerPose {
        case .idle:
            "CharacterMagician"
        case .fight:
            "CharacterMagicianFight"
        case .hurt:
            "CharacterMagicianBeaten"
        }
    }

    private func handleOptionTap(_ option: String) {
        guard feedbackQuestion == nil, let question = displayedQuestion else { return }
        let snapshotOptions = displayedOptions
        let word = question.answer
        let outcome = coordinator.submitBattleOptionForAnimation(option)
        guard let outcome else { return }
        let event = BattleAnimationEvent(outcome: outcome, word: word)

        feedbackQuestion = question
        feedbackOptions = snapshotOptions
        selectedOption = option
        optionFeedback = outcome.correct ? .correct : .wrong
        feedbackText = event.feedbackText
        feedbackColor = outcome.comboTriggered ? AppTheme.gold : (outcome.correct ? Color(red: 0.18, green: 0.65, blue: 0.35) : AppTheme.red)
        pendingBattleEnd = outcome.battleEnded
        feedbackSerial += 1
        triggerAnimation(event)
    }

    private func clearFeedback() {
        feedbackQuestion = nil
        feedbackOptions = []
        selectedOption = nil
        optionFeedback = .idle
        feedbackText = "Choose the right spell"
        feedbackColor = .secondary
    }

    private func clearFeedbackAfterDelay() async {
        guard feedbackSerial > 0 else { return }
        try? await Task.sleep(nanoseconds: 650_000_000)
        if Task.isCancelled { return }
        await MainActor.run {
            let shouldFinishBattle = pendingBattleEnd
            clearFeedback()
            pendingBattleEnd = false
            if shouldFinishBattle {
                coordinator.finishBattle()
            } else {
                coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)
            }
        }
    }

    private func tint(for option: String) -> Color {
        guard selectedOption == option else {
            return feedbackQuestion == nil ? AppTheme.purple : Color.gray
        }
        switch optionFeedback {
        case .idle:
            return AppTheme.purple
        case .correct:
            return Color(red: 0.18, green: 0.75, blue: 0.38)
        case .wrong:
            return AppTheme.red
        }
    }

    private func triggerAnimation(_ event: BattleAnimationEvent) {
        let damage = max(event.projectileIntensity, 1)
        coordinator.playBattleSfx(sfxCue(for: event))
        if event.playsMonsterDefeatCue {
            coordinator.playBattleSfx(.monsterDefeat)
        }
        triggerProjectile(event)
        switch event.playerMotion {
        case .nudge:
            triggerPlayerNudge()
        case .hurt:
            scheduleBattleImpact {
                triggerPlayerHurt()
                pushFloater(side: .player, amount: damage)
            }
        case .cast:
            triggerPlayerCast()
        case .idle, .zoom:
            break
        }

        Task {
            try? await Task.sleep(nanoseconds: battleImpactDelayNs)
            if Task.isCancelled { return }
            await MainActor.run {
                switch event.monsterMotion {
                case .hurt:
                    triggerMonsterHurt()
                    pushFloater(side: .monster, amount: damage)
                case .zoom:
                    triggerMonsterZoom()
                    triggerCritOverlay(damageLabel: event.damageLabel)
                    pushFloater(side: .monster, amount: damage)
                case .idle, .nudge, .cast:
                    break
                }
            }
        }
    }

    private func sfxCue(for event: BattleAnimationEvent) -> BattleSfxCue {
        if event.showsCritOverlay {
            return .comboHit
        }
        switch event.projectileDirection {
        case .forward:
            return .normalHit
        case .backward:
            return event.playerMotion == .hurt ? .hurt : .wrong
        }
    }

    @ViewBuilder
    private func damageFloaterStack(floaters: [FloaterPending], side: BattleFloaterSide) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(floaters.enumerated()), id: \.element.id) { index, item in
                DamageFloaterLabel(
                    amount: item.amount,
                    stackOffset: item.stackOffset,
                    accessibilityId: floaterAccessibilityId(side: side, index: index, count: floaters.count, key: item.id),
                    onDispose: { removeFloater(side: side, key: item.id) },
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func floaterAccessibilityId(side: BattleFloaterSide, index: Int, count: Int, key: Int) -> String {
        let base = side == .player ? "BattleDamageFloaterLabel_player" : "BattleDamageFloaterLabel_monster"
        if index == count - 1 {
            return base
        }
        return "\(base)_\(key)"
    }

    private func pushFloater(side: BattleFloaterSide, amount: Int) {
        let dmg = amount >= 2 ? 2 : 1
        switch side {
        case .player:
            var next = playerFloaters
            if next.count >= maxFloatersPerSide {
                next.removeFirst()
            }
            let pending = FloaterPending(
                id: nextFloaterKey,
                amount: dmg,
                stackOffset: CGFloat(next.count) * floaterStackOffset,
            )
            nextFloaterKey += 1
            next.append(pending)
            playerFloaters = next
        case .monster:
            var next = monsterFloaters
            if next.count >= maxFloatersPerSide {
                next.removeFirst()
            }
            let pending = FloaterPending(
                id: nextFloaterKey,
                amount: dmg,
                stackOffset: CGFloat(next.count) * floaterStackOffset,
            )
            nextFloaterKey += 1
            next.append(pending)
            monsterFloaters = next
        }
    }

    private func removeFloater(side: BattleFloaterSide, key: Int) {
        switch side {
        case .player:
            playerFloaters.removeAll { $0.id == key }
        case .monster:
            monsterFloaters.removeAll { $0.id == key }
        }
    }

    private func scheduleBattleImpact(_ action: @escaping () -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: battleImpactDelayNs)
            if Task.isCancelled { return }
            await MainActor.run {
                action()
            }
        }
    }

    private func triggerProjectile(_ event: BattleAnimationEvent) {
        activeProjectile = BattleProjectile(
            direction: event.projectileDirection,
            intensity: Double(event.projectileIntensity),
            label: event.projectileLabel
        )
        withAnimation(.easeOut(duration: 0.08)) {
            activeProjectile?.opacity = 1
            activeProjectile?.scale = 1
        }
        Task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.26)) {
                    activeProjectile?.progress = 1
                }
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.16)) {
                    activeProjectile?.opacity = 0
                    activeProjectile?.scale = 2.2
                }
            }
            try? await Task.sleep(nanoseconds: 190_000_000)
            await MainActor.run {
                activeProjectile = nil
            }
        }
    }

    private func triggerPlayerNudge() {
        playerPose = .fight
        withAnimation(.easeOut(duration: 0.06)) {
            playerOffsetX = 8
        }
        Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.08)) {
                    playerOffsetX = 0
                }
            }
            try? await Task.sleep(nanoseconds: 360_000_000)
            await MainActor.run {
                playerPose = .idle
            }
        }
    }

    private func triggerPlayerCast() {
        playerPose = .fight
        withAnimation(.easeOut(duration: 0.18)) {
            playerScale = 1.15
            playerRotation = -10
            playerGlowOpacity = 0.9
        }
        Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    playerRotation = 10
                }
            }
            try? await Task.sleep(nanoseconds: 180_000_000)
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.14)) {
                    playerScale = 1
                    playerRotation = 0
                    playerGlowOpacity = 0
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run {
                playerPose = .idle
            }
        }
    }

    private func triggerPlayerHurt() {
        playerPose = .hurt
        runHurtAnimation(
            recoil: -12,
            setScale: { playerScale = $0 },
            setOffset: { playerOffsetX = $0 },
            setOpacity: { playerHurtOpacity = $0 },
            completion: { playerPose = .idle }
        )
    }

    private func triggerMonsterHurt() {
        runHurtAnimation(
            recoil: 12,
            setScale: { monsterScale = $0 },
            setOffset: { monsterOffsetX = $0 },
            setOpacity: { monsterHurtOpacity = $0 },
            completion: {}
        )
    }

    private func triggerMonsterZoom() {
        withAnimation(.easeOut(duration: 0.22)) {
            monsterScale = 1.12
        }
        Task {
            try? await Task.sleep(nanoseconds: 340_000_000)
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.16)) {
                    monsterScale = 1
                }
            }
        }
    }

    private func runHurtAnimation(
        recoil: Double,
        setScale: @escaping (Double) -> Void,
        setOffset: @escaping (Double) -> Void,
        setOpacity: @escaping (Double) -> Void,
        completion: @escaping () -> Void
    ) {
        withAnimation(.easeOut(duration: 0.06)) {
            setScale(0.92)
            setOpacity(0.55)
            setOffset(recoil)
        }
        Task {
            let steps: [(UInt64, Double)] = [
                (60_000_000, -recoil * 0.7),
                (70_000_000, recoil * 0.4),
                (70_000_000, -recoil * 0.2)
            ]
            for step in steps {
                try? await Task.sleep(nanoseconds: step.0)
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.07)) {
                        setOffset(step.1)
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 70_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.13)) {
                    setScale(1)
                    setOpacity(0)
                    setOffset(0)
                }
            }
            try? await Task.sleep(nanoseconds: 130_000_000)
            await MainActor.run {
                completion()
            }
        }
    }

    private func triggerCritOverlay(damageLabel: String) {
        critOverlay.damageLabel = damageLabel
        withAnimation(.easeOut(duration: 0.12)) {
            critOverlay.flashOpacity = 0.58
            critOverlay.numberOpacity = 1
            critOverlay.numberScale = 1.35
            critOverlay.numberOffsetY = -20
            critOverlay.shockwaveOpacity = 0.95
            critOverlay.shockwaveScale = 0.4
            critOverlay.innerShockwaveOpacity = 0.85
            critOverlay.innerShockwaveScale = 0.5
        }
        withAnimation(.easeOut(duration: 0.52).delay(0.06)) {
            critOverlay.shockwaveOpacity = 0
            critOverlay.shockwaveScale = 7.0
        }
        withAnimation(.easeOut(duration: 0.46).delay(0.14)) {
            critOverlay.innerShockwaveOpacity = 0
            critOverlay.innerShockwaveScale = 5.2
        }
        withAnimation(.easeIn(duration: 0.24).delay(0.26)) {
            critOverlay.flashOpacity = 0
        }
        withAnimation(.easeInOut(duration: 0.22).delay(0.28)) {
            critOverlay.numberScale = 1.15
            critOverlay.numberOffsetY = -50
        }
        withAnimation(.easeIn(duration: 0.28).delay(0.50)) {
            critOverlay.numberOpacity = 0
            critOverlay.numberOffsetY = -90
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func runCountdown() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                coordinator.tickBattleCountdown()
            }
        }
    }

    @ViewBuilder
    private func bossIntroBubble(proxy: GeometryProxy) -> some View {
        if let bossIntro {
            MessageBubble(
                width: 224,
                height: 96,
                radius: 18,
                borderWidth: 1,
                fill: Color(red: 1.0, green: 0.99, blue: 0.96),
                stroke: Color(red: 0.91, green: 0.84, blue: 0.71),
                contentPadding: .bossStyle,
                tail: MessageBubbleTail.preset(.bottomRight, box: .bossStyle),
                bubbleShadow: .bossStyle,
            ) {
                VStack(spacing: 3) {
                    Text(bossIntro.name)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.42, green: 0.29, blue: 0.14))
                        .accessibilityIdentifier("BattleBossIntroName")
                    Text(bossIntro.dialogue.introLine.en)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Color(red: 0.11, green: 0.21, blue: 0.34))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("BattleBossIntroLineEn")
                    Text(bossIntro.dialogue.introLine.zh)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(red: 0.43, green: 0.37, blue: 0.33))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("BattleBossIntroLineZh")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 248, height: 144)
            .position(
                x: proxy.size.width * BattleBossIntroLayoutSpec.positionXRatio,
                y: proxy.size.height * BattleBossIntroLayoutSpec.positionYRatio
            )
            .allowsHitTesting(false)
            .accessibilityIdentifier("BattleBossIntroBubble")
            .accessibilityLabel("\(bossIntro.name) \(bossIntro.dialogue.introLine.en) \(bossIntro.dialogue.introLine.zh)")
        }
    }

    private func presentBossIntroIfNeeded() {
        guard state.status == .playing else { return }
        let catalogIndex = currentMonsterCatalogIndex
        guard state.monsterIndex != lastBossIntroMonsterIndex,
              !shownBossIntroCatalogIndices.contains(catalogIndex)
        else {
            if bossIntro?.monsterIndex != state.monsterIndex {
                bossIntro = nil
            }
            return
        }

        let entry = MonsterCodex.entry(catalogIndex1Based: catalogIndex)
        bossIntro = BossIntroOverlayState(
            monsterIndex: state.monsterIndex,
            catalogIndex: catalogIndex,
            name: entry.nameEn,
            dialogue: MonsterDialogueCatalog.resolve(catalogIndex1Based: catalogIndex, monsterName: entry.nameEn)
        )
        shownBossIntroCatalogIndices.insert(catalogIndex)
        lastBossIntroMonsterIndex = state.monsterIndex

        guard !ProcessInfo.processInfo.arguments.contains("-UITestKeepBossIntroVisible") else { return }
        let monsterIndex = state.monsterIndex
        Task {
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                if bossIntro?.monsterIndex == monsterIndex {
                    bossIntro = nil
                }
            }
        }
    }

    private var currentMonsterArt: MonsterArt {
        let entry = MonsterCodex.entry(catalogIndex1Based: currentMonsterCatalogIndex)
        return MonsterArt(name: entry.nameEn, imageName: entry.assetName)
    }

    private var currentMonsterLevel: MonsterLevel {
        MonsterCodex.entry(catalogIndex1Based: currentMonsterCatalogIndex).level
    }

    private var currentMonsterCatalogIndex: Int {
        state.currentMonsterCatalogIndex
    }
}

private struct MonsterArt {
    let name: String
    let imageName: String
}

private struct BossIntroOverlayState: Equatable {
    var monsterIndex: Int
    var catalogIndex: Int
    var name: String
    var dialogue: MonsterDialogue
}

private enum OptionFeedback {
    case idle
    case correct
    case wrong
}

private enum FighterPose {
    case idle
    case fight
    case hurt
}

private struct BattleProjectile: Identifiable {
    let id = UUID()
    let direction: ProjectileDirection
    let intensity: Double
    let label: String
    var progress = 0.0
    var opacity = 0.0
    var scale = 0.4
}

private struct CritOverlayState {
    var damageLabel = "-2!"
    var flashOpacity = 0.0
    var numberOpacity = 0.0
    var numberOffsetY = 0.0
    var numberScale = 0.6
    var shockwaveOpacity = 0.0
    var shockwaveScale = 0.2
    var innerShockwaveOpacity = 0.0
    var innerShockwaveScale = 0.2
}

private struct MagicProjectileOverlay: View {
    let projectile: BattleProjectile?

    var body: some View {
        GeometryReader { proxy in
            if let projectile {
                let margin = proxy.size.width * 0.34
                let start = projectile.direction == .forward ? -margin : margin
                let end = projectile.direction == .forward ? margin : -margin
                let x = start + (end - start) * projectile.progress
                let core = projectile.intensity > 1 ? AppTheme.gold : (projectile.direction == .forward ? Color(red: 0.48, green: 0.66, blue: 1.0) : AppTheme.red)
                let glow = projectile.intensity > 1 ? Color(red: 1.0, green: 0.90, blue: 0.44) : core.opacity(0.45)

                ZStack {
                    Circle()
                        .fill(glow)
                        .frame(width: 64 * projectile.intensity, height: 64 * projectile.intensity)
                        .scaleEffect(projectile.scale * 1.2)
                    ZStack {
                        Capsule()
                            .fill(core)
                            .overlay {
                                Capsule()
                                    .stroke(projectile.intensity > 1 ? Color.orange : AppTheme.navy.opacity(0.55), lineWidth: 2)
                            }
                        Text(projectile.label)
                            .font(.system(size: projectile.intensity > 1 ? 16 : 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.55), radius: 1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 6)
                    }
                    .frame(width: 60 * projectile.intensity, height: 34 * projectile.intensity)
                    .scaleEffect(projectile.scale)
                }
                .opacity(projectile.opacity)
                .position(x: proxy.size.width / 2 + x, y: proxy.size.height / 2)
                .allowsHitTesting(false)
                .accessibilityIdentifier(projectile.direction == .forward ? "MagicProjectileForward" : "MagicProjectileBackward")
            }
        }
        .allowsHitTesting(false)
    }
}

private struct CritSpectacleOverlay: View {
    let state: CritOverlayState

    var body: some View {
        ZStack {
            Color(red: 1.0, green: 0.71, blue: 0.0)
                .opacity(state.flashOpacity)
                .accessibilityIdentifier("CritGoldFlash")

            Circle()
                .stroke(AppTheme.gold, lineWidth: 10)
                .frame(width: 120, height: 120)
                .scaleEffect(state.shockwaveScale)
                .opacity(state.shockwaveOpacity)
                .accessibilityIdentifier("CritShockwave")

            Circle()
                .stroke(.white, lineWidth: 6)
                .frame(width: 90, height: 90)
                .scaleEffect(state.innerShockwaveScale)
                .opacity(state.innerShockwaveOpacity)
                .accessibilityIdentifier("CritShockwaveInner")

            Text(state.damageLabel)
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.red)
                .scaleEffect(state.numberScale)
                .offset(y: state.numberOffsetY)
                .opacity(state.numberOpacity)
                .accessibilityIdentifier("CritDamageNumber")
        }
        .allowsHitTesting(false)
    }
}
