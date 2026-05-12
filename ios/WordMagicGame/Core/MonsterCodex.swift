import Foundation

struct MonsterCodexEntry: Identifiable, Equatable {
    let key: String
    let nameEn: String
    let kindLabelZh: String
    let descriptionZh: String
    let assetName: String

    var id: String { key }
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
        )
    ]
}
