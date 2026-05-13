import Foundation

enum GameMode: String, Codable, Equatable {
    case normal
    case review
    case today
}

struct GameConfig: Codable, Equatable {
    static let timerChoices = [30, 180, 300, 600]
    static let timerCustomRange = 1...3600
    static let hpRange = 1...10
    static let monsterCountRange = 1...10
    static let `default` = GameConfig()

    var playerMaxHp: Int = 5
    var monsterMaxHp: Int = 3
    var monstersTotal: Int = 5
    var startingSeconds: Int = 300
    var autoSpeak: Bool = true
    var mode: GameMode = .normal
    var parentPin: String = ""

    init(
        playerMaxHp: Int = 5,
        monsterMaxHp: Int = 3,
        monstersTotal: Int = 5,
        startingSeconds: Int = 300,
        autoSpeak: Bool = true,
        mode: GameMode = .normal,
        parentPin: String = ""
    ) {
        self.playerMaxHp = Self.clampHp(playerMaxHp)
        self.monsterMaxHp = Self.clampHp(monsterMaxHp)
        self.monstersTotal = Self.clampMonsterCount(monstersTotal)
        self.startingSeconds = Self.isValidTimer(startingSeconds) ? startingSeconds : 300
        self.autoSpeak = autoSpeak
        self.mode = mode
        self.parentPin = parentPin
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
        return (48...57).contains(scalar.value)
    }
}
