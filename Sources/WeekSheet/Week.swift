import Foundation

public struct Item: Identifiable, Equatable, Hashable, Codable {
    public let id: UUID
    public var text: String
    public var done: Bool

    public init(id: UUID = UUID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        done = try container.decodeIfPresent(Bool.self, forKey: .done) ?? false
    }
}

public enum Day: String, CaseIterable, Hashable, Codable {
    case mon, tue, wed, thu, fri, wknd
}

/// One column of the sheet. A weekday bucket is keyed by its own date; Saturday and Sunday
/// share one bucket, keyed by the Saturday. Constructing a key is the only way to apply that
/// rule, so nothing downstream can accidentally address a Sunday.
public struct BucketKey: Hashable, Comparable, Codable {
    /// ISO "yyyy-MM-dd", local time.
    public let id: String

    private init(unchecked id: String) { self.id = id }

    public init?(_ id: String) {
        guard let date = Week.parseDate(id) else { return nil }
        self = Self.containing(date)
    }

    public static func containing(_ date: Date) -> BucketKey {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        // .weekday is 1 for Sunday and 7 for Saturday whatever firstWeekday is set to.
        if cal.component(.weekday, from: day) == 1 {
            return BucketKey(unchecked: Week.formatDate(cal.date(byAdding: .day, value: -1, to: day)!))
        }
        return BucketKey(unchecked: Week.formatDate(day))
    }

    /// The Monday of the week containing `date`. Used to key the weekly focus.
    public static func monday(of date: Date) -> BucketKey {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return BucketKey(unchecked: Week.formatDate(cal.date(from: comps)!))
    }

    public var isWeekend: Bool { Calendar.current.component(.weekday, from: firstDate) == 7 }

    public var firstDate: Date { Week.parseDate(id)! }

    /// The last calendar day this bucket covers — the Sunday, for a weekend bucket.
    public var lastDate: Date {
        isWeekend ? Calendar.current.date(byAdding: .day, value: 1, to: firstDate)! : firstDate
    }

    /// Steps by whole buckets, not days, so Friday +1 is the weekend and the weekend +1 is Monday.
    public func stepped(by n: Int) -> BucketKey {
        var result = self
        var remaining = n
        while remaining > 0 { result = result.next; remaining -= 1 }
        while remaining < 0 { result = result.previous; remaining += 1 }
        return result
    }

    private var next: BucketKey {
        // Leaving the weekend bucket means clearing both of its days.
        let step = isWeekend ? 2 : 1
        return Self.containing(Calendar.current.date(byAdding: .day, value: step, to: firstDate)!)
    }

    private var previous: BucketKey {
        // Monday steps back onto Sunday, which `containing` snaps to its Saturday.
        Self.containing(Calendar.current.date(byAdding: .day, value: -1, to: firstDate)!)
    }

    // MARK: Labels

    /// Column header: MON…FRI, or WKND. Matches the strings the old `Day` rawValues produced.
    public var headerLabel: String {
        if isWeekend { return "WKND" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: firstDate).uppercased()
    }

    /// Vertical layout's label: "21", or "26/27" for a weekend.
    public var compactDateLabel: String {
        let cal = Calendar.current
        if isWeekend {
            return "\(cal.component(.day, from: firstDate))/\(cal.component(.day, from: lastDate))"
        }
        return String(format: "%02d", cal.component(.day, from: firstDate))
    }

    /// Horizontal layout's label: "21 SEP", or "26-27 SEP" for a weekend. The month is the
    /// Saturday's, so a weekend spanning a month boundary reads "31-1 OCT" — as it did before.
    public var wideDateLabel: String {
        let cal = Calendar.current
        let monthF = DateFormatter()
        monthF.locale = Locale(identifier: "en_US_POSIX")
        monthF.dateFormat = "MMM"
        if isWeekend {
            let month = monthF.string(from: firstDate).uppercased()
            return "\(cal.component(.day, from: firstDate))-\(cal.component(.day, from: lastDate)) \(month)"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        return f.string(from: firstDate).uppercased()
    }

    // MARK: Conformances

    public static func < (lhs: BucketKey, rhs: BucketKey) -> Bool { lhs.id < rhs.id }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let key = BucketKey(raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not an ISO yyyy-MM-dd date: \(raw)"
            ))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}

public enum WeekError: Error, Equatable {
    case dayFull(Day)
    case itemNotFound(UUID)
}

public struct Week: Equatable, Codable {
    public static let maxItemsPerDay = 3

    public var weekStart: String
    public var days: [Day: [Item]]
    public var ideas: [Item]
    public var reminder: String

    public init(weekStart: String, days: [Day: [Item]], ideas: [Item], reminder: String) {
        self.weekStart = weekStart
        self.days = days
        self.ideas = ideas
        self.reminder = reminder
    }

    public static func empty(weekStart: String) -> Week {
        Week(
            weekStart: weekStart,
            days: Dictionary(uniqueKeysWithValues: Day.allCases.map { ($0, [Item]()) }),
            ideas: [],
            reminder: ""
        )
    }

    private enum CodingKeys: String, CodingKey {
        case weekStart, days, ideas, reminder
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try container.decode(String.self, forKey: .weekStart)
        let stringDays = try container.decodeIfPresent([String: [Item]].self, forKey: .days) ?? [:]
        var allDays: [Day: [Item]] = [:]
        for day in Day.allCases { allDays[day] = stringDays[day.rawValue] ?? [] }
        days = allDays
        ideas = try container.decodeIfPresent([Item].self, forKey: .ideas) ?? []
        reminder = try container.decodeIfPresent(String.self, forKey: .reminder) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weekStart, forKey: .weekStart)
        let stringDays = Dictionary(uniqueKeysWithValues: days.map { ($0.key.rawValue, $0.value) })
        try container.encode(stringDays, forKey: .days)
        try container.encode(ideas, forKey: .ideas)
        try container.encode(reminder, forKey: .reminder)
    }

    // MARK: - Validation

    public mutating func validate() {
        for day in Day.allCases {
            var items = days[day, default: []]
            while items.count > Self.maxItemsPerDay {
                var overflow = items.removeLast()
                overflow.done = false
                ideas.append(overflow)
            }
            days[day] = items
        }
        for i in ideas.indices { ideas[i].done = false }
    }

    // MARK: - Day items

    @discardableResult
    public mutating func addItem(to day: Day, text: String) throws -> Item {
        guard days[day, default: []].count < Self.maxItemsPerDay else {
            throw WeekError.dayFull(day)
        }
        let item = Item(text: text)
        days[day, default: []].append(item)
        return item
    }

    public mutating func toggleDone(_ itemID: UUID) throws {
        for day in Day.allCases {
            if let idx = days[day]?.firstIndex(where: { $0.id == itemID }) {
                days[day]![idx].done.toggle()
                return
            }
        }
        if ideas.contains(where: { $0.id == itemID }) { return }
        throw WeekError.itemNotFound(itemID)
    }

    public mutating func deleteItem(_ itemID: UUID) throws {
        for day in Day.allCases {
            if let idx = days[day]?.firstIndex(where: { $0.id == itemID }) {
                days[day]!.remove(at: idx)
                return
            }
        }
        if let idx = ideas.firstIndex(where: { $0.id == itemID }) {
            ideas.remove(at: idx)
            return
        }
        throw WeekError.itemNotFound(itemID)
    }

    public mutating func moveItem(_ itemID: UUID, to day: Day, at position: Int) throws {
        let targetItems = days[day, default: []]
        let isInTarget = targetItems.contains(where: { $0.id == itemID })
        let effectiveCount = isInTarget ? targetItems.count - 1 : targetItems.count
        guard effectiveCount < Self.maxItemsPerDay else {
            throw WeekError.dayFull(day)
        }

        var found: Item?
        for d in Day.allCases {
            if let idx = days[d]?.firstIndex(where: { $0.id == itemID }) {
                found = days[d]!.remove(at: idx)
                break
            }
        }
        if found == nil, let idx = ideas.firstIndex(where: { $0.id == itemID }) {
            found = ideas.remove(at: idx)
        }
        guard let item = found else { throw WeekError.itemNotFound(itemID) }

        let pos = min(position, days[day, default: []].count)
        days[day, default: []].insert(item, at: pos)
    }

    public mutating func moveToIdeas(_ itemID: UUID) throws {
        for day in Day.allCases {
            if let idx = days[day]?.firstIndex(where: { $0.id == itemID }) {
                var item = days[day]!.remove(at: idx)
                item.done = false
                ideas.append(item)
                return
            }
        }
        if ideas.contains(where: { $0.id == itemID }) { return }
        throw WeekError.itemNotFound(itemID)
    }

    // MARK: - Ideas

    @discardableResult
    public mutating func addIdea(text: String) -> Item {
        let item = Item(text: text)
        ideas.append(item)
        return item
    }

    public mutating func removeIdea(_ itemID: UUID) throws {
        guard let idx = ideas.firstIndex(where: { $0.id == itemID }) else {
            throw WeekError.itemNotFound(itemID)
        }
        ideas.remove(at: idx)
    }

    // MARK: - Reset

    public func needsReset(now: Date = Date()) -> Bool {
        guard let start = Self.parseDate(weekStart),
              let reset = Self.resetDate(for: start) else { return false }
        return now >= reset
    }

    public func reset(now: Date = Date()) -> Week {
        var newIdeas = ideas
        for day in Day.allCases {
            for item in days[day, default: []] where !item.done {
                newIdeas.append(Item(id: item.id, text: item.text))
            }
        }
        return Week(
            weekStart: Self.mondayOfWeek(containing: now),
            days: Dictionary(uniqueKeysWithValues: Day.allCases.map { ($0, [Item]()) }),
            ideas: newIdeas,
            reminder: ""
        )
    }

    // MARK: - Date helpers

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    public static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
    }

    public static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    public static func resetDate(for weekStart: Date) -> Date? {
        let cal = Calendar.current
        guard let nextMonday = cal.date(byAdding: .day, value: 7, to: weekStart) else { return nil }
        return cal.date(bySettingHour: 4, minute: 0, second: 0, of: nextMonday)
    }

    public static func mondayOfWeek(containing date: Date) -> String {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let monday = cal.date(from: comps)!
        return formatDate(monday)
    }
}

public enum WindowMode: String, Codable {
    /// Six buckets starting at the Monday of the anchor's week.
    case week
    /// Six buckets starting one bucket before the anchor's, so the anchor sits in slot 1.
    case sliding
}

public enum SheetError: Error, Equatable {
    case dayFull(BucketKey)
    case itemNotFound(UUID)
}

/// Everything the sheet stores. There is no "current week": buckets are addressed by date and
/// the view decides which six to render, so nothing here has to be reset when Monday arrives.
public struct Sheet: Equatable, Codable {
    public static let maxItemsPerDay = 3
    public static let retentionDays = 7

    public var buckets: [BucketKey: [Item]]
    public var ideas: [Item]
    /// Keyed by the Monday of the week it belongs to.
    public var weeklyFocus: [BucketKey: String]

    public init(buckets: [BucketKey: [Item]], ideas: [Item], weeklyFocus: [BucketKey: String]) {
        self.buckets = buckets
        self.ideas = ideas
        self.weeklyFocus = weeklyFocus
    }

    public static func empty() -> Sheet {
        Sheet(buckets: [:], ideas: [], weeklyFocus: [:])
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case buckets, ideas, weeklyFocus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Swift encodes a Dictionary as a JSON object only when its key is String or Int, so
        // both maps are stored string-keyed and re-keyed here. An unparseable key is dropped.
        let rawBuckets = try container.decodeIfPresent([String: [Item]].self, forKey: .buckets) ?? [:]
        var decodedBuckets: [BucketKey: [Item]] = [:]
        for (raw, items) in rawBuckets {
            guard let key = BucketKey(raw) else { continue }
            decodedBuckets[key, default: []].append(contentsOf: items)
        }
        buckets = decodedBuckets

        ideas = try container.decodeIfPresent([Item].self, forKey: .ideas) ?? []

        let rawFocus = try container.decodeIfPresent([String: String].self, forKey: .weeklyFocus) ?? [:]
        var decodedFocus: [BucketKey: String] = [:]
        for (raw, text) in rawFocus {
            guard let key = BucketKey(raw) else { continue }
            decodedFocus[key] = text
        }
        weeklyFocus = decodedFocus
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: buckets.map { ($0.key.id, $0.value) }), forKey: .buckets)
        try container.encode(ideas, forKey: .ideas)
        try container.encode(Dictionary(uniqueKeysWithValues: weeklyFocus.map { ($0.key.id, $0.value) }), forKey: .weeklyFocus)
    }

    // MARK: - Validation

    public mutating func validate() {
        // Sorted so overflow lands in `ideas` in a deterministic order.
        for key in buckets.keys.sorted() {
            var items = buckets[key, default: []]
            while items.count > Self.maxItemsPerDay {
                var overflow = items.removeLast()
                overflow.done = false
                ideas.append(overflow)
            }
            if items.isEmpty {
                buckets.removeValue(forKey: key)
            } else {
                buckets[key] = items
            }
        }
        for i in ideas.indices { ideas[i].done = false }
    }

    // MARK: - Bucket items

    @discardableResult
    public mutating func addItem(to key: BucketKey, text: String) throws -> Item {
        guard buckets[key, default: []].count < Self.maxItemsPerDay else {
            throw SheetError.dayFull(key)
        }
        let item = Item(text: text)
        buckets[key, default: []].append(item)
        return item
    }

    public mutating func toggleDone(_ itemID: UUID) throws {
        // `Array(...)` throughout: these loops mutate `buckets`, so they must not iterate a
        // keys view over the dictionary they are changing.
        for key in Array(buckets.keys) {
            if let idx = buckets[key]?.firstIndex(where: { $0.id == itemID }) {
                buckets[key]![idx].done.toggle()
                return
            }
        }
        if ideas.contains(where: { $0.id == itemID }) { return }
        throw SheetError.itemNotFound(itemID)
    }

    public mutating func deleteItem(_ itemID: UUID) throws {
        for key in Array(buckets.keys) {
            if let idx = buckets[key]?.firstIndex(where: { $0.id == itemID }) {
                buckets[key]!.remove(at: idx)
                if buckets[key]!.isEmpty { buckets.removeValue(forKey: key) }
                return
            }
        }
        if let idx = ideas.firstIndex(where: { $0.id == itemID }) {
            ideas.remove(at: idx)
            return
        }
        throw SheetError.itemNotFound(itemID)
    }

    public mutating func moveItem(_ itemID: UUID, to key: BucketKey, at position: Int) throws {
        let target = buckets[key, default: []]
        let isInTarget = target.contains(where: { $0.id == itemID })
        let effectiveCount = isInTarget ? target.count - 1 : target.count
        guard effectiveCount < Self.maxItemsPerDay else {
            throw SheetError.dayFull(key)
        }

        var found: Item?
        for k in Array(buckets.keys) {
            if let idx = buckets[k]?.firstIndex(where: { $0.id == itemID }) {
                found = buckets[k]!.remove(at: idx)
                if buckets[k]!.isEmpty, k != key { buckets.removeValue(forKey: k) }
                break
            }
        }
        if found == nil, let idx = ideas.firstIndex(where: { $0.id == itemID }) {
            found = ideas.remove(at: idx)
        }
        guard let item = found else { throw SheetError.itemNotFound(itemID) }

        let pos = min(position, buckets[key, default: []].count)
        buckets[key, default: []].insert(item, at: pos)
    }

    public mutating func moveToIdeas(_ itemID: UUID) throws {
        for key in Array(buckets.keys) {
            if let idx = buckets[key]?.firstIndex(where: { $0.id == itemID }) {
                var item = buckets[key]!.remove(at: idx)
                if buckets[key]!.isEmpty { buckets.removeValue(forKey: key) }
                item.done = false
                ideas.append(item)
                return
            }
        }
        if ideas.contains(where: { $0.id == itemID }) { return }
        throw SheetError.itemNotFound(itemID)
    }

    // MARK: - Ideas

    @discardableResult
    public mutating func addIdea(text: String) -> Item {
        let item = Item(text: text)
        ideas.append(item)
        return item
    }

    public mutating func removeIdea(_ itemID: UUID) throws {
        guard let idx = ideas.firstIndex(where: { $0.id == itemID }) else {
            throw SheetError.itemNotFound(itemID)
        }
        ideas.remove(at: idx)
    }

    // MARK: - Weekly focus

    public func focus(for anchor: Date) -> String {
        weeklyFocus[BucketKey.monday(of: anchor)] ?? ""
    }

    public mutating func setFocus(_ text: String, for anchor: Date) {
        let key = BucketKey.monday(of: anchor)
        if text.isEmpty {
            weeklyFocus.removeValue(forKey: key)
        } else {
            weeklyFocus[key] = text
        }
    }
}
