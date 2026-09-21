import Foundation

public final class FileStore {
    private let fileManager = FileManager.default
    private let baseURL: URL
    private let fileURL: URL

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
    }

    public func load() throws -> Sheet {
        guard fileManager.fileExists(atPath: fileURL.path) else { return .empty() }
        let data = try Data(contentsOf: fileURL)

        let wasLegacy = isLegacyPayload(data)
        var sheet: Sheet
        do {
            sheet = wasLegacy
                ? try JSONDecoder().decode(LegacyWeek.self, from: data).toSheet()
                : try JSONDecoder().decode(Sheet.self, from: data)
        } catch {
            // We cannot interpret this file. Move it aside before rethrowing: the caller degrades
            // to an empty sheet, and the user's first edit would otherwise save over the only
            // copy of their items. Moving rather than copying means the next launch starts clean
            // instead of failing forever.
            try? quarantineUnreadableFile()
            throw error
        }
        // Convert on disk so this branch runs exactly once per install.
        if wasLegacy { try save(sheet) }
        sheet.validate()
        return sheet
    }

    /// Renames an uninterpretable `week.json` so nothing can overwrite it. Named with today's
    /// date, suffixed if that name is taken.
    private func quarantineUnreadableFile() throws {
        let stamp = Sheet.formatDate(Date())
        var dest = baseURL.appendingPathComponent("week-unreadable-\(stamp).json")
        var attempt = 2
        while fileManager.fileExists(atPath: dest.path) {
            dest = baseURL.appendingPathComponent("week-unreadable-\(stamp)-\(attempt).json")
            attempt += 1
        }
        try fileManager.moveItem(at: fileURL, to: dest)
    }

    public func save(_ sheet: Sheet) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sheet)
        try data.write(to: fileURL, options: .atomic)
    }

    public func loadAndPrune(now: Date = Date()) throws -> Sheet {
        var sheet = try load()
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
}
