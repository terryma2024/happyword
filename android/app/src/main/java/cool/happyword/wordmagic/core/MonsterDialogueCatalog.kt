package cool.happyword.wordmagic.core

/** V0.9.2 boss dialogue copied from HarmonyOS monster_catalog.json. */
object MonsterDialogueCatalog {
    private val rows: Map<Int, MonsterDialogue> = mapOf(
        1 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Bounce into my wiggly quiz!", zh = "跳进我的软软小题吧！"),
            defeatLine = MonsterDialogueLine(en = "Your magic made me wobble away.", zh = "你的魔法让我晃走啦。"),
        ),
        2 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Shuffle fast and spell faster!", zh = "我慢慢走，你快快拼！"),
            defeatLine = MonsterDialogueLine(en = "Oof, your word woke me up.", zh = "哎呀，单词把我叫醒了。"),
        ),
        3 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My fiery riddle is ready!", zh = "我的火焰谜题来啦！"),
            defeatLine = MonsterDialogueLine(en = "Your word cooled my flames.", zh = "你的单词让火焰降温了。"),
        ),
        4 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Try my tricky harvest spell!", zh = "试试我的南瓜咒语！"),
            defeatLine = MonsterDialogueLine(en = "My crown rolled into the vines.", zh = "我的王冠滚进藤蔓啦。"),
        ),
        5 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "I hid a tiny word trap!", zh = "我藏了个小单词陷阱！"),
            defeatLine = MonsterDialogueLine(en = "You spotted my sneaky trick.", zh = "你看穿我的小把戏了。"),
        ),
        6 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Can you catch a flaming word?", zh = "你能抓住火焰单词吗？"),
            defeatLine = MonsterDialogueLine(en = "I rise again after your win.", zh = "你赢了，我会再飞起。"),
        ),
        7 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My spellbook picked this word.", zh = "我的魔法书选了这词。"),
            defeatLine = MonsterDialogueLine(en = "Your answer broke my spell.", zh = "你的答案破咒啦。"),
        ),
        8 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My frost keeps words frozen.", zh = "我的霜冻住了单词。"),
            defeatLine = MonsterDialogueLine(en = "Your words warmed the castle.", zh = "你的单词暖了城堡。"),
        ),
        9 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Follow my shiny word trail.", zh = "跟上我的闪亮词路。"),
            defeatLine = MonsterDialogueLine(en = "Your magic sparkled brighter.", zh = "你的魔法更闪亮。"),
        ),
        10 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "The deep hides my final word.", zh = "深海藏着终极单词。"),
            defeatLine = MonsterDialogueLine(en = "The tide bows to your words.", zh = "潮水向你的单词低头。"),
        ),
        11 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Float through my glowing clue.", zh = "漂过我的发光线索吧。"),
            defeatLine = MonsterDialogueLine(en = "Your answer lit the reef.", zh = "你的答案点亮礁石。"),
        ),
        12 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "I peeked at the next word!", zh = "我偷看了下个单词！"),
            defeatLine = MonsterDialogueLine(en = "You found me before I blinked.", zh = "你眨眼前就找到我了。"),
        ),
        13 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My cap hides a tiny clue.", zh = "我的菇帽藏着线索。"),
            defeatLine = MonsterDialogueLine(en = "Your word popped my puzzle.", zh = "你的单词弹开谜题。"),
        ),
        14 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Step softly through my moss.", zh = "轻轻走过我的苔藓。"),
            defeatLine = MonsterDialogueLine(en = "Even moss heard your answer.", zh = "苔藓都听见答案了。"),
        ),
        15 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My stone clue will not move.", zh = "我的石头线索不动。"),
            defeatLine = MonsterDialogueLine(en = "Your word rolled me aside.", zh = "你的单词把我推开。"),
        ),
        16 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Read by my lantern glow.", zh = "借我的灯光读吧。"),
            defeatLine = MonsterDialogueLine(en = "Your answer shines brighter.", zh = "你的答案更亮。"),
        ),
        17 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Echo my crystal word!", zh = "回响我的水晶单词！"),
            defeatLine = MonsterDialogueLine(en = "Your sound cracked my echo.", zh = "你的声音震开回声。"),
        ),
        18 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Fly up to my cloudy clue.", zh = "飞向我的云端线索。"),
            defeatLine = MonsterDialogueLine(en = "Your word cleared the sky.", zh = "你的单词扫开云。"),
        ),
        19 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My clue slips like water.", zh = "我的线索像水滑走。"),
            defeatLine = MonsterDialogueLine(en = "Your answer caught the stream.", zh = "你的答案抓住水流。"),
        ),
        20 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Dance through my leafy quiz.", zh = "跳过我的叶子小题。"),
            defeatLine = MonsterDialogueLine(en = "Your rhythm beat my riddle.", zh = "你的节奏赢了谜题。"),
        ),
        21 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Catch my berry word if you can!", zh = "有本事抓莓果词！"),
            defeatLine = MonsterDialogueLine(en = "You picked the right berry.", zh = "你摘到正确莓果了。"),
        ),
        22 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Dig for my buried word.", zh = "挖出我的地下单词。"),
            defeatLine = MonsterDialogueLine(en = "Your answer tunneled through.", zh = "你的答案打通地道。"),
        ),
        23 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Tick-tock, choose the word!", zh = "滴答滴答，选单词！"),
            defeatLine = MonsterDialogueLine(en = "Your word stopped my gears.", zh = "你的单词停住齿轮。"),
        ),
        24 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Guess which page bites back!", zh = "猜哪页会咬人！"),
            defeatLine = MonsterDialogueLine(en = "You read me perfectly.", zh = "你把我读懂了。"),
        ),
        25 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My chest snaps at wrong words.", zh = "我的宝箱会咬错词。"),
            defeatLine = MonsterDialogueLine(en = "Your word opened the lock.", zh = "你的单词开了锁。"),
        ),
        26 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Slow clues still win races.", zh = "慢线索也会赢比赛。"),
            defeatLine = MonsterDialogueLine(en = "Your word raced ahead.", zh = "你的单词跑在前面。"),
        ),
        27 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "I copied your next clue.", zh = "我复制了下个线索。"),
            defeatLine = MonsterDialogueLine(en = "Your answer showed the truth.", zh = "你的答案照出真相。"),
        ),
        28 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My candle flickers a clue.", zh = "我的烛光闪着线索。"),
            defeatLine = MonsterDialogueLine(en = "Your word blew my trick away.", zh = "你的单词吹走把戏。"),
        ),
        29 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Fold my riddle if you dare.", zh = "敢折我的纸谜吗？"),
            defeatLine = MonsterDialogueLine(en = "Your answer smoothed the page.", zh = "你的答案抚平纸页。"),
        ),
        30 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My marble word is heavy.", zh = "我的石纹单词很重。"),
            defeatLine = MonsterDialogueLine(en = "Your word lifted the stone.", zh = "你的单词举起石头。"),
        ),
        31 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Sing back my tricky word.", zh = "唱回我的调皮词。"),
            defeatLine = MonsterDialogueLine(en = "Your answer found the tune.", zh = "你的答案找准调子。"),
        ),
        32 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My clue rides a feather.", zh = "我的线索乘羽毛飞。"),
            defeatLine = MonsterDialogueLine(en = "Your word landed first.", zh = "你的单词先落地。"),
        ),
        33 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Small wings, sharp riddle!", zh = "小翅膀，大谜题！"),
            defeatLine = MonsterDialogueLine(en = "Your word clipped my trick.", zh = "你的单词剪掉把戏。"),
        ),
        34 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Blink and miss my clue!", zh = "一眨眼线索就没啦！"),
            defeatLine = MonsterDialogueLine(en = "You looked and answered well.", zh = "你看准并答对了。"),
        ),
        35 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Three clues, one right word!", zh = "三个线索，一个对词！"),
            defeatLine = MonsterDialogueLine(en = "Your word tamed my mix-up.", zh = "你的单词理顺混搭。"),
        ),
        36 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My tail points to trouble.", zh = "我的尾巴指向麻烦。"),
            defeatLine = MonsterDialogueLine(en = "Your answer softened my sting.", zh = "你的答案收起尖刺。"),
        ),
        37 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Bow, then answer my clue.", zh = "先鞠躬，再答题吧。"),
            defeatLine = MonsterDialogueLine(en = "Your word earned my bow.", zh = "你的单词赢得敬礼。"),
        ),
        38 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Race my sky-bright word.", zh = "追上我的天空词。"),
            defeatLine = MonsterDialogueLine(en = "Your word flew farther.", zh = "你的单词飞得更远。"),
        ),
        39 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My moon clue flutters by.", zh = "月光线索轻轻飞。"),
            defeatLine = MonsterDialogueLine(en = "Your answer caught the wings.", zh = "你的答案接住翅膀。"),
        ),
        40 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Hop after my star clue.", zh = "跳着追星星线索吧。"),
            defeatLine = MonsterDialogueLine(en = "Your word hopped ahead.", zh = "你的单词跳到前面。"),
        ),
        41 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My ember word is hot!", zh = "我的火星词很烫！"),
            defeatLine = MonsterDialogueLine(en = "Your answer cooled the sparks.", zh = "你的答案冷却火星。"),
        ),
        42 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My clue flows around you.", zh = "我的线索绕着你流。"),
            defeatLine = MonsterDialogueLine(en = "Your word held the wave.", zh = "你的单词稳住浪花。"),
        ),
        43 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Leaves whisper the answer.", zh = "叶子悄悄说答案。"),
            defeatLine = MonsterDialogueLine(en = "Your word rustled louder.", zh = "你的单词响得更亮。"),
        ),
        44 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My clue grows from stone.", zh = "我的线索从石里长。"),
            defeatLine = MonsterDialogueLine(en = "Your answer shook the ground.", zh = "你的答案震动大地。"),
        ),
        45 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Catch my invisible word.", zh = "抓住我的隐形词。"),
            defeatLine = MonsterDialogueLine(en = "Your word caught the breeze.", zh = "你的单词抓住微风。"),
        ),
        46 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My clue skates on ice.", zh = "我的线索在冰上滑。"),
            defeatLine = MonsterDialogueLine(en = "Your answer melted the trail.", zh = "你的答案融开冰路。"),
        ),
        47 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Bark out the stormy word!", zh = "叫出雷声单词！"),
            defeatLine = MonsterDialogueLine(en = "Your word calmed my thunder.", zh = "你的单词安抚雷声。"),
        ),
        48 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Slide across seven clues.", zh = "滑过七彩线索吧。"),
            defeatLine = MonsterDialogueLine(en = "Your word found every color.", zh = "你的单词找齐颜色。"),
        ),
        49 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My sunny clue roars!", zh = "我的阳光线索吼！"),
            defeatLine = MonsterDialogueLine(en = "Your answer brightened noon.", zh = "你的答案照亮正午。"),
        ),
        50 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Hoot once for the right word.", zh = "为正确单词叫一声。"),
            defeatLine = MonsterDialogueLine(en = "Your word woke the moon.", zh = "你的单词唤醒月亮。"),
        ),
        51 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Pinch the right sea word.", zh = "夹住正确海洋词。"),
            defeatLine = MonsterDialogueLine(en = "Your answer opened my claws.", zh = "你的答案松开蟹钳。"),
        ),
        52 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Charge through my sea clue.", zh = "冲过我的海中线索。"),
            defeatLine = MonsterDialogueLine(en = "Your word won the joust.", zh = "你的单词赢得比试。"),
        ),
        53 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Pop my bubble clue!", zh = "戳破我的泡泡线索！"),
            defeatLine = MonsterDialogueLine(en = "Your answer floated up.", zh = "你的答案浮上来了。"),
        ),
        54 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My pearl hides a word.", zh = "我的珍珠藏着词。"),
            defeatLine = MonsterDialogueLine(en = "Your word made it shine.", zh = "你的单词让它发亮。"),
        ),
        55 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Skip across my reef clue.", zh = "跳过我的礁石线索。"),
            defeatLine = MonsterDialogueLine(en = "Your word splashed true.", zh = "你的单词溅出真相。"),
        ),
        56 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "I spin words in the tide.", zh = "我在潮里转单词。"),
            defeatLine = MonsterDialogueLine(en = "Your answer rode the current.", zh = "你的答案顺流而来。"),
        ),
        57 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Slow shell, sneaky clue!", zh = "慢壳里有小线索！"),
            defeatLine = MonsterDialogueLine(en = "Your word passed my shell.", zh = "你的单词越过壳啦。"),
        ),
        58 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Five points guard my clue.", zh = "五个角守着线索。"),
            defeatLine = MonsterDialogueLine(en = "Your answer sparked my wand.", zh = "你的答案点亮魔杖。"),
        ),
        59 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Leap over my wave word.", zh = "跳过我的海浪词。"),
            defeatLine = MonsterDialogueLine(en = "Your word made the wave cheer.", zh = "你的单词让浪花欢呼。"),
        ),
        60 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Stomp through my frosty clue.", zh = "踩过我的冰霜线索。"),
            defeatLine = MonsterDialogueLine(en = "Your answer warmed my paws.", zh = "你的答案暖了脚掌。"),
        ),
        61 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "I packed snow around a word.", zh = "我把词包进雪球。"),
            defeatLine = MonsterDialogueLine(en = "Your word cracked the snowball.", zh = "你的单词敲开雪球。"),
        ),
        62 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My pointy clue drips fast.", zh = "我的冰锥线索滴答。"),
            defeatLine = MonsterDialogueLine(en = "Your answer snapped the ice.", zh = "你的答案折断冰锥。"),
        ),
        63 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Chase my dancing light clue.", zh = "追我的极光线索吧。"),
            defeatLine = MonsterDialogueLine(en = "Your word caught the glow.", zh = "你的单词抓住光。"),
        ),
        64 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My frozen word stands tall.", zh = "我的冻词站得高。"),
            defeatLine = MonsterDialogueLine(en = "Your answer moved the mountain.", zh = "你的答案移开冰山。"),
        ),
        65 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Climb up to my sky word.", zh = "爬上我的天空词。"),
            defeatLine = MonsterDialogueLine(en = "Your word reached my cloud.", zh = "你的单词抵达云端。"),
        ),
        66 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My clue sings in the sky.", zh = "我的线索在天上唱。"),
            defeatLine = MonsterDialogueLine(en = "Your answer echoed higher.", zh = "你的答案回声更高。"),
        ),
        67 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Whirl through my windy word.", zh = "穿过我的旋风词。"),
            defeatLine = MonsterDialogueLine(en = "Your word stilled the gust.", zh = "你的单词停住风。"),
        ),
        68 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My riddle rides the thunder.", zh = "我的谜题乘雷声来。"),
            defeatLine = MonsterDialogueLine(en = "Your answer cleared the storm.", zh = "你的答案扫清风暴。"),
        ),
        69 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My comet clue burns bright.", zh = "我的彗星线索发亮。"),
            defeatLine = MonsterDialogueLine(en = "Your word outran the comet.", zh = "你的单词追过彗星。"),
        ),
        70 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Dig my clue from the dune.", zh = "从沙丘挖出线索。"),
            defeatLine = MonsterDialogueLine(en = "Your answer found the oasis.", zh = "你的答案找到绿洲。"),
        ),
        71 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Careful, my clue has prickles.", zh = "小心，线索有刺。"),
            defeatLine = MonsterDialogueLine(en = "Your word dodged every thorn.", zh = "你的单词躲过尖刺。"),
        ),
        72 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Answer my tiny riddle.", zh = "回答我的小谜语。"),
            defeatLine = MonsterDialogueLine(en = "Your word solved my smile.", zh = "你的单词解开笑容。"),
        ),
        73 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "March past my shiny clue.", zh = "走过我的亮甲线索。"),
            defeatLine = MonsterDialogueLine(en = "Your answer polished my shield.", zh = "你的答案擦亮盾牌。"),
        ),
        74 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Is my word here or there?", zh = "我的词在这还是那？"),
            defeatLine = MonsterDialogueLine(en = "Your answer caught the shimmer.", zh = "你的答案抓住幻光。"),
        ),
        75 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My warm clue darts away.", zh = "我的暖线索飞快跑。"),
            defeatLine = MonsterDialogueLine(en = "Your word basked in victory.", zh = "你的单词晒着胜利。"),
        ),
        76 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Spin through my dusty word.", zh = "旋过我的尘土词。"),
            defeatLine = MonsterDialogueLine(en = "Your answer settled the dust.", zh = "你的答案落定尘土。"),
        ),
        77 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Hop to my cool clue.", zh = "跳向我的清凉线索。"),
            defeatLine = MonsterDialogueLine(en = "Your word splashed just right.", zh = "你的单词溅得刚好。"),
        ),
        78 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Climb my pyramid of clues.", zh = "爬上我的线索金字塔。"),
            defeatLine = MonsterDialogueLine(en = "Your answer reached the top.", zh = "你的答案到顶啦。"),
        ),
        79 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My ember clue flicks fast.", zh = "我的余烬线索很快。"),
            defeatLine = MonsterDialogueLine(en = "Your word followed the spark.", zh = "你的单词跟上火星。"),
        ),
        80 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Leap over my lava word!", zh = "跳过我的岩浆词！"),
            defeatLine = MonsterDialogueLine(en = "Your answer cooled the stones.", zh = "你的答案冷却石头。"),
        ),
        81 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My ash clue hides in gray.", zh = "我的灰烬线索藏着。"),
            defeatLine = MonsterDialogueLine(en = "Your word brushed it clean.", zh = "你的单词扫干净了。"),
        ),
        82 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Swoop through my smoky clue.", zh = "掠过我的烟雾线索。"),
            defeatLine = MonsterDialogueLine(en = "Your answer cleared my wings.", zh = "你的答案清亮翅膀。"),
        ),
        83 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Snap up my tiny spark word.", zh = "抓住我的小火花词。"),
            defeatLine = MonsterDialogueLine(en = "Your word flashed brighter.", zh = "你的单词闪得更亮。"),
        ),
        84 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Gallop through my flame clue.", zh = "奔过我的火焰线索。"),
            defeatLine = MonsterDialogueLine(en = "Your answer won the race.", zh = "你的答案赢了赛跑。"),
        ),
        85 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My slow lava clue glows.", zh = "我的慢岩浆线索发光。"),
            defeatLine = MonsterDialogueLine(en = "Your word cooled my trail.", zh = "你的单词冷却小路。"),
        ),
        86 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My thorny clue growls.", zh = "我的荆棘线索低吼。"),
            defeatLine = MonsterDialogueLine(en = "Your answer tamed the thorns.", zh = "你的答案驯服荆棘。"),
        ),
        87 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Duel my little acorn clue.", zh = "和橡果线索决斗吧。"),
            defeatLine = MonsterDialogueLine(en = "Your word won the acorn duel.", zh = "你的单词赢了决斗。"),
        ),
        88 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My sweet clue sticks tight.", zh = "我的甜线索粘住啦。"),
            defeatLine = MonsterDialogueLine(en = "Your answer unstuck the honey.", zh = "你的答案化开蜂蜜。"),
        ),
        89 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My vine clue curls close.", zh = "我的藤蔓线索卷来。"),
            defeatLine = MonsterDialogueLine(en = "Your word untangled the vines.", zh = "你的单词解开藤蔓。"),
        ),
        90 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Listen to my whispering leaves.", zh = "听我柳叶的悄悄话。"),
            defeatLine = MonsterDialogueLine(en = "Your answer swayed the branches.", zh = "你的答案摇动树枝。"),
        ),
        91 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My pollen clue tickles.", zh = "我的花粉线索痒痒的。"),
            defeatLine = MonsterDialogueLine(en = "Your word made me sneeze.", zh = "你的单词让我打喷嚏。"),
        ),
        92 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Find my lucky word!", zh = "找到我的幸运词！"),
            defeatLine = MonsterDialogueLine(en = "Your answer found the clover.", zh = "你的答案找到苜蓿。"),
        ),
        93 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My green clue darts away.", zh = "我的绿色线索飞跑。"),
            defeatLine = MonsterDialogueLine(en = "Your word caught my tail.", zh = "你的单词追到尾巴。"),
        ),
        94 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My mushroom gate is closed.", zh = "我的蘑菇门关着。"),
            defeatLine = MonsterDialogueLine(en = "Your word opened the cap.", zh = "你的单词打开菇帽。"),
        ),
        95 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "March to my toy-box clue.", zh = "向玩具盒线索前进。"),
            defeatLine = MonsterDialogueLine(en = "Your word won the parade.", zh = "你的单词赢了游行。"),
        ),
        96 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My tiny clue sits still.", zh = "我的小线索静静坐着。"),
            defeatLine = MonsterDialogueLine(en = "Your answer made me smile.", zh = "你的答案让我微笑。"),
        ),
        97 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Press the right word button!", zh = "按下正确单词按钮！"),
            defeatLine = MonsterDialogueLine(en = "Your word clicked into place.", zh = "你的单词咔哒归位。"),
        ),
        98 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "My laundry clue curls up.", zh = "我的袜子线索卷起来。"),
            defeatLine = MonsterDialogueLine(en = "Your answer paired the socks.", zh = "你的答案配好袜子。"),
        ),
        99 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Tug my windy kite word.", zh = "拉住我的风筝词。"),
            defeatLine = MonsterDialogueLine(en = "Your word held the string.", zh = "你的单词牵住线。"),
        ),
        100 to MonsterDialogue(
            introLine = MonsterDialogueLine(en = "Turn my music-box clue.", zh = "转动我的音乐盒线索。"),
            defeatLine = MonsterDialogueLine(en = "Your answer played the tune.", zh = "你的答案奏出旋律。"),
        ),
    )

    fun dialogueForIndex(index1Based: Int, monsterName: String): MonsterDialogue =
        resolveDialogue(index1Based = index1Based, monsterName = monsterName)

    fun resolveDialogue(
        index1Based: Int,
        monsterName: String,
        override: MonsterDialogue? = null,
    ): MonsterDialogue {
        val fallback = fallbackDialogue(monsterName)
        val base = override ?: rows[index1Based]
        if (base == null) return fallback
        return MonsterDialogue(
            introLine = MonsterDialogueLine(
                en = base.introLine.en.ifBlank { fallback.introLine.en },
                zh = base.introLine.zh.ifBlank { fallback.introLine.zh },
            ),
            defeatLine = MonsterDialogueLine(
                en = base.defeatLine.en.ifBlank { fallback.defeatLine.en },
                zh = base.defeatLine.zh.ifBlank { fallback.defeatLine.zh },
            ),
        )
    }

    private fun fallbackDialogue(monsterName: String): MonsterDialogue {
        val safeName = monsterName.trim().ifEmpty { "Boss" }
        return MonsterDialogue(
            introLine = MonsterDialogueLine(
                en = "$safeName is ready!",
                zh = "${safeName}准备好啦！",
            ),
            defeatLine = MonsterDialogueLine(
                en = "$safeName yields this round.",
                zh = "${safeName}这回让你赢。",
            ),
        )
    }
}
