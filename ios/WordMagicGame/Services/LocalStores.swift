import Foundation

@MainActor
final class GameConfigStore: ObservableObject {
    @Published private(set) var config: GameConfig
    private let defaults: UserDefaults
    private let key = "iosReplicaGameConfig"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults.removeObject(forKey: key)
        }
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(GameConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
        }
    }

    func save(_ newConfig: GameConfig) {
        config = newConfig
        if let data = try? JSONEncoder().encode(newConfig) {
            defaults.set(data, forKey: key)
        }
    }
}

@MainActor
final class CoinAccount: ObservableObject {
    enum TransactionReason: String {
        case todayReward
        case redemption
    }

    struct Transaction: Equatable, Identifiable {
        var id: String
        var delta: Int
        var reason: TransactionReason
        var createdAt: Date
    }

    static let dailyCap = 20

    @Published private(set) var balance: Int
    @Published private(set) var transactions: [Transaction] = []
    private var earnedByDay: [String: Int] = [:]

    init(balance: Int = 0) {
        self.balance = balance
    }

    func earn(_ amount: Int) -> Int {
        balance += max(amount, 0)
        return balance
    }

    func earn(stars: Int, now: Date = Date()) -> Int {
        earn(amount: stars, reason: .todayReward, now: now)
    }

    @discardableResult
    func earn(amount: Int, reason: TransactionReason, now: Date = Date()) -> Int {
        let day = Self.dayKey(now)
        let remaining = max(Self.dailyCap - earnedByDay[day, default: 0], 0)
        let actual = max(0, min(amount, remaining))
        guard actual > 0 else { return 0 }
        earnedByDay[day, default: 0] += actual
        balance += actual
        transactions.insert(Transaction(id: UUID().uuidString, delta: actual, reason: reason, createdAt: now), at: 0)
        return actual
    }

    @discardableResult
    func redeem(_ amount: Int, now: Date = Date()) -> Bool {
        guard amount > 0, balance >= amount else { return false }
        balance -= amount
        transactions.insert(Transaction(id: UUID().uuidString, delta: -amount, reason: .redemption, createdAt: now), at: 0)
        return true
    }

    private static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

struct MagicWish: Equatable, Identifiable {
    var id: String
    var displayName: String
    var costCoins: Int
    var iconEmoji: String
    var isCustom: Bool
}

struct RedemptionRecord: Equatable, Identifiable {
    var id: String
    var wishId: String
    var displayName: String
    var iconEmoji: String
    var costCoins: Int
    var createdAt: Date
}

final class RedemptionHistoryStore: ObservableObject {
    static let cap = 50

    @Published private(set) var records: [RedemptionRecord]

    init(records: [RedemptionRecord] = []) {
        self.records = Array(records.sorted { $0.createdAt > $1.createdAt }.prefix(Self.cap))
    }

    func add(_ record: RedemptionRecord) {
        records.insert(record, at: 0)
        if records.count > Self.cap {
            records = Array(records.prefix(Self.cap))
        }
    }
}

final class WishlistStore: ObservableObject {
    @Published private(set) var wishes: [MagicWish]

    init(wishes: [MagicWish] = WishlistStore.defaultWishes) {
        self.wishes = wishes
    }

    @discardableResult
    func addCustomWish(name: String, costCoins: Int, iconEmoji: String, now: Date = Date()) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let emoji = iconEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, costCoins > 0, !emoji.isEmpty else { return "" }
        let id = "custom-\(Int(now.timeIntervalSince1970 * 1000))-\(wishes.count)"
        wishes.append(MagicWish(id: id, displayName: trimmedName, costCoins: costCoins, iconEmoji: emoji, isCustom: true))
        return id
    }

    @discardableResult
    func deleteCustomWish(_ id: String) -> Bool {
        guard let index = wishes.firstIndex(where: { $0.id == id && $0.isCustom }) else { return false }
        wishes.remove(at: index)
        return true
    }

    @discardableResult
    @MainActor
    func redeem(wishId: String, coins: CoinAccount, history: RedemptionHistoryStore, now: Date = Date()) -> RedemptionRecord? {
        guard let wish = wishes.first(where: { $0.id == wishId }),
              coins.redeem(wish.costCoins, now: now)
        else {
            return nil
        }
        let record = RedemptionRecord(
            id: "redemption-\(Int(now.timeIntervalSince1970 * 1000))-\(wish.id)",
            wishId: wish.id,
            displayName: wish.displayName,
            iconEmoji: wish.iconEmoji,
            costCoins: wish.costCoins,
            createdAt: now
        )
        history.add(record)
        return record
    }

    static let defaultWishes: [MagicWish] = [
        MagicWish(id: "wish-ipad-20min", displayName: "看 iPad 20 分钟", costCoins: 10, iconEmoji: "📱", isCustom: false),
        MagicWish(id: "wish-watch-topup-10", displayName: "手表零钱充值 10 元", costCoins: 25, iconEmoji: "⌚", isCustom: false),
        MagicWish(id: "wish-small-gift", displayName: "买一个礼物 (≤20 元)", costCoins: 50, iconEmoji: "🎁", isCustom: false),
    ]
}
