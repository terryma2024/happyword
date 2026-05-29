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

enum MonsterPlanSlotKind: String, Codable, Equatable {
    case normal
    case spelling
    case review
    case elite
    case boss
}

struct MonsterPlanSlot: Codable, Equatable {
    var kind: MonsterPlanSlotKind
    var catalogIndex: Int
}

struct SceneMetadata: Codable, Equatable {
    var bgPrimary: String
    var bgAccent: String
    var bossName: String
    var bossCandidates: [Int]
    var monsterPlan: [MonsterPlanSlot]
    var storyEn: String?
    var storyZh: String?

    static let empty = SceneMetadata()

    init(
        bgPrimary: String = "",
        bgAccent: String = "",
        bossName: String = "",
        bossCandidates: [Int] = [],
        monsterPlan: [MonsterPlanSlot] = [],
        storyEn: String? = nil,
        storyZh: String? = nil
    ) {
        self.bgPrimary = bgPrimary
        self.bgAccent = bgAccent
        self.bossName = bossName
        self.bossCandidates = bossCandidates
        self.monsterPlan = monsterPlan
        self.storyEn = storyEn
        self.storyZh = storyZh
    }

    var isEmpty: Bool {
        bgPrimary.isEmpty
            && bgAccent.isEmpty
            && bossName.isEmpty
            && bossCandidates.isEmpty
            && monsterPlan.isEmpty
            && storyEn == nil
            && storyZh == nil
    }

    private enum CodingKeys: String, CodingKey {
        case bgPrimary
        case bgAccent
        case bossName
        case bossCandidates
        case monsterPlan
        case storyEn
        case storyZh
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bgPrimary = try container.decodeIfPresent(String.self, forKey: .bgPrimary) ?? ""
        bgAccent = try container.decodeIfPresent(String.self, forKey: .bgAccent) ?? ""
        bossName = try container.decodeIfPresent(String.self, forKey: .bossName) ?? ""
        bossCandidates = try container.decodeIfPresent([Int].self, forKey: .bossCandidates) ?? []
        monsterPlan = try container.decodeIfPresent([MonsterPlanSlot].self, forKey: .monsterPlan) ?? []
        storyEn = try container.decodeIfPresent(String.self, forKey: .storyEn)
        storyZh = try container.decodeIfPresent(String.self, forKey: .storyZh)
    }
}

struct Pack: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var labelZh: String
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
        labelZh: String = "",
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
        self.labelZh = labelZh
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
    static let builtin: [Pack] = BuiltinPackLoader.loadBundled()
}

enum DemoWords {
    static let words = Pack.builtin.flatMap(\.words)
}
