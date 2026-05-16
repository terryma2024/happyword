package cool.happyword.wordmagic.ui.navigation

import cool.happyword.wordmagic.core.ChildProfileException

internal fun childProfileErrorMessage(err: ChildProfileException): String = when (err.code) {
    "INVALID_NICKNAME" -> "名字不能为空"
    "BINDING_NOT_FOUND" -> "当前后端未找到绑定记录"
    "BINDING_REVOKED" -> "绑定已被撤销，请重新扫码配对"
    "NETWORK" -> "网络错误，请稍后重试"
    "NOT_BOUND" -> "当前未绑定，请先扫码"
    else -> if (err.status > 0) "保存失败 (HTTP ${err.status})" else "保存失败，请稍后重试"
}
