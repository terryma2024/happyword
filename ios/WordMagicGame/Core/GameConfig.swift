import Foundation

enum GameMode: String, Codable, Equatable {
    case normal
    case review
    case today
}

struct GameConfig: Codable, Equatable {
    static let timerChoices = [30, 180, 300, 600]
    static let timerCustomRange = 1 ... 3600
    static let hpRange = 1 ... 10
    static let monsterCountRange = 1 ... 10
    static let `default` = GameConfig()

    var playerMaxHp: Int = 5
    var monsterMaxHp: Int = 3
    var monstersTotal: Int = 5
    var startingSeconds: Int = 300
    var autoSpeak: Bool = true
    var mode: GameMode = .normal
    var parentPin: String = ""
    var enabledQuestionTypes: [String]

    private enum CodingKeys: String, CodingKey {
        case playerMaxHp
        case monsterMaxHp
        case monstersTotal
        case startingSeconds
        case autoSpeak
        case mode
        case parentPin
        case enabledQuestionTypes
    }

    init(
        playerMaxHp: Int = 5,
        monsterMaxHp: Int = 3,
        monstersTotal: Int = 5,
        startingSeconds: Int = 300,
        autoSpeak: Bool = true,
        mode: GameMode = .normal,
        parentPin: String = "",
        enabledQuestionTypes: [String]? = nil,
    ) {
        self.playerMaxHp = Self.clampHp(playerMaxHp)
        self.monsterMaxHp = Self.clampHp(monsterMaxHp)
        self.monstersTotal = Self.clampMonsterCount(monstersTotal)
        self.startingSeconds = Self.isValidTimer(startingSeconds) ? startingSeconds : 300
        self.autoSpeak = autoSpeak
        self.mode = mode
        self.parentPin = parentPin
        self.enabledQuestionTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(
            enabledQuestionTypes ?? BattleQuestionTypePolicy.defaultOrderedTypeIds,
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerMaxHp = Self.clampHp(try container.decode(Int.self, forKey: .playerMaxHp))
        monsterMaxHp = Self.clampHp(try container.decode(Int.self, forKey: .monsterMaxHp))
        monstersTotal = Self.clampMonsterCount(try container.decode(Int.self, forKey: .monstersTotal))
        let decodedSeconds = try container.decode(Int.self, forKey: .startingSeconds)
        startingSeconds = Self.isValidTimer(decodedSeconds) ? decodedSeconds : 300
        autoSpeak = try container.decode(Bool.self, forKey: .autoSpeak)
        mode = try container.decode(GameMode.self, forKey: .mode)
        parentPin = try container.decode(String.self, forKey: .parentPin)
        let rawTypes = try container.decodeIfPresent([String].self, forKey: .enabledQuestionTypes)
        enabledQuestionTypes = BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(
            rawTypes ?? BattleQuestionTypePolicy.defaultOrderedTypeIds,
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(playerMaxHp, forKey: .playerMaxHp)
        try container.encode(monsterMaxHp, forKey: .monsterMaxHp)
        try container.encode(monstersTotal, forKey: .monstersTotal)
        try container.encode(startingSeconds, forKey: .startingSeconds)
        try container.encode(autoSpeak, forKey: .autoSpeak)
        try container.encode(mode, forKey: .mode)
        try container.encode(parentPin, forKey: .parentPin)
        try container.encode(enabledQuestionTypes, forKey: .enabledQuestionTypes)
    }

    static func isValidTimer(_ seconds: Int) -> Bool {
        timerCustomRange.contains(seconds)
    }

    static func clampHp(_ value: Int) -> Int {
        min(max(value, hpRange.lowerBound), hpRange.upperBound)
    }

    static func clampMonsterCount(_ value: Int) -> Int {
        min(max(value, monsterCountRange.lowerBound), monsterCountRange.upperBound)
    }

    static func isValidPin(_ value: String) -> Bool {
        value.count == 6 && value.allSatisfy(isASCIIDigit)
    }

    static func sanitizePinInput(_ value: String) -> String {
        String(value.filter(isASCIIDigit).prefix(6))
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first
        else {
            return false
        }
        return (48 ... 57).contains(scalar.value)
    }

    /// Mirrors Harmony `validateCustomTimerSeconds` in `CustomTimerDialog.ets`.
    static func validateCustomTimerInput(_ input: String) -> CustomTimerInputValidation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return CustomTimerInputValidation(ok: false, seconds: 0, message: "请输入秒数")
        }
        if trimmed.range(of: "^[0-9]+$", options: .regularExpression) == nil {
            return CustomTimerInputValidation(ok: false, seconds: 0, message: "请输入正整数秒数")
        }
        guard let parsed = Int(trimmed) else {
            return CustomTimerInputValidation(ok: false, seconds: 0, message: "请输入正整数秒数")
        }
        if parsed < timerCustomRange.lowerBound {
            return CustomTimerInputValidation(
                ok: false,
                seconds: 0,
                message: "最少 \(timerCustomRange.lowerBound) 秒",
            )
        }
        if parsed > timerCustomRange.upperBound {
            return CustomTimerInputValidation(
                ok: false,
                seconds: 0,
                message: "最多 \(timerCustomRange.upperBound) 秒",
            )
        }
        return CustomTimerInputValidation(ok: true, seconds: parsed, message: "")
    }

    /// Mirrors Harmony `validateCustomTimerSeconds` in `CustomTimerDialog.ets`.
    static func validateCustomTimerInput(_ input: String) -> CustomTimerInputValidation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return CustomTimerInputValidation(ok: false, seconds: 0, message: "请输入秒数")
        }
        if trimmed.range(of: "^[0-9]+$", options: .regularExpression) == nil {
            return CustomTimerInputValidation(ok: false, seconds: 0, message: "请输入正整数秒数")
        }
        guard let parsed = Int(trimmed) else {
            return CustomTimerInputValidation(ok: false, seconds: 0, message: "请输入正整数秒数")
        }
        if parsed < timerCustomRange.lowerBound {
            return CustomTimerInputValidation(
                ok: false,
                seconds: 0,
                message: "最少 \(timerCustomRange.lowerBound) 秒",
            )
        }
        if parsed > timerCustomRange.upperBound {
            return CustomTimerInputValidation(
                ok: false,
                seconds: 0,
                message: "最多 \(timerCustomRange.upperBound) 秒",
            )
        }
        return CustomTimerInputValidation(ok: true, seconds: parsed, message: "")
    }
}

struct CustomTimerInputValidation: Equatable {
    let ok: Bool
    let seconds: Int
    let message: String
}

struct CustomTimerInputValidation: Equatable {
    let ok: Bool
    let seconds: Int
    let message: String
}
