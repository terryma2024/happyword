package cool.happyword.wordmagic.core

import org.junit.Assert.assertEquals
import org.junit.Test

class BindingQrPayloadTest {
    @Test
    fun extractTokenFromQrPayload_readsHappywordUrl() {
        assertEquals(
            "uitestqr01",
            extractTokenFromQrPayload("https://happyword.com.cn/p/uitestqr01"),
        )
    }

    @Test
    fun extractTokenFromQrPayload_stripsQueryAndFragment() {
        assertEquals(
            "abc",
            extractTokenFromQrPayload("https://example.com/p/abc?x=1#frag"),
        )
    }

    @Test
    fun bindingFailureHint_mapsKnownReasons() {
        assertEquals("二维码或短码无效。", bindingFailureHint("TOKEN_INVALID"))
    }
}
