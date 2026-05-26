package cool.happyword.wordmagic.ui.battle

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BattleBossIntroLayoutSpecTest {
    @Test
    fun bossIntroBubbleUsesBattleCanvasPositionFromReferenceShot() {
        assertEquals(0.56f, BattleBossIntroLayoutSpec.bubbleXRatio, 0.001f)
        assertEquals(0.10f, BattleBossIntroLayoutSpec.bubbleYRatio, 0.001f)
        assertEquals(224f, BattleBossIntroLayoutSpec.bubbleWidthDp, 0.001f)
        assertEquals(96f, BattleBossIntroLayoutSpec.bubbleHeightDp, 0.001f)
        assertTrue(BattleBossIntroLayoutSpec.bubbleZIndex > BattleBossIntroLayoutSpec.levelTagZIndex)
    }

    @Test
    fun monsterLevelTagIsInlineWithMonsterName() {
        assertEquals(8f, BattleBossIntroLayoutSpec.levelTagStartGapDp, 0.001f)
        assertEquals(14f, BattleBossIntroLayoutSpec.levelTagCornerRadiusDp, 0.001f)
    }
}
