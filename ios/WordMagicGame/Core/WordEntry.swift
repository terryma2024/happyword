import Foundation

struct ExampleSentence: Codable, Equatable, Hashable {
    var en: String
    var zh: String
}

struct WordEntry: Codable, Equatable, Hashable, Identifiable {
    var id: String
    var word: String
    var meaningZh: String
    var category: String
    var difficulty: Int
    var image: String?
    var audio: String?
    var distractors: [String]?
    var example: ExampleSentence?
    var illustrationUrl: String?
    var audioUrl: String?

    var isValid: Bool {
        !id.isEmpty && !word.isEmpty && !meaningZh.isEmpty && !category.isEmpty && difficulty >= 1
    }
}

enum PackSource: String, Codable, Equatable {
    case builtin
    case global
    case family

    var labelZh: String {
        switch self {
        case .builtin: "内置"
        case .global: "官方"
        case .family: "家庭"
        }
    }
}

struct SceneMetadata: Codable, Equatable {
    var bgPrimary: String
    var bgAccent: String
    var bossName: String

    static let empty = SceneMetadata(bgPrimary: "", bgAccent: "", bossName: "")

    var isEmpty: Bool {
        bgPrimary.isEmpty && bgAccent.isEmpty && bossName.isEmpty
    }
}

struct Pack: Equatable, Identifiable {
    var id: String
    var title: String
    var subtitle: String
    var story: String
    var source: PackSource
    var version: Int
    var publishedAt: Date?
    var scene: SceneMetadata
    var words: [WordEntry]

    init(
        id: String,
        title: String,
        subtitle: String,
        story: String,
        source: PackSource = .builtin,
        version: Int = 1,
        publishedAt: Date? = nil,
        scene: SceneMetadata = .empty,
        words: [WordEntry]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.story = story
        self.source = source
        self.version = version
        self.publishedAt = publishedAt
        self.scene = scene
        self.words = words
    }
}

extension Pack {
    static let builtin: [Pack] = [
        Pack(
            id: "forest",
            title: "Fruit Forest",
            subtitle: "Starter magic words",
            story: "今天的冒险包含 5 关卡，含拼写、复习与首领奖励",
            words: DemoWords.words
        ),
        Pack(
            id: "school",
            title: "School Castle",
            subtitle: "Classroom words",
            story: "收集课堂里的学习咒语。",
            words: DemoWords.words
        ),
        Pack(
            id: "home",
            title: "Home Cottage",
            subtitle: "Daily object words",
            story: "在魔法小屋里找到熟悉的日常单词。",
            words: DemoWords.words
        ),
        Pack(
            id: "castle",
            title: "Animal Safari",
            subtitle: "Boss warmup words",
            story: "出发前先完成动物王国的热身。",
            words: DemoWords.words
        ),
        Pack(
            id: "park",
            title: "Ocean Realm",
            subtitle: "Outdoor words",
            story: "在海风里练习今天的阳光单词。",
            words: DemoWords.words
        ),
    ]
}

enum DemoWords {
    static let words = [
        WordEntry(id: "fruit-apple", word: "apple", meaningZh: "苹果", category: "fruit", difficulty: 1),
        WordEntry(id: "fruit-pear", word: "pear", meaningZh: "梨", category: "fruit", difficulty: 1),
        WordEntry(id: "fruit-banana", word: "banana", meaningZh: "香蕉", category: "fruit", difficulty: 1),
        WordEntry(id: "home-door", word: "door", meaningZh: "门", category: "home", difficulty: 1),
        WordEntry(id: "home-desk", word: "desk", meaningZh: "书桌", category: "home", difficulty: 1),
        WordEntry(id: "place-park", word: "park", meaningZh: "公园", category: "place", difficulty: 1),
    ]
}
