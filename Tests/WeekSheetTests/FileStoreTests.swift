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
        let sheet = try store.load()
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.ideas.isEmpty)
    }

    func testSaveAndLoadSheet() throws {
        var sheet = Sheet.empty()
        let monday = BucketKey("2026-09-21")!
        try sheet.addItem(to: monday, text: "Persisted")
        sheet.addIdea(text: "Saved idea")
        sheet.setFocus("Rent", for: Sheet.parseDate("2026-09-21")!)

        try store.save(sheet)
        let loaded = try store.load()

        XCTAssertEqual(loaded.buckets[monday]?.first?.text, "Persisted")
        XCTAssertEqual(loaded.ideas.first?.text, "Saved idea")
        XCTAssertEqual(loaded.focus(for: Sheet.parseDate("2026-09-21")!), "Rent")
    }

    func testLoadSheetValidatesOverflow() throws {
        var sheet = Sheet.empty()
        let tuesday = BucketKey("2026-09-22")!
        sheet.buckets[tuesday] = (0..<5).map { Item(text: "Item \($0)") }
        try store.save(sheet)

        let loaded = try store.load()
        XCTAssertEqual(loaded.buckets[tuesday]?.count, 3)
        XCTAssertEqual(loaded.ideas.count, 2)
    }

    func testLoadSheetMigratesALegacyFile() throws {
        try writeRawFile(legacyFileJSON)
        let sheet = try store.load()
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-21")!]?.first?.text, "Monday thing")
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-26")!]?.first?.text, "Weekend thing")
        XCTAssertEqual(sheet.focus(for: Sheet.parseDate("2026-09-21")!), "Rent")
    }

    func testMigrationRewritesTheFileInTheNewShape() throws {
        try writeRawFile(legacyFileJSON)
        _ = try store.load()

        let data = try Data(contentsOf: tmpDir.appendingPathComponent("week.json"))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(obj?["buckets"])
        XCTAssertNil(obj?["days"], "the legacy shape should be gone from disk")
    }

    func testMigratedFileLoadsAgainUnchanged() throws {
        try writeRawFile(legacyFileJSON)
        let first = try store.load()
        let second = try store.load()
        XCTAssertEqual(first, second, "migration must be idempotent")
    }

    func testLoadSheetAndPruneDropsOldBuckets() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-11")!, text: "Too old")
        try sheet.addItem(to: BucketKey("2026-09-21")!, text: "Current")
        try store.save(sheet)

        let loaded = try store.loadAndPrune(now: Sheet.parseDate("2026-09-21")!)
        XCTAssertNil(loaded.buckets[BucketKey("2026-09-11")!])
        XCTAssertEqual(loaded.buckets[BucketKey("2026-09-21")!]?.count, 1)
    }

    func testPruneOnLoadIsPersisted() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-11")!, text: "Too old")
        try store.save(sheet)

        _ = try store.loadAndPrune(now: Sheet.parseDate("2026-09-21")!)
        let reloaded = try store.load()
        XCTAssertTrue(reloaded.buckets.isEmpty, "the prune should have been written back")
    }

    func testLoadSheetWritesNoHistory() throws {
        try writeRawFile(legacyFileJSON)
        _ = try store.loadAndPrune(now: Sheet.parseDate("2026-09-21")!)
        let historyDir = tmpDir.appendingPathComponent("history")
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDir.path))
    }

    // MARK: - Migration refusals leave the file intact

    func testLoadSheetLeavesTheFileIntactWhenWeekStartIsUnparseable() throws {
        let bad = """
        {
            "weekStart": "not-a-date",
            "days": { "mon": [{ "id": "550E8400-E29B-41D4-A716-446655440001", "text": "Precious", "done": false }] },
            "ideas": [],
            "reminder": "Keep me"
        }
        """.data(using: .utf8)!
        try writeRawFile(bad)

        XCTAssertThrowsError(try store.load())

        let after = try Data(contentsOf: tmpDir.appendingPathComponent("week.json"))
        XCTAssertEqual(after, bad, "a rejected migration must leave week.json byte-identical")
    }

    func testLoadSheetLeavesTheFileIntactWhenWeekStartIsNotAMonday() throws {
        // 2026-09-22 is a Tuesday, so fri and wknd would collide.
        let bad = """
        {
            "weekStart": "2026-09-22",
            "days": { "fri": [{ "id": "550E8400-E29B-41D4-A716-446655440002", "text": "Friday", "done": false }] },
            "ideas": [],
            "reminder": ""
        }
        """.data(using: .utf8)!
        try writeRawFile(bad)

        XCTAssertThrowsError(try store.load())

        let after = try Data(contentsOf: tmpDir.appendingPathComponent("week.json"))
        XCTAssertEqual(after, bad)
    }

    func testLoadSheetThrowsOnMalformedJSONWithoutWriting() throws {
        let garbage = "this is not json at all".data(using: .utf8)!
        try writeRawFile(garbage)

        XCTAssertThrowsError(try store.load())

        let after = try Data(contentsOf: tmpDir.appendingPathComponent("week.json"))
        XCTAssertEqual(after, garbage, "an unreadable file must be left alone, not replaced")
    }

    func testLoadSheetTreatsAnEmptyObjectAsAnEmptySheetWithoutWriting() throws {
        let empty = "{}".data(using: .utf8)!
        try writeRawFile(empty)

        let sheet = try store.load()
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.ideas.isEmpty)

        let after = try Data(contentsOf: tmpDir.appendingPathComponent("week.json"))
        XCTAssertEqual(after, empty, "reading a new-shape file must not rewrite it")
    }

    func testLoadSheetAndPruneDoesNotRewriteWhenNothingIsPruned() throws {
        // Compact and unsorted on purpose: any write would re-encode this prettyPrinted and
        // sortedKeys, so byte-equality afterwards is what proves no write happened.
        let compact = """
        {"ideas":[],"weeklyFocus":{},"buckets":{"2026-09-21":[{"id":"550E8400-E29B-41D4-A716-446655440003","text":"Current","done":false}]}}
        """.data(using: .utf8)!
        try writeRawFile(compact)

        let sheet = try store.loadAndPrune(now: Sheet.parseDate("2026-09-21")!)
        XCTAssertEqual(sheet.buckets.count, 1, "the bucket is inside the retention window")

        let after = try Data(contentsOf: tmpDir.appendingPathComponent("week.json"))
        XCTAssertEqual(after, compact, "nothing was pruned, so the file must not be rewritten")
    }
}
