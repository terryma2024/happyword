package cool.happyword.wordmagic.core

data class CoinCreditResult(val account: CoinAccount, val delta: Int)

data class CoinAccount(
    /** Default matches first catalog wish cost (10) so one row shows 申请兑换 and others show 还差 N ✨. */
    val balance: Int = 10,
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
            // Keep ids/copy aligned with harmonyos/entry/src/main/ets/data/WishlistCatalog.ets (WISHLIST_CATALOG).
            defaultWishes = listOf(
                WishItem("wish-ipad-20min", "看 iPad 20 分钟", 10, "📱", false),
                WishItem("wish-watch-topup-10", "手表零钱充值 10 元", 25, "⌚", false),
                WishItem("wish-small-gift", "买一个礼物 (≤20 元)", 50, "🎁", false),
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
    /** Legacy field; rows match HarmonyOS (no per-row status label). */
    val status: String = "已兑换",
    /** Wish icon/emoji at redemption time — aligns with Harmony `RedemptionRecord.iconEmoji`. */
    val iconEmoji: String = "",
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
            iconEmoji = wish.icon,
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
                MonsterEntry("slime", "Slime", "普通怪物", "Slime 是一只软软的小精灵，整天住在森林深处的青草丛里。它最喜欢的事情就是在月光下打滚，把身体滚得圆圆的。它见到谁都会咧开大嘴笑一笑，从来不会真的生气。", "character_slime"),
                MonsterEntry("zombie", "Zombie", "拼写专家", "Zombie 来自一座很老很老的图书馆，他喜欢把翻烂的书页披在身上当披风。他口袋里装满了散落一地的字母，每天都要把它们重新摆一摆。他看起来有点呆呆的，其实只是太爱发呆。", "character_zombie"),
                MonsterEntry("dragon", "Dragon", "精英挑战者", "Dragon 是住在云朵后面的一只老巨龙，鳞片闪着金色的光。他大部分时间都在睡觉，一觉就是一百年。打喷嚏的时候会喷出小小的火苗，把天上的云染成漂亮的橘红色。", "character_dragon"),
                MonsterEntry("pumpkin-king", "Pumpkin King", "秋夜灯王", "南瓜王戴着藤蔓皇冠，住在最大的那个南瓜里面。每到秋天他就把灯一盏一盏点起来，让回家的小孩不会迷路。他的笑声脆脆的，像踩在落叶上。", "character_pumpkin_king"),
                MonsterEntry("imp-king", "Imp King", "林间舞者", "小妖王是个赤脚的小胖精灵，戴一顶蘑菇帽。森林里所有的萤火虫都听他的口令。傍晚他敲敲蘑菇，全林子的小妖就出来跟他绕着大树跳舞。", "character_imp_king"),
                MonsterEntry("phoenix", "Phoenix", "火羽之灵", "凤凰是一只长着金色尾羽的大鸟，住在最高的果园树梢。每天清晨翅膀一拍就把太阳唤醒。羽毛掉下来就变成秋叶，谁捡到都会觉得手心暖暖的。", "character_phoenix"),
                MonsterEntry("witch", "Witch", "夜空魔法师", "女巫住在云海后面的小阁楼里，每天晚上骑着弯月去看星星。她的尖帽子里藏着小书签，权杖头上的星星会自己唱歌。听见小孩笑声会偷偷飞过来一起转圈圈。", "character_witch"),
                MonsterEntry("snow-queen", "Snow Queen", "冰雪歌者", "雪女王披着透明的冰纱，唱起歌来就有大片大片的雪花飘下来。她特别爱穿越寒夜守护迷路的小动物，把它们送回温暖的洞口才放心地飞回北方。", "character_snow_queen"),
                MonsterEntry("unicorn", "Unicorn", "彩虹守护", "独角兽走过的地方会留下淡淡的彩虹。它最喜欢小孩子悄悄递来的方糖，吃完会把头低下来让人摸摸鬃毛。它的水晶角能听见星星说悄悄话。", "character_unicorn"),
                MonsterEntry("kraken", "Kraken", "深海歌唱家", "克拉肯住在很深很深的海底，触手长长地能伸到海面捞月光。它有八只手，每只都拿一个不同的乐器。月圆的夜晚，海风里就是它在唱摇篮曲。", "character_kraken"),
                MonsterEntry("jellyfish", "Jellyfish", "水晶漂漂", "水母像一盏会游泳的小灯，慢慢飘过蓝色海草。它喜欢收集亮晶晶的泡泡，排成一串给迷路的小鱼照路。", "character_jellyfish"),
                MonsterEntry("goblin-scout", "Goblin Scout", "绿帽侦察员", "哥布林侦察员背着小木望远镜，专门在草丛里寻找掉队的纽扣。它走路很轻，发现朋友时会挥动绿帽子打招呼。", "character_goblin_scout"),
                MonsterEntry("mushroom-sprite", "Mushroom Sprite", "蘑菇小灵", "蘑菇小灵住在红伞菇下面，雨后会把露珠擦得亮亮的。它说话声音很小，却能让整片草地都闻到甜甜的泥土香。", "character_mushroom_sprite"),
                MonsterEntry("moss-troll", "Moss Troll", "苔藓巨友", "苔藓巨友个子很大，脚步却像棉花一样轻。它背上长着小花和青苔，最喜欢让小鸟停在肩膀上讲故事。", "character_moss_troll"),
                MonsterEntry("pebble-golem", "Pebble Golem", "小石守卫", "小石守卫由许多圆圆的鹅卵石拼成，走一步就叮当响。它会把路边的小石子排成箭头，帮冒险者找到回家的路。", "character_pebble_golem"),
                MonsterEntry("lantern-wisp", "Lantern Wisp", "灯火微光", "灯火微光像一团会害羞的金色小火苗，住在玻璃灯笼里。夜晚它会轻轻闪烁，提醒大家慢慢走不要摔跤。", "character_lantern_wisp"),
                MonsterEntry("crystal-bat", "Crystal Bat", "水晶蝙蝠", "水晶蝙蝠有透明的小翅膀，飞过洞穴时会发出叮铃声。它不喜欢吓人，只爱把回声唱成短短的歌。", "character_crystal_bat"),
                MonsterEntry("cloud-griffin", "Cloud Griffin", "云朵狮鹫", "云朵狮鹫的翅膀像两片白云，爪子踩到地上几乎没有声音。它每天负责把乱跑的云宝宝送回天空队伍。", "character_cloud_griffin"),
                MonsterEntry("river-nymph", "River Nymph", "溪水歌手", "溪水歌手坐在圆石头上练习发音，尾音会变成一圈圈小水纹。她会把漂来的落叶折成小船，送给路过的孩子。", "character_river_nymph"),
                MonsterEntry("forest-satyr", "Forest Satyr", "林笛小羊", "林笛小羊有弯弯的小角和毛茸茸的蹄子，随身带着木笛。它吹出的旋律能让树叶一起拍手。", "character_forest_satyr"),
                MonsterEntry("berry-imp", "Berry Imp", "莓果小妖", "莓果小妖总把红莓当帽子戴，口袋里塞满酸甜果子。它很爱分享，只是每次递果子前都要先数三遍。", "character_berry_imp"),
                MonsterEntry("cave-molekin", "Cave Molekin", "洞穴鼹仔", "洞穴鼹仔戴着圆圆矿灯，鼻子能闻到新鲜泥土的方向。它挖洞时会把墙壁磨得很光滑，像地下滑梯。", "character_cave_molekin"),
                MonsterEntry("clockwork-beetle", "Clockwork Beetle", "齿轮甲虫", "齿轮甲虫背上有会转的小发条，走路时滴答滴答。它喜欢修理坏掉的门铃，也会给花朵准时报时。", "character_clockwork_beetle"),
                MonsterEntry("book-mimic", "Book Mimic", "会笑的书", "会笑的书喜欢假装自己是普通故事书，等朋友靠近才翻开第一页。它的书页会轻轻挥手，里面全是温柔的谜语。", "character_book_mimic"),
                MonsterEntry("treasure-mimic", "Treasure Mimic", "宝箱伙伴", "宝箱伙伴长着一排圆圆小牙，其实只用来咬苹果。它肚子里装的不是金币，而是彩色贴纸和备用铅笔。", "character_treasure_mimic"),
                MonsterEntry("rune-tortoise", "Rune Tortoise", "符文慢龟", "符文慢龟壳上刻着会发光的字母，走得慢却记性特别好。它愿意停下来听每个人把单词读完。", "character_rune_tortoise"),
                MonsterEntry("mirror-sprite", "Mirror Sprite", "镜光精灵", "镜光精灵住在一面小圆镜里，最会模仿大家的表情。它每天把笑脸擦亮，让经过的人都能看到勇敢的自己。", "character_mirror_sprite"),
                MonsterEntry("candle-ghost", "Candle Ghost", "烛光小幽", "烛光小幽是一朵温暖的小影子，头顶有不会烫人的烛火。它最怕黑，所以总是把走廊照得亮亮的。", "character_candle_ghost"),
                MonsterEntry("paper-gargoyle", "Paper Gargoyle", "纸翼守像", "纸翼守像看起来像石像，其实翅膀是折纸做的。风一吹它就轻轻飞起，帮图书馆把书签送回书里。", "character_paper_gargoyle"),
                MonsterEntry("marble-golem", "Marble Golem", "大理石朋友", "大理石朋友身上有漂亮的云纹，喜欢站在喷泉旁边听水声。它会把重重的门推开，让小朋友先通过。", "character_marble_golem"),
                MonsterEntry("harpy-bard", "Harpy Bard", "羽翼歌手", "羽翼歌手有彩色翅膀和小竖琴，唱歌时羽毛会轻轻发亮。她喜欢把难读的单词编进旋律里。", "character_harpy_bard"),
                MonsterEntry("feather-drake", "Feather Drake", "羽毛小龙", "羽毛小龙不喷火，只会喷出一串轻飘飘的羽毛。它把羽毛收进枕头里，送给需要午睡的小动物。", "character_feather_drake"),
                MonsterEntry("tiny-wyvern", "Tiny Wyvern", "小翼龙", "小翼龙只有茶杯那么大，却总想练习英雄式降落。它会把翅膀展开成斗篷，认真保护一颗小石头。", "character_tiny_wyvern"),
                MonsterEntry("basilisk-buddy", "Basilisk Buddy", "眨眼蜥友", "眨眼蜥友有亮亮的大眼睛，但它看人时只会让人想笑。它练习眨眼比赛，赢了也会把奖牌分给朋友。", "character_basilisk_buddy"),
                MonsterEntry("chimera-cub", "Chimera Cub", "拼拼幼兽", "拼拼幼兽像把几种小动物的可爱部分拼在一起。它每天研究自己的尾巴，猜今天会不会打个蝴蝶结。", "character_chimera_cub"),
                MonsterEntry("manticore-kit", "Manticore Kit", "软刺小兽", "软刺小兽尾巴末端像一朵毛球花，完全不会扎人。它喜欢把尾巴当画笔，在沙地上画笑脸。", "character_manticore_kit"),
                MonsterEntry("hippogriff", "Hippogriff", "礼貌鹰马", "礼貌鹰马见面前一定会先点头，翅膀收得整整齐齐。它跑起来像风，停下来却会等最慢的朋友。", "character_hippogriff"),
                MonsterEntry("pegasus", "Pegasus", "白云飞马", "白云飞马的蹄子踩过天空会留下小星点。它喜欢载着信件飞过彩虹，把鼓励的话送到窗边。", "character_pegasus"),
                MonsterEntry("moon-moth", "Moon Moth", "月光飞蛾", "月光飞蛾的翅膀像两片小月亮，夜里会安静地发光。它最爱围着睡前故事转圈，让房间变得柔柔的。", "character_moon_moth"),
                MonsterEntry("star-hare", "Star Hare", "星星野兔", "星星野兔跳一下，耳朵上的小星点就亮一下。它跑得很快，却总会回头等忘记带铅笔的朋友。", "character_star_hare"),
                MonsterEntry("fire-elemental", "Fire Elemental", "暖焰小灵", "暖焰小灵像一团会跳舞的篝火，靠近时只会觉得手心暖暖的。它负责给露营队点亮晚餐灯。", "character_fire_elemental"),
                MonsterEntry("water-elemental", "Water Elemental", "水滴小灵", "水滴小灵身体透明得像一颗大水珠，走路会留下小小涟漪。它会把花园里口渴的花一朵朵浇醒。", "character_water_elemental"),
                MonsterEntry("leaf-elemental", "Leaf Elemental", "叶风小灵", "叶风小灵的身体由许多叶片组成，转身时像一阵绿色旋风。它会把掉落的叶子排成漂亮书签。", "character_leaf_elemental"),
                MonsterEntry("earth-elemental", "Earth Elemental", "泥土小灵", "泥土小灵有圆圆的泥土手臂，头上长着一棵小苗。它每天把松软的土拍平，给种子盖好被子。", "character_earth_elemental"),
                MonsterEntry("air-elemental", "Air Elemental", "清风小灵", "清风小灵像一条会笑的丝带，飘来飘去不碰倒任何东西。它把风筝托得高高的，也把纸飞机送回手里。", "character_air_elemental"),
                MonsterEntry("ice-sprite", "Ice Sprite", "冰晶小灵", "冰晶小灵住在雪花中央，说话会叮叮响。它能在窗上画出小花，但太阳出来前会自己擦干净。", "character_ice_sprite"),
                MonsterEntry("thunder-pup", "Thunder Pup", "雷声小狗", "雷声小狗打哈欠时会发出小小轰隆声，却一点也不吓人。它摇尾巴能点亮云朵边上的金线。", "character_thunder_pup"),
                MonsterEntry("rainbow-serpent", "Rainbow Serpent", "彩虹小蛇", "彩虹小蛇身上的颜色会慢慢流动，像一条弯弯的彩带。它从不咬人，只用尾巴给朋友指路。", "character_rainbow_serpent"),
                MonsterEntry("sun-lion", "Sun Lion", "太阳狮子", "太阳狮子的鬃毛像一圈暖暖的阳光，午后会变得特别蓬松。它喜欢趴在草地上守护午睡时间。", "character_sun_lion"),
                MonsterEntry("moon-owl", "Moon Owl", "月亮猫头鹰", "月亮猫头鹰戴着小圆眼镜，翅膀上有银色月纹。它夜里帮星星排队，白天就在树洞里睡觉。", "character_moon_owl"),
                MonsterEntry("coral-crab", "Coral Crab", "珊瑚小蟹", "珊瑚小蟹背着一小丛彩色珊瑚，横着走也从不迷路。它用钳子轻轻敲贝壳，给海浪打节拍。", "character_coral_crab"),
                MonsterEntry("seahorse-knight", "Seahorse Knight", "海马骑士", "海马骑士穿着贝壳盔甲，长枪其实是一根海草。它巡逻时会向每条小鱼敬礼，样子特别认真。", "character_seahorse_knight"),
                MonsterEntry("bubble-turtle", "Bubble Turtle", "泡泡海龟", "泡泡海龟会吹出不会破的大泡泡，小鱼可以躲进去玩捉迷藏。它游得很慢，却总能准时到达。", "character_bubble_turtle"),
                MonsterEntry("pearl-mermaid", "Pearl Mermaid", "珍珠人鱼", "珍珠人鱼把海星当发夹，唱歌时会有小珍珠滚进贝壳。她喜欢教螃蟹排队，也喜欢听孩子读新词。", "character_pearl_mermaid"),
                MonsterEntry("reef-sprite", "Reef Sprite", "礁石小灵", "礁石小灵躲在彩色海葵旁，头发像软软的海草。它每天给珊瑚浇海水，还会把贝壳擦亮。", "character_reef_sprite"),
                MonsterEntry("tide-otter", "Tide Otter", "潮汐水獭", "潮汐水獭抱着一块圆石头，在海面上漂来漂去。它最会收集漂流瓶，把里面的愿望送回岸边。", "character_tide_otter"),
                MonsterEntry("shell-snail", "Shell Snail", "贝壳蜗牛", "贝壳蜗牛背着螺旋海螺屋，走过沙滩会留下闪闪的路线。它不着急，因为沿途每粒沙都值得看看。", "character_shell_snail"),
                MonsterEntry("starfish-wizard", "Starfish Wizard", "海星法师", "海星法师戴着小尖帽，五只手各拿一颗泡泡星。它念咒时泡泡会排成单词，然后啪地变成笑声。", "character_starfish_wizard"),
                MonsterEntry("dolphin-drake", "Dolphin Drake", "海豚小龙", "海豚小龙有海豚的笑脸和小龙的背鳍，跳出水面时会带起彩虹水花。它最喜欢和浪花比赛。", "character_dolphin_drake"),
                MonsterEntry("frost-yeti", "Frost Yeti", "雪山毛友", "雪山毛友全身毛茸茸，脚印像两只大棉拖鞋。它会把热可可捧给登山的小伙伴，还提醒大家戴围巾。", "character_frost_yeti"),
                MonsterEntry("snow-goblin", "Snow Goblin", "雪球哥布林", "雪球哥布林把雪球当背包，里面藏着胡萝卜鼻子和备用手套。它会认真修补雪人，直到每个雪人都笑起来。", "character_snow_goblin"),
                MonsterEntry("icicle-imp", "Icicle Imp", "冰柱小妖", "冰柱小妖头上挂着透明冰帽，走路会发出清脆铃声。它喜欢把冰柱排成风铃，送给北风当礼物。", "character_icicle_imp"),
                MonsterEntry("aurora-fox", "Aurora Fox", "极光狐狸", "极光狐狸尾巴像一条会发光的彩带，跑过雪地时天空也会跟着变亮。它会带迷路的人找到温暖木屋。", "character_aurora_fox"),
                MonsterEntry("polar-golem", "Polar Golem", "极地石守", "极地石守由圆冰石组成，胸口有一盏小蓝灯。它站在风雪里给大家挡风，自己却只觉得凉快。", "character_polar_golem"),
                MonsterEntry("cloud-giant", "Cloud Giant", "云端巨人", "云端巨人把云朵当枕头，打喷嚏会吹出一群小白羊云。它声音很低，却总是轻轻说话怕吓到鸟。", "character_cloud_giant"),
                MonsterEntry("sky-whale", "Sky Whale", "天空鲸鱼", "天空鲸鱼慢慢游过蓝天，肚子下面挂着几颗小星铃。它唱歌时，云朵会排成柔软的楼梯。", "character_sky_whale"),
                MonsterEntry("wind-djinn", "Wind Djinn", "旋风精灵", "旋风精灵住在一只小瓶子里，出来时会变成卷卷的清风。它最会吹干湿袜子，也会帮风车转圈。", "character_wind_djinn"),
                MonsterEntry("storm-sprite", "Storm Sprite", "雨云小灵", "雨云小灵穿着小雨衣，随身带一把迷你闪电伞。它会把大雨分成小雨滴，让花园慢慢喝水。", "character_storm_sprite"),
                MonsterEntry("comet-dragon", "Comet Dragon", "彗星小龙", "彗星小龙尾巴后面拖着星尘，飞过夜空像一支亮亮的铅笔。它会在天空写下晚安两个字。", "character_comet_dragon"),
                MonsterEntry("sand-gnome", "Sand Gnome", "沙丘地精", "沙丘地精戴着宽宽的遮阳帽，胡子里总有几粒闪亮细沙。它会用小铲子堆城堡，还给每座城堡插旗。", "character_sand_gnome"),
                MonsterEntry("cactus-imp", "Cactus Imp", "仙人掌小妖", "仙人掌小妖身上长着软软的小刺，抱起来像毛线球。它每天给自己浇一滴水，然后开心地开一朵小花。", "character_cactus_imp"),
                MonsterEntry("sphinx-cub", "Sphinx Cub", "谜语狮崽", "谜语狮崽喜欢坐在小石台上问简单问题。答对了它会眯眼点头，答错了也会给一个提示。", "character_sphinx_cub"),
                MonsterEntry("scarab-knight", "Scarab Knight", "甲虫骑士", "甲虫骑士穿着亮亮的壳甲，盾牌像一颗小太阳。它很守规矩，过桥前一定排队。", "character_scarab_knight"),
                MonsterEntry("mirage-cat", "Mirage Cat", "海市蜃猫", "海市蜃猫走路像一阵热风，影子会慢半拍跟上来。它喜欢躲猫猫，但尾巴上的铃铛总会泄密。", "character_mirage_cat"),
                MonsterEntry("sun-salamander", "Sun Salamander", "阳光蝾螈", "阳光蝾螈趴在暖石头上晒太阳，背上有小小太阳斑。它会把冷掉的面包轻轻烤热。", "character_sun_salamander"),
                MonsterEntry("dust-whirl", "Dust Whirl", "沙卷小旋", "沙卷小旋像一团会跳舞的小龙卷，转起来却不会弄脏衣服。它负责把沙地上的脚印扫成花纹。", "character_dust_whirl"),
                MonsterEntry("oasis-frog", "Oasis Frog", "绿洲青蛙", "绿洲青蛙坐在荷叶伞下，口袋里装着清凉薄荷叶。它叫一声，水面就会冒出圆圆泡泡。", "character_oasis_frog"),
                MonsterEntry("pyramid-sprite", "Pyramid Sprite", "金塔小灵", "金塔小灵住在小小金字塔顶端，负责擦亮星光入口。它最爱把沙粒排成箭头，帮旅人绕开热石头。", "character_pyramid_sprite"),
                MonsterEntry("ember-fox", "Ember Fox", "余烬狐狸", "余烬狐狸的尾巴像一串温暖炭火，跑步时只留下淡淡金光。它会帮露营的小朋友看好篝火。", "character_ember_fox"),
                MonsterEntry("lava-toad", "Lava Toad", "熔岩圆蛙", "熔岩圆蛙坐在温热岩石上，肚子一鼓一鼓像小灯笼。它只会吐出暖气泡，给冷手取暖。", "character_lava_toad"),
                MonsterEntry("ash-golem", "Ash Golem", "灰烬守卫", "灰烬守卫由软软的灰云和黑石块组成，动作慢慢的。它会把熄灭的火堆整理干净，留下安全的营地。", "character_ash_golem"),
                MonsterEntry("cinder-bat", "Cinder Bat", "火星蝙蝠", "火星蝙蝠翅膀边缘亮着小火星，飞起来像夜空里的逗号。它会把火星收进小罐子，照亮回家的路。", "character_cinder_bat"),
                MonsterEntry("spark-sprite", "Spark Sprite", "火花小灵", "火花小灵像一颗淘气的小星星，笑起来会蹦出金色火花。它总把火花变成烟花，但声音只有噗的一下。", "character_spark_sprite"),
                MonsterEntry("flame-pony", "Flame Pony", "焰鬃小马", "焰鬃小马有柔软的火焰鬃毛，摸起来像晒过太阳的毛毯。它跑过原野时，会给露珠镀上一层金边。", "character_flame_pony"),
                MonsterEntry("molten-snail", "Molten Snail", "暖壳蜗牛", "暖壳蜗牛背着像小火山的壳，里面只冒温柔热气。它走得慢，适合陪大家练习耐心。", "character_molten_snail"),
                MonsterEntry("briar-wolf", "Briar Wolf", "蔷薇小狼", "蔷薇小狼的毛里夹着柔软花瓣，鼻子总能闻到新开的花。它嚎叫时不像狼，更像在唱摇篮曲。", "character_briar_wolf"),
                MonsterEntry("acorn-knight", "Acorn Knight", "橡果骑士", "橡果骑士戴着橡果头盔，盾牌是一片圆圆树叶。它个子很小，却坚持护送蚂蚁队伍过小溪。", "character_acorn_knight"),
                MonsterEntry("honey-bear", "Honey Bear", "蜂蜜小熊", "蜂蜜小熊背着一只小蜂蜜罐，走到哪里都香香甜甜。它会把蜂蜜分给咳嗽的朋友，还给蜜蜂说谢谢。", "character_honey_bear"),
                MonsterEntry("thorn-dryad", "Thorn Dryad", "柔刺树灵", "柔刺树灵的头发像藤蔓，刺尖都包着小叶子。她守护花园入口，提醒大家轻轻走路别踩幼苗。", "character_thorn_dryad"),
                MonsterEntry("willow-treant", "Willow Treant", "柳树长者", "柳树长者的枝条像长长胡须，说话慢得像摇篮曲。它喜欢把阴凉借给读书的孩子，也听鸟儿汇报天气。", "character_willow_treant"),
                MonsterEntry("pollen-pixie", "Pollen Pixie", "花粉小仙", "花粉小仙背着透明翅膀，飞过花朵时会打一个小喷嚏。她把花粉撒得刚刚好，让每朵花都精神起来。", "character_pollen_pixie"),
                MonsterEntry("clover-kobold", "Clover Kobold", "四叶小怪", "四叶小怪喜欢把幸运草别在耳朵后面，收集掉落的鞋带。它很会打结，能把礼物绑得漂漂亮亮。", "character_clover_kobold"),
                MonsterEntry("fern-lizard", "Fern Lizard", "蕨叶蜥蜴", "蕨叶蜥蜴背上长着一排小蕨叶，趴在树根旁几乎看不见。它喜欢玩安静的捉迷藏，找到后会眨眨眼。", "character_fern_lizard"),
                MonsterEntry("toadstool-ogre", "Toadstool Ogre", "菇帽大友", "菇帽大友虽然叫大怪，其实只爱搬重篮子。它戴着大蘑菇帽，走进森林时会弯腰不碰小树枝。", "character_toadstool_ogre"),
                MonsterEntry("toy-soldier", "Toy Soldier", "玩具小兵", "玩具小兵站得笔直，鼓声一响就迈开短短步子。它守护玩具箱，晚上还会帮散落的积木排队。", "character_toy_soldier"),
                MonsterEntry("porcelain-doll", "Porcelain Doll", "瓷娃娃守护", "瓷娃娃守护穿着小披肩，脸上永远是温柔微笑。她会把掉在地上的缎带捡起来，系成漂亮蝴蝶结。", "character_porcelain_doll"),
                MonsterEntry("button-golem", "Button Golem", "纽扣魔像", "纽扣魔像由各种圆纽扣拼成，胸口最大那颗会闪光。它最擅长修补外套，让每颗纽扣都回到位置。", "character_button_golem"),
                MonsterEntry("sock-dragon", "Sock Dragon", "袜子小龙", "袜子小龙喜欢把丢失的袜子卷成小窝，打喷嚏会喷出棉絮云。它能帮大家找到另一只袜子。", "character_sock_dragon"),
                MonsterEntry("kite-serpent", "Kite Serpent", "风筝长蛇", "风筝长蛇身体像彩色风筝串，尾巴系着长长飘带。它飞得很高，却总把线交给最小的朋友握着。", "character_kite_serpent"),
                MonsterEntry("music-box-fairy", "Music Box Fairy", "八音盒仙子", "八音盒仙子站在小小发条台上，转一圈就洒出几颗音符星。她的音乐很轻，适合睡前复习单词。", "character_music_box_fairy"),
            ),
        )
    }
}
