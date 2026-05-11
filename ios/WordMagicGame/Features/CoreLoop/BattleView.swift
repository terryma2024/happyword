import SwiftUI

struct BattleView: View {
    @ObservedObject var coordinator: AppCoordinator
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

    private var state: BattleState? {
        coordinator.battleEngine?.state
    }

    private var displayedQuestion: Question? {
        feedbackQuestion ?? state?.currentQuestion
    }

    private var displayedOptions: [String] {
        feedbackQuestion == nil ? (state?.currentQuestion?.options ?? []) : feedbackOptions
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 10) {
                    topStatus

                    HStack(spacing: 18) {
                        fighterCard(
                            imageName: playerImageName,
                            title: "Magician",
                            subtitle: "Player",
                            hp: state?.playerHp ?? 0,
                            maxHp: state?.playerMaxHp ?? 1,
                            tint: AppTheme.paleBlue,
                            scale: playerScale,
                            offsetX: playerOffsetX,
                            rotation: playerRotation,
                            glowOpacity: playerGlowOpacity,
                            hurtOpacity: playerHurtOpacity
                        )
                        .accessibilityIdentifier("PlayerArea")

                        questionPanel
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        fighterCard(
                            imageName: currentMonsterArt.imageName,
                            title: currentMonsterArt.name,
                            subtitle: "Monster \(state?.monsterIndex ?? 1) / \(state?.monstersTotal ?? 5)",
                            hp: state?.monsterHp ?? 0,
                            maxHp: state?.monsterMaxHp ?? 1,
                            tint: AppTheme.palePink,
                            scale: monsterScale,
                            offsetX: monsterOffsetX,
                            rotation: 0,
                            glowOpacity: 0,
                            hurtOpacity: monsterHurtOpacity
                        )
                        .accessibilityIdentifier("MonsterArea")
                    }
                    .frame(height: max(170, proxy.size.height - 132))

                    answerRow
                }
                .padding(.horizontal, 26)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .frame(width: proxy.size.width, height: proxy.size.height)

                MagicProjectileOverlay(projectile: activeProjectile)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                CritSpectacleOverlay(state: critOverlay)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(AppTheme.page)
        .onAppear {
            coordinator.autoSpeakCurrentBattleAnswer(isRevealing: false)
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
            Text("Combo: \(state?.comboCount ?? 0)")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("BattleComboLabel")
            Spacer()
            Text("Battle")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("BattleTitle")
            Spacer()
            Text("Countdown \(formatTime(state?.remainingSeconds ?? 0))")
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .accessibilityIdentifier("BattleTimerLabel")
        }
    }

    private var questionPanel: some View {
        VStack(spacing: 10) {
            Text("Question")
                .font(.title2.weight(.medium))
                .foregroundStyle(Color(red: 0.23, green: 0.45, blue: 0.61))
            Text(displayedQuestion?.promptZh ?? "")
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(AppTheme.navy)
                .minimumScaleFactor(0.5)
                .accessibilityIdentifier("BattlePrompt")
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
    }

    private var answerRow: some View {
        HStack(spacing: 18) {
            ForEach(Array(displayedOptions.enumerated()), id: \.offset) { index, option in
                Button {
                    handleOptionTap(option)
                } label: {
                    Text(option)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(tint(for: option))
                .disabled(feedbackQuestion != nil)
                .accessibilityIdentifier("BattleOption\(String(UnicodeScalar(65 + index)!))")
            }
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
        hurtOpacity: Double
    ) -> some View {
        VStack(spacing: 8) {
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
            Text(title)
                .font(.title2.weight(.heavy))
                .foregroundStyle(AppTheme.navy)
            Text(subtitle)
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("HP \(hp) / \(maxHp)")
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(AppTheme.navy)
                .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView(value: Double(hp), total: Double(max(maxHp, 1)))
                .tint(Color(red: 0.15, green: 0.80, blue: 0.42))
                .scaleEffect(x: 1, y: 1.8, anchor: .center)
        }
        .frame(width: 190)
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
            "HarmonyCharacterMagician"
        case .fight:
            "HarmonyCharacterMagicianFight"
        case .hurt:
            "HarmonyCharacterMagicianBeaten"
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
        triggerProjectile(event)
        switch event.playerMotion {
        case .nudge:
            triggerPlayerNudge()
        case .hurt:
            triggerPlayerHurt()
        case .cast:
            triggerPlayerCast()
        case .idle, .zoom:
            break
        }

        Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                switch event.monsterMotion {
                case .hurt:
                    triggerMonsterHurt()
                case .zoom:
                    triggerMonsterZoom()
                    triggerCritOverlay(damageLabel: event.damageLabel)
                case .idle, .nudge, .cast:
                    break
                }
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

    private var currentMonsterArt: MonsterArt {
        let roster = [
            MonsterArt(name: "Slime", imageName: "HarmonyCharacterSlime"),
            MonsterArt(name: "Zombie", imageName: "HarmonyCharacterZombie"),
            MonsterArt(name: "Dragon", imageName: "HarmonyCharacterDragon"),
            MonsterArt(name: "Jellyfish", imageName: "HarmonyCharacterJellyfish"),
            MonsterArt(name: "Kraken", imageName: "HarmonyCharacterKraken")
        ]
        let index = min(max((state?.monsterIndex ?? 1) - 1, 0), roster.count - 1)
        return roster[index]
    }
}

private struct MonsterArt {
    let name: String
    let imageName: String
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
