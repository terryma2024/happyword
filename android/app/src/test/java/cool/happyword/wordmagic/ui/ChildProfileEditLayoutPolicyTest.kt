package cool.happyword.wordmagic.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class ChildProfileEditLayoutPolicyTest {
    @Test
    fun avatarChoicesAreUniqueAndWrappingIsEnabled() {
        assertEquals(true, ChildAvatarEmojiWrapEnabled)
        val choices = childAvatarEmojiChoices("🐻")
        assertEquals(10, choices.size)
        assertEquals("🐻", choices.first())
        assertEquals(choices.size, choices.toSet().size)
    }
}
