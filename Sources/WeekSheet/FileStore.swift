import Foundation

public final class FileStore {
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let fileURL: URL
    private let historyURL: URL
    private let maxHistoryFiles = 8

    public init(baseURL: URL? = nil) {
        let base: URL
        if let provided = baseURL {
            base = provided
        } else {
            base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("WeekSheet")
        }
        self.baseURL = base
        self.fileURL = base.appendingPathComponent("week.json")
        self.historyURL = base.appendingPathComponent("history")
    }

    public func load() throws -> Week {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return Week.empty(weekStart: Week.mondayOfWeek(containing: Date()))
        }
        let data = try Data(contentsOf: fileURL)
        var week = try JSONDecoder().decode(Week.self, from: data)
        week.validate()
        return week
    }

    public func save(_ week: Week) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(week)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Sheet

    public func loadSheet() throws -> Sheet {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .empty() }
        let data = try Data(contentsOf: fileURL)

        var sheet: Sheet
        if isLegacyPayload(data) {
            sheet = try JSONDecoder().decode(LegacyWeek.self, from: data).toSheet()
            // Convert on disk so this branch runs exactly once per install.
            try save(sheet)
        } else {
            sheet = try JSONDecoder().decode(Sheet.self, from: data)
        }
        sheet.validate()
        return sheet
    }

    public func save(_ sheet: Sheet) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sheet)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadSheetAndPrune(now: Date = Date()) throws -> Sheet {
        var sheet = try loadSheet()
        let countBefore = sheet.buckets.count
        sheet.prune(now: now)
        if sheet.buckets.count != countBefore { try save(sheet) }
        return sheet
    }

    /// The old shape has `days` and no `buckets`.
    private func isLegacyPayload(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return obj["buckets"] == nil && obj["days"] != nil
    }

    public func loadAndResetIfNeeded(now: Date = Date()) throws -> Week {
        var week = try load()
        if week.needsReset(now: now) {
            try archiveToHistory(week)
            week = week.reset(now: now)
            try save(week)
        }
        return week
    }

    func archiveToHistory(_ week: Week) throws {
        try fileManager.createDirectory(at: historyURL, withIntermediateDirectories: true)
        let filename = "week-\(week.weekStart).json"
        let dest = historyURL.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(week)
        try data.write(to: dest, options: .atomic)
        try pruneHistory()
    }

    func pruneHistory() throws {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }
        var files = try fileManager.contentsOfDirectory(at: historyURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        while files.count > maxHistoryFiles {
            try fileManager.removeItem(at: files.removeLast())
        }
    }
}
