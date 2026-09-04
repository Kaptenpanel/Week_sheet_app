import XCTest
@testable import WeekSheet

final class WeekTests: XCTestCase {

    // MARK: - Empty / init

    func testEmptyWeek() {
        let week = Week.empty(weekStart: "2026-08-31")
        XCTAssertEqual(week.weekStart, "2026-08-31")
        for day in Day.allCases {
            XCTAssertEqual(week.days[day]?.count, 0)
        }
        XCTAssertTrue(week.ideas.isEmpty)
        XCTAssertEqual(week.reminder, "")
        XCTAssertEqual(week.notes, "")
    }

    // MARK: - Add item

    func testAddItemSucceeds() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let item = try week.addItem(to: .mon, text: "Call Ana")
        XCTAssertEqual(week.days[.mon]?.count, 1)
        XCTAssertEqual(week.days[.mon]?.first?.text, "Call Ana")
        XCTAssertFalse(item.done)
    }

    func testAddItemThrowsWhenDayFull() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        try week.addItem(to: .tue, text: "A")
        try week.addItem(to: .tue, text: "B")
        try week.addItem(to: .tue, text: "C")
        XCTAssertThrowsError(try week.addItem(to: .tue, text: "D")) { error in
            XCTAssertEqual(error as? WeekError, .dayFull(.tue))
        }
        XCTAssertEqual(week.days[.tue]?.count, 3)
    }

    // MARK: - Toggle done

    func testToggleDoneOnDayItem() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let item = try week.addItem(to: .wed, text: "Task")
        try week.toggleDone(item.id)
        XCTAssertTrue(week.days[.wed]![0].done)
        try week.toggleDone(item.id)
        XCTAssertFalse(week.days[.wed]![0].done)
    }

    func testToggleDoneNoOpOnIdea() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let idea = week.addIdea(text: "Maybe")
        try week.toggleDone(idea.id)
        XCTAssertFalse(week.ideas[0].done)
    }

    func testToggleDoneThrowsForUnknownID() {
        var week = Week.empty(weekStart: "2026-08-31")
        XCTAssertThrowsError(try week.toggleDone(UUID())) { error in
            XCTAssertTrue(error is WeekError)
        }
    }

    // MARK: - Delete

    func testDeleteFromDay() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let item = try week.addItem(to: .fri, text: "Gone")
        try week.deleteItem(item.id)
        XCTAssertTrue(week.days[.fri]!.isEmpty)
    }

    func testDeleteFromIdeas() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let idea = week.addIdea(text: "Nope")
        try week.deleteItem(idea.id)
        XCTAssertTrue(week.ideas.isEmpty)
    }

    func testDeleteThrowsForUnknownID() {
        var week = Week.empty(weekStart: "2026-08-31")
        XCTAssertThrowsError(try week.deleteItem(UUID()))
    }

    // MARK: - Move item

    func testMoveBetweenDays() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let item = try week.addItem(to: .mon, text: "Shift")
        try week.moveItem(item.id, to: .thu, at: 0)
        XCTAssertTrue(week.days[.mon]!.isEmpty)
        XCTAssertEqual(week.days[.thu]?.first?.id, item.id)
    }

    func testMoveFromIdeasToDay() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let idea = week.addIdea(text: "Promote")
        try week.moveItem(idea.id, to: .wed, at: 0)
        XCTAssertTrue(week.ideas.isEmpty)
        XCTAssertEqual(week.days[.wed]?.first?.text, "Promote")
    }

    func testMoveToFullDayThrows() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        try week.addItem(to: .fri, text: "A")
        try week.addItem(to: .fri, text: "B")
        try week.addItem(to: .fri, text: "C")
        let outsider = try week.addItem(to: .mon, text: "X")
        XCTAssertThrowsError(try week.moveItem(outsider.id, to: .fri, at: 0)) { error in
            XCTAssertEqual(error as? WeekError, .dayFull(.fri))
        }
    }

    func testMoveWithinSameDay() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let a = try week.addItem(to: .mon, text: "A")
        try week.addItem(to: .mon, text: "B")
        try week.moveItem(a.id, to: .mon, at: 1)
        XCTAssertEqual(week.days[.mon]?[0].text, "B")
        XCTAssertEqual(week.days[.mon]?[1].text, "A")
    }

    // MARK: - Move to ideas

    func testMoveToIdeas() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let item = try week.addItem(to: .tue, text: "Demote")
        try week.toggleDone(item.id)
        try week.moveToIdeas(item.id)
        XCTAssertTrue(week.days[.tue]!.isEmpty)
        XCTAssertEqual(week.ideas.count, 1)
        XCTAssertFalse(week.ideas[0].done)
    }

    func testMoveToIdeasNoOpWhenAlreadyIdea() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let idea = week.addIdea(text: "Stay")
        try week.moveToIdeas(idea.id)
        XCTAssertEqual(week.ideas.count, 1)
    }

    // MARK: - Ideas

    func testAddIdea() {
        var week = Week.empty(weekStart: "2026-08-31")
        let idea = week.addIdea(text: "Brainstorm")
        XCTAssertEqual(week.ideas.count, 1)
        XCTAssertEqual(idea.text, "Brainstorm")
        XCTAssertFalse(idea.done)
    }

    func testRemoveIdea() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let idea = week.addIdea(text: "Delete me")
        try week.removeIdea(idea.id)
        XCTAssertTrue(week.ideas.isEmpty)
    }

    func testRemoveIdeaThrowsForDayItem() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        let item = try week.addItem(to: .mon, text: "Day task")
        XCTAssertThrowsError(try week.removeIdea(item.id))
    }

    // MARK: - Validation

    func testValidateOverflowMovesToIdeas() {
        var week = Week.empty(weekStart: "2026-08-31")
        week.days[.mon] = (0..<5).map { Item(text: "Item \($0)") }
        week.validate()
        XCTAssertEqual(week.days[.mon]?.count, 3)
        XCTAssertEqual(week.ideas.count, 2)
    }

    func testValidateResetsIdeaDoneFlag() {
        var week = Week.empty(weekStart: "2026-08-31")
        week.ideas = [Item(text: "Hacked", done: true)]
        week.validate()
        XCTAssertFalse(week.ideas[0].done)
    }

    // MARK: - Reset

    func testNeedsResetFalseWithinWeek() {
        let week = Week.empty(weekStart: "2026-08-31")
        let wed = Week.parseDate("2026-09-02")!
        XCTAssertFalse(week.needsReset(now: wed))
    }

    func testNeedsResetTrueAfterMonday4AM() {
        let week = Week.empty(weekStart: "2026-08-31")
        let cal = Calendar.current
        let nextMon = Week.parseDate("2026-09-07")!
        let at4am = cal.date(bySettingHour: 4, minute: 0, second: 0, of: nextMon)!
        XCTAssertTrue(week.needsReset(now: at4am))
    }

    func testNeedsResetFalseBefore4AM() {
        let week = Week.empty(weekStart: "2026-08-31")
        let cal = Calendar.current
        let nextMon = Week.parseDate("2026-09-07")!
        let at3am = cal.date(bySettingHour: 3, minute: 59, second: 59, of: nextMon)!
        XCTAssertFalse(week.needsReset(now: at3am))
    }

    func testResetClearsDoneKeepsUnfinished() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        try week.addItem(to: .mon, text: "Done task")
        try week.toggleDone(week.days[.mon]![0].id)
        try week.addItem(to: .mon, text: "Unfinished")
        let _ = week.addIdea(text: "Existing idea")
        week.reminder = "Pay rent"
        week.notes = "Some notes"

        let cal = Calendar.current
        let nextMon = Week.parseDate("2026-09-07")!
        let resetTime = cal.date(bySettingHour: 5, minute: 0, second: 0, of: nextMon)!
        let newWeek = week.reset(now: resetTime)

        XCTAssertEqual(newWeek.weekStart, "2026-09-07")
        for day in Day.allCases {
            XCTAssertTrue(newWeek.days[day]!.isEmpty)
        }
        XCTAssertEqual(newWeek.ideas.count, 2)
        XCTAssertTrue(newWeek.ideas.contains(where: { $0.text == "Existing idea" }))
        XCTAssertTrue(newWeek.ideas.contains(where: { $0.text == "Unfinished" }))
        XCTAssertFalse(newWeek.ideas.contains(where: { $0.text == "Done task" }))
        XCTAssertEqual(newWeek.reminder, "")
        XCTAssertEqual(newWeek.notes, "")
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        try week.addItem(to: .mon, text: "Monday thing")
        try week.addItem(to: .wknd, text: "Weekend thing")
        let _ = week.addIdea(text: "An idea")
        week.reminder = "Rent"
        week.notes = "Keep it simple"

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(week)
        let decoded = try JSONDecoder().decode(Week.self, from: data)
        XCTAssertEqual(week, decoded)
    }

    func testDecodesIdeaWithoutDoneField() throws {
        let json = """
        {
            "weekStart": "2026-08-31",
            "days": { "mon": [], "tue": [], "wed": [], "thu": [], "fri": [], "wknd": [] },
            "ideas": [{ "id": "550E8400-E29B-41D4-A716-446655440000", "text": "No done field" }],
            "reminder": "",
            "notes": ""
        }
        """.data(using: .utf8)!
        let week = try JSONDecoder().decode(Week.self, from: json)
        XCTAssertEqual(week.ideas.count, 1)
        XCTAssertFalse(week.ideas[0].done)
    }

    func testDecodesMissingDaysGracefully() throws {
        let json = """
        {
            "weekStart": "2026-08-31",
            "days": { "mon": [{ "id": "550E8400-E29B-41D4-A716-446655440000", "text": "Solo", "done": false }] }
        }
        """.data(using: .utf8)!
        let week = try JSONDecoder().decode(Week.self, from: json)
        XCTAssertEqual(week.days[.mon]?.count, 1)
        for day in [Day.tue, .wed, .thu, .fri, .wknd] {
            XCTAssertEqual(week.days[day]?.count, 0)
        }
    }

    // MARK: - Date helpers

    func testMondayOfWeek() {
        let wed = Week.parseDate("2026-09-02")!
        XCTAssertEqual(Week.mondayOfWeek(containing: wed), "2026-08-31")
    }

    func testMondayOfWeekOnMonday() {
        let mon = Week.parseDate("2026-08-31")!
        XCTAssertEqual(Week.mondayOfWeek(containing: mon), "2026-08-31")
    }

    func testMondayOfWeekOnSunday() {
        let sun = Week.parseDate("2026-09-06")!
        XCTAssertEqual(Week.mondayOfWeek(containing: sun), "2026-08-31")
    }
}
