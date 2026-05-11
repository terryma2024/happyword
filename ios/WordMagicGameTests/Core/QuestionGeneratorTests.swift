@testable import WordMagicGame
import XCTest

final class QuestionGeneratorTests: XCTestCase {
    func testChoiceQuestionContainsAnswerAndUniqueOptions() throws {
        let repo = WordRepository(words: Self.words)
        let generator = QuestionGenerator(repository: repo, random: SeededRandom(seed: 1))

        let question = try generator.nextQuestion()

        XCTAssertEqual(question.kind, .choice)
        XCTAssertEqual(Set(question.options).count, 3)
        XCTAssertTrue(question.options.contains(question.answer))
        XCTAssertTrue(question.isValid)
    }

    func testFallsBackToGlobalDistractorsWhenCategoryIsSmall() throws {
        let repo = WordRepository(words: Self.words)
        let answer = try XCTUnwrap(repo.word(id: "home-door"))
        let generator = QuestionGenerator(repository: repo, random: SeededRandom(seed: 2))

        let question = try generator.question(for: answer)

        XCTAssertEqual(question.answer, "door")
        XCTAssertEqual(Set(question.options).count, 3)
        XCTAssertTrue(question.options.contains("door"))
    }

    private static let words: [WordEntry] = [
        WordEntry(id: "fruit-apple", word: "apple", meaningZh: "苹果", category: "fruit", difficulty: 1),
        WordEntry(id: "fruit-pear", word: "pear", meaningZh: "梨", category: "fruit", difficulty: 1),
        WordEntry(id: "place-park", word: "park", meaningZh: "公园", category: "place", difficulty: 1),
        WordEntry(id: "home-door", word: "door", meaningZh: "门", category: "home", difficulty: 1),
    ]
}
