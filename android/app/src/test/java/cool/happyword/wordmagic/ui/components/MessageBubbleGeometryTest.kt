package cool.happyword.wordmagic.ui.components

import org.junit.Assert.assertEquals
import org.junit.Test

class MessageBubbleGeometryTest {
    @Test
    fun bottomRightPresetMatchesHarmonyBossTail() {
        val tail = buildMessageBubbleTailPreset(
            preset = MessageBubbleTailPreset.BottomRight,
            box = MessageBubbleBox(
                width = 224f,
                height = 96f,
                borderWidth = 1f,
                tailBase = 24f,
                tailLength = 16f,
                inset = 28f,
                tipInset = 12f,
            ),
        )

        assertEquals(MessageBubblePoint(172f, 96f), tail.baseStart)
        assertEquals(MessageBubblePoint(196f, 96f), tail.baseEnd)
        assertEquals(MessageBubblePoint(212f, 112f), tail.tip)
    }

    @Test
    fun presetsCoverEachSideAndAlignBaseToBubbleEdge() {
        val box = MessageBubbleBox(
            width = 224f,
            height = 96f,
            borderWidth = 1f,
            tailBase = 24f,
            tailLength = 16f,
            inset = 28f,
            tipInset = 12f,
        )

        assertEquals(12, MessageBubbleTailPreset.entries.size)
        MessageBubbleTailPreset.entries.forEach { preset ->
            val tail = buildMessageBubbleTailPreset(preset, box)
            when (preset) {
                MessageBubbleTailPreset.TopLeft,
                MessageBubbleTailPreset.TopMiddle,
                MessageBubbleTailPreset.TopRight -> {
                    assertEquals(0f, tail.baseStart.y)
                    assertEquals(0f, tail.baseEnd.y)
                    assertEquals(-box.tailLength, tail.tip.y)
                }
                MessageBubbleTailPreset.BottomLeft,
                MessageBubbleTailPreset.BottomMiddle,
                MessageBubbleTailPreset.BottomRight -> {
                    assertEquals(box.height, tail.baseStart.y)
                    assertEquals(box.height, tail.baseEnd.y)
                    assertEquals(box.height + box.tailLength, tail.tip.y)
                }
                MessageBubbleTailPreset.LeftTop,
                MessageBubbleTailPreset.LeftMiddle,
                MessageBubbleTailPreset.LeftBottom -> {
                    assertEquals(0f, tail.baseStart.x)
                    assertEquals(0f, tail.baseEnd.x)
                    assertEquals(-box.tailLength, tail.tip.x)
                }
                MessageBubbleTailPreset.RightTop,
                MessageBubbleTailPreset.RightMiddle,
                MessageBubbleTailPreset.RightBottom -> {
                    assertEquals(box.width, tail.baseStart.x)
                    assertEquals(box.width, tail.baseEnd.x)
                    assertEquals(box.width + box.tailLength, tail.tip.x)
                }
            }
        }
    }

    @Test
    fun frameExpandsToIncludeTailOutsideBubbleBounds() {
        val frame = messageBubbleFrame(
            width = 224f,
            height = 96f,
            tail = MessageBubbleTail(
                baseStart = MessageBubblePoint(172f, 96f),
                baseEnd = MessageBubblePoint(196f, 96f),
                tip = MessageBubblePoint(212f, 112f),
            ),
        )

        assertEquals(MessageBubbleFrame(width = 224f, height = 112f, offsetX = 0f, offsetY = 0f), frame)
    }
}
