package cool.happyword.wordmagic.core

data class ExampleSentence(
    val en: String,
    val zh: String,
)

data class WordEntry(
    val id: String,
    val word: String,
    val meaning: String,
    val distractors: List<String> = emptyList(),
    val example: ExampleSentence? = null,
    val difficulty: Int = 1,
)

data class GameConfig(
    val playerHp: Int = 10,
    val monsterHp: Int = 5,
    val monsterCount: Int = 10,
    val timerSeconds: Int = 300,
    val autoPronunciation: Boolean = true,
    val playBgm: Boolean = false,
    val actionSfx: Boolean = true,
    val enabledQuestionTypes: List<String> = BattleQuestionTypePolicy.defaultOrderedTypeIds,
) {
    fun sanitizedQuestionTypes(): List<String> =
        BattleQuestionTypePolicy.sanitizeEnabledQuestionTypes(enabledQuestionTypes)
    companion object {
        val timerPresets = listOf(30, 180, 300, 600)
        const val TIMER_CUSTOM_MIN = 1
        const val TIMER_CUSTOM_MAX = 3600

        fun sanitizeTimerSeconds(value: Int): Int = value.coerceIn(TIMER_CUSTOM_MIN, TIMER_CUSTOM_MAX)

        /** Parity with Harmony `validateCustomTimerSeconds` in `CustomTimerDialog.ets`. */
        fun validateCustomTimerInput(input: String): CustomTimerValidation {
            val trimmed = input.trim()
            if (trimmed.isEmpty()) {
                return CustomTimerValidation(ok = false, seconds = 0, message = "请输入秒数")
            }
            if (!trimmed.all { it.isDigit() }) {
                return CustomTimerValidation(ok = false, seconds = 0, message = "请输入正整数秒数")
            }
            val parsed = trimmed.toIntOrNull()
                ?: return CustomTimerValidation(ok = false, seconds = 0, message = "请输入正整数秒数")
            if (parsed < TIMER_CUSTOM_MIN) {
                return CustomTimerValidation(ok = false, seconds = 0, message = "最少 $TIMER_CUSTOM_MIN 秒")
            }
            if (parsed > TIMER_CUSTOM_MAX) {
                return CustomTimerValidation(ok = false, seconds = 0, message = "最多 $TIMER_CUSTOM_MAX 秒")
            }
            return CustomTimerValidation(ok = true, seconds = parsed, message = "")
        }
    }
}

data class CustomTimerValidation(val ok: Boolean, val seconds: Int, val message: String)

enum class BattleStatus {
    Playing,
    Won,
    Lost,
}

enum class QuestionKind {
    Choice,
    FillLetter,
    FillLetterMedium,
    Spell,
    SentenceCloze,
}

data class Question(
    val prompt: String,
    val correctAnswer: String,
    val options: List<String>,
    val wordId: String = "",
    val kind: QuestionKind = QuestionKind.Choice,
    val letterTemplate: String = "",
    val missingIndex: Int = -1,
    val letterOptions: List<String> = emptyList(),
    val letterAnswer: String = "",
    val letterTemplateBase: String = "",
    val missingIndices: List<Int> = emptyList(),
    val letterOptionsSteps: List<List<String>> = emptyList(),
    val letterAnswers: List<String> = emptyList(),
    val currentStep: Int = 0,
    val spellLetters: List<String> = emptyList(),
    val spellRevealedMask: List<Boolean> = emptyList(),
    val spellPool: List<String> = emptyList(),
    val sentenceTemplate: String = "",
    val sentenceZh: String = "",
) {
    /** Text the battle speaker should pronounce: full sentence for cloze, else the answer word. */
    val battleSpeakText: String
        get() = if (kind == QuestionKind.SentenceCloze && sentenceTemplate.isNotEmpty()) {
            sentenceTemplate.replace("____", correctAnswer)
        } else {
            correctAnswer
        }
}

data class BattleState(
    val playerHp: Int,
    val monsterHp: Int,
    val monsterIndex: Int,
    val combo: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val defeatedMonsters: Int,
    val question: Question,
    val status: BattleStatus = BattleStatus.Playing,
    val currentMonsterBonus: Boolean = false,
    val bonusKillCount: Int = 0,
    val defeatedMonsterLevelScore: Int = 0,
    val monsterCatalogIndex: Int = 1,
)

data class ActiveBattleSnapshot(
    val packId: String,
    val isReview: Boolean,
    val dailyDayKey: String,
    val targetWordIds: List<String>,
    val config: GameConfig,
    val state: BattleState,
    val timeLeft: Int,
    val runId: Int,
    val servedQuestions: List<BattleServedQuestion> = emptyList(),
)

data class BattleServedQuestion(
    val wordId: String,
    val typeId: String,
)

data class BattleAnswerOutcome(
    val selectedAnswer: String,
    val correctAnswer: String,
    val question: Question,
    val correct: Boolean,
    val damage: Int,
    val comboTriggered: Boolean,
    val monsterDefeated: Boolean,
    val playerDamaged: Boolean,
    val battleEnded: Boolean,
    val nextState: BattleState,
    val advancedStep: Boolean = false,
)

data class SessionResult(
    val won: Boolean,
    val stars: Int,
    val defeatedMonsters: Int,
    val correctCount: Int,
    val wrongCount: Int,
    val learnedWordCount: Int,
    val coinDelta: Int,
    val bonusKillCount: Int = 0,
    val monsterLevelScore: Int = 0,
    val packId: String = "fruit-forest",
    val checkInRecorded: Boolean = false,
    val checkInCurrentStreak: Int = 0,
    val checkInBonusCoins: Int = 0,
    val checkInBonusDayKey: String = "",
) {
    val accuracyPercent: Int
        get() {
            val total = correctCount + wrongCount
            return if (total == 0) 0 else (correctCount * 100) / total
        }
}

object ParentPinStore {
    fun isValidPin(value: String): Boolean = value.length == 6 && value.all { it.isDigit() }
}
