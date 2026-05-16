package cool.happyword.wordmagic.core

/** Extracts the pair token from a `/p/<token>` URL. Returns '' on miss. Mirrors HarmonyOS. */
fun extractTokenFromQrPayload(payload: String): String {
    val idx = payload.indexOf("/p/")
    if (idx < 0) return ""
    var tail = payload.substring(idx + "/p/".length)
    val qIdx = tail.indexOf('?')
    if (qIdx >= 0) tail = tail.substring(0, qIdx)
    val hIdx = tail.indexOf('#')
    if (hIdx >= 0) tail = tail.substring(0, hIdx)
    return tail.trimEnd('/')
}

fun bindingFailureHint(reason: String): String = when (reason) {
    "TOKEN_EXPIRED" -> "二维码已过期，请让家长在网页重新生成。"
    "TOKEN_REDEEMED" -> "此二维码已被使用过。"
    "TOKEN_INVALID" -> "二维码或短码无效。"
    "NETWORK" -> "网络异常，请检查后重试。"
    "UNKNOWN" -> "出错了，请稍后再试。"
    else -> ""
}

fun bindingFailureReasonFromMessage(message: String): String = when {
    message.contains("过期") -> "TOKEN_EXPIRED"
    message.contains("已被使用") -> "TOKEN_REDEEMED"
    message.contains("无效") || message.contains("6 位") -> "TOKEN_INVALID"
    message.contains("网络") -> "NETWORK"
    else -> "UNKNOWN"
}
