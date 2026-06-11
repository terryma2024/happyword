import XCTest
@testable import WordMagicGame

final class CocosBattleBridgeMessageTests: XCTestCase {
    private static let fixturesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // file -> Core
        .deletingLastPathComponent() // Core -> WordMagicGameTests
        .deletingLastPathComponent() // WordMagicGameTests -> ios
        .deletingLastPathComponent() // ios -> repo root
        .appendingPathComponent("shared/fixtures/cocos-battle-bridge")

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Self.fixturesURL.appendingPathComponent(name))
    }

    func testDecodesEveryScriptToNativeFixture() throws {
        for name in ["ready.json", "submit-option.json", "spell-wrong-tap.json", "speak-answer.json", "escape.json", "pong.json"] {
            let message = try CocosBridgeInbound.decode(from: fixture(name))
            XCTAssertNotNil(message, name)
        }
    }

    func testSubmitOptionCarriesOption() throws {
        guard case .submitOption(let option) = try CocosBridgeInbound.decode(from: fixture("submit-option.json")) else {
            return XCTFail("expected submitOption")
        }
        XCTAssertEqual(option, "apple")
    }

    func testEncodedStateMatchesFixture() throws {
        let payload = BattleStatePayload(
            playerHp: 9, playerMaxHp: 10, monsterHp: 1, monsterMaxHp: 1,
            monsterIndex: 1, monstersTotal: 2, remainingSeconds: 297, comboCount: 2,
            status: "playing",
            monster: MonsterArtPayload(catalogIndex: 3, imageKey: "CharacterSnowGoblin",
                                       name: "Snow Goblin", levelLabel: "L1", bonus: false)
        )
        let encoded = try CocosBridgeOutbound.state(payload).encodedJSON()
        let expected = try JSONSerialization.jsonObject(with: fixture("state.json")) as! NSDictionary
        let actual = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as! NSDictionary
        XCTAssertEqual(actual, expected)
    }

    func testEncodedQuestionMatchesChoiceFixture() throws {
        let question = Question.choice(
            wordId: "w-apple", promptZh: "苹果", answer: "apple",
            options: ["orange", "blueberry", "apple"]
        )
        let encoded = try CocosBridgeOutbound.question(BattleQuestionPayload(question: question)).encodedJSON()
        let expected = try JSONSerialization.jsonObject(with: fixture("question-choice.json")) as! NSDictionary
        let actual = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as! NSDictionary
        XCTAssertEqual(actual, expected)
    }

    func testEncodedInitMatchesFixture() throws {
        let payload = BattleInitPayload(
            playerMaxHp: 10, monsterMaxHp: 1, monstersTotal: 2, startingSeconds: 300,
            playerArt: PlayerArtPayload(idle: "CharacterMagician", fight: "CharacterMagicianFight", hurt: "CharacterMagicianBeaten")
        )
        let encoded = try CocosBridgeOutbound.initialize(payload).encodedJSON()
        let expected = try JSONSerialization.jsonObject(with: fixture("init.json")) as! NSDictionary
        let actual = try JSONSerialization.jsonObject(with: Data(encoded.utf8)) as! NSDictionary
        XCTAssertEqual(actual, expected)
    }

    func testUnknownTypeDecodesToNil() throws {
        let data = Data(#"{"v":1,"type":"battle/unknown","payload":{}}"#.utf8)
        XCTAssertNil(try CocosBridgeInbound.decode(from: data))
    }

    func testWrongVersionDecodesToNil() throws {
        let data = Data(#"{"v":2,"type":"battle/ready","payload":{}}"#.utf8)
        XCTAssertNil(try CocosBridgeInbound.decode(from: data))
    }
}
