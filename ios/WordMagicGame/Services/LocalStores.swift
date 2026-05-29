import Foundation

@MainActor
final class GameConfigStore: ObservableObject {
    @Published private(set) var config: GameConfig
    private let defaults: UserDefaults
    private let key = "iosReplicaGameConfig"
    var backingDefaults: UserDefaults { defaults }

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
final class DailyLearningStateService: ObservableObject {
    private static let key = "daily_learning_state/snapshot_v1"

    @Published private(set) var state: DailyLearningState
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults.removeObject(forKey: Self.key)
        }
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(DailyLearningState.self, from: data) {
            state = Self.normalized(decoded)
        } else {
            state = DailyLearningState()
        }
    }

    @discardableResult
    func ensureForDay(
        words: [WordEntry],
        stats: [WordLearningStat],
        now: Date = Date(),
        selectedWordIds: [String],
        calendar: Calendar = .current
    ) -> DailyLearningState {
        let dayKey = DailyLearningDayKey.compact(now, calendar: calendar)
        if state.dayKey != dayKey {
            var next = DailyLearningState(dayKey: dayKey)
            next.reviewSnapshot = ReviewQueueBuilder().buildSnapshot(
                words: words,
                stats: stats,
                now: now,
                selectedWordIds: selectedWordIds,
                calendar: calendar
            )
            next.reviewAllDone = next.reviewSnapshot.wordIds.isEmpty
            state = next
            save()
        }
        return state
    }

    func markPackBattleWon(now: Date = Date(), calendar: Calendar = .current) {
        resetIfNeeded(now: now, calendar: calendar)
        markPackBattleWon(in: &state)
        save()
    }

    func markReviewedWords(_ wordIds: [String], now: Date = Date(), calendar: Calendar = .current) {
        resetIfNeeded(now: now, calendar: calendar)
        markReviewedWords(wordIds, in: &state)
        save()
    }

    func markPackBattleWon(in state: inout DailyLearningState) {
        state.packBattleWon = true
    }

    func markReviewedWords(_ wordIds: [String], in state: inout DailyLearningState) {
        let expected = Set(state.reviewSnapshot.wordIds)
        var reviewed = Set(state.reviewSnapshot.reviewedWordIds)
        for id in wordIds where expected.contains(id) && !reviewed.contains(id) {
            reviewed.insert(id)
            state.reviewSnapshot.reviewedWordIds.append(id)
        }
        state.reviewAllDone = state.reviewSnapshot.remainingWordIds.isEmpty
    }

    private func resetIfNeeded(now: Date, calendar: Calendar) {
        let dayKey = DailyLearningDayKey.compact(now, calendar: calendar)
        guard state.dayKey != dayKey else { return }
        state = DailyLearningState(dayKey: dayKey)
        state.reviewAllDone = true
    }

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static func normalized(_ input: DailyLearningState) -> DailyLearningState {
        var out = input
        let known = Set(out.reviewSnapshot.wordIds)
        var uniqueReviewed: [String] = []
        for id in out.reviewSnapshot.reviewedWordIds where known.contains(id) && !uniqueReviewed.contains(id) {
            uniqueReviewed.append(id)
        }
        out.reviewSnapshot.reviewedWordIds = uniqueReviewed
        out.reviewAllDone = out.reviewAllDone || out.reviewSnapshot.remainingWordIds.isEmpty
        return out
    }
}

@MainActor
final class CoinAccount: ObservableObject {
    enum TransactionReason: String, Codable {
        case todayReward
        case redemption
        case checkInWeeklyBonus
        case spellbookPackComplete
    }

    struct Transaction: Equatable, Identifiable, Codable {
        var id: String
        var delta: Int
        var reason: TransactionReason
        var createdAt: Date
    }

    static let dailyCap = 20
    private static let key = "wordmagic_coin_account/snapshot_v1"

    private struct Snapshot: Codable, Equatable {
        var version: Int = 1
        var balance: Int
        var transactions: [Transaction]
        var earnedByDay: [String: Int]
    }

    @Published private(set) var balance: Int
    @Published private(set) var transactions: [Transaction]
    private var earnedByDay: [String: Int]
    private let defaults: UserDefaults?

    init(balance: Int = 0, defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults?.removeObject(forKey: Self.key)
        }
        if let data = defaults?.data(forKey: Self.key),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.balance = max(0, snapshot.balance)
            transactions = snapshot.transactions.sorted { $0.createdAt > $1.createdAt }
            earnedByDay = snapshot.earnedByDay
        } else {
            self.balance = balance
            transactions = []
            earnedByDay = [:]
        }
    }

    func earn(_ amount: Int) -> Int {
        let actual = max(amount, 0)
        balance += actual
        if actual > 0 {
            save()
        }
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
        save()
        return actual
    }

    @discardableResult
    func creditCheckInWeeklyBonus(dayKey: String, amount: Int = CheckInStore.weeklyBonusCoins, now: Date = Date()) -> Int {
        let actual = max(amount, 0)
        guard actual > 0 else { return 0 }
        balance += actual
        transactions.insert(
            Transaction(id: "checkin-weekly-bonus:\(dayKey)", delta: actual, reason: .checkInWeeklyBonus, createdAt: now),
            at: 0
        )
        save()
        return actual
    }

    @discardableResult
    func creditSpellbookPackReward(packId: String, amount: Int = SpellbookService.rewardCoins, now: Date = Date()) -> Int {
        let actual = max(amount, 0)
        let normalizedPackId = packId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard actual > 0, !normalizedPackId.isEmpty else { return 0 }
        balance += actual
        transactions.insert(
            Transaction(id: "spellbook-pack-complete:\(normalizedPackId)", delta: actual, reason: .spellbookPackComplete, createdAt: now),
            at: 0
        )
        save()
        return actual
    }

    @discardableResult
    func redeem(_ amount: Int, now: Date = Date()) -> Bool {
        guard amount > 0, balance >= amount else { return false }
        balance -= amount
        transactions.insert(Transaction(id: UUID().uuidString, delta: -amount, reason: .redemption, createdAt: now), at: 0)
        save()
        return true
    }

    private func save() {
        guard let defaults else { return }
        let snapshot = Snapshot(balance: balance, transactions: transactions, earnedByDay: earnedByDay)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

struct CheckInSnapshot: Codable, Equatable {
    var version: Int = 1
    var checkedDayKeys: [String] = []
    var weeklyBonusDayKeys: [String] = []
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var lastSyncedAtMs: Int = 0
    var pendingSync: Bool = false
}

struct CheckInRecordResult: Equatable {
    var changed = false
    var dayKey = ""
    var currentStreak = 0
    var bestStreak = 0
    var bonusCoins = 0
    var bonusDayKey = ""
    var snapshot = CheckInSnapshot()
}

struct CheckInDayCell: Equatable, Identifiable {
    var dayKey = ""
    var label = ""
    var checked = false
    var inMonth = false
    var id: String { inMonth ? dayKey : UUID().uuidString }
}

struct CheckInWeekRow: Equatable, Identifiable {
    var cells: [CheckInDayCell] = []
    var id = UUID()
}

enum CheckInCalendar {
    static func monthAnchor(_ date: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1, hour: 12)) ?? date
    }

    static func shiftMonth(_ date: Date, delta: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: delta, to: monthAnchor(date, calendar: calendar)) ?? date
    }

    static func monthLabel(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)年\(parts.month ?? 0)月"
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return ymd(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    static func buildMonthWeeks(visibleMonth: Date, checkedDayKeys: [String], calendar: Calendar = .current) -> [CheckInWeekRow] {
        let checked = Set(checkedDayKeys)
        let anchor = monthAnchor(visibleMonth, calendar: calendar)
        let parts = calendar.dateComponents([.year, .month], from: anchor)
        guard let first = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return [] }
        let lead = calendar.component(.weekday, from: first) - 1
        var rows: [CheckInWeekRow] = []
        var current = CheckInWeekRow()
        for _ in 0..<lead {
            current.cells.append(CheckInDayCell())
        }
        for day in range {
            let key = ymd(year: parts.year ?? 0, month: parts.month ?? 0, day: day)
            current.cells.append(CheckInDayCell(dayKey: key, label: "\(day)", checked: checked.contains(key), inMonth: true))
            if current.cells.count == 7 {
                rows.append(current)
                current = CheckInWeekRow()
            }
        }
        if !current.cells.isEmpty {
            while current.cells.count < 7 {
                current.cells.append(CheckInDayCell())
            }
            rows.append(current)
        }
        return rows
    }

    private static func ymd(year: Int, month: Int, day: Int) -> String {
        "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
    }
}

@MainActor
final class CheckInStore: ObservableObject {
    static let weeklyBonusCoins = 50
    private static let key = "wordmagic_checkins/snapshot_v1"

    @Published private(set) var snapshot: CheckInSnapshot
    private let defaults: UserDefaults

    init(snapshot: CheckInSnapshot = CheckInSnapshot(), defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults.removeObject(forKey: Self.key)
        }
        if snapshot != CheckInSnapshot() {
            self.snapshot = Self.recomputed(snapshot)
        } else if let data = defaults.data(forKey: Self.key),
                  let decoded = try? JSONDecoder().decode(CheckInSnapshot.self, from: data) {
            self.snapshot = Self.recomputed(decoded)
        } else {
            self.snapshot = snapshot
        }
    }

    @discardableResult
    func recordWin(now: Date = Date(), coins: CoinAccount? = nil) -> CheckInRecordResult {
        let dayKey = CheckInCalendar.dayKey(now)
        var result = CheckInRecordResult(dayKey: dayKey, currentStreak: snapshot.currentStreak, bestStreak: snapshot.bestStreak, snapshot: snapshot)
        guard !snapshot.checkedDayKeys.contains(dayKey) else { return result }

        snapshot.checkedDayKeys.append(dayKey)
        snapshot.checkedDayKeys = Self.sortedUnique(snapshot.checkedDayKeys)
        snapshot.pendingSync = true
        snapshot = Self.recomputed(snapshot, anchorDayKey: dayKey)
        result.changed = true
        result.currentStreak = snapshot.currentStreak
        result.bestStreak = snapshot.bestStreak
        if snapshot.currentStreak > 0,
           snapshot.currentStreak % 7 == 0,
           !snapshot.weeklyBonusDayKeys.contains(dayKey) {
            snapshot.weeklyBonusDayKeys.append(dayKey)
            snapshot.weeklyBonusDayKeys = Self.sortedUnique(snapshot.weeklyBonusDayKeys)
            result.bonusCoins = Self.weeklyBonusCoins
            result.bonusDayKey = dayKey
            _ = coins?.creditCheckInWeeklyBonus(dayKey: dayKey, now: now)
        }
        result.snapshot = snapshot
        save()
        return result
    }

    func applyCloudMerge(checkedDayKeys: [String], weeklyBonusDayKeys: [String], serverNowMs: Int) {
        snapshot.checkedDayKeys = Self.sortedUnique(snapshot.checkedDayKeys + checkedDayKeys)
        snapshot.weeklyBonusDayKeys = Self.sortedUnique(snapshot.weeklyBonusDayKeys + weeklyBonusDayKeys)
        snapshot.lastSyncedAtMs = serverNowMs
        snapshot.pendingSync = false
        snapshot = Self.recomputed(snapshot)
        save()
    }

    func markPendingSync() {
        snapshot.pendingSync = true
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static func recomputed(_ input: CheckInSnapshot, anchorDayKey: String? = nil) -> CheckInSnapshot {
        var out = input
        out.checkedDayKeys = sortedUnique(out.checkedDayKeys)
        out.weeklyBonusDayKeys = sortedUnique(out.weeklyBonusDayKeys)
        var best = 0
        var currentRun = 0
        var previous = ""
        for day in out.checkedDayKeys {
            if previous.isEmpty || isNextDay(previous, day) {
                currentRun += 1
            } else {
                currentRun = 1
            }
            best = max(best, currentRun)
            previous = day
        }
        let anchor = anchorDayKey ?? out.checkedDayKeys.last ?? ""
        out.currentStreak = countStreakEndingAt(out.checkedDayKeys, dayKey: anchor)
        out.bestStreak = max(best, out.currentStreak)
        return out
    }

    private static func sortedUnique(_ items: [String]) -> [String] {
        Array(Set(items.filter { !$0.isEmpty })).sorted()
    }

    private static func countStreakEndingAt(_ sortedDays: [String], dayKey: String) -> Int {
        guard !dayKey.isEmpty, sortedDays.contains(dayKey) else { return 0 }
        var count = 1
        var cursor = dayKey
        for day in sortedDays.reversed() {
            if day >= cursor { continue }
            if isNextDay(day, cursor) {
                count += 1
                cursor = day
            } else {
                break
            }
        }
        return count
    }

    private static func isNextDay(_ previous: String, _ next: String) -> Bool {
        dayNumber(next) - dayNumber(previous) == 1
    }

    private static func dayNumber(_ dayKey: String) -> Int {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey) else { return 0 }
        return Int(date.timeIntervalSince1970 / 86_400)
    }
}

struct MagicWish: Equatable, Identifiable, Codable {
    var id: String
    var displayName: String
    var costCoins: Int
    var iconEmoji: String
    var isCustom: Bool
}

struct RedemptionRecord: Equatable, Identifiable, Codable {
    var id: String
    var wishId: String
    var displayName: String
    var iconEmoji: String
    var costCoins: Int
    var createdAt: Date
}

final class RedemptionHistoryStore: ObservableObject {
    static let cap = 50
    private static let key = "wordmagic_redemption_history/snapshot_v1"

    private struct Snapshot: Codable, Equatable {
        var version: Int = 1
        var records: [RedemptionRecord]
    }

    @Published private(set) var records: [RedemptionRecord]
    private let defaults: UserDefaults?

    init(records: [RedemptionRecord] = [], defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults?.removeObject(forKey: Self.key)
        }
        let restored = defaults
            .flatMap { $0.data(forKey: Self.key) }
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let source = records.isEmpty ? restored?.records ?? records : records
        self.records = Array(source.sorted { $0.createdAt > $1.createdAt }.prefix(Self.cap))
    }

    func add(_ record: RedemptionRecord) {
        records.insert(record, at: 0)
        if records.count > Self.cap {
            records = Array(records.prefix(Self.cap))
        }
        save()
    }

    private func save() {
        guard let defaults else { return }
        let snapshot = Snapshot(records: records)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

final class WishlistStore: ObservableObject {
    private static let key = "wordmagic_wishlist/snapshot_v1"

    private struct Snapshot: Codable, Equatable {
        var version: Int = 1
        var customWishes: [MagicWish]
    }

    @Published private(set) var wishes: [MagicWish]
    private let defaults: UserDefaults?

    init(wishes: [MagicWish] = WishlistStore.defaultWishes, defaults: UserDefaults? = nil) {
        self.defaults = defaults
        if ProcessInfo.processInfo.arguments.contains("-UITestResetState") {
            defaults?.removeObject(forKey: Self.key)
        }
        let restored = defaults
            .flatMap { $0.data(forKey: Self.key) }
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        let baseWishes = wishes.filter { !$0.isCustom }
        let customWishes = restored?.customWishes ?? wishes.filter(\.isCustom)
        self.wishes = baseWishes + Self.uniqueCustomWishes(customWishes)
    }

    @discardableResult
    func addCustomWish(name: String, costCoins: Int, iconEmoji: String, now: Date = Date()) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let emoji = iconEmoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, costCoins > 0, !emoji.isEmpty else { return "" }
        let id = "custom-\(Int(now.timeIntervalSince1970 * 1000))-\(wishes.count)"
        wishes.append(MagicWish(id: id, displayName: trimmedName, costCoins: costCoins, iconEmoji: emoji, isCustom: true))
        save()
        return id
    }

    @discardableResult
    func deleteCustomWish(_ id: String) -> Bool {
        guard let index = wishes.firstIndex(where: { $0.id == id && $0.isCustom }) else { return false }
        wishes.remove(at: index)
        save()
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

    private func save() {
        guard let defaults else { return }
        let snapshot = Snapshot(customWishes: wishes.filter(\.isCustom))
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.key)
        }
    }

    private static func uniqueCustomWishes(_ wishes: [MagicWish]) -> [MagicWish] {
        var seen: Set<String> = []
        return wishes.filter { wish in
            guard wish.isCustom, !wish.id.isEmpty, !seen.contains(wish.id) else { return false }
            seen.insert(wish.id)
            return true
        }
    }

    static let defaultWishes: [MagicWish] = [
        MagicWish(id: "wish-ipad-20min", displayName: "看 iPad 20 分钟", costCoins: 10, iconEmoji: "📱", isCustom: false),
        MagicWish(id: "wish-watch-topup-10", displayName: "手表零钱充值 10 元", costCoins: 25, iconEmoji: "⌚", isCustom: false),
        MagicWish(id: "wish-small-gift", displayName: "买一个礼物 (≤20 元)", costCoins: 50, iconEmoji: "🎁", isCustom: false),
    ]
}
