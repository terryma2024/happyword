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

export class MonsterEntry {
  name: string = '';
  fill: string = '';
  stroke: string = '';
  kind: MonsterKind = MonsterKind.Normal;
  assetPath: string = '';
  level: MonsterLevel = MonsterLevel.Beginner;
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

for (let i: number = 0; i < MONSTER_CATALOG.length; i++) {
  MONSTER_CATALOG[i].level = monsterLevelForCatalogIndex(i + 1);
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

export function getMonsterByIndex(index1Based: number): MonsterEntry {
  if (index1Based <= 0) {
    return MONSTER_CATALOG[0];
  }
  const idx0: number = (index1Based - 1) % MONSTER_CATALOG.length;
  return MONSTER_CATALOG[idx0];
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
