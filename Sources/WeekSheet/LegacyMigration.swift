import Foundation

/// The pre-sliding `week.json` shape: one week, weekday-keyed, with a merged weekend and a
/// single reminder line. Decode-only — nothing writes this format any more.
///
/// Delete this file, its tests, and the branch in `FileStore.load()` once no installs remain on
/// the old format.
struct LegacyWeek: Decodable {
    let weekStart: String
    let days: [String: [Item]]
    let ideas: [Item]
    let reminder: String

    private enum CodingKeys: String, CodingKey {
        case weekStart, days, ideas, reminder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        weekStart = try container.decode(String.self, forKey: .weekStart)
        days = try container.decodeIfPresent([String: [Item]].self, forKey: .days) ?? [:]
        ideas = try container.decodeIfPresent([Item].self, forKey: .ideas) ?? []
        reminder = try container.decodeIfPresent(String.self, forKey: .reminder) ?? ""
    }

    /// Day offsets from the Monday `weekStart`. `wknd` maps to the Saturday, which is exactly
    /// how `BucketKey` keys a weekend bucket.
    private static let offsets: [String: Int] = [
        "mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "wknd": 5
    ]

    /// Throws rather than returning a partial or empty sheet: the caller writes the result back
    /// over `week.json`, so a file we cannot interpret must abort the migration and leave the
    /// original untouched. `weekStart` was always a Monday when the old app wrote it, and the
    /// offset table is only collision-free if it still is.
    func toSheet() throws -> Sheet {
        guard let monday = Week.parseDate(weekStart) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "weekStart is not an ISO yyyy-MM-dd date: \(weekStart)"
            ))
        }
        var cal = Calendar.current
        cal.firstWeekday = 2
        guard cal.component(.weekday, from: monday) == 2 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "weekStart is not a Monday: \(weekStart)"
            ))
        }

        var buckets: [BucketKey: [Item]] = [:]
        for (day, items) in days {
            guard !items.isEmpty,
                  let offset = Self.offsets[day],
                  let date = cal.date(byAdding: .day, value: offset, to: monday) else { continue }
            buckets[BucketKey.containing(date), default: []].append(contentsOf: items)
        }

        var sheet = Sheet(buckets: buckets, ideas: ideas, weeklyFocus: [:])
        sheet.setFocus(reminder, for: monday)
        sheet.validate()
        return sheet
    }
}
