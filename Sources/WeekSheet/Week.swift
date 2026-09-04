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
    public var notes: String

    public init(weekStart: String, days: [Day: [Item]], ideas: [Item], reminder: String, notes: String) {
        self.weekStart = weekStart
        self.days = days
        self.ideas = ideas
        self.reminder = reminder
        self.notes = notes
    }

    public static func empty(weekStart: String) -> Week {
        Week(
            weekStart: weekStart,
            days: Dictionary(uniqueKeysWithValues: Day.allCases.map { ($0, [Item]()) }),
            ideas: [],
            reminder: "",
            notes: ""
        )
    }

    private enum CodingKeys: String, CodingKey {
        case weekStart, days, ideas, reminder, notes
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
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(weekStart, forKey: .weekStart)
        let stringDays = Dictionary(uniqueKeysWithValues: days.map { ($0.key.rawValue, $0.value) })
        try container.encode(stringDays, forKey: .days)
        try container.encode(ideas, forKey: .ideas)
        try container.encode(reminder, forKey: .reminder)
        try container.encode(notes, forKey: .notes)
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
            reminder: "",
            notes: ""
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
