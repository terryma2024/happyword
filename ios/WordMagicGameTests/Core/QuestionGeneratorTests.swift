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

    func testNextQuestionForWordKeepsChinesePromptAndCanMoveAnswerFromFirstOption() throws {
        let repo = WordRepository(words: Pack.builtin[0].words)
        let answer = try XCTUnwrap(repo.word(id: "fruit-apple"))
        var sawAnswerAwayFromFirstOption = false

        for seed in 1 ... 20 {
            let generator = QuestionGenerator(repository: repo, random: SeededRandom(seed: UInt64(seed)))
            let question = try generator.nextQuestionForWord(answer)

            XCTAssertEqual(question.wordId, "fruit-apple")
            XCTAssertEqual(question.promptZh, "苹果")
            XCTAssertEqual(question.answer, "apple")
            XCTAssertEqual(Set(question.options).count, 3)
            XCTAssertTrue(question.options.contains("apple"))
            sawAnswerAwayFromFirstOption = sawAnswerAwayFromFirstOption || question.options.first != question.answer
        }

        XCTAssertTrue(sawAnswerAwayFromFirstOption)
    }

    func testFillLetterGeneratorMatchesHarmonyQuestionShapes() throws {
        let generator = FillLetterGenerator(random: SeededRandom(seed: 6))
        let beginner = try XCTUnwrap(generator.generate(Self.word(id: "fruit-apple", word: "apple", meaningZh: "苹果")))
        XCTAssertEqual(beginner.kind, .fillLetter)
        XCTAssertEqual(beginner.answer, "apple")
        XCTAssertGreaterThanOrEqual(beginner.missingIndex, 1)
        XCTAssertEqual(beginner.letterOptions.count, 3)
        XCTAssertTrue(beginner.letterOptions.contains(beginner.letterAnswer))
        XCTAssertTrue(beginner.isValid)

        let medium = try XCTUnwrap(generator.generateMedium(Self.word(id: "fruit-banana", word: "banana", meaningZh: "香蕉")))
        XCTAssertEqual(medium.kind, .fillLetterMedium)
        XCTAssertEqual(medium.missingIndices.count, 2)
        XCTAssertEqual(medium.letterOptionsSteps.count, 2)
        XCTAssertEqual(medium.letterAnswers.count, 2)
        XCTAssertTrue(medium.missingIndices.allSatisfy { $0 >= 1 })
        XCTAssertTrue(medium.isValid)

        XCTAssertNil(generator.generate(Self.word(id: "home-tv", word: "TV", meaningZh: "电视")))
        XCTAssertNil(generator.generateMedium(Self.word(id: "place-zoo", word: "zoo", meaningZh: "动物园")))
    }

    func testFillLetterGeneratorPreservesPhraseSpacesAndSkipsArticles() throws {
        let generator = FillLetterGenerator(random: SeededRandom(seed: 10))
        let beginner = try XCTUnwrap(generator.generate(Self.word(id: "phrase-magic-wand", word: "magic wand", meaningZh: "魔法棒")))
        XCTAssertTrue(beginner.letterTemplate.contains("   "))

        let medium = try XCTUnwrap(generator.generateMedium(Self.word(id: "phrase-magic-wand", word: "magic wand", meaningZh: "魔法棒")))
        XCTAssertTrue(medium.letterTemplateBase.contains("   "))

        let articleGenerator = FillLetterGenerator(random: SeededRandom(seed: 1))
        for index in 0 ..< 20 {
            let article = try XCTUnwrap(articleGenerator.generate(Self.word(id: "phrase-an-puppy-\(index)", word: "an puppy", meaningZh: "一只小狗")))
            XCTAssertFalse(["a", "n"].contains(article.letterAnswer))
        }
    }

    func testSpellGeneratorMatchesHarmonyBoundsAndShape() throws {
        let generator = SpellGenerator(random: SeededRandom(seed: 1))
        let question = try XCTUnwrap(generator.generate(Self.word(id: "fruit-apple", word: "apple", meaningZh: "苹果")))

        XCTAssertEqual(question.kind, .spell)
        XCTAssertEqual(question.answer, "apple")
        XCTAssertEqual(question.spellLetters, ["a", "p", "p", "l", "e"])
        XCTAssertEqual(question.spellRevealedMask, [true, false, false, false, false])
        XCTAssertEqual(question.spellPool.sorted(), ["e", "l", "p", "p"])
        XCTAssertTrue(question.isValid)

        XCTAssertNil(generator.generate(Self.word(id: "fruit-cat", word: "cat", meaningZh: "猫")))
        XCTAssertNil(generator.generate(Self.word(id: "fruit-strawberry", word: "strawberry", meaningZh: "草莓")))
        XCTAssertNotNil(generator.generate(Self.word(id: "w-fish", word: "fish", meaningZh: "鱼")))
        XCTAssertNotNil(generator.generate(Self.word(id: "w-elephant", word: "elephant", meaningZh: "大象")))
    }

    func testSpellGeneratorShowsPhraseSpacesAndPrefillsArticles() throws {
        let generator = SpellGenerator(random: SeededRandom(seed: 8))
        let question = try XCTUnwrap(generator.generate(Self.word(id: "phrase-the-apple", word: "the apple", meaningZh: "这个苹果")))

        XCTAssertEqual(question.spellLetters.joined(), "the apple")
        XCTAssertEqual(Array(question.spellRevealedMask.prefix(5)), [true, true, true, true, true])
        XCTAssertEqual(question.spellPool.sorted(), ["e", "l", "p", "p"])
        XCTAssertTrue(question.isValid)
    }

    func testPlanQuestionSourceUsesMonsterSlotQuestionChain() throws {
        let repo = WordRepository(words: Self.planWords)
        let source = PlanQuestionSource(
            plan: BattleQuestionPlan(
                wordIds: ["fruit-apple", "fruit-banana", "fruit-orange", "place-zoo", "w-fish"],
                monsterSlots: [
                    MonsterPlanSlot(kind: .normal, catalogIndex: 0),
                    MonsterPlanSlot(kind: .spelling, catalogIndex: 1),
                    MonsterPlanSlot(kind: .elite, catalogIndex: 2),
                    MonsterPlanSlot(kind: .review, catalogIndex: 3),
                    MonsterPlanSlot(kind: .boss, catalogIndex: 4),
                ]
            ),
            repository: repo,
            randomSeed: 42
        )

        source.setMonsterIndexProvider { 1 }
        XCTAssertEqual(try source.nextQuestion().kind, .choice)
        source.setMonsterIndexProvider { 2 }
        XCTAssertEqual(try source.nextQuestion().kind, .fillLetter)
        source.setMonsterIndexProvider { 3 }
        XCTAssertEqual(try source.nextQuestion().kind, .fillLetterMedium)
        source.setMonsterIndexProvider { 4 }
        XCTAssertEqual(try source.nextQuestion().kind, .choice)
        source.setMonsterIndexProvider { 5 }
        XCTAssertEqual(try source.nextQuestion().kind, .spell)
    }

    func testPlanQuestionSourceFallsBackByWordLengthLikeHarmony() throws {
        let repo = WordRepository(words: Self.planWords)
        let source = PlanQuestionSource(
            plan: BattleQuestionPlan(
                wordIds: ["place-zoo", "home-tv", "w-extraordinary", "fruit-orange"],
                monsterSlots: [MonsterPlanSlot(kind: .boss, catalogIndex: 0)]
            ),
            repository: repo,
            randomSeed: 7
        )
        source.setMonsterIndexProvider { 1 }

        XCTAssertEqual(try source.nextQuestion().kind, .fillLetter)
        XCTAssertEqual(try source.nextQuestion().kind, .choice)
        XCTAssertEqual(try source.nextQuestion().kind, .fillLetterMedium)
        XCTAssertEqual(try source.nextQuestion().kind, .spell)
    }

    private static let words: [WordEntry] = [
        WordEntry(id: "fruit-apple", word: "apple", meaningZh: "苹果", category: "fruit", difficulty: 1),
        WordEntry(id: "fruit-pear", word: "pear", meaningZh: "梨", category: "fruit", difficulty: 1),
        WordEntry(id: "place-park", word: "park", meaningZh: "公园", category: "place", difficulty: 1),
        WordEntry(id: "home-door", word: "door", meaningZh: "门", category: "home", difficulty: 1),
    ]

    private static let planWords: [WordEntry] = [
        word(id: "fruit-apple", word: "apple", meaningZh: "苹果"),
        word(id: "fruit-banana", word: "banana", meaningZh: "香蕉"),
        word(id: "fruit-orange", word: "orange", meaningZh: "橙子"),
        word(id: "place-zoo", word: "zoo", meaningZh: "动物园", category: "place"),
        word(id: "home-tv", word: "TV", meaningZh: "电视", category: "home"),
        word(id: "w-extraordinary", word: "extraordinary", meaningZh: "非凡的"),
        word(id: "w-fish", word: "fish", meaningZh: "鱼"),
        word(id: "w-elephant", word: "elephant", meaningZh: "大象"),
    ]

    private static func word(id: String, word: String, meaningZh: String, category: String = "fruit") -> WordEntry {
        WordEntry(id: id, word: word, meaningZh: meaningZh, category: category, difficulty: 1)
    }
}
