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

        var sheet: Sheet
        var wasLegacy = false
        do {
            let data = try Data(contentsOf: fileURL)
            wasLegacy = isLegacyPayload(data)
            sheet = wasLegacy
                ? try JSONDecoder().decode(LegacyWeek.self, from: data).toSheet()
                : try JSONDecoder().decode(Sheet.self, from: data)
        } catch {
            // We cannot interpret this file. Move it aside before rethrowing: the caller degrades
            // to an empty sheet, and the user's first edit would otherwise save over the only copy
            // of their items. The read lives inside this `do` so a file we cannot even read off
            // disk is quarantined too — the caller is about to overwrite it either way.
            try? quarantineUnreadableFile()
            throw error
        }
        if wasLegacy {
            // Keep the legacy file: the conversion is irreversible and drops the notes text.
            try? fileManager.copyItem(at: fileURL, to: uniqueSibling(named: "week-legacy"))
            // Best-effort: the sheet in hand is correct either way, and a failed write must not
            // make the caller think there is no data — it would overwrite this file on the next edit.
            try? save(sheet)
        }
        sheet.validate()
        return sheet
    }

    /// A sibling of `week.json` named `<base>-<today>.json`, suffixed if that name is taken.
    private func uniqueSibling(named base: String) -> URL {
        let stamp = Sheet.formatDate(Date())
        var dest = baseURL.appendingPathComponent("\(base)-\(stamp).json")
        var attempt = 2
        while fileManager.fileExists(atPath: dest.path) {
            dest = baseURL.appendingPathComponent("\(base)-\(stamp)-\(attempt).json")
            attempt += 1
        }
        return dest
    }

    /// Renames an uninterpretable `week.json` so nothing can overwrite it.
    private func quarantineUnreadableFile() throws {
        try fileManager.moveItem(at: fileURL, to: uniqueSibling(named: "week-unreadable"))
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
        // Best-effort: prune is recomputed on every load, so a failed write just means it retries
        // next time — the in-memory sheet is correct either way (see load() above).
        if sheet.buckets.count != countBefore { try? save(sheet) }
        return sheet
    }

    /// The old shape has `days` and no `buckets`.
    private func isLegacyPayload(_ data: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return obj["buckets"] == nil && obj["days"] != nil
    }
}
