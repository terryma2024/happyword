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
        let singleWord = try XCTUnwrap(generator.generate(Self.word(id: "fruit-apple", word: "apple", meaningZh: "苹果")))
        XCTAssertEqual(singleWord.letterTemplate.filter { $0 == " " }.count, 0)

        let beginner = try XCTUnwrap(generator.generate(Self.word(id: "phrase-magic-wand", word: "magic wand", meaningZh: "魔法棒")))
        XCTAssertEqual(beginner.letterTemplate.filter { $0 == " " }.count, 1)

        let medium = try XCTUnwrap(generator.generateMedium(Self.word(id: "phrase-magic-wand", word: "magic wand", meaningZh: "魔法棒")))
        XCTAssertEqual(medium.letterTemplateBase.filter { $0 == " " }.count, 1)

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

    func testSentenceClozeGeneratorMatchesHarmonyRules() throws {
        let apple = Self.word(
            id: "fruit-apple",
            word: "apple",
            meaningZh: "苹果",
            example: ExampleSentence(en: "I eat an apple.", zh: "我吃一个苹果。")
        )
        let repo = WordRepository(words: [
            apple,
            Self.word(id: "fruit-banana", word: "banana", meaningZh: "香蕉"),
            Self.word(id: "fruit-orange", word: "orange", meaningZh: "橙子"),
        ])

        let question = try XCTUnwrap(SentenceClozeGenerator(random: SeededRandom(seed: 1)).generate(apple, repo: repo))

        XCTAssertEqual(question.kind, .sentenceCloze)
        XCTAssertEqual(question.sentenceTemplate, "I eat an ____.")
        XCTAssertEqual(question.sentenceZh, "我吃一个苹果。")
        XCTAssertEqual(Set(question.options).count, 3)
        XCTAssertTrue(question.options.contains("apple"))
        XCTAssertTrue(question.isValid)
        XCTAssertNil(findSentenceClozeTargetSpan(exampleEn: "A caterpillar is small.", targetWord: "cat"))
    }

    func testSentenceClozeGeneratorMatchesPhrasesFirstMatchAndUniqueDistractors() throws {
        let wand = Self.word(
            id: "magic-wand",
            word: "magic wand",
            meaningZh: "魔法棒",
            example: ExampleSentence(en: "I hold a magic wand.", zh: "我拿着一根魔法棒。")
        )
        let repo = WordRepository(words: [
            wand,
            Self.word(id: "fruit-apple", word: "apple", meaningZh: "苹果"),
            Self.word(id: "fruit-banana", word: "banana", meaningZh: "香蕉"),
        ])
        XCTAssertEqual(
            try XCTUnwrap(SentenceClozeGenerator(random: SeededRandom(seed: 2)).generate(wand, repo: repo)).sentenceTemplate,
            "I hold a ____."
        )

        var apple = Self.word(
            id: "fruit-apple",
            word: "apple",
            meaningZh: "苹果",
            example: ExampleSentence(en: "Apple pie has apple slices.", zh: "苹果派里有苹果片。")
        )
        apple.distractors = ["Apple", "banana"]
        let appleRepo = WordRepository(words: [
            apple,
            Self.word(id: "fruit-orange", word: "orange", meaningZh: "橙子"),
            Self.word(id: "fruit-grape", word: "grape", meaningZh: "葡萄"),
        ])
        let question = try XCTUnwrap(SentenceClozeGenerator(random: SeededRandom(seed: 3)).generate(apple, repo: appleRepo))
        XCTAssertEqual(question.sentenceTemplate, "____ pie has apple slices.")
        XCTAssertEqual(question.options.count, 3)
        XCTAssertTrue(question.options.contains("apple"))
        XCTAssertTrue(question.options.contains("banana"))
        XCTAssertFalse(question.options.contains("Apple"))
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

    func testPlanQuestionSourceEmitsSentenceClozeWhenOnlySentenceClozeEnabled() throws {
        let repo = WordRepository(words: Self.planWords)
        let source = PlanQuestionSource(
            plan: BattleQuestionPlan(
                wordIds: ["fruit-apple"],
                monsterSlots: [MonsterPlanSlot(kind: .boss, catalogIndex: 4)]
            ),
            repository: repo,
            randomSeed: 3,
            enabledQuestionTypes: [QuestionKind.sentenceCloze.rawValue]
        )

        let question = try source.nextQuestion()

        XCTAssertEqual(question.kind, .sentenceCloze)
        XCTAssertEqual(question.sentenceTemplate, "I eat an ____.")
        XCTAssertEqual(question.sentenceZh, "我吃苹果。")
    }

    func testPlanQuestionSourceRotatesSingleEnabledTypeAcrossPackWords() throws {
        let pack = try XCTUnwrap(Pack.builtin.first { $0.id == "fruit-forest" })
        let expectedIds = pack.words.prefix(5).map(\.id)
        let source = PlanQuestionSource(
            plan: BattleQuestionPlan(
                wordIds: pack.words.map(\.id),
                monsterSlots: [MonsterPlanSlot(kind: .boss, catalogIndex: 4)]
            ),
            repository: WordRepository(words: pack.words),
            randomSeed: 3,
            enabledQuestionTypes: [QuestionKind.sentenceCloze.rawValue]
        )
        var lastWordId: String?
        var actualIds: [String] = []

        for _ in expectedIds {
            let question = try source.nextQuestion(lastWordId: lastWordId)
            XCTAssertEqual(question.kind, .sentenceCloze)
            actualIds.append(question.wordId)
            lastWordId = question.wordId
        }

        XCTAssertEqual(actualIds, Array(expectedIds))
    }

    func testPlanQuestionSourceFallsBackToChoiceWhenSentenceClozeUnsupported() throws {
        let repo = WordRepository(words: Self.planWords)
        let source = PlanQuestionSource(
            plan: BattleQuestionPlan(
                wordIds: ["fruit-orange"],
                monsterSlots: [MonsterPlanSlot(kind: .boss, catalogIndex: 4)]
            ),
            repository: repo,
            randomSeed: 3,
            enabledQuestionTypes: [QuestionKind.sentenceCloze.rawValue]
        )

        XCTAssertEqual(try source.nextQuestion().kind, .choice)
    }

    private static let words: [WordEntry] = [
        WordEntry(id: "fruit-apple", word: "apple", meaningZh: "苹果", category: "fruit", difficulty: 1),
        WordEntry(id: "fruit-pear", word: "pear", meaningZh: "梨", category: "fruit", difficulty: 1),
        WordEntry(id: "place-park", word: "park", meaningZh: "公园", category: "place", difficulty: 1),
        WordEntry(id: "home-door", word: "door", meaningZh: "门", category: "home", difficulty: 1),
    ]

    private static let planWords: [WordEntry] = [
        word(id: "fruit-apple", word: "apple", meaningZh: "苹果", example: ExampleSentence(en: "I eat an apple.", zh: "我吃苹果。")),
        word(id: "fruit-banana", word: "banana", meaningZh: "香蕉"),
        word(id: "fruit-orange", word: "orange", meaningZh: "橙子"),
        word(id: "place-zoo", word: "zoo", meaningZh: "动物园", category: "place"),
        word(id: "home-tv", word: "TV", meaningZh: "电视", category: "home"),
        word(id: "w-extraordinary", word: "extraordinary", meaningZh: "非凡的"),
        word(id: "w-fish", word: "fish", meaningZh: "鱼"),
        word(id: "w-elephant", word: "elephant", meaningZh: "大象"),
    ]

    private static func word(
        id: String,
        word: String,
        meaningZh: String,
        category: String = "fruit",
        example: ExampleSentence? = nil
    ) -> WordEntry {
        WordEntry(id: id, word: word, meaningZh: meaningZh, category: category, difficulty: 1, example: example)
    }
}
