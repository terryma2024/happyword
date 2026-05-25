/**
 * MonsterCatalog: a frozen, 1-based roster of monsters fought in BattlePage.
 * The catalog order mirrors MONSTER_CODEX so codex lore and battle art stay aligned.
 */
export enum MonsterKind {
  Normal = 'normal',
  Spelling = 'spelling',
  Review = 'review',
  Elite = 'elite',
  Boss = 'boss',
}

/** V0.8.3 difficulty tier — orthogonal to {@link MonsterKind} art grouping. */
export enum MonsterLevel {
  Beginner = 'beginner',
  Intermediate = 'intermediate',
  Advanced = 'advanced',
  Super = 'super',
}

export class MonsterDialogueLine {
  en: string = '';
  zh: string = '';
}

export class MonsterDialogue {
  introLine: MonsterDialogueLine = new MonsterDialogueLine();
  defeatLine: MonsterDialogueLine = new MonsterDialogueLine();
}

function line(en: string, zh: string): MonsterDialogueLine {
  const out: MonsterDialogueLine = new MonsterDialogueLine();
  out.en = en;
  out.zh = zh;
  return out;
}

function dialogue(introEn: string, introZh: string, defeatEn: string, defeatZh: string): MonsterDialogue {
  const out: MonsterDialogue = new MonsterDialogue();
  out.introLine = line(introEn, introZh);
  out.defeatLine = line(defeatEn, defeatZh);
  return out;
}

export class MonsterEntry {
  name: string = '';
  fill: string = '';
  stroke: string = '';
  kind: MonsterKind = MonsterKind.Normal;
  assetPath: string = '';
  level: MonsterLevel = MonsterLevel.Beginner;
  dialogue: MonsterDialogue = dialogue(
    'Face my word challenge!',
    '来挑战我的单词吧！',
    'Your word wins this round.',
    '这回你的单词赢啦。'
  );
}

export function makeMonsterEntryWithKind(
  name: string,
  fill: string,
  stroke: string,
  kind: MonsterKind
): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = name;
  e.fill = fill;
  e.stroke = stroke;
  e.kind = kind;
  return e;
}

export function makeBossEntry(
  name: string,
  fill: string,
  stroke: string,
  assetPath: string
): MonsterEntry {
  const e: MonsterEntry = new MonsterEntry();
  e.name = name;
  e.fill = fill;
  e.stroke = stroke;
  e.kind = MonsterKind.Boss;
  e.assetPath = assetPath;
  return e;
}

export const MONSTER_CATALOG: MonsterEntry[] = [
  makeMonsterEntryWithKind('Slime', '#7BD389', '#3F8C50', MonsterKind.Normal), // 1
  makeMonsterEntryWithKind('Zombie', '#9DAA7A', '#4F5E33', MonsterKind.Spelling), // 2
  makeMonsterEntryWithKind('Dragon', '#E63946', '#7C1A23', MonsterKind.Elite), // 3
  makeBossEntry('Pumpkin King', '#F2812B', '#B5530F', 'character/pumpkin-king.svg'), // 4
  makeBossEntry('Imp King', '#5C9C3B', '#355E20', 'character/imp-king.svg'), // 5
  makeBossEntry('Phoenix', '#F4A261', '#9A4A1F', 'character/phoenix.svg'), // 6
  makeBossEntry('Witch', '#2B3470', '#13183A', 'character/witch.svg'), // 7
  makeBossEntry('Snow Queen', '#9DC8E2', '#3F6B7F', 'character/snow-queen.svg'), // 8
  makeBossEntry('Unicorn', '#F2B5C3', '#9C4F6E', 'character/unicorn.svg'), // 9
  makeBossEntry('Kraken', '#1A6E7A', '#0F3B45', 'character/kraken.svg'), // 10
  makeBossEntry('Jellyfish', '#9A3C3C', '#5D1D1D', 'character/jellyfish.svg'), // 11
  makeBossEntry('Goblin Scout', '#9A4F3C', '#5D2A1D', 'character/goblin-scout.svg'), // 12
  makeBossEntry('Mushroom Sprite', '#9A623C', '#5D371D', 'character/mushroom-sprite.svg'), // 13
  makeBossEntry('Moss Troll', '#9A753C', '#5D441D', 'character/moss-troll.svg'), // 14
  makeBossEntry('Pebble Golem', '#9A873C', '#5D501D', 'character/pebble-golem.svg'), // 15
  makeBossEntry('Lantern Wisp', '#9A9A3C', '#5D5D1D', 'character/lantern-wisp.svg'), // 16
  makeBossEntry('Crystal Bat', '#879A3C', '#505D1D', 'character/crystal-bat.svg'), // 17
  makeBossEntry('Cloud Griffin', '#759A3C', '#445D1D', 'character/cloud-griffin.svg'), // 18
  makeBossEntry('River Nymph', '#629A3C', '#375D1D', 'character/river-nymph.svg'), // 19
  makeBossEntry('Forest Satyr', '#4F9A3C', '#2A5D1D', 'character/forest-satyr.svg'), // 20
  makeBossEntry('Berry Imp', '#3C9A3C', '#1D5D1D', 'character/berry-imp.svg'), // 21
  makeBossEntry('Cave Molekin', '#3C9A4F', '#1D5D2A', 'character/cave-molekin.svg'), // 22
  makeBossEntry('Clockwork Beetle', '#3C9A62', '#1D5D37', 'character/clockwork-beetle.svg'), // 23
  makeBossEntry('Book Mimic', '#3C9A75', '#1D5D44', 'character/book-mimic.svg'), // 24
  makeBossEntry('Treasure Mimic', '#3C9A87', '#1D5D50', 'character/treasure-mimic.svg'), // 25
  makeBossEntry('Rune Tortoise', '#3C9A9A', '#1D5D5D', 'character/rune-tortoise.svg'), // 26
  makeBossEntry('Mirror Sprite', '#3C879A', '#1D505D', 'character/mirror-sprite.svg'), // 27
  makeBossEntry('Candle Ghost', '#3C759A', '#1D445D', 'character/candle-ghost.svg'), // 28
  makeBossEntry('Paper Gargoyle', '#3C629A', '#1D375D', 'character/paper-gargoyle.svg'), // 29
  makeBossEntry('Marble Golem', '#3C4F9A', '#1D2A5D', 'character/marble-golem.svg'), // 30
  makeBossEntry('Harpy Bard', '#9A3C87', '#5D1D50', 'character/harpy-bard.svg'), // 31
  makeBossEntry('Feather Drake', '#9A3C75', '#5D1D44', 'character/feather-drake.svg'), // 32
  makeBossEntry('Tiny Wyvern', '#9A3C62', '#5D1D37', 'character/tiny-wyvern.svg'), // 33
  makeBossEntry('Basilisk Buddy', '#9A3C4F', '#5D1D2A', 'character/basilisk-buddy.svg'), // 34
  makeBossEntry('Chimera Cub', '#A33333', '#621818', 'character/chimera-cub.svg'), // 35
  makeBossEntry('Manticore Kit', '#A34A33', '#622718', 'character/manticore-kit.svg'), // 36
  makeBossEntry('Hippogriff', '#A36033', '#623618', 'character/hippogriff.svg'), // 37
  makeBossEntry('Pegasus', '#A37633', '#624518', 'character/pegasus.svg'), // 38
  makeBossEntry('Moon Moth', '#A38D33', '#625318', 'character/moon-moth.svg'), // 39
  makeBossEntry('Star Hare', '#A3A333', '#626218', 'character/star-hare.svg'), // 40
  makeBossEntry('Fire Elemental', '#8DA333', '#536218', 'character/fire-elemental.svg'), // 41
  makeBossEntry('Water Elemental', '#76A333', '#456218', 'character/water-elemental.svg'), // 42
  makeBossEntry('Leaf Elemental', '#60A333', '#366218', 'character/leaf-elemental.svg'), // 43
  makeBossEntry('Earth Elemental', '#4AA333', '#276218', 'character/earth-elemental.svg'), // 44
  makeBossEntry('Air Elemental', '#33A333', '#186218', 'character/air-elemental.svg'), // 45
  makeBossEntry('Ice Sprite', '#33A34A', '#186227', 'character/ice-sprite.svg'), // 46
  makeBossEntry('Thunder Pup', '#33A360', '#186236', 'character/thunder-pup.svg'), // 47
  makeBossEntry('Rainbow Serpent', '#33A376', '#186245', 'character/rainbow-serpent.svg'), // 48
  makeBossEntry('Sun Lion', '#33A38D', '#186253', 'character/sun-lion.svg'), // 49
  makeBossEntry('Moon Owl', '#33A3A3', '#186262', 'character/moon-owl.svg'), // 50
  makeBossEntry('Coral Crab', '#338DA3', '#185362', 'character/coral-crab.svg'), // 51
  makeBossEntry('Seahorse Knight', '#3376A3', '#184562', 'character/seahorse-knight.svg'), // 52
  makeBossEntry('Bubble Turtle', '#3360A3', '#183662', 'character/bubble-turtle.svg'), // 53
  makeBossEntry('Pearl Mermaid', '#334AA3', '#182762', 'character/pearl-mermaid.svg'), // 54
  makeBossEntry('Reef Sprite', '#A3338D', '#621853', 'character/reef-sprite.svg'), // 55
  makeBossEntry('Tide Otter', '#A33376', '#621845', 'character/tide-otter.svg'), // 56
  makeBossEntry('Shell Snail', '#A33360', '#621836', 'character/shell-snail.svg'), // 57
  makeBossEntry('Starfish Wizard', '#A3334A', '#621827', 'character/starfish-wizard.svg'), // 58
  makeBossEntry('Dolphin Drake', '#AB2B2B', '#671414', 'character/dolphin-drake.svg'), // 59
  makeBossEntry('Frost Yeti', '#AB452B', '#672414', 'character/frost-yeti.svg'), // 60
  makeBossEntry('Snow Goblin', '#AB5E2B', '#673514', 'character/snow-goblin.svg'), // 61
  makeBossEntry('Icicle Imp', '#AB782B', '#674614', 'character/icicle-imp.svg'), // 62
  makeBossEntry('Aurora Fox', '#AB922B', '#675614', 'character/aurora-fox.svg'), // 63
  makeBossEntry('Polar Golem', '#ABAB2B', '#676714', 'character/polar-golem.svg'), // 64
  makeBossEntry('Cloud Giant', '#92AB2B', '#566714', 'character/cloud-giant.svg'), // 65
  makeBossEntry('Sky Whale', '#78AB2B', '#466714', 'character/sky-whale.svg'), // 66
  makeBossEntry('Wind Djinn', '#5EAB2B', '#356714', 'character/wind-djinn.svg'), // 67
  makeBossEntry('Storm Sprite', '#45AB2B', '#246714', 'character/storm-sprite.svg'), // 68
  makeBossEntry('Comet Dragon', '#2BAB2B', '#146714', 'character/comet-dragon.svg'), // 69
  makeBossEntry('Sand Gnome', '#2BAB45', '#146724', 'character/sand-gnome.svg'), // 70
  makeBossEntry('Cactus Imp', '#2BAB5E', '#146735', 'character/cactus-imp.svg'), // 71
  makeBossEntry('Sphinx Cub', '#2BAB78', '#146746', 'character/sphinx-cub.svg'), // 72
  makeBossEntry('Scarab Knight', '#2BAB92', '#146756', 'character/scarab-knight.svg'), // 73
  makeBossEntry('Mirage Cat', '#2BABAB', '#146767', 'character/mirage-cat.svg'), // 74
  makeBossEntry('Sun Salamander', '#2B92AB', '#145667', 'character/sun-salamander.svg'), // 75
  makeBossEntry('Dust Whirl', '#2B78AB', '#144667', 'character/dust-whirl.svg'), // 76
  makeBossEntry('Oasis Frog', '#2B5EAB', '#143567', 'character/oasis-frog.svg'), // 77
  makeBossEntry('Pyramid Sprite', '#2B45AB', '#142467', 'character/pyramid-sprite.svg'), // 78
  makeBossEntry('Ember Fox', '#AB2B92', '#671456', 'character/ember-fox.svg'), // 79
  makeBossEntry('Lava Toad', '#AB2B78', '#671446', 'character/lava-toad.svg'), // 80
  makeBossEntry('Ash Golem', '#AB2B5E', '#671435', 'character/ash-golem.svg'), // 81
  makeBossEntry('Cinder Bat', '#AB2B45', '#671424', 'character/cinder-bat.svg'), // 82
  makeBossEntry('Spark Sprite', '#B42222', '#6C0F0F', 'character/spark-sprite.svg'), // 83
  makeBossEntry('Flame Pony', '#B43F22', '#6C210F', 'character/flame-pony.svg'), // 84
  makeBossEntry('Molten Snail', '#B45D22', '#6C340F', 'character/molten-snail.svg'), // 85
  makeBossEntry('Briar Wolf', '#B47A22', '#6C470F', 'character/briar-wolf.svg'), // 86
  makeBossEntry('Acorn Knight', '#B49722', '#6C590F', 'character/acorn-knight.svg'), // 87
  makeBossEntry('Honey Bear', '#B4B422', '#6C6C0F', 'character/honey-bear.svg'), // 88
  makeBossEntry('Thorn Dryad', '#97B422', '#596C0F', 'character/thorn-dryad.svg'), // 89
  makeBossEntry('Willow Treant', '#7AB422', '#476C0F', 'character/willow-treant.svg'), // 90
  makeBossEntry('Pollen Pixie', '#5DB422', '#346C0F', 'character/pollen-pixie.svg'), // 91
  makeBossEntry('Clover Kobold', '#3FB422', '#216C0F', 'character/clover-kobold.svg'), // 92
  makeBossEntry('Fern Lizard', '#22B422', '#0F6C0F', 'character/fern-lizard.svg'), // 93
  makeBossEntry('Toadstool Ogre', '#22B43F', '#0F6C21', 'character/toadstool-ogre.svg'), // 94
  makeBossEntry('Toy Soldier', '#22B45D', '#0F6C34', 'character/toy-soldier.svg'), // 95
  makeBossEntry('Porcelain Doll', '#22B47A', '#0F6C47', 'character/porcelain-doll.svg'), // 96
  makeBossEntry('Button Golem', '#22B497', '#0F6C59', 'character/button-golem.svg'), // 97
  makeBossEntry('Sock Dragon', '#22B4B4', '#0F6C6C', 'character/sock-dragon.svg'), // 98
  makeBossEntry('Kite Serpent', '#2297B4', '#0F596C', 'character/kite-serpent.svg'), // 99
  makeBossEntry('Music Box Fairy', '#227AB4', '#0F476C', 'character/music-box-fairy.svg'), // 100
];

const MONSTER_DIALOGUES: MonsterDialogue[] = [
  dialogue('Bounce into my wiggly quiz!', '跳进我的软软小题吧！', 'Your magic made me wobble away.', '你的魔法让我晃走啦。'),
  dialogue('Shuffle fast and spell faster!', '我慢慢走，你快快拼！', 'Oof, your word woke me up.', '哎呀，单词把我叫醒了。'),
  dialogue('My fiery riddle is ready!', '我的火焰谜题来啦！', 'Your word cooled my flames.', '你的单词让火焰降温了。'),
  dialogue('Try my tricky harvest spell!', '试试我的南瓜咒语！', 'My crown rolled into the vines.', '我的王冠滚进藤蔓啦。'),
  dialogue('I hid a tiny word trap!', '我藏了个小单词陷阱！', 'You spotted my sneaky trick.', '你看穿我的小把戏了。'),
  dialogue('Can you catch a flaming word?', '你能抓住火焰单词吗？', 'I rise again after your win.', '你赢了，我会再飞起。'),
  dialogue('My spellbook picked this word.', '我的魔法书选了这词。', 'Your answer broke my spell.', '你的答案破咒啦。'),
  dialogue('My frost keeps words frozen.', '我的霜冻住了单词。', 'Your words warmed the castle.', '你的单词暖了城堡。'),
  dialogue('Follow my shiny word trail.', '跟上我的闪亮词路。', 'Your magic sparkled brighter.', '你的魔法更闪亮。'),
  dialogue('The deep hides my final word.', '深海藏着终极单词。', 'The tide bows to your words.', '潮水向你的单词低头。'),
  dialogue('Float through my glowing clue.', '漂过我的发光线索吧。', 'Your answer lit the reef.', '你的答案点亮礁石。'),
  dialogue('I peeked at the next word!', '我偷看了下个单词！', 'You found me before I blinked.', '你眨眼前就找到我了。'),
  dialogue('My cap hides a tiny clue.', '我的菇帽藏着线索。', 'Your word popped my puzzle.', '你的单词弹开谜题。'),
  dialogue('Step softly through my moss.', '轻轻走过我的苔藓。', 'Even moss heard your answer.', '苔藓都听见答案了。'),
  dialogue('My stone clue will not move.', '我的石头线索不动。', 'Your word rolled me aside.', '你的单词把我推开。'),
  dialogue('Read by my lantern glow.', '借我的灯光读吧。', 'Your answer shines brighter.', '你的答案更亮。'),
  dialogue('Echo my crystal word!', '回响我的水晶单词！', 'Your sound cracked my echo.', '你的声音震开回声。'),
  dialogue('Fly up to my cloudy clue.', '飞向我的云端线索。', 'Your word cleared the sky.', '你的单词扫开云。'),
  dialogue('My clue slips like water.', '我的线索像水滑走。', 'Your answer caught the stream.', '你的答案抓住水流。'),
  dialogue('Dance through my leafy quiz.', '跳过我的叶子小题。', 'Your rhythm beat my riddle.', '你的节奏赢了谜题。'),
  dialogue('Catch my berry word if you can!', '有本事抓莓果词！', 'You picked the right berry.', '你摘到正确莓果了。'),
  dialogue('Dig for my buried word.', '挖出我的地下单词。', 'Your answer tunneled through.', '你的答案打通地道。'),
  dialogue('Tick-tock, choose the word!', '滴答滴答，选单词！', 'Your word stopped my gears.', '你的单词停住齿轮。'),
  dialogue('Guess which page bites back!', '猜哪页会咬人！', 'You read me perfectly.', '你把我读懂了。'),
  dialogue('My chest snaps at wrong words.', '我的宝箱会咬错词。', 'Your word opened the lock.', '你的单词开了锁。'),
  dialogue('Slow clues still win races.', '慢线索也会赢比赛。', 'Your word raced ahead.', '你的单词跑在前面。'),
  dialogue('I copied your next clue.', '我复制了下个线索。', 'Your answer showed the truth.', '你的答案照出真相。'),
  dialogue('My candle flickers a clue.', '我的烛光闪着线索。', 'Your word blew my trick away.', '你的单词吹走把戏。'),
  dialogue('Fold my riddle if you dare.', '敢折我的纸谜吗？', 'Your answer smoothed the page.', '你的答案抚平纸页。'),
  dialogue('My marble word is heavy.', '我的石纹单词很重。', 'Your word lifted the stone.', '你的单词举起石头。'),
  dialogue('Sing back my tricky word.', '唱回我的调皮词。', 'Your answer found the tune.', '你的答案找准调子。'),
  dialogue('My clue rides a feather.', '我的线索乘羽毛飞。', 'Your word landed first.', '你的单词先落地。'),
  dialogue('Small wings, sharp riddle!', '小翅膀，大谜题！', 'Your word clipped my trick.', '你的单词剪掉把戏。'),
  dialogue('Blink and miss my clue!', '一眨眼线索就没啦！', 'You looked and answered well.', '你看准并答对了。'),
  dialogue('Three clues, one right word!', '三个线索，一个对词！', 'Your word tamed my mix-up.', '你的单词理顺混搭。'),
  dialogue('My tail points to trouble.', '我的尾巴指向麻烦。', 'Your answer softened my sting.', '你的答案收起尖刺。'),
  dialogue('Bow, then answer my clue.', '先鞠躬，再答题吧。', 'Your word earned my bow.', '你的单词赢得敬礼。'),
  dialogue('Race my sky-bright word.', '追上我的天空词。', 'Your word flew farther.', '你的单词飞得更远。'),
  dialogue('My moon clue flutters by.', '月光线索轻轻飞。', 'Your answer caught the wings.', '你的答案接住翅膀。'),
  dialogue('Hop after my star clue.', '跳着追星星线索吧。', 'Your word hopped ahead.', '你的单词跳到前面。'),
  dialogue('My ember word is hot!', '我的火星词很烫！', 'Your answer cooled the sparks.', '你的答案冷却火星。'),
  dialogue('My clue flows around you.', '我的线索绕着你流。', 'Your word held the wave.', '你的单词稳住浪花。'),
  dialogue('Leaves whisper the answer.', '叶子悄悄说答案。', 'Your word rustled louder.', '你的单词响得更亮。'),
  dialogue('My clue grows from stone.', '我的线索从石里长。', 'Your answer shook the ground.', '你的答案震动大地。'),
  dialogue('Catch my invisible word.', '抓住我的隐形词。', 'Your word caught the breeze.', '你的单词抓住微风。'),
  dialogue('My clue skates on ice.', '我的线索在冰上滑。', 'Your answer melted the trail.', '你的答案融开冰路。'),
  dialogue('Bark out the stormy word!', '叫出雷声单词！', 'Your word calmed my thunder.', '你的单词安抚雷声。'),
  dialogue('Slide across seven clues.', '滑过七彩线索吧。', 'Your word found every color.', '你的单词找齐颜色。'),
  dialogue('My sunny clue roars!', '我的阳光线索吼！', 'Your answer brightened noon.', '你的答案照亮正午。'),
  dialogue('Hoot once for the right word.', '为正确单词叫一声。', 'Your word woke the moon.', '你的单词唤醒月亮。'),
  dialogue('Pinch the right sea word.', '夹住正确海洋词。', 'Your answer opened my claws.', '你的答案松开蟹钳。'),
  dialogue('Charge through my sea clue.', '冲过我的海中线索。', 'Your word won the joust.', '你的单词赢得比试。'),
  dialogue('Pop my bubble clue!', '戳破我的泡泡线索！', 'Your answer floated up.', '你的答案浮上来了。'),
  dialogue('My pearl hides a word.', '我的珍珠藏着词。', 'Your word made it shine.', '你的单词让它发亮。'),
  dialogue('Skip across my reef clue.', '跳过我的礁石线索。', 'Your word splashed true.', '你的单词溅出真相。'),
  dialogue('I spin words in the tide.', '我在潮里转单词。', 'Your answer rode the current.', '你的答案顺流而来。'),
  dialogue('Slow shell, sneaky clue!', '慢壳里有小线索！', 'Your word passed my shell.', '你的单词越过壳啦。'),
  dialogue('Five points guard my clue.', '五个角守着线索。', 'Your answer sparked my wand.', '你的答案点亮魔杖。'),
  dialogue('Leap over my wave word.', '跳过我的海浪词。', 'Your word made the wave cheer.', '你的单词让浪花欢呼。'),
  dialogue('Stomp through my frosty clue.', '踩过我的冰霜线索。', 'Your answer warmed my paws.', '你的答案暖了脚掌。'),
  dialogue('I packed snow around a word.', '我把词包进雪球。', 'Your word cracked the snowball.', '你的单词敲开雪球。'),
  dialogue('My pointy clue drips fast.', '我的冰锥线索滴答。', 'Your answer snapped the ice.', '你的答案折断冰锥。'),
  dialogue('Chase my dancing light clue.', '追我的极光线索吧。', 'Your word caught the glow.', '你的单词抓住光。'),
  dialogue('My frozen word stands tall.', '我的冻词站得高。', 'Your answer moved the mountain.', '你的答案移开冰山。'),
  dialogue('Climb up to my sky word.', '爬上我的天空词。', 'Your word reached my cloud.', '你的单词抵达云端。'),
  dialogue('My clue sings in the sky.', '我的线索在天上唱。', 'Your answer echoed higher.', '你的答案回声更高。'),
  dialogue('Whirl through my windy word.', '穿过我的旋风词。', 'Your word stilled the gust.', '你的单词停住风。'),
  dialogue('My riddle rides the thunder.', '我的谜题乘雷声来。', 'Your answer cleared the storm.', '你的答案扫清风暴。'),
  dialogue('My comet clue burns bright.', '我的彗星线索发亮。', 'Your word outran the comet.', '你的单词追过彗星。'),
  dialogue('Dig my clue from the dune.', '从沙丘挖出线索。', 'Your answer found the oasis.', '你的答案找到绿洲。'),
  dialogue('Careful, my clue has prickles.', '小心，线索有刺。', 'Your word dodged every thorn.', '你的单词躲过尖刺。'),
  dialogue('Answer my tiny riddle.', '回答我的小谜语。', 'Your word solved my smile.', '你的单词解开笑容。'),
  dialogue('March past my shiny clue.', '走过我的亮甲线索。', 'Your answer polished my shield.', '你的答案擦亮盾牌。'),
  dialogue('Is my word here or there?', '我的词在这还是那？', 'Your answer caught the shimmer.', '你的答案抓住幻光。'),
  dialogue('My warm clue darts away.', '我的暖线索飞快跑。', 'Your word basked in victory.', '你的单词晒着胜利。'),
  dialogue('Spin through my dusty word.', '旋过我的尘土词。', 'Your answer settled the dust.', '你的答案落定尘土。'),
  dialogue('Hop to my cool clue.', '跳向我的清凉线索。', 'Your word splashed just right.', '你的单词溅得刚好。'),
  dialogue('Climb my pyramid of clues.', '爬上我的线索金字塔。', 'Your answer reached the top.', '你的答案到顶啦。'),
  dialogue('My ember clue flicks fast.', '我的余烬线索很快。', 'Your word followed the spark.', '你的单词跟上火星。'),
  dialogue('Leap over my lava word!', '跳过我的岩浆词！', 'Your answer cooled the stones.', '你的答案冷却石头。'),
  dialogue('My ash clue hides in gray.', '我的灰烬线索藏着。', 'Your word brushed it clean.', '你的单词扫干净了。'),
  dialogue('Swoop through my smoky clue.', '掠过我的烟雾线索。', 'Your answer cleared my wings.', '你的答案清亮翅膀。'),
  dialogue('Snap up my tiny spark word.', '抓住我的小火花词。', 'Your word flashed brighter.', '你的单词闪得更亮。'),
  dialogue('Gallop through my flame clue.', '奔过我的火焰线索。', 'Your answer won the race.', '你的答案赢了赛跑。'),
  dialogue('My slow lava clue glows.', '我的慢岩浆线索发光。', 'Your word cooled my trail.', '你的单词冷却小路。'),
  dialogue('My thorny clue growls.', '我的荆棘线索低吼。', 'Your answer tamed the thorns.', '你的答案驯服荆棘。'),
  dialogue('Duel my little acorn clue.', '和橡果线索决斗吧。', 'Your word won the acorn duel.', '你的单词赢了决斗。'),
  dialogue('My sweet clue sticks tight.', '我的甜线索粘住啦。', 'Your answer unstuck the honey.', '你的答案化开蜂蜜。'),
  dialogue('My vine clue curls close.', '我的藤蔓线索卷来。', 'Your word untangled the vines.', '你的单词解开藤蔓。'),
  dialogue('Listen to my whispering leaves.', '听我柳叶的悄悄话。', 'Your answer swayed the branches.', '你的答案摇动树枝。'),
  dialogue('My pollen clue tickles.', '我的花粉线索痒痒的。', 'Your word made me sneeze.', '你的单词让我打喷嚏。'),
  dialogue('Find my lucky word!', '找到我的幸运词！', 'Your answer found the clover.', '你的答案找到苜蓿。'),
  dialogue('My green clue darts away.', '我的绿色线索飞跑。', 'Your word caught my tail.', '你的单词追到尾巴。'),
  dialogue('My mushroom gate is closed.', '我的蘑菇门关着。', 'Your word opened the cap.', '你的单词打开菇帽。'),
  dialogue('March to my toy-box clue.', '向玩具盒线索前进。', 'Your word won the parade.', '你的单词赢了游行。'),
  dialogue('My tiny clue sits still.', '我的小线索静静坐着。', 'Your answer made me smile.', '你的答案让我微笑。'),
  dialogue('Press the right word button!', '按下正确单词按钮！', 'Your word clicked into place.', '你的单词咔哒归位。'),
  dialogue('My laundry clue curls up.', '我的袜子线索卷起来。', 'Your answer paired the socks.', '你的答案配好袜子。'),
  dialogue('Tug my windy kite word.', '拉住我的风筝词。', 'Your word held the string.', '你的单词牵住线。'),
  dialogue('Turn my music-box clue.', '转动我的音乐盒线索。', 'Your answer played the tune.', '你的答案奏出旋律。'),
];

for (let i: number = 0; i < MONSTER_CATALOG.length; i++) {
  MONSTER_CATALOG[i].level = monsterLevelForCatalogIndex(i + 1);
  if (i < MONSTER_DIALOGUES.length) {
    MONSTER_CATALOG[i].dialogue = MONSTER_DIALOGUES[i];
  }
}

/**
 * Level for a 1-based catalog index. Indices 1–10 follow the V0.8.3
 * design table; 11–100 fill the 10 / 60 / 20 / 10 ratio bands.
 */
export function monsterLevelForCatalogIndex(index1Based: number): MonsterLevel {
  if (index1Based <= 0) {
    return MonsterLevel.Beginner;
  }
  const i: number = ((index1Based - 1) % MONSTER_CATALOG.length) + 1;
  if (i === 1) {
    return MonsterLevel.Beginner;
  }
  if (i >= 2 && i <= 7) {
    return MonsterLevel.Intermediate;
  }
  if (i >= 8 && i <= 9) {
    return MonsterLevel.Advanced;
  }
  if (i === 10) {
    return MonsterLevel.Super;
  }
  if (i >= 11 && i <= 19) {
    return MonsterLevel.Beginner;
  }
  if (i >= 20 && i <= 73) {
    return MonsterLevel.Intermediate;
  }
  if (i >= 74 && i <= 91) {
    return MonsterLevel.Advanced;
  }
  return MonsterLevel.Super;
}

/** Representative catalog index per level (today-plan slot wiring). */
export function monsterCatalogIndexForLevel(level: MonsterLevel): number {
  if (level === MonsterLevel.Beginner) {
    return 1;
  }
  if (level === MonsterLevel.Intermediate) {
    return 2;
  }
  if (level === MonsterLevel.Advanced) {
    return 8;
  }
  return 10;
}

export function monsterCatalogIndicesForLevel(level: MonsterLevel): number[] {
  const out: number[] = [];
  for (let i: number = 1; i <= MONSTER_CATALOG.length; i++) {
    if (monsterLevelForCatalogIndex(i) === level) {
      out.push(i);
    }
  }
  if (out.length === 0) {
    out.push(monsterCatalogIndexForLevel(level));
  }
  return out;
}

export function levelBadgeZhForMonsterLevel(level: MonsterLevel): string {
  if (level === MonsterLevel.Beginner) {
    return '初';
  }
  if (level === MonsterLevel.Intermediate) {
    return '中';
  }
  if (level === MonsterLevel.Advanced) {
    return '高';
  }
  return 'Super';
}

export function battleLevelLabelForMonsterLevel(level: MonsterLevel): string {
  if (level === MonsterLevel.Beginner) {
    return 'L1 初级';
  }
  if (level === MonsterLevel.Intermediate) {
    return 'L2 中级';
  }
  if (level === MonsterLevel.Advanced) {
    return 'L3 高级';
  }
  return 'L4 Super';
}

export function getMonsterByIndex(index1Based: number): MonsterEntry {
  if (index1Based <= 0) {
    return MONSTER_CATALOG[0];
  }
  const idx0: number = (index1Based - 1) % MONSTER_CATALOG.length;
  return MONSTER_CATALOG[idx0];
}

export function getMonsterDialogueByIndex(index1Based: number): MonsterDialogue {
  return getMonsterByIndex(index1Based).dialogue;
}

export function monsterIndexForKind(kind: MonsterKind): number {
  if (kind === MonsterKind.Normal || kind === MonsterKind.Review) {
    return monsterCatalogIndexForLevel(MonsterLevel.Beginner);
  }
  if (kind === MonsterKind.Spelling) {
    return monsterCatalogIndexForLevel(MonsterLevel.Intermediate);
  }
  if (kind === MonsterKind.Elite) {
    return monsterCatalogIndexForLevel(MonsterLevel.Advanced);
  }
  return monsterCatalogIndexForLevel(MonsterLevel.Super);
}
