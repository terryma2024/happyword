package cool.happyword.wordmagic.ui.navigation

import cool.happyword.wordmagic.R

internal data class PackUi(
    val id: String,
    val nameZh: String,
    val nameEn: String,
    val story: String,
    val monsterRes: Int,
)

internal val packs = listOf(
    PackUi("fruit-forest", "水果森林", "Fruit Forest", "藤蔓和果香里的第一场魔法单词冒险。", R.raw.character_slime),
    PackUi("school-castle", "校园城堡", "School Castle", "在书本城堡里挑战会拼写的怪物。", R.raw.character_zombie),
    PackUi("home-cottage", "家庭小屋", "Home Cottage", "把熟悉的家庭物品变成轻松复习。", R.raw.character_dragon),
    PackUi("animal-safari", "动物远征", "Animal Safari", "跟动物朋友一起找回单词记忆。", R.raw.character_slime),
    PackUi("ocean-realm", "海洋王国", "Ocean Realm", "在蓝色海底完成今日练习。", R.raw.character_zombie),
)

internal val homePackOrder = listOf("school-castle", "ocean-realm", "home-cottage", "fruit-forest", "animal-safari")
internal val homePacks = homePackOrder.mapNotNull { id -> packs.firstOrNull { it.id == id } }

internal const val DEFAULT_BATTLE_TIMER_SECONDS = 300
internal const val BATTLE_FEEDBACK_MS = 650L
internal const val PROJECTILE_IMPACT_MS = 320L
internal const val GIFTBOX_TRIGGER_DELAY_MS = 60L
internal const val GIFTBOX_MODAL_TOTAL_MS = 3_180L
internal const val WISH_REDEEMED_ACK_MS = 1_500L
