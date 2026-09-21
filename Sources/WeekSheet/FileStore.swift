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
