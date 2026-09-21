import XCTest
@testable import WeekSheet

final class FileStoreTests: XCTestCase {
    var tmpDir: URL!
    var store: FileStore!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeekSheetTests-\(UUID().uuidString)")
        store = FileStore(baseURL: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    // MARK: - Load / Save

    func testLoadReturnsEmptyWhenNoFile() throws {
        let week = try store.load()
        for day in Day.allCases {
            XCTAssertTrue(week.days[day]!.isEmpty)
        }
        XCTAssertTrue(week.ideas.isEmpty)
    }

    func testSaveAndLoad() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        try week.addItem(to: .mon, text: "Persisted")
        let _ = week.addIdea(text: "Saved idea")
        week.reminder = "Rent"

        try store.save(week)
        let loaded = try store.load()

        XCTAssertEqual(loaded.weekStart, "2026-08-31")
        XCTAssertEqual(loaded.days[.mon]?.first?.text, "Persisted")
        XCTAssertEqual(loaded.ideas.first?.text, "Saved idea")
        XCTAssertEqual(loaded.reminder, "Rent")
    }

    func testLoadValidatesOverflow() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        week.days[.tue] = (0..<5).map { Item(text: "Item \($0)") }
        try store.save(week)

        let loaded = try store.load()
        XCTAssertEqual(loaded.days[.tue]?.count, 3)
        XCTAssertEqual(loaded.ideas.count, 2)
    }

    // MARK: - Reset

    func testLoadAndResetNotNeeded() throws {
        let week = Week.empty(weekStart: "2026-08-31")
        try store.save(week)

        let wed = Week.parseDate("2026-09-02")!
        let loaded = try store.loadAndResetIfNeeded(now: wed)
        XCTAssertEqual(loaded.weekStart, "2026-08-31")
    }

    func testLoadAndResetPerformsReset() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        try week.addItem(to: .mon, text: "Unfinished")
        try week.addItem(to: .tue, text: "Done")
        try week.toggleDone(week.days[.tue]![0].id)
        week.reminder = "Old reminder"
        try store.save(week)

        let cal = Calendar.current
        let nextMon = Week.parseDate("2026-09-07")!
        let resetTime = cal.date(bySettingHour: 5, minute: 0, second: 0, of: nextMon)!
        let loaded = try store.loadAndResetIfNeeded(now: resetTime)

        XCTAssertEqual(loaded.weekStart, "2026-09-07")
        for day in Day.allCases {
            XCTAssertTrue(loaded.days[day]!.isEmpty)
        }
        XCTAssertEqual(loaded.ideas.count, 1)
        XCTAssertEqual(loaded.ideas[0].text, "Unfinished")
        XCTAssertEqual(loaded.reminder, "")
    }

    // MARK: - History

    func testResetCreatesHistoryFile() throws {
        let week = Week.empty(weekStart: "2026-08-31")
        try store.save(week)

        let cal = Calendar.current
        let nextMon = Week.parseDate("2026-09-07")!
        let resetTime = cal.date(bySettingHour: 5, minute: 0, second: 0, of: nextMon)!
        _ = try store.loadAndResetIfNeeded(now: resetTime)

        let historyDir = tmpDir.appendingPathComponent("history")
        let files = try FileManager.default.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].lastPathComponent.hasPrefix("week-2026-08-31"))
    }

    func testPruneKeepsOnly8() throws {
        let historyDir = tmpDir.appendingPathComponent("history")
        try FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)

        for i in 0..<10 {
            let name = String(format: "week-2026-01-%02d.json", i + 1)
            let data = "{}".data(using: .utf8)!
            try data.write(to: historyDir.appendingPathComponent(name))
        }

        try store.pruneHistory()

        let files = try FileManager.default.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 8)

        let names = files.map(\.lastPathComponent).sorted()
        XCTAssertFalse(names.contains("week-2026-01-01.json"))
        XCTAssertFalse(names.contains("week-2026-01-02.json"))
        XCTAssertTrue(names.contains("week-2026-01-10.json"))
    }

    // MARK: - Sheet load / save

    private var legacyFileJSON: Data {
        """
        {
            "weekStart": "2026-09-21",
            "days": {
                "mon": [{ "id": "550E8400-E29B-41D4-A716-446655440001", "text": "Monday thing", "done": false }],
                "wknd": [{ "id": "550E8400-E29B-41D4-A716-446655440003", "text": "Weekend thing", "done": false }]
            },
            "ideas": [],
            "reminder": "Rent",
            "notes": "gone"
        }
        """.data(using: .utf8)!
    }

    private func writeRawFile(_ data: Data) throws {
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try data.write(to: tmpDir.appendingPathComponent("week.json"))
    }

    func testLoadSheetReturnsEmptyWhenNoFile() throws {
        let sheet = try store.loadSheet()
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.ideas.isEmpty)
    }

    func testSaveAndLoadSheet() throws {
        var sheet = Sheet.empty()
        let monday = BucketKey("2026-09-21")!
        try sheet.addItem(to: monday, text: "Persisted")
        sheet.addIdea(text: "Saved idea")
        sheet.setFocus("Rent", for: Week.parseDate("2026-09-21")!)

        try store.save(sheet)
        let loaded = try store.loadSheet()

        XCTAssertEqual(loaded.buckets[monday]?.first?.text, "Persisted")
        XCTAssertEqual(loaded.ideas.first?.text, "Saved idea")
        XCTAssertEqual(loaded.focus(for: Week.parseDate("2026-09-21")!), "Rent")
    }

    func testLoadSheetValidatesOverflow() throws {
        var sheet = Sheet.empty()
        let tuesday = BucketKey("2026-09-22")!
        sheet.buckets[tuesday] = (0..<5).map { Item(text: "Item \($0)") }
        try store.save(sheet)

        let loaded = try store.loadSheet()
        XCTAssertEqual(loaded.buckets[tuesday]?.count, 3)
        XCTAssertEqual(loaded.ideas.count, 2)
    }

    func testLoadSheetMigratesALegacyFile() throws {
        try writeRawFile(legacyFileJSON)
        let sheet = try store.loadSheet()
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-21")!]?.first?.text, "Monday thing")
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-26")!]?.first?.text, "Weekend thing")
        XCTAssertEqual(sheet.focus(for: Week.parseDate("2026-09-21")!), "Rent")
    }

    func testMigrationRewritesTheFileInTheNewShape() throws {
        try writeRawFile(legacyFileJSON)
        _ = try store.loadSheet()

        let data = try Data(contentsOf: tmpDir.appendingPathComponent("week.json"))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["buckets"])
        XCTAssertNil(obj?["days"], "the legacy shape should be gone from disk")
    }

    func testMigratedFileLoadsAgainUnchanged() throws {
        try writeRawFile(legacyFileJSON)
        let first = try store.loadSheet()
        let second = try store.loadSheet()
        XCTAssertEqual(first, second, "migration must be idempotent")
    }

    func testLoadSheetAndPruneDropsOldBuckets() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-11")!, text: "Too old")
        try sheet.addItem(to: BucketKey("2026-09-21")!, text: "Current")
        try store.save(sheet)

        let loaded = try store.loadSheetAndPrune(now: Week.parseDate("2026-09-21")!)
        XCTAssertNil(loaded.buckets[BucketKey("2026-09-11")!])
        XCTAssertEqual(loaded.buckets[BucketKey("2026-09-21")!]?.count, 1)
    }

    func testPruneOnLoadIsPersisted() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-11")!, text: "Too old")
        try store.save(sheet)

        _ = try store.loadSheetAndPrune(now: Week.parseDate("2026-09-21")!)
        let reloaded = try store.loadSheet()
        XCTAssertTrue(reloaded.buckets.isEmpty, "the prune should have been written back")
    }

    func testLoadSheetWritesNoHistory() throws {
        try writeRawFile(legacyFileJSON)
        _ = try store.loadSheetAndPrune(now: Week.parseDate("2026-09-21")!)
        let historyDir = tmpDir.appendingPathComponent("history")
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDir.path))
    }
}
