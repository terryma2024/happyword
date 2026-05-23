import Foundation

enum MonsterLevel: String, CaseIterable, Equatable {
    case beginner
    case intermediate
    case advanced
    case `super`

    var badgeZh: String {
        switch self {
        case .beginner:
            "初"
        case .intermediate:
            "中"
        case .advanced:
            "高"
        case .super:
            "Super"
        }
    }
}

struct MonsterCodexEntry: Identifiable, Equatable {
    let key: String
    let nameEn: String
    let kindLabelZh: String
    let descriptionZh: String
    let assetName: String

    var id: String { key }
    var level: MonsterLevel { MonsterCodex.level(forKey: key) }
    var levelBadgeZh: String { level.badgeZh }
}

enum MonsterCodex {
    static let entries: [MonsterCodexEntry] = [
        MonsterCodexEntry(
            key: "slime",
            nameEn: "Slime",
            kindLabelZh: "普通怪物",
            descriptionZh: "Slime 是一只软软的小精灵，整天住在森林深处的青草丛里。它最喜欢的事情就是在月光下打滚，把身体滚得圆圆的。它见到谁都会咧开大嘴笑一笑，从来不会真的生气。",
            assetName: "CharacterSlime"
        ),
        MonsterCodexEntry(
            key: "zombie",
            nameEn: "Zombie",
            kindLabelZh: "拼写专家",
            descriptionZh: "Zombie 来自一座很老很老的图书馆，他喜欢把翻烂的书页披在身上当披风。他口袋里装满了散落一地的字母，每天都要把它们重新摆一摆。他看起来有点呆呆的，其实只是太爱发呆。",
            assetName: "CharacterZombie"
        ),
        MonsterCodexEntry(
            key: "dragon",
            nameEn: "Dragon",
            kindLabelZh: "精英挑战者",
            descriptionZh: "Dragon 是住在云朵后面的一只老巨龙，鳞片闪着金色的光。他大部分时间都在睡觉，一觉就是一百年。打喷嚏的时候会喷出小小的火苗，把天上的云染成漂亮的橘红色。",
            assetName: "CharacterDragon"
        ),
        MonsterCodexEntry(
            key: "pumpkin-king",
            nameEn: "Pumpkin King",
            kindLabelZh: "秋夜灯王",
            descriptionZh: "南瓜王戴着藤蔓皇冠，住在最大的那个南瓜里面。每到秋天他就把灯一盏一盏点起来，让回家的小孩不会迷路。他的笑声脆脆的，像踩在落叶上。",
            assetName: "CharacterPumpkinKing"
        ),
        MonsterCodexEntry(
            key: "imp-king",
            nameEn: "Imp King",
            kindLabelZh: "林间舞者",
            descriptionZh: "小妖王是个赤脚的小胖精灵，戴一顶蘑菇帽。森林里所有的萤火虫都听他的口令。傍晚他敲敲蘑菇，全林子的小妖就出来跟他绕着大树跳舞。",
            assetName: "CharacterImpKing"
        ),
        MonsterCodexEntry(
            key: "phoenix",
            nameEn: "Phoenix",
            kindLabelZh: "火羽之灵",
            descriptionZh: "凤凰是一只长着金色尾羽的大鸟，住在最高的果园树梢。每天清晨翅膀一拍就把太阳唤醒。羽毛掉下来就变成秋叶，谁捡到都会觉得手心暖暖的。",
            assetName: "CharacterPhoenix"
        ),
        MonsterCodexEntry(
            key: "witch",
            nameEn: "Witch",
            kindLabelZh: "夜空魔法师",
            descriptionZh: "女巫住在云海后面的小阁楼里，每天晚上骑着弯月去看星星。她的尖帽子里藏着小书签，权杖头上的星星会自己唱歌。听见小孩笑声会偷偷飞过来一起转圈圈。",
            assetName: "CharacterWitch"
        ),
        MonsterCodexEntry(
            key: "snow-queen",
            nameEn: "Snow Queen",
            kindLabelZh: "冰雪歌者",
            descriptionZh: "雪女王披着透明的冰纱，唱起歌来就有大片大片的雪花飘下来。她特别爱穿越寒夜守护迷路的小动物，把它们送回温暖的洞口才放心地飞回北方。",
            assetName: "CharacterSnowQueen"
        ),
        MonsterCodexEntry(
            key: "unicorn",
            nameEn: "Unicorn",
            kindLabelZh: "彩虹守护",
            descriptionZh: "独角兽走过的地方会留下淡淡的彩虹。它最喜欢小孩子悄悄递来的方糖，吃完会把头低下来让人摸摸鬃毛。它的水晶角能听见星星说悄悄话。",
            assetName: "CharacterUnicorn"
        ),
        MonsterCodexEntry(
            key: "kraken",
            nameEn: "Kraken",
            kindLabelZh: "深海歌唱家",
            descriptionZh: "克拉肯住在很深很深的海底，触手长长地能伸到海面捞月光。它有八只手，每只都拿一个不同的乐器。月圆的夜晚，海风里就是它在唱摇篮曲。",
            assetName: "CharacterKraken"
        ),
        MonsterCodexEntry(
            key: "jellyfish",
            nameEn: "Jellyfish",
            kindLabelZh: "水晶漂漂",
            descriptionZh: "水母像一盏会游泳的小灯，慢慢飘过蓝色海草。它喜欢收集亮晶晶的泡泡，排成一串给迷路的小鱼照路。",
            assetName: "CharacterJellyfish"
        ),
        MonsterCodexEntry(
            key: "goblin-scout",
            nameEn: "Goblin Scout",
            kindLabelZh: "绿帽侦察员",
            descriptionZh: "哥布林侦察员背着小木望远镜，专门在草丛里寻找掉队的纽扣。它走路很轻，发现朋友时会挥动绿帽子打招呼。",
            assetName: "CharacterGoblinScout"
        ),
        MonsterCodexEntry(
            key: "mushroom-sprite",
            nameEn: "Mushroom Sprite",
            kindLabelZh: "蘑菇小灵",
            descriptionZh: "蘑菇小灵住在红伞菇下面，雨后会把露珠擦得亮亮的。它说话声音很小，却能让整片草地都闻到甜甜的泥土香。",
            assetName: "CharacterMushroomSprite"
        ),
        MonsterCodexEntry(
            key: "moss-troll",
            nameEn: "Moss Troll",
            kindLabelZh: "苔藓巨友",
            descriptionZh: "苔藓巨友个子很大，脚步却像棉花一样轻。它背上长着小花和青苔，最喜欢让小鸟停在肩膀上讲故事。",
            assetName: "CharacterMossTroll"
        ),
        MonsterCodexEntry(
            key: "pebble-golem",
            nameEn: "Pebble Golem",
            kindLabelZh: "小石守卫",
            descriptionZh: "小石守卫由许多圆圆的鹅卵石拼成，走一步就叮当响。它会把路边的小石子排成箭头，帮冒险者找到回家的路。",
            assetName: "CharacterPebbleGolem"
        ),
        MonsterCodexEntry(
            key: "lantern-wisp",
            nameEn: "Lantern Wisp",
            kindLabelZh: "灯火微光",
            descriptionZh: "灯火微光像一团会害羞的金色小火苗，住在玻璃灯笼里。夜晚它会轻轻闪烁，提醒大家慢慢走不要摔跤。",
            assetName: "CharacterLanternWisp"
        ),
        MonsterCodexEntry(
            key: "crystal-bat",
            nameEn: "Crystal Bat",
            kindLabelZh: "水晶蝙蝠",
            descriptionZh: "水晶蝙蝠有透明的小翅膀，飞过洞穴时会发出叮铃声。它不喜欢吓人，只爱把回声唱成短短的歌。",
            assetName: "CharacterCrystalBat"
        ),
        MonsterCodexEntry(
            key: "cloud-griffin",
            nameEn: "Cloud Griffin",
            kindLabelZh: "云朵狮鹫",
            descriptionZh: "云朵狮鹫的翅膀像两片白云，爪子踩到地上几乎没有声音。它每天负责把乱跑的云宝宝送回天空队伍。",
            assetName: "CharacterCloudGriffin"
        ),
        MonsterCodexEntry(
            key: "river-nymph",
            nameEn: "River Nymph",
            kindLabelZh: "溪水歌手",
            descriptionZh: "溪水歌手坐在圆石头上练习发音，尾音会变成一圈圈小水纹。她会把漂来的落叶折成小船，送给路过的孩子。",
            assetName: "CharacterRiverNymph"
        ),
        MonsterCodexEntry(
            key: "forest-satyr",
            nameEn: "Forest Satyr",
            kindLabelZh: "林笛小羊",
            descriptionZh: "林笛小羊有弯弯的小角和毛茸茸的蹄子，随身带着木笛。它吹出的旋律能让树叶一起拍手。",
            assetName: "CharacterForestSatyr"
        ),
        MonsterCodexEntry(
            key: "berry-imp",
            nameEn: "Berry Imp",
            kindLabelZh: "莓果小妖",
            descriptionZh: "莓果小妖总把红莓当帽子戴，口袋里塞满酸甜果子。它很爱分享，只是每次递果子前都要先数三遍。",
            assetName: "CharacterBerryImp"
        ),
        MonsterCodexEntry(
            key: "cave-molekin",
            nameEn: "Cave Molekin",
            kindLabelZh: "洞穴鼹仔",
            descriptionZh: "洞穴鼹仔戴着圆圆矿灯，鼻子能闻到新鲜泥土的方向。它挖洞时会把墙壁磨得很光滑，像地下滑梯。",
            assetName: "CharacterCaveMolekin"
        ),
        MonsterCodexEntry(
            key: "clockwork-beetle",
            nameEn: "Clockwork Beetle",
            kindLabelZh: "齿轮甲虫",
            descriptionZh: "齿轮甲虫背上有会转的小发条，走路时滴答滴答。它喜欢修理坏掉的门铃，也会给花朵准时报时。",
            assetName: "CharacterClockworkBeetle"
        ),
        MonsterCodexEntry(
            key: "book-mimic",
            nameEn: "Book Mimic",
            kindLabelZh: "会笑的书",
            descriptionZh: "会笑的书喜欢假装自己是普通故事书，等朋友靠近才翻开第一页。它的书页会轻轻挥手，里面全是温柔的谜语。",
            assetName: "CharacterBookMimic"
        ),
        MonsterCodexEntry(
            key: "treasure-mimic",
            nameEn: "Treasure Mimic",
            kindLabelZh: "宝箱伙伴",
            descriptionZh: "宝箱伙伴长着一排圆圆小牙，其实只用来咬苹果。它肚子里装的不是金币，而是彩色贴纸和备用铅笔。",
            assetName: "CharacterTreasureMimic"
        ),
        MonsterCodexEntry(
            key: "rune-tortoise",
            nameEn: "Rune Tortoise",
            kindLabelZh: "符文慢龟",
            descriptionZh: "符文慢龟壳上刻着会发光的字母，走得慢却记性特别好。它愿意停下来听每个人把单词读完。",
            assetName: "CharacterRuneTortoise"
        ),
        MonsterCodexEntry(
            key: "mirror-sprite",
            nameEn: "Mirror Sprite",
            kindLabelZh: "镜光精灵",
            descriptionZh: "镜光精灵住在一面小圆镜里，最会模仿大家的表情。它每天把笑脸擦亮，让经过的人都能看到勇敢的自己。",
            assetName: "CharacterMirrorSprite"
        ),
        MonsterCodexEntry(
            key: "candle-ghost",
            nameEn: "Candle Ghost",
            kindLabelZh: "烛光小幽",
            descriptionZh: "烛光小幽是一朵温暖的小影子，头顶有不会烫人的烛火。它最怕黑，所以总是把走廊照得亮亮的。",
            assetName: "CharacterCandleGhost"
        ),
        MonsterCodexEntry(
            key: "paper-gargoyle",
            nameEn: "Paper Gargoyle",
            kindLabelZh: "纸翼守像",
            descriptionZh: "纸翼守像看起来像石像，其实翅膀是折纸做的。风一吹它就轻轻飞起，帮图书馆把书签送回书里。",
            assetName: "CharacterPaperGargoyle"
        ),
        MonsterCodexEntry(
            key: "marble-golem",
            nameEn: "Marble Golem",
            kindLabelZh: "大理石朋友",
            descriptionZh: "大理石朋友身上有漂亮的云纹，喜欢站在喷泉旁边听水声。它会把重重的门推开，让小朋友先通过。",
            assetName: "CharacterMarbleGolem"
        ),
        MonsterCodexEntry(
            key: "harpy-bard",
            nameEn: "Harpy Bard",
            kindLabelZh: "羽翼歌手",
            descriptionZh: "羽翼歌手有彩色翅膀和小竖琴，唱歌时羽毛会轻轻发亮。她喜欢把难读的单词编进旋律里。",
            assetName: "CharacterHarpyBard"
        ),
        MonsterCodexEntry(
            key: "feather-drake",
            nameEn: "Feather Drake",
            kindLabelZh: "羽毛小龙",
            descriptionZh: "羽毛小龙不喷火，只会喷出一串轻飘飘的羽毛。它把羽毛收进枕头里，送给需要午睡的小动物。",
            assetName: "CharacterFeatherDrake"
        ),
        MonsterCodexEntry(
            key: "tiny-wyvern",
            nameEn: "Tiny Wyvern",
            kindLabelZh: "小翼龙",
            descriptionZh: "小翼龙只有茶杯那么大，却总想练习英雄式降落。它会把翅膀展开成斗篷，认真保护一颗小石头。",
            assetName: "CharacterTinyWyvern"
        ),
        MonsterCodexEntry(
            key: "basilisk-buddy",
            nameEn: "Basilisk Buddy",
            kindLabelZh: "眨眼蜥友",
            descriptionZh: "眨眼蜥友有亮亮的大眼睛，但它看人时只会让人想笑。它练习眨眼比赛，赢了也会把奖牌分给朋友。",
            assetName: "CharacterBasiliskBuddy"
        ),
        MonsterCodexEntry(
            key: "chimera-cub",
            nameEn: "Chimera Cub",
            kindLabelZh: "拼拼幼兽",
            descriptionZh: "拼拼幼兽像把几种小动物的可爱部分拼在一起。它每天研究自己的尾巴，猜今天会不会打个蝴蝶结。",
            assetName: "CharacterChimeraCub"
        ),
        MonsterCodexEntry(
            key: "manticore-kit",
            nameEn: "Manticore Kit",
            kindLabelZh: "软刺小兽",
            descriptionZh: "软刺小兽尾巴末端像一朵毛球花，完全不会扎人。它喜欢把尾巴当画笔，在沙地上画笑脸。",
            assetName: "CharacterManticoreKit"
        ),
        MonsterCodexEntry(
            key: "hippogriff",
            nameEn: "Hippogriff",
            kindLabelZh: "礼貌鹰马",
            descriptionZh: "礼貌鹰马见面前一定会先点头，翅膀收得整整齐齐。它跑起来像风，停下来却会等最慢的朋友。",
            assetName: "CharacterHippogriff"
        ),
        MonsterCodexEntry(
            key: "pegasus",
            nameEn: "Pegasus",
            kindLabelZh: "白云飞马",
            descriptionZh: "白云飞马的蹄子踩过天空会留下小星点。它喜欢载着信件飞过彩虹，把鼓励的话送到窗边。",
            assetName: "CharacterPegasus"
        ),
        MonsterCodexEntry(
            key: "moon-moth",
            nameEn: "Moon Moth",
            kindLabelZh: "月光飞蛾",
            descriptionZh: "月光飞蛾的翅膀像两片小月亮，夜里会安静地发光。它最爱围着睡前故事转圈，让房间变得柔柔的。",
            assetName: "CharacterMoonMoth"
        ),
        MonsterCodexEntry(
            key: "star-hare",
            nameEn: "Star Hare",
            kindLabelZh: "星星野兔",
            descriptionZh: "星星野兔跳一下，耳朵上的小星点就亮一下。它跑得很快，却总会回头等忘记带铅笔的朋友。",
            assetName: "CharacterStarHare"
        ),
        MonsterCodexEntry(
            key: "fire-elemental",
            nameEn: "Fire Elemental",
            kindLabelZh: "暖焰小灵",
            descriptionZh: "暖焰小灵像一团会跳舞的篝火，靠近时只会觉得手心暖暖的。它负责给露营队点亮晚餐灯。",
            assetName: "CharacterFireElemental"
        ),
        MonsterCodexEntry(
            key: "water-elemental",
            nameEn: "Water Elemental",
            kindLabelZh: "水滴小灵",
            descriptionZh: "水滴小灵身体透明得像一颗大水珠，走路会留下小小涟漪。它会把花园里口渴的花一朵朵浇醒。",
            assetName: "CharacterWaterElemental"
        ),
        MonsterCodexEntry(
            key: "leaf-elemental",
            nameEn: "Leaf Elemental",
            kindLabelZh: "叶风小灵",
            descriptionZh: "叶风小灵的身体由许多叶片组成，转身时像一阵绿色旋风。它会把掉落的叶子排成漂亮书签。",
            assetName: "CharacterLeafElemental"
        ),
        MonsterCodexEntry(
            key: "earth-elemental",
            nameEn: "Earth Elemental",
            kindLabelZh: "泥土小灵",
            descriptionZh: "泥土小灵有圆圆的泥土手臂，头上长着一棵小苗。它每天把松软的土拍平，给种子盖好被子。",
            assetName: "CharacterEarthElemental"
        ),
        MonsterCodexEntry(
            key: "air-elemental",
            nameEn: "Air Elemental",
            kindLabelZh: "清风小灵",
            descriptionZh: "清风小灵像一条会笑的丝带，飘来飘去不碰倒任何东西。它把风筝托得高高的，也把纸飞机送回手里。",
            assetName: "CharacterAirElemental"
        ),
        MonsterCodexEntry(
            key: "ice-sprite",
            nameEn: "Ice Sprite",
            kindLabelZh: "冰晶小灵",
            descriptionZh: "冰晶小灵住在雪花中央，说话会叮叮响。它能在窗上画出小花，但太阳出来前会自己擦干净。",
            assetName: "CharacterIceSprite"
        ),
        MonsterCodexEntry(
            key: "thunder-pup",
            nameEn: "Thunder Pup",
            kindLabelZh: "雷声小狗",
            descriptionZh: "雷声小狗打哈欠时会发出小小轰隆声，却一点也不吓人。它摇尾巴能点亮云朵边上的金线。",
            assetName: "CharacterThunderPup"
        ),
        MonsterCodexEntry(
            key: "rainbow-serpent",
            nameEn: "Rainbow Serpent",
            kindLabelZh: "彩虹小蛇",
            descriptionZh: "彩虹小蛇身上的颜色会慢慢流动，像一条弯弯的彩带。它从不咬人，只用尾巴给朋友指路。",
            assetName: "CharacterRainbowSerpent"
        ),
        MonsterCodexEntry(
            key: "sun-lion",
            nameEn: "Sun Lion",
            kindLabelZh: "太阳狮子",
            descriptionZh: "太阳狮子的鬃毛像一圈暖暖的阳光，午后会变得特别蓬松。它喜欢趴在草地上守护午睡时间。",
            assetName: "CharacterSunLion"
        ),
        MonsterCodexEntry(
            key: "moon-owl",
            nameEn: "Moon Owl",
            kindLabelZh: "月亮猫头鹰",
            descriptionZh: "月亮猫头鹰戴着小圆眼镜，翅膀上有银色月纹。它夜里帮星星排队，白天就在树洞里睡觉。",
            assetName: "CharacterMoonOwl"
        ),
        MonsterCodexEntry(
            key: "coral-crab",
            nameEn: "Coral Crab",
            kindLabelZh: "珊瑚小蟹",
            descriptionZh: "珊瑚小蟹背着一小丛彩色珊瑚，横着走也从不迷路。它用钳子轻轻敲贝壳，给海浪打节拍。",
            assetName: "CharacterCoralCrab"
        ),
        MonsterCodexEntry(
            key: "seahorse-knight",
            nameEn: "Seahorse Knight",
            kindLabelZh: "海马骑士",
            descriptionZh: "海马骑士穿着贝壳盔甲，长枪其实是一根海草。它巡逻时会向每条小鱼敬礼，样子特别认真。",
            assetName: "CharacterSeahorseKnight"
        ),
        MonsterCodexEntry(
            key: "bubble-turtle",
            nameEn: "Bubble Turtle",
            kindLabelZh: "泡泡海龟",
            descriptionZh: "泡泡海龟会吹出不会破的大泡泡，小鱼可以躲进去玩捉迷藏。它游得很慢，却总能准时到达。",
            assetName: "CharacterBubbleTurtle"
        ),
        MonsterCodexEntry(
            key: "pearl-mermaid",
            nameEn: "Pearl Mermaid",
            kindLabelZh: "珍珠人鱼",
            descriptionZh: "珍珠人鱼把海星当发夹，唱歌时会有小珍珠滚进贝壳。她喜欢教螃蟹排队，也喜欢听孩子读新词。",
            assetName: "CharacterPearlMermaid"
        ),
        MonsterCodexEntry(
            key: "reef-sprite",
            nameEn: "Reef Sprite",
            kindLabelZh: "礁石小灵",
            descriptionZh: "礁石小灵躲在彩色海葵旁，头发像软软的海草。它每天给珊瑚浇海水，还会把贝壳擦亮。",
            assetName: "CharacterReefSprite"
        ),
        MonsterCodexEntry(
            key: "tide-otter",
            nameEn: "Tide Otter",
            kindLabelZh: "潮汐水獭",
            descriptionZh: "潮汐水獭抱着一块圆石头，在海面上漂来漂去。它最会收集漂流瓶，把里面的愿望送回岸边。",
            assetName: "CharacterTideOtter"
        ),
        MonsterCodexEntry(
            key: "shell-snail",
            nameEn: "Shell Snail",
            kindLabelZh: "贝壳蜗牛",
            descriptionZh: "贝壳蜗牛背着螺旋海螺屋，走过沙滩会留下闪闪的路线。它不着急，因为沿途每粒沙都值得看看。",
            assetName: "CharacterShellSnail"
        ),
        MonsterCodexEntry(
            key: "starfish-wizard",
            nameEn: "Starfish Wizard",
            kindLabelZh: "海星法师",
            descriptionZh: "海星法师戴着小尖帽，五只手各拿一颗泡泡星。它念咒时泡泡会排成单词，然后啪地变成笑声。",
            assetName: "CharacterStarfishWizard"
        ),
        MonsterCodexEntry(
            key: "dolphin-drake",
            nameEn: "Dolphin Drake",
            kindLabelZh: "海豚小龙",
            descriptionZh: "海豚小龙有海豚的笑脸和小龙的背鳍，跳出水面时会带起彩虹水花。它最喜欢和浪花比赛。",
            assetName: "CharacterDolphinDrake"
        ),
        MonsterCodexEntry(
            key: "frost-yeti",
            nameEn: "Frost Yeti",
            kindLabelZh: "雪山毛友",
            descriptionZh: "雪山毛友全身毛茸茸，脚印像两只大棉拖鞋。它会把热可可捧给登山的小伙伴，还提醒大家戴围巾。",
            assetName: "CharacterFrostYeti"
        ),
        MonsterCodexEntry(
            key: "snow-goblin",
            nameEn: "Snow Goblin",
            kindLabelZh: "雪球哥布林",
            descriptionZh: "雪球哥布林把雪球当背包，里面藏着胡萝卜鼻子和备用手套。它会认真修补雪人，直到每个雪人都笑起来。",
            assetName: "CharacterSnowGoblin"
        ),
        MonsterCodexEntry(
            key: "icicle-imp",
            nameEn: "Icicle Imp",
            kindLabelZh: "冰柱小妖",
            descriptionZh: "冰柱小妖头上挂着透明冰帽，走路会发出清脆铃声。它喜欢把冰柱排成风铃，送给北风当礼物。",
            assetName: "CharacterIcicleImp"
        ),
        MonsterCodexEntry(
            key: "aurora-fox",
            nameEn: "Aurora Fox",
            kindLabelZh: "极光狐狸",
            descriptionZh: "极光狐狸尾巴像一条会发光的彩带，跑过雪地时天空也会跟着变亮。它会带迷路的人找到温暖木屋。",
            assetName: "CharacterAuroraFox"
        ),
        MonsterCodexEntry(
            key: "polar-golem",
            nameEn: "Polar Golem",
            kindLabelZh: "极地石守",
            descriptionZh: "极地石守由圆冰石组成，胸口有一盏小蓝灯。它站在风雪里给大家挡风，自己却只觉得凉快。",
            assetName: "CharacterPolarGolem"
        ),
        MonsterCodexEntry(
            key: "cloud-giant",
            nameEn: "Cloud Giant",
            kindLabelZh: "云端巨人",
            descriptionZh: "云端巨人把云朵当枕头，打喷嚏会吹出一群小白羊云。它声音很低，却总是轻轻说话怕吓到鸟。",
            assetName: "CharacterCloudGiant"
        ),
        MonsterCodexEntry(
            key: "sky-whale",
            nameEn: "Sky Whale",
            kindLabelZh: "天空鲸鱼",
            descriptionZh: "天空鲸鱼慢慢游过蓝天，肚子下面挂着几颗小星铃。它唱歌时，云朵会排成柔软的楼梯。",
            assetName: "CharacterSkyWhale"
        ),
        MonsterCodexEntry(
            key: "wind-djinn",
            nameEn: "Wind Djinn",
            kindLabelZh: "旋风精灵",
            descriptionZh: "旋风精灵住在一只小瓶子里，出来时会变成卷卷的清风。它最会吹干湿袜子，也会帮风车转圈。",
            assetName: "CharacterWindDjinn"
        ),
        MonsterCodexEntry(
            key: "storm-sprite",
            nameEn: "Storm Sprite",
            kindLabelZh: "雨云小灵",
            descriptionZh: "雨云小灵穿着小雨衣，随身带一把迷你闪电伞。它会把大雨分成小雨滴，让花园慢慢喝水。",
            assetName: "CharacterStormSprite"
        ),
        MonsterCodexEntry(
            key: "comet-dragon",
            nameEn: "Comet Dragon",
            kindLabelZh: "彗星小龙",
            descriptionZh: "彗星小龙尾巴后面拖着星尘，飞过夜空像一支亮亮的铅笔。它会在天空写下晚安两个字。",
            assetName: "CharacterCometDragon"
        ),
        MonsterCodexEntry(
            key: "sand-gnome",
            nameEn: "Sand Gnome",
            kindLabelZh: "沙丘地精",
            descriptionZh: "沙丘地精戴着宽宽的遮阳帽，胡子里总有几粒闪亮细沙。它会用小铲子堆城堡，还给每座城堡插旗。",
            assetName: "CharacterSandGnome"
        ),
        MonsterCodexEntry(
            key: "cactus-imp",
            nameEn: "Cactus Imp",
            kindLabelZh: "仙人掌小妖",
            descriptionZh: "仙人掌小妖身上长着软软的小刺，抱起来像毛线球。它每天给自己浇一滴水，然后开心地开一朵小花。",
            assetName: "CharacterCactusImp"
        ),
        MonsterCodexEntry(
            key: "sphinx-cub",
            nameEn: "Sphinx Cub",
            kindLabelZh: "谜语狮崽",
            descriptionZh: "谜语狮崽喜欢坐在小石台上问简单问题。答对了它会眯眼点头，答错了也会给一个提示。",
            assetName: "CharacterSphinxCub"
        ),
        MonsterCodexEntry(
            key: "scarab-knight",
            nameEn: "Scarab Knight",
            kindLabelZh: "甲虫骑士",
            descriptionZh: "甲虫骑士穿着亮亮的壳甲，盾牌像一颗小太阳。它很守规矩，过桥前一定排队。",
            assetName: "CharacterScarabKnight"
        ),
        MonsterCodexEntry(
            key: "mirage-cat",
            nameEn: "Mirage Cat",
            kindLabelZh: "海市蜃猫",
            descriptionZh: "海市蜃猫走路像一阵热风，影子会慢半拍跟上来。它喜欢躲猫猫，但尾巴上的铃铛总会泄密。",
            assetName: "CharacterMirageCat"
        ),
        MonsterCodexEntry(
            key: "sun-salamander",
            nameEn: "Sun Salamander",
            kindLabelZh: "阳光蝾螈",
            descriptionZh: "阳光蝾螈趴在暖石头上晒太阳，背上有小小太阳斑。它会把冷掉的面包轻轻烤热。",
            assetName: "CharacterSunSalamander"
        ),
        MonsterCodexEntry(
            key: "dust-whirl",
            nameEn: "Dust Whirl",
            kindLabelZh: "沙卷小旋",
            descriptionZh: "沙卷小旋像一团会跳舞的小龙卷，转起来却不会弄脏衣服。它负责把沙地上的脚印扫成花纹。",
            assetName: "CharacterDustWhirl"
        ),
        MonsterCodexEntry(
            key: "oasis-frog",
            nameEn: "Oasis Frog",
            kindLabelZh: "绿洲青蛙",
            descriptionZh: "绿洲青蛙坐在荷叶伞下，口袋里装着清凉薄荷叶。它叫一声，水面就会冒出圆圆泡泡。",
            assetName: "CharacterOasisFrog"
        ),
        MonsterCodexEntry(
            key: "pyramid-sprite",
            nameEn: "Pyramid Sprite",
            kindLabelZh: "金塔小灵",
            descriptionZh: "金塔小灵住在小小金字塔顶端，负责擦亮星光入口。它最爱把沙粒排成箭头，帮旅人绕开热石头。",
            assetName: "CharacterPyramidSprite"
        ),
        MonsterCodexEntry(
            key: "ember-fox",
            nameEn: "Ember Fox",
            kindLabelZh: "余烬狐狸",
            descriptionZh: "余烬狐狸的尾巴像一串温暖炭火，跑步时只留下淡淡金光。它会帮露营的小朋友看好篝火。",
            assetName: "CharacterEmberFox"
        ),
        MonsterCodexEntry(
            key: "lava-toad",
            nameEn: "Lava Toad",
            kindLabelZh: "熔岩圆蛙",
            descriptionZh: "熔岩圆蛙坐在温热岩石上，肚子一鼓一鼓像小灯笼。它只会吐出暖气泡，给冷手取暖。",
            assetName: "CharacterLavaToad"
        ),
        MonsterCodexEntry(
            key: "ash-golem",
            nameEn: "Ash Golem",
            kindLabelZh: "灰烬守卫",
            descriptionZh: "灰烬守卫由软软的灰云和黑石块组成，动作慢慢的。它会把熄灭的火堆整理干净，留下安全的营地。",
            assetName: "CharacterAshGolem"
        ),
        MonsterCodexEntry(
            key: "cinder-bat",
            nameEn: "Cinder Bat",
            kindLabelZh: "火星蝙蝠",
            descriptionZh: "火星蝙蝠翅膀边缘亮着小火星，飞起来像夜空里的逗号。它会把火星收进小罐子，照亮回家的路。",
            assetName: "CharacterCinderBat"
        ),
        MonsterCodexEntry(
            key: "spark-sprite",
            nameEn: "Spark Sprite",
            kindLabelZh: "火花小灵",
            descriptionZh: "火花小灵像一颗淘气的小星星，笑起来会蹦出金色火花。它总把火花变成烟花，但声音只有噗的一下。",
            assetName: "CharacterSparkSprite"
        ),
        MonsterCodexEntry(
            key: "flame-pony",
            nameEn: "Flame Pony",
            kindLabelZh: "焰鬃小马",
            descriptionZh: "焰鬃小马有柔软的火焰鬃毛，摸起来像晒过太阳的毛毯。它跑过原野时，会给露珠镀上一层金边。",
            assetName: "CharacterFlamePony"
        ),
        MonsterCodexEntry(
            key: "molten-snail",
            nameEn: "Molten Snail",
            kindLabelZh: "暖壳蜗牛",
            descriptionZh: "暖壳蜗牛背着像小火山的壳，里面只冒温柔热气。它走得慢，适合陪大家练习耐心。",
            assetName: "CharacterMoltenSnail"
        ),
        MonsterCodexEntry(
            key: "briar-wolf",
            nameEn: "Briar Wolf",
            kindLabelZh: "蔷薇小狼",
            descriptionZh: "蔷薇小狼的毛里夹着柔软花瓣，鼻子总能闻到新开的花。它嚎叫时不像狼，更像在唱摇篮曲。",
            assetName: "CharacterBriarWolf"
        ),
        MonsterCodexEntry(
            key: "acorn-knight",
            nameEn: "Acorn Knight",
            kindLabelZh: "橡果骑士",
            descriptionZh: "橡果骑士戴着橡果头盔，盾牌是一片圆圆树叶。它个子很小，却坚持护送蚂蚁队伍过小溪。",
            assetName: "CharacterAcornKnight"
        ),
        MonsterCodexEntry(
            key: "honey-bear",
            nameEn: "Honey Bear",
            kindLabelZh: "蜂蜜小熊",
            descriptionZh: "蜂蜜小熊背着一只小蜂蜜罐，走到哪里都香香甜甜。它会把蜂蜜分给咳嗽的朋友，还给蜜蜂说谢谢。",
            assetName: "CharacterHoneyBear"
        ),
        MonsterCodexEntry(
            key: "thorn-dryad",
            nameEn: "Thorn Dryad",
            kindLabelZh: "柔刺树灵",
            descriptionZh: "柔刺树灵的头发像藤蔓，刺尖都包着小叶子。她守护花园入口，提醒大家轻轻走路别踩幼苗。",
            assetName: "CharacterThornDryad"
        ),
        MonsterCodexEntry(
            key: "willow-treant",
            nameEn: "Willow Treant",
            kindLabelZh: "柳树长者",
            descriptionZh: "柳树长者的枝条像长长胡须，说话慢得像摇篮曲。它喜欢把阴凉借给读书的孩子，也听鸟儿汇报天气。",
            assetName: "CharacterWillowTreant"
        ),
        MonsterCodexEntry(
            key: "pollen-pixie",
            nameEn: "Pollen Pixie",
            kindLabelZh: "花粉小仙",
            descriptionZh: "花粉小仙背着透明翅膀，飞过花朵时会打一个小喷嚏。她把花粉撒得刚刚好，让每朵花都精神起来。",
            assetName: "CharacterPollenPixie"
        ),
        MonsterCodexEntry(
            key: "clover-kobold",
            nameEn: "Clover Kobold",
            kindLabelZh: "四叶小怪",
            descriptionZh: "四叶小怪喜欢把幸运草别在耳朵后面，收集掉落的鞋带。它很会打结，能把礼物绑得漂漂亮亮。",
            assetName: "CharacterCloverKobold"
        ),
        MonsterCodexEntry(
            key: "fern-lizard",
            nameEn: "Fern Lizard",
            kindLabelZh: "蕨叶蜥蜴",
            descriptionZh: "蕨叶蜥蜴背上长着一排小蕨叶，趴在树根旁几乎看不见。它喜欢玩安静的捉迷藏，找到后会眨眨眼。",
            assetName: "CharacterFernLizard"
        ),
        MonsterCodexEntry(
            key: "toadstool-ogre",
            nameEn: "Toadstool Ogre",
            kindLabelZh: "菇帽大友",
            descriptionZh: "菇帽大友虽然叫大怪，其实只爱搬重篮子。它戴着大蘑菇帽，走进森林时会弯腰不碰小树枝。",
            assetName: "CharacterToadstoolOgre"
        ),
        MonsterCodexEntry(
            key: "toy-soldier",
            nameEn: "Toy Soldier",
            kindLabelZh: "玩具小兵",
            descriptionZh: "玩具小兵站得笔直，鼓声一响就迈开短短步子。它守护玩具箱，晚上还会帮散落的积木排队。",
            assetName: "CharacterToySoldier"
        ),
        MonsterCodexEntry(
            key: "porcelain-doll",
            nameEn: "Porcelain Doll",
            kindLabelZh: "瓷娃娃守护",
            descriptionZh: "瓷娃娃守护穿着小披肩，脸上永远是温柔微笑。她会把掉在地上的缎带捡起来，系成漂亮蝴蝶结。",
            assetName: "CharacterPorcelainDoll"
        ),
        MonsterCodexEntry(
            key: "button-golem",
            nameEn: "Button Golem",
            kindLabelZh: "纽扣魔像",
            descriptionZh: "纽扣魔像由各种圆纽扣拼成，胸口最大那颗会闪光。它最擅长修补外套，让每颗纽扣都回到位置。",
            assetName: "CharacterButtonGolem"
        ),
        MonsterCodexEntry(
            key: "sock-dragon",
            nameEn: "Sock Dragon",
            kindLabelZh: "袜子小龙",
            descriptionZh: "袜子小龙喜欢把丢失的袜子卷成小窝，打喷嚏会喷出棉絮云。它能帮大家找到另一只袜子。",
            assetName: "CharacterSockDragon"
        ),
        MonsterCodexEntry(
            key: "kite-serpent",
            nameEn: "Kite Serpent",
            kindLabelZh: "风筝长蛇",
            descriptionZh: "风筝长蛇身体像彩色风筝串，尾巴系着长长飘带。它飞得很高，却总把线交给最小的朋友握着。",
            assetName: "CharacterKiteSerpent"
        ),
        MonsterCodexEntry(
            key: "music-box-fairy",
            nameEn: "Music Box Fairy",
            kindLabelZh: "八音盒仙子",
            descriptionZh: "八音盒仙子站在小小发条台上，转一圈就洒出几颗音符星。她的音乐很轻，适合睡前复习单词。",
            assetName: "CharacterMusicBoxFairy"
        ),
    ]

    static func entry(catalogIndex1Based: Int) -> MonsterCodexEntry {
        guard catalogIndex1Based > 0 else { return entries[0] }
        return entries[(catalogIndex1Based - 1) % entries.count]
    }

    static func level(forCatalogIndex1Based catalogIndex1Based: Int) -> MonsterLevel {
        guard catalogIndex1Based > 0 else { return .beginner }
        let position = (catalogIndex1Based - 1) % 10
        switch position {
        case 0:
            return .beginner
        case 1...6:
            return .intermediate
        case 7...8:
            return .advanced
        default:
            return .super
        }
    }

    static func level(forKey key: String) -> MonsterLevel {
        guard let index = entries.firstIndex(where: { $0.key == key }) else {
            return .beginner
        }
        return level(forCatalogIndex1Based: index + 1)
    }
}
