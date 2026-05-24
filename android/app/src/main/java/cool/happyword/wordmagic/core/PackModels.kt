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
                WordEntry("fruit-pear", "pear", "梨", example = ExampleSentence("A pear grows on the tree.", "一颗梨长在树上。")),
                WordEntry("fruit-orange", "orange", "橙子", example = ExampleSentence("This orange smells sweet.", "这个橙子闻起来很甜。")),
                WordEntry("fruit-grape", "grape", "葡萄", example = ExampleSentence("I put a grape in my bowl.", "我把一颗葡萄放进碗里。")),
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
                WordEntry("school-book", "book", "书", example = ExampleSentence("I open my book in class.", "我在课堂上打开书。")),
                WordEntry("school-pencil", "pencil", "铅笔", example = ExampleSentence("My pencil is on the desk.", "我的铅笔在课桌上。")),
                WordEntry("school-desk", "desk", "课桌", example = ExampleSentence("The desk is near the window.", "课桌在窗户旁边。")),
                WordEntry("school-teacher", "teacher", "老师", example = ExampleSentence("The teacher smiles at us.", "老师对我们微笑。")),
                WordEntry("school-bag", "bag", "书包", example = ExampleSentence("I pack my bag before school.", "我上学前整理书包。")),
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
                WordEntry("home-chair", "chair", "椅子", example = ExampleSentence("The chair is beside the table.", "椅子在桌子旁边。")),
                WordEntry("home-table", "table", "桌子", example = ExampleSentence("We eat dinner at the table.", "我们在桌子旁吃晚饭。")),
                WordEntry("home-door", "door", "门", example = ExampleSentence("Please close the door softly.", "请轻轻关上门。")),
                WordEntry("home-bed", "bed", "床", example = ExampleSentence("My bed is warm at night.", "我的床晚上很暖和。")),
                WordEntry("home-lamp", "lamp", "台灯", example = ExampleSentence("The lamp shines on my book.", "台灯照着我的书。")),
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
                WordEntry("animal-dog", "dog", "狗", example = ExampleSentence("The dog runs in the park.", "狗在公园里奔跑。")),
                WordEntry("animal-bird", "bird", "鸟", example = ExampleSentence("A bird sings in the tree.", "一只鸟在树上唱歌。")),
                WordEntry("animal-fish", "fish", "鱼", example = ExampleSentence("The fish swims in the pond.", "鱼在池塘里游泳。")),
                WordEntry("animal-lion", "lion", "狮子", example = ExampleSentence("The lion roars in the sun.", "狮子在阳光下吼叫。")),
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
                WordEntry("ocean-sea", "sea", "海洋", example = ExampleSentence("The sea is blue today.", "今天的大海是蓝色的。")),
                WordEntry("ocean-ship", "ship", "船", example = ExampleSentence("A ship sails across the sea.", "一艘船驶过大海。")),
                WordEntry("ocean-shell", "shell", "贝壳", example = ExampleSentence("I find a shell on the sand.", "我在沙滩上找到一个贝壳。")),
                WordEntry("ocean-wave", "wave", "海浪", example = ExampleSentence("A wave rolls to the shore.", "一朵海浪涌向岸边。")),
                WordEntry("ocean-star", "star", "海星", example = ExampleSentence("A star shines above the sea.", "一颗星星在海面上闪耀。")),
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
