import Foundation

// Swift side of the cocos battle bridge contract.
// Contract + fixtures: shared/contracts/cocos-battle-bridge/.
// TS mirror: cocos/assets/scripts/bridge/messages.ts.

struct MonsterArtPayload: Codable, Equatable {
    var catalogIndex: Int
    var imageKey: String
    var name: String
    var levelLabel: String
    var bonus: Bool
}

struct PlayerArtPayload: Codable, Equatable {
    var idle: String
    var fight: String
    var hurt: String
}

struct BattleInitPayload: Codable, Equatable {
    var playerMaxHp: Int
    var monsterMaxHp: Int
    var monstersTotal: Int
    var startingSeconds: Int
    var playerArt: PlayerArtPayload
}

struct BattleStatePayload: Codable, Equatable {
    var playerHp: Int
    var playerMaxHp: Int
    var monsterHp: Int
    var monsterMaxHp: Int
    var monsterIndex: Int
    var monstersTotal: Int
    var remainingSeconds: Int
    var comboCount: Int
    var status: String
    var monster: MonsterArtPayload
}

struct BattleQuestionPayload: Codable, Equatable {
    var wordId: String
    var kind: String
    var promptZh: String
    var answer: String
    var options: [String]
    var letterTemplate: String
    var missingIndex: Int
    var letterOptions: [String]
    var letterAnswer: String
    var letterTemplateBase: String
    var missingIndices: [Int]
    var letterOptionsSteps: [[String]]
    var letterAnswers: [String]
    var currentStep: Int
    var spellLetters: [String]
    var spellRevealedMask: [Bool]
    var spellPool: [String]
    var sentenceTemplate: String
    var sentenceZh: String

    init(question: Question) {
        wordId = question.wordId
        kind = question.kind.rawValue
        promptZh = question.promptZh
        answer = question.answer
        options = question.options
        letterTemplate = question.letterTemplate
        missingIndex = question.missingIndex
        letterOptions = question.letterOptions
        letterAnswer = question.letterAnswer
        letterTemplateBase = question.letterTemplateBase
        missingIndices = question.missingIndices
        letterOptionsSteps = question.letterOptionsSteps
        letterAnswers = question.letterAnswers
        currentStep = question.currentStep
        spellLetters = question.spellLetters
        spellRevealedMask = question.spellRevealedMask
        spellPool = question.spellPool
        sentenceTemplate = question.sentenceTemplate
        sentenceZh = question.sentenceZh
    }
}

struct BattleAnimationPayload: Codable, Equatable {
    var projectileDirection: String
    var projectileIntensity: Int
    var projectileLabel: String
    var playerMotion: String
    var monsterMotion: String
    var feedbackText: String
    var showsCritOverlay: Bool
    var damageLabel: String
    var playsMonsterDefeatCue: Bool
    var correct: Bool
    var comboTriggered: Bool
    var battleEnded: Bool
}

struct BattleBossIntroPayload: Codable, Equatable {
    var monsterIndex: Int
    var name: String
    var introLineEn: String
    var introLineZh: String
}

struct BattleEndPayload: Codable, Equatable {
    var status: String
}

enum CocosBridgeOutbound {
    case initialize(BattleInitPayload)
    case state(BattleStatePayload)
    case question(BattleQuestionPayload)
    case animation(BattleAnimationPayload)
    case bossIntro(BattleBossIntroPayload)
    case end(BattleEndPayload)
    case ping(echo: String)

    private var typeName: String {
        switch self {
        case .initialize: "battle/init"
        case .state: "battle/state"
        case .question: "battle/question"
        case .animation: "battle/animation"
        case .bossIntro: "battle/bossIntro"
        case .end: "battle/end"
        case .ping: "battle/ping"
        }
    }

    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        let payloadData: Data
        switch self {
        case .initialize(let payload): payloadData = try encoder.encode(payload)
        case .state(let payload): payloadData = try encoder.encode(payload)
        case .question(let payload): payloadData = try encoder.encode(payload)
        case .animation(let payload): payloadData = try encoder.encode(payload)
        case .bossIntro(let payload): payloadData = try encoder.encode(payload)
        case .end(let payload): payloadData = try encoder.encode(payload)
        case .ping(let echo): payloadData = try encoder.encode(["echo": echo])
        }
        let payload = try JSONSerialization.jsonObject(with: payloadData)
        let envelope: [String: Any] = ["v": 1, "type": typeName, "payload": payload]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

enum CocosBridgeInbound: Equatable {
    case ready
    case submitOption(String)
    case spellWrongTap
    case speakAnswer
    case escape
    case pong(echo: String)

    private struct Header: Decodable {
        var v: Int
        var type: String
    }

    private struct OptionPayload: Decodable { var option: String }
    private struct EchoPayload: Decodable { var echo: String }
    private struct Envelope<P: Decodable>: Decodable { var payload: P }

    static func decode(from data: Data) throws -> CocosBridgeInbound? {
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.v == 1 else { return nil }
        switch header.type {
        case "battle/ready":
            return .ready
        case "battle/submitOption":
            return .submitOption(try decoder.decode(Envelope<OptionPayload>.self, from: data).payload.option)
        case "battle/spellWrongTap":
            return .spellWrongTap
        case "battle/speakAnswer":
            return .speakAnswer
        case "battle/escape":
            return .escape
        case "battle/pong":
            return .pong(echo: try decoder.decode(Envelope<EchoPayload>.self, from: data).payload.echo)
        default:
            return nil
        }
    }
}
