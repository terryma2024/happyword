package cool.happyword.wordmagic.ui.config

import cool.happyword.wordmagic.core.BattleQuestionTypePolicy
import org.junit.Assert.assertEquals
import org.junit.Test

class ConfigLayoutPolicyTest {
    @Test
    fun formRowsMatchHarmonyLabelAndControlColumnMetrics() {
        assertEquals(120, ConfigLabelWidthDp)
        assertEquals(12, ConfigControlGapDp)
        assertEquals(220, ConfigControlColumnWidthDp)
        assertEquals(352, ConfigFormRowWidthDp)
        assertEquals(72, ConfigSwitchColumnWidthDp)
        assertEquals(16, ConfigSettingGroupGapDp)
        assertEquals(2, ConfigSettingOptionGapDp)
        assertEquals(42, ConfigSettingOptionHeightDp)
    }

    @Test
    fun actionAndSwitchColorsMatchSettledHarmonyGuideline() {
        assertEquals(0xFFFFB400.toInt(), ConfigSwitchCheckedTrackColor)
        assertEquals(0xFFE5E7EB.toInt(), ConfigSwitchUncheckedTrackColor)
        assertEquals(0xFFE0F2FE.toInt(), ConfigParentActionBgColor)
        assertEquals(0xFF0369A1.toInt(), ConfigParentActionTextColor)
        assertEquals(0xFF0EA5E9.toInt(), ConfigParentActionBorderColor)
    }

    @Test
    fun questionTypesStackVerticallyAndTimerUsesThreeItemsPerRow() {
        assertEquals(3, ConfigTimerOptionsPerRow)
        assertEquals(
            listOf(
                listOf(BattleQuestionTypePolicy.CHOICE),
                listOf(BattleQuestionTypePolicy.FILL_LETTER),
                listOf(BattleQuestionTypePolicy.FILL_LETTER_MEDIUM),
                listOf(BattleQuestionTypePolicy.SPELL),
                listOf(BattleQuestionTypePolicy.SENTENCE_CLOZE),
            ),
            configQuestionTypeRows(BattleQuestionTypePolicy.defaultOrderedTypeIds),
        )
        assertEquals(
            listOf(listOf(30, 180, 300), listOf(600, 0)),
            configTimerOptionRows(listOf(30, 180, 300, 600, 0)),
        )
    }
}
