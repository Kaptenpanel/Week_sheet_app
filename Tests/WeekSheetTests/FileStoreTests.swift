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
        week.notes = "Notes here"

        try store.save(week)
        let loaded = try store.load()

        XCTAssertEqual(loaded.weekStart, "2026-08-31")
        XCTAssertEqual(loaded.days[.mon]?.first?.text, "Persisted")
        XCTAssertEqual(loaded.ideas.first?.text, "Saved idea")
        XCTAssertEqual(loaded.reminder, "Rent")
        XCTAssertEqual(loaded.notes, "Notes here")
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
}
