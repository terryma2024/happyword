package cool.happyword.wordmagic.core

data class CoinCreditResult(val account: CoinAccount, val delta: Int)

data class CoinAccount(
    val balance: Int = 28,
    val earnedByDay: Map<String, Int> = emptyMap(),
) {
    fun creditBattleReward(stars: Int, dayKey: String): CoinCreditResult {
        val reward = stars.coerceIn(0, 3)
        val earnedToday = earnedByDay[dayKey] ?: 0
        val allowed = (DAILY_BATTLE_REWARD_CAP - earnedToday).coerceAtLeast(0)
        val delta = reward.coerceAtMost(allowed)
        return CoinCreditResult(
            account = copy(
                balance = balance + delta,
                earnedByDay = earnedByDay + (dayKey to (earnedToday + delta)),
            ),
            delta = delta,
        )
    }

    fun debit(cost: Int): CoinAccount {
        require(cost > 0) { "coin cost must be positive" }
        require(balance >= cost) { "not enough coins" }
        return copy(balance = balance - cost)
    }

    companion object {
        const val DAILY_BATTLE_REWARD_CAP = 20
    }
}

data class WishItem(
    val id: String,
    val title: String,
    val cost: Int,
    val icon: String,
    val custom: Boolean,
)

data class WishlistState(
    val defaultWishes: List<WishItem>,
    val customWishes: List<WishItem>,
) {
    fun allWishes(): List<WishItem> = defaultWishes + customWishes

    companion object {
        fun default(): WishlistState = WishlistState(
            defaultWishes = listOf(
                WishItem("sticker", "贴纸", 5, "🌟", false),
                WishItem("story", "睡前故事", 8, "📖", false),
                WishItem("park", "公园时间", 12, "🎈", false),
            ),
            customWishes = emptyList(),
        )
    }
}

data class RedemptionRecord(
    val id: String,
    val wishId: String,
    val title: String,
    val cost: Int,
    val redeemedAtMs: Long,
    val status: String = "已兑换",
)

data class RedemptionResult(
    val accepted: Boolean,
    val account: CoinAccount,
    val history: RedemptionHistoryStore,
    val message: String,
)

data class RedemptionHistoryStore(
    val records: List<RedemptionRecord> = emptyList(),
) {
    fun redeem(
        account: CoinAccount,
        wishlist: WishlistState,
        wishId: String,
        redeemedAtMs: Long,
        parentApproved: Boolean,
    ): RedemptionResult {
        if (!parentApproved) {
            return RedemptionResult(false, account, this, "需要家长确认")
        }
        val wish = wishlist.allWishes().firstOrNull { it.id == wishId }
            ?: return RedemptionResult(false, account, this, "愿望不存在")
        if (account.balance < wish.cost) {
            return RedemptionResult(false, account, this, "魔法币不足")
        }
        val nextAccount = account.debit(wish.cost)
        val nextRecord = RedemptionRecord(
            id = "redemption-$redeemedAtMs-${wish.id}",
            wishId = wish.id,
            title = wish.title,
            cost = wish.cost,
            redeemedAtMs = redeemedAtMs,
        )
        return RedemptionResult(
            accepted = true,
            account = nextAccount,
            history = copy(records = (listOf(nextRecord) + records).take(MAX_RECORDS)),
            message = "兑换成功",
        )
    }

    companion object {
        const val MAX_RECORDS = 50
    }
}

data class MonsterEntry(
    val id: String,
    val nameEn: String,
    val kindZh: String,
    val descriptionZh: String,
    val rawResourceName: String,
)

data class MonsterCatalog(
    val entries: List<MonsterEntry>,
    val index: Int = 0,
) {
    fun current(): MonsterEntry = entries[Math.floorMod(index, entries.size)]

    fun next(): MonsterCatalog = copy(index = (index + 1).coerceAtMost(entries.lastIndex))

    fun previous(): MonsterCatalog = copy(index = (index - 1).coerceAtLeast(0))

    companion object {
        fun default(): MonsterCatalog = MonsterCatalog(
            entries = listOf(
                MonsterEntry(
                    "slime",
                    "Slime",
                    "普通怪物",
                    "Slime 是一只软软的小精灵，整天住在森林深处的青草丛里。它最喜欢的事情就是在月光下打滚，把身体滚得圆圆的。它见到谁都会咧开大嘴笑一笑，从来不会真的生气。",
                    "character_slime",
                ),
                MonsterEntry(
                    "zombie",
                    "Zombie",
                    "拼写专家",
                    "Zombie 来自一座很老很老的图书馆，他喜欢把翻烂的书页披在身上当披风。他口袋里装满了散落一地的字母，每天都要把它们重新摆一摆。他看起来有点呆呆的，其实只是太爱发呆。",
                    "character_zombie",
                ),
                MonsterEntry(
                    "dragon",
                    "Dragon",
                    "精英挑战者",
                    "Dragon 是住在云朵后面的一只老巨龙，鳞片闪着金色的光。他大部分时间都在睡觉，一觉就是一百年。打喷嚏的时候会喷出小小的火苗，把天上的云染成漂亮的橘红色。",
                    "character_dragon",
                ),
            ),
        )
    }
}
