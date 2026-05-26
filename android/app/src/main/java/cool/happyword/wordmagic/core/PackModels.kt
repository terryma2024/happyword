package cool.happyword.wordmagic.core

enum class PackSource {
    Builtin,
    Global,
    Family,
}

data class SceneMetadata(
    val bgPrimary: String,
    val bgAccent: String,
    val bossName: String,
    val monsterPlan: List<String>,
    val bossCandidates: List<String>,
    val storyZh: String,
)

data class WordPack(
    val id: String,
    val nameEn: String,
    val nameZh: String,
    val source: PackSource,
    val version: Int,
    val publishedAtMs: Long?,
    val scene: SceneMetadata,
    val words: List<WordEntry>,
) {
    init {
        require(id.isNotBlank()) { "pack id is required" }
        require(nameEn.isNotBlank()) { "English pack name is required" }
        require(nameZh.isNotBlank()) { "Chinese pack name is required" }
        require(version >= 1) { "pack version must be positive" }
        require(words.isNotEmpty()) { "pack must include words" }
    }
}

object BuiltinPacks {
    val all: List<WordPack> = listOf(
        pack(
            id = "fruit-forest",
            nameEn = "Fruit Forest",
            nameZh = "水果森林",
            storyZh = "藤蔓和果香里的第一场魔法单词冒险。",
            bgPrimary = "#FFF6E0",
            bgAccent = "#FFD49A",
            monsterPlan = listOf("slime", "slime", "zombie", "dragon", "boss-fruit"),
            words = listOf(
                WordEntry("fruit-apple", "apple", "苹果", example = ExampleSentence("I eat an apple after lunch.", "我午饭后吃一个苹果。")),
                WordEntry("fruit-banana", "banana", "香蕉", example = ExampleSentence("The banana is yellow.", "这根香蕉是黄色的。")),
                WordEntry("fruit-orange", "orange", "橙子", example = ExampleSentence("She peels an orange.", "她剥开一个橙子。")),
                WordEntry("fruit-grape", "grape", "葡萄", example = ExampleSentence("One grape rolls on the plate.", "一颗葡萄在盘子上滚动。")),
                WordEntry("fruit-pear", "pear", "梨", example = ExampleSentence("This pear tastes sweet.", "这个梨尝起来很甜。")),
                WordEntry("fruit-peach", "peach", "桃子", example = ExampleSentence("A peach grows on the tree.", "一颗桃子长在树上。")),
                WordEntry("fruit-lemon", "lemon", "柠檬", example = ExampleSentence("The lemon smells fresh.", "这个柠檬闻起来很清新。")),
                WordEntry("fruit-mango", "mango", "芒果", example = ExampleSentence("Dad cuts a mango for me.", "爸爸给我切了一个芒果。")),
                WordEntry("fruit-melon", "melon", "瓜", example = ExampleSentence("We share a melon in summer.", "夏天我们分享一个瓜。")),
                WordEntry("fruit-cherry", "cherry", "樱桃", example = ExampleSentence("The cherry is on the cake.", "樱桃在蛋糕上。")),
                WordEntry("fruit-strawberry", "strawberry", "草莓", distractors = listOf("pineapple", "watermelon"), example = ExampleSentence("The strawberry is red.", "草莓是红色的。")),
                WordEntry("fruit-pineapple", "pineapple", "菠萝", distractors = listOf("strawberry", "kiwi"), example = ExampleSentence("The pineapple has green leaves.", "菠萝有绿色叶子。")),
                WordEntry("fruit-watermelon", "watermelon", "西瓜", distractors = listOf("blueberry", "pineapple"), example = ExampleSentence("We cut a watermelon today.", "我们今天切西瓜。")),
                WordEntry("fruit-kiwi", "kiwi", "猕猴桃", distractors = listOf("strawberry", "blueberry"), example = ExampleSentence("I put a kiwi in my bowl.", "我把猕猴桃放进碗里。")),
                WordEntry("fruit-blueberry", "blueberry", "蓝莓", distractors = listOf("watermelon", "kiwi"), example = ExampleSentence("A blueberry is small and blue.", "蓝莓又小又蓝。")),
            ),
        ),
        pack(
            id = "school-castle",
            nameEn = "School Castle",
            nameZh = "校园城堡",
            storyZh = "在书本城堡里挑战会拼写的怪物。",
            bgPrimary = "#E8F0FE",
            bgAccent = "#AECBFA",
            monsterPlan = listOf("zombie", "slime", "zombie", "dragon", "boss-school"),
            words = listOf(
                WordEntry("place-school", "school", "学校", example = ExampleSentence("We go to school by bus.", "我们坐公交车去学校。")),
                WordEntry("place-hospital", "hospital", "医院", example = ExampleSentence("The hospital is near the park.", "医院在公园附近。")),
                WordEntry("place-park", "park", "公园", example = ExampleSentence("I fly a kite in the park.", "我在公园里放风筝。")),
                WordEntry("place-supermarket", "supermarket", "超市", example = ExampleSentence("Mom buys milk at the supermarket.", "妈妈在超市买牛奶。")),
                WordEntry("place-library", "library", "图书馆", example = ExampleSentence("The library is quiet.", "图书馆很安静。")),
                WordEntry("place-zoo", "zoo", "动物园", example = ExampleSentence("We see pandas at the zoo.", "我们在动物园看熊猫。")),
                WordEntry("place-bank", "bank", "银行", example = ExampleSentence("The bank opens at nine.", "银行九点开门。")),
                WordEntry("place-museum", "museum", "博物馆", example = ExampleSentence("The museum has old maps.", "博物馆里有旧地图。")),
                WordEntry("place-station", "station", "车站", example = ExampleSentence("The station is busy today.", "今天车站很忙。")),
                WordEntry("place-home", "home", "家", example = ExampleSentence("I read a book at home.", "我在家读书。")),
                WordEntry("place-restaurant", "restaurant", "餐厅", distractors = listOf("cinema", "airport"), example = ExampleSentence("The restaurant serves warm soup.", "餐厅供应热汤。")),
                WordEntry("place-cinema", "cinema", "电影院", distractors = listOf("restaurant", "bookstore"), example = ExampleSentence("The cinema has a big screen.", "电影院有大屏幕。")),
                WordEntry("place-airport", "airport", "机场", distractors = listOf("playground", "cinema"), example = ExampleSentence("The airport is full of planes.", "机场里有许多飞机。")),
                WordEntry("place-playground", "playground", "操场", distractors = listOf("airport", "bookstore"), example = ExampleSentence("The playground is near our class.", "操场在我们班旁边。")),
                WordEntry("place-bookstore", "bookstore", "书店", distractors = listOf("restaurant", "playground"), example = ExampleSentence("The bookstore sells picture books.", "书店卖图画书。")),
            ),
        ),
        pack(
            id = "home-cottage",
            nameEn = "Home Cottage",
            nameZh = "家庭小屋",
            storyZh = "把熟悉的家庭物品变成轻松复习。",
            bgPrimary = "#FFF1E6",
            bgAccent = "#F4B98A",
            monsterPlan = listOf("dragon", "slime", "zombie", "dragon", "boss-home"),
            words = listOf(
                WordEntry("home-tv", "TV", "电视", example = ExampleSentence("The TV is on.", "电视开着。")),
                WordEntry("home-chair", "chair", "椅子", example = ExampleSentence("The chair is by the table.", "椅子在桌子旁边。")),
                WordEntry("home-bed", "bed", "床", example = ExampleSentence("My bed is soft.", "我的床很软。")),
                WordEntry("home-table", "table", "桌子", example = ExampleSentence("A cup is on the table.", "一个杯子在桌子上。")),
                WordEntry("home-sofa", "sofa", "沙发", example = ExampleSentence("The sofa is big.", "沙发很大。")),
                WordEntry("home-lamp", "lamp", "台灯", example = ExampleSentence("The lamp is bright.", "台灯很亮。")),
                WordEntry("home-door", "door", "门", example = ExampleSentence("Please close the door.", "请关上门。")),
                WordEntry("home-window", "window", "窗户", example = ExampleSentence("The window is open.", "窗户开着。")),
                WordEntry("home-book", "book", "书", example = ExampleSentence("This book is fun.", "这本书很有趣。")),
                WordEntry("home-cup", "cup", "杯子", example = ExampleSentence("The cup has water.", "杯子里有水。")),
                WordEntry("home-kitchen", "kitchen", "厨房", distractors = listOf("bathroom", "fridge"), example = ExampleSentence("The kitchen smells like bread.", "厨房闻起来像面包。")),
                WordEntry("home-bathroom", "bathroom", "浴室", distractors = listOf("kitchen", "clock"), example = ExampleSentence("The bathroom has a blue towel.", "浴室里有蓝毛巾。")),
                WordEntry("home-clock", "clock", "时钟", distractors = listOf("phone", "fridge"), example = ExampleSentence("The clock rings at seven.", "时钟七点响。")),
                WordEntry("home-phone", "phone", "电话", distractors = listOf("clock", "bathroom"), example = ExampleSentence("The phone is on the table.", "电话在桌子上。")),
                WordEntry("home-fridge", "fridge", "冰箱", distractors = listOf("kitchen", "phone"), example = ExampleSentence("The fridge keeps milk cold.", "冰箱让牛奶保持冰凉。")),
            ),
        ),
        pack(
            id = "animal-safari",
            nameEn = "Animal Safari",
            nameZh = "动物远征",
            storyZh = "跟动物朋友一起找回单词记忆。",
            bgPrimary = "#FFF4D9",
            bgAccent = "#E0B973",
            monsterPlan = listOf("slime", "dragon", "zombie", "dragon", "boss-animal"),
            words = listOf(
                WordEntry("animal-cat", "cat", "猫", example = ExampleSentence("The cat sleeps on the mat.", "猫睡在垫子上。")),
                WordEntry("animal-dog", "dog", "狗", example = ExampleSentence("My dog likes to run.", "我的狗喜欢跑步。")),
                WordEntry("animal-lion", "lion", "狮子", example = ExampleSentence("The lion has a big mane.", "狮子有大大的鬃毛。")),
                WordEntry("animal-tiger", "tiger", "老虎", example = ExampleSentence("A tiger walks in the grass.", "一只老虎在草地里走。")),
                WordEntry("animal-bear", "bear", "熊", example = ExampleSentence("The bear eats honey.", "熊吃蜂蜜。")),
                WordEntry("animal-frog", "frog", "青蛙", example = ExampleSentence("The frog jumps high.", "青蛙跳得很高。")),
                WordEntry("animal-duck", "duck", "鸭子", example = ExampleSentence("A duck swims in the pond.", "一只鸭子在池塘里游泳。")),
                WordEntry("animal-mouse", "mouse", "老鼠", example = ExampleSentence("The mouse hides under a box.", "老鼠躲在盒子下面。")),
                WordEntry("animal-sheep", "sheep", "绵羊", example = ExampleSentence("The sheep eats green grass.", "绵羊吃青草。")),
                WordEntry("animal-horse", "horse", "马", example = ExampleSentence("The horse runs fast.", "马跑得很快。")),
                WordEntry("animal-bird", "bird", "鸟", distractors = listOf("rabbit", "monkey"), example = ExampleSentence("The bird sings in the tree.", "鸟在树上唱歌。")),
                WordEntry("animal-elephant", "elephant", "大象", distractors = listOf("panda", "bird"), example = ExampleSentence("The elephant has a long nose.", "大象有长鼻子。")),
                WordEntry("animal-monkey", "monkey", "猴子", distractors = listOf("elephant", "rabbit"), example = ExampleSentence("The monkey climbs a tree.", "猴子爬上树。")),
                WordEntry("animal-rabbit", "rabbit", "兔子", distractors = listOf("bird", "panda"), example = ExampleSentence("The rabbit eats a carrot.", "兔子吃胡萝卜。")),
                WordEntry("animal-panda", "panda", "熊猫", distractors = listOf("monkey", "elephant"), example = ExampleSentence("The panda likes green bamboo.", "熊猫喜欢绿色竹子。")),
            ),
        ),
        pack(
            id = "ocean-realm",
            nameEn = "Ocean Realm",
            nameZh = "海洋王国",
            storyZh = "在蓝色海底完成今日练习。",
            bgPrimary = "#E0F4F7",
            bgAccent = "#7BB6BF",
            monsterPlan = listOf("slime", "zombie", "dragon", "slime", "boss-ocean"),
            words = listOf(
                WordEntry("ocean-fish", "fish", "鱼", example = ExampleSentence("A fish swims in the sea.", "一条鱼在海里游。")),
                WordEntry("ocean-whale", "whale", "鲸鱼", example = ExampleSentence("The whale is very big.", "鲸鱼非常大。")),
                WordEntry("ocean-shark", "shark", "鲨鱼", example = ExampleSentence("A shark has sharp teeth.", "鲨鱼有锋利的牙齿。")),
                WordEntry("ocean-crab", "crab", "螃蟹", example = ExampleSentence("The crab walks sideways.", "螃蟹横着走。")),
                WordEntry("ocean-dolphin", "dolphin", "海豚", example = ExampleSentence("A dolphin jumps over a wave.", "一只海豚跃过海浪。")),
                WordEntry("ocean-octopus", "octopus", "章鱼", example = ExampleSentence("The octopus has eight arms.", "章鱼有八只腕足。")),
                WordEntry("ocean-seal", "seal", "海豹", example = ExampleSentence("The seal rests on a rock.", "海豹在岩石上休息。")),
                WordEntry("ocean-turtle", "turtle", "海龟", example = ExampleSentence("A turtle moves slowly.", "海龟慢慢地移动。")),
                WordEntry("ocean-starfish", "starfish", "海星", example = ExampleSentence("A starfish rests on the sand.", "一只海星躺在沙子上。")),
                WordEntry("ocean-jellyfish", "jellyfish", "水母", example = ExampleSentence("The jellyfish floats in the water.", "水母漂在水中。")),
                WordEntry("ocean-shell", "shell", "贝壳", distractors = listOf("coral", "wave"), example = ExampleSentence("The shell is on the beach.", "贝壳在沙滩上。")),
                WordEntry("ocean-coral", "coral", "珊瑚", distractors = listOf("shell", "seaweed"), example = ExampleSentence("The coral is bright and pink.", "珊瑚又亮又粉。")),
                WordEntry("ocean-beach", "beach", "沙滩", distractors = listOf("wave", "coral"), example = ExampleSentence("We walk on the beach.", "我们走在沙滩上。")),
                WordEntry("ocean-wave", "wave", "海浪", distractors = listOf("beach", "shell"), example = ExampleSentence("A wave splashes my feet.", "海浪溅到我的脚。")),
                WordEntry("ocean-seaweed", "seaweed", "海草", distractors = listOf("coral", "beach"), example = ExampleSentence("The seaweed moves in the water.", "海草在水里摆动。")),
            ),
        ),
    )

    val defaultActiveOrder: List<String> = listOf(
        "school-castle",
        "ocean-realm",
        "home-cottage",
        "fruit-forest",
        "animal-safari",
    )

    private fun pack(
        id: String,
        nameEn: String,
        nameZh: String,
        storyZh: String,
        bgPrimary: String,
        bgAccent: String,
        monsterPlan: List<String>,
        words: List<WordEntry>,
    ): WordPack {
        return WordPack(
            id = id,
            nameEn = nameEn,
            nameZh = nameZh,
            source = PackSource.Builtin,
            version = 1,
            publishedAtMs = null,
            scene = SceneMetadata(
                bgPrimary = bgPrimary,
                bgAccent = bgAccent,
                bossName = "$nameEn Boss",
                monsterPlan = monsterPlan,
                bossCandidates = monsterPlan.takeLast(1),
                storyZh = storyZh,
            ),
            words = words,
        )
    }
}
