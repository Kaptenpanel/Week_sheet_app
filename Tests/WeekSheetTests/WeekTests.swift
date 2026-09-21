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
    }

    // MARK: - Codable

    func testCodableRoundTrip() throws {
        var week = Week.empty(weekStart: "2026-08-31")
        try week.addItem(to: .mon, text: "Monday thing")
        try week.addItem(to: .wknd, text: "Weekend thing")
        let _ = week.addIdea(text: "An idea")
        week.reminder = "Rent"

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
            "reminder": ""
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

    func testDecodesLegacyFileWithNotesKey() throws {
        let json = """
        {
            "weekStart": "2026-08-31",
            "days": { "mon": [{ "id": "550E8400-E29B-41D4-A716-446655440000", "text": "Kept", "done": false }] },
            "ideas": [],
            "reminder": "Rent",
            "notes": "This field no longer exists on the model."
        }
        """.data(using: .utf8)!
        let week = try JSONDecoder().decode(Week.self, from: json)
        XCTAssertEqual(week.days[.mon]?.first?.text, "Kept")
        XCTAssertEqual(week.reminder, "Rent")
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

    // MARK: - BucketKey

    func testWeekdayBucketKeysItself() {
        let tue = Week.parseDate("2026-09-22")!
        XCTAssertEqual(BucketKey.containing(tue).id, "2026-09-22")
        XCTAssertFalse(BucketKey.containing(tue).isWeekend)
    }

    func testSaturdayIsAWeekendBucket() {
        let sat = Week.parseDate("2026-09-26")!
        let key = BucketKey.containing(sat)
        XCTAssertEqual(key.id, "2026-09-26")
        XCTAssertTrue(key.isWeekend)
    }

    func testSundaySnapsBackToItsSaturday() {
        let sun = Week.parseDate("2026-09-27")!
        let key = BucketKey.containing(sun)
        XCTAssertEqual(key.id, "2026-09-26")
        XCTAssertTrue(key.isWeekend)
    }

    func testWeekendBucketSpansTwoDays() {
        let key = BucketKey("2026-09-26")!
        XCTAssertEqual(key.firstDate, Week.parseDate("2026-09-26")!)
        XCTAssertEqual(key.lastDate, Week.parseDate("2026-09-27")!)
    }

    func testWeekdayBucketSpansOneDay() {
        let key = BucketKey("2026-09-22")!
        XCTAssertEqual(key.firstDate, key.lastDate)
    }

    func testInitRejectsNonDate() {
        XCTAssertNil(BucketKey("not-a-date"))
        XCTAssertNil(BucketKey(""))
    }

    func testInitSnapsASundayString() {
        XCTAssertEqual(BucketKey("2026-09-27")?.id, "2026-09-26")
    }

    func testMondayOfAnchor() {
        XCTAssertEqual(BucketKey.monday(of: Week.parseDate("2026-09-23")!).id, "2026-09-21")
        XCTAssertEqual(BucketKey.monday(of: Week.parseDate("2026-09-21")!).id, "2026-09-21")
        XCTAssertEqual(BucketKey.monday(of: Week.parseDate("2026-09-27")!).id, "2026-09-21")
    }

    func testSteppedForwardFridayToWeekend() {
        XCTAssertEqual(BucketKey("2026-09-25")!.stepped(by: 1).id, "2026-09-26")
    }

    func testSteppedForwardWeekendSkipsToMonday() {
        XCTAssertEqual(BucketKey("2026-09-26")!.stepped(by: 1).id, "2026-09-28")
    }

    func testSteppedBackMondayLandsOnWeekend() {
        XCTAssertEqual(BucketKey("2026-09-21")!.stepped(by: -1).id, "2026-09-19")
    }

    func testSteppedBackWeekendLandsOnFriday() {
        XCTAssertEqual(BucketKey("2026-09-19")!.stepped(by: -1).id, "2026-09-18")
    }

    func testSteppedZeroIsIdentity() {
        let key = BucketKey("2026-09-22")!
        XCTAssertEqual(key.stepped(by: 0), key)
    }

    func testSixStepsForwardIsOneWeek() {
        XCTAssertEqual(BucketKey("2026-09-21")!.stepped(by: 6).id, "2026-09-28")
    }

    func testSteppedRoundTrips() {
        let key = BucketKey("2026-09-19")!
        XCTAssertEqual(key.stepped(by: 4).stepped(by: -4), key)
    }

    func testHeaderLabels() {
        XCTAssertEqual(BucketKey("2026-09-21")!.headerLabel, "MON")
        XCTAssertEqual(BucketKey("2026-09-25")!.headerLabel, "FRI")
        XCTAssertEqual(BucketKey("2026-09-26")!.headerLabel, "WKND")
    }

    func testCompactDateLabels() {
        XCTAssertEqual(BucketKey("2026-09-21")!.compactDateLabel, "21")
        XCTAssertEqual(BucketKey("2026-09-26")!.compactDateLabel, "26/27")
    }

    func testWideDateLabels() {
        XCTAssertEqual(BucketKey("2026-09-21")!.wideDateLabel, "21 SEP")
        XCTAssertEqual(BucketKey("2026-09-26")!.wideDateLabel, "26-27 SEP")
    }

    func testComparableIsChronological() {
        XCTAssertTrue(BucketKey("2026-09-21")! < BucketKey("2026-09-22")!)
    }

    func testCodableAsBareString() throws {
        let key = BucketKey("2026-09-26")!
        let data = try JSONEncoder().encode(key)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"2026-09-26\"")
        XCTAssertEqual(try JSONDecoder().decode(BucketKey.self, from: data), key)
    }

    // MARK: - Sheet: items

    private let mon = BucketKey("2026-09-21")!
    private let tue = BucketKey("2026-09-22")!
    private let wknd = BucketKey("2026-09-26")!

    func testSheetEmptyHasNothing() {
        let sheet = Sheet.empty()
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.ideas.isEmpty)
        XCTAssertTrue(sheet.weeklyFocus.isEmpty)
    }

    func testSheetAddItem() throws {
        var sheet = Sheet.empty()
        let item = try sheet.addItem(to: mon, text: "Call Ana")
        XCTAssertEqual(sheet.buckets[mon]?.count, 1)
        XCTAssertEqual(sheet.buckets[mon]?.first?.text, "Call Ana")
        XCTAssertFalse(item.done)
    }

    func testSheetAddItemThrowsWhenBucketFull() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: tue, text: "A")
        try sheet.addItem(to: tue, text: "B")
        try sheet.addItem(to: tue, text: "C")
        XCTAssertThrowsError(try sheet.addItem(to: tue, text: "D")) { error in
            XCTAssertEqual(error as? SheetError, .dayFull(self.tue))
        }
        XCTAssertEqual(sheet.buckets[tue]?.count, 3)
    }

    func testSheetToggleDone() throws {
        var sheet = Sheet.empty()
        let item = try sheet.addItem(to: mon, text: "Thing")
        try sheet.toggleDone(item.id)
        XCTAssertTrue(sheet.buckets[mon]![0].done)
        try sheet.toggleDone(item.id)
        XCTAssertFalse(sheet.buckets[mon]![0].done)
    }

    func testSheetToggleDoneThrowsForUnknownID() {
        var sheet = Sheet.empty()
        XCTAssertThrowsError(try sheet.toggleDone(UUID()))
    }

    func testSheetDeleteItem() throws {
        var sheet = Sheet.empty()
        let item = try sheet.addItem(to: mon, text: "Thing")
        try sheet.deleteItem(item.id)
        XCTAssertNil(sheet.buckets[mon]?.first)
    }

    func testSheetMoveItemBetweenBuckets() throws {
        var sheet = Sheet.empty()
        let item = try sheet.addItem(to: mon, text: "Slides")
        try sheet.moveItem(item.id, to: wknd, at: 0)
        XCTAssertTrue(sheet.buckets[mon, default: []].isEmpty)
        XCTAssertEqual(sheet.buckets[wknd]?.first?.text, "Slides")
    }

    func testSheetMoveItemThrowsWhenTargetFull() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: tue, text: "A")
        try sheet.addItem(to: tue, text: "B")
        try sheet.addItem(to: tue, text: "C")
        let item = try sheet.addItem(to: mon, text: "D")
        XCTAssertThrowsError(try sheet.moveItem(item.id, to: tue, at: 0)) { error in
            XCTAssertEqual(error as? SheetError, .dayFull(self.tue))
        }
    }

    func testSheetMoveWithinBucketWhenFullIsAllowed() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: tue, text: "A")
        try sheet.addItem(to: tue, text: "B")
        let c = try sheet.addItem(to: tue, text: "C")
        try sheet.moveItem(c.id, to: tue, at: 0)
        XCTAssertEqual(sheet.buckets[tue]?.map(\.text), ["C", "A", "B"])
    }

    func testSheetMoveToIdeasClearsDone() throws {
        var sheet = Sheet.empty()
        let item = try sheet.addItem(to: mon, text: "Thing")
        try sheet.toggleDone(item.id)
        try sheet.moveToIdeas(item.id)
        XCTAssertTrue(sheet.buckets[mon, default: []].isEmpty)
        XCTAssertEqual(sheet.ideas.count, 1)
        XCTAssertFalse(sheet.ideas[0].done)
    }

    func testSheetRemoveIdea() throws {
        var sheet = Sheet.empty()
        let idea = sheet.addIdea(text: "Someday")
        try sheet.removeIdea(idea.id)
        XCTAssertTrue(sheet.ideas.isEmpty)
    }

    // MARK: - Sheet: validate

    func testSheetValidateOverflowsToIdeas() {
        var sheet = Sheet.empty()
        sheet.buckets[tue] = (0..<5).map { Item(text: "Item \($0)") }
        sheet.validate()
        XCTAssertEqual(sheet.buckets[tue]?.count, 3)
        XCTAssertEqual(sheet.ideas.count, 2)
        XCTAssertEqual(sheet.ideas.map(\.text), ["Item 4", "Item 3"])
    }

    func testSheetValidateClearsIdeaDoneFlag() {
        var sheet = Sheet.empty()
        sheet.ideas = [Item(text: "Idea", done: true)]
        sheet.validate()
        XCTAssertFalse(sheet.ideas[0].done)
    }

    func testSheetValidateDropsEmptyBuckets() {
        var sheet = Sheet.empty()
        sheet.buckets[mon] = []
        sheet.validate()
        XCTAssertTrue(sheet.buckets.isEmpty)
    }

    // MARK: - Sheet: weekly focus

    func testFocusIsKeyedByMonday() {
        var sheet = Sheet.empty()
        let wed = Week.parseDate("2026-09-23")!
        sheet.setFocus("Ship the window", for: wed)
        XCTAssertEqual(sheet.weeklyFocus[BucketKey("2026-09-21")!], "Ship the window")
        XCTAssertEqual(sheet.focus(for: Week.parseDate("2026-09-27")!), "Ship the window")
    }

    func testFocusIsEmptyForAnUntouchedWeek() {
        let sheet = Sheet.empty()
        XCTAssertEqual(sheet.focus(for: Week.parseDate("2026-09-21")!), "")
    }

    func testSettingEmptyFocusRemovesIt() {
        var sheet = Sheet.empty()
        let mondayDate = Week.parseDate("2026-09-21")!
        sheet.setFocus("Something", for: mondayDate)
        sheet.setFocus("", for: mondayDate)
        XCTAssertTrue(sheet.weeklyFocus.isEmpty)
    }

    // MARK: - Sheet: Codable

    func testSheetCodableRoundTrip() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: mon, text: "Monday thing")
        try sheet.addItem(to: wknd, text: "Weekend thing")
        sheet.addIdea(text: "An idea")
        sheet.setFocus("Rent", for: Week.parseDate("2026-09-21")!)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sheet)
        XCTAssertEqual(try JSONDecoder().decode(Sheet.self, from: data), sheet)
    }

    func testSheetEncodesBucketsAsAJSONObject() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: mon, text: "Thing")
        let data = try JSONEncoder().encode(sheet)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let buckets = obj?["buckets"] as? [String: Any]
        XCTAssertNotNil(buckets?["2026-09-21"])
    }

    func testSheetDecodeSnapsASundayKey() throws {
        let json = """
        {
            "buckets": { "2026-09-27": [{ "id": "550E8400-E29B-41D4-A716-446655440000", "text": "Sunday", "done": false }] },
            "ideas": [],
            "weeklyFocus": {}
        }
        """.data(using: .utf8)!
        let sheet = try JSONDecoder().decode(Sheet.self, from: json)
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-26")!]?.first?.text, "Sunday")
    }

    func testSheetDecodeToleratesMissingFields() throws {
        let sheet = try JSONDecoder().decode(Sheet.self, from: "{}".data(using: .utf8)!)
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.ideas.isEmpty)
        XCTAssertTrue(sheet.weeklyFocus.isEmpty)
    }

    func testSheetDecodeDropsUnparseableKeys() throws {
        let json = """
        { "buckets": { "garbage": [] }, "ideas": [], "weeklyFocus": {} }
        """.data(using: .utf8)!
        let sheet = try JSONDecoder().decode(Sheet.self, from: json)
        XCTAssertTrue(sheet.buckets.isEmpty)
    }

    // MARK: - Sheet: window

    func testWeekModeWindowIsMondayThroughWeekend() {
        let wed = Week.parseDate("2026-09-23")!
        let keys = Sheet.window(anchor: wed, mode: .week).map(\.id)
        XCTAssertEqual(keys, [
            "2026-09-21", "2026-09-22", "2026-09-23",
            "2026-09-24", "2026-09-25", "2026-09-26"
        ])
    }

    func testWeekModeWindowIsStableAcrossTheWholeWeek() {
        let expected = Sheet.window(anchor: Week.parseDate("2026-09-21")!, mode: .week)
        for day in ["2026-09-22", "2026-09-25", "2026-09-26", "2026-09-27"] {
            XCTAssertEqual(Sheet.window(anchor: Week.parseDate(day)!, mode: .week), expected, day)
        }
    }

    func testWeekModeHeadersReadMonThroughWknd() {
        let keys = Sheet.window(anchor: Week.parseDate("2026-09-21")!, mode: .week)
        XCTAssertEqual(keys.map(\.headerLabel), ["MON", "TUE", "WED", "THU", "FRI", "WKND"])
    }

    func testSlidingModePutsTheAnchorInSlotOneEveryDay() {
        // Mon 21 through Sun 27 — one full cycle, weekend included.
        for day in ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24",
                    "2026-09-25", "2026-09-26", "2026-09-27"] {
            let date = Week.parseDate(day)!
            let keys = Sheet.window(anchor: date, mode: .sliding)
            XCTAssertEqual(keys.count, 6, day)
            XCTAssertEqual(keys[1], BucketKey.containing(date), day)
        }
    }

    func testSlidingModeWindowOnMonday() {
        let keys = Sheet.window(anchor: Week.parseDate("2026-09-21")!, mode: .sliding).map(\.id)
        XCTAssertEqual(keys, [
            "2026-09-19", "2026-09-21", "2026-09-22",
            "2026-09-23", "2026-09-24", "2026-09-25"
        ])
    }

    func testSlidingModeWindowOnSundayStartsAtFriday() {
        // Saturday shares Sunday's bucket, so slot 0 falls back to Friday.
        let keys = Sheet.window(anchor: Week.parseDate("2026-09-27")!, mode: .sliding).map(\.id)
        XCTAssertEqual(keys, [
            "2026-09-25", "2026-09-26", "2026-09-28",
            "2026-09-29", "2026-09-30", "2026-10-01"
        ])
    }

    func testWindowIsAlwaysSixDistinctBuckets() {
        for mode in [WindowMode.week, .sliding] {
            for day in ["2026-09-21", "2026-09-26", "2026-09-27", "2026-12-31"] {
                let keys = Sheet.window(anchor: Week.parseDate(day)!, mode: mode)
                XCTAssertEqual(keys.count, 6)
                XCTAssertEqual(Set(keys).count, 6, "\(mode) \(day)")
            }
        }
    }

    // MARK: - Sheet: anchor stepping

    func testWeekModeAnchorStepsAWholeWeek() {
        let mon = Week.parseDate("2026-09-21")!
        let back = Sheet.steppedAnchor(mon, by: -1, mode: .week)
        XCTAssertEqual(Sheet.window(anchor: back, mode: .week).first?.id, "2026-09-14")
        let forward = Sheet.steppedAnchor(mon, by: 1, mode: .week)
        XCTAssertEqual(Sheet.window(anchor: forward, mode: .week).first?.id, "2026-09-28")
    }

    func testSlidingModeAnchorStepsOneBucket() {
        let mon = Week.parseDate("2026-09-21")!
        let back = Sheet.steppedAnchor(mon, by: -1, mode: .sliding)
        XCTAssertEqual(BucketKey.containing(back).id, "2026-09-19")
        let forward = Sheet.steppedAnchor(mon, by: 1, mode: .sliding)
        XCTAssertEqual(BucketKey.containing(forward).id, "2026-09-22")
    }

    // MARK: - Sheet: navigation clamp

    func testCanStepBackOneWeekButNotTwo() {
        let now = Week.parseDate("2026-09-21")!
        XCTAssertTrue(Sheet.canStepBack(from: now, mode: .week, now: now))
        let oneBack = Sheet.steppedAnchor(now, by: -1, mode: .week)
        XCTAssertFalse(Sheet.canStepBack(from: oneBack, mode: .week, now: now))
    }

    func testCanStepBackStopsAtTheRetentionHorizon() {
        let now = Week.parseDate("2026-09-21")!
        var anchor = now
        var steps = 0
        while Sheet.canStepBack(from: anchor, mode: .sliding, now: now), steps < 20 {
            anchor = Sheet.steppedAnchor(anchor, by: -1, mode: .sliding)
            steps += 1
        }
        XCTAssertLessThan(steps, 20, "clamp never engaged")
        // The oldest reachable slot 0 must still be inside the 7-day horizon.
        let horizon = Calendar.current.date(byAdding: .day, value: -Sheet.retentionDays,
                                            to: Calendar.current.startOfDay(for: now))!
        let slot0 = Sheet.window(anchor: anchor, mode: .sliding)[0]
        XCTAssertGreaterThanOrEqual(slot0.lastDate, horizon)
    }

    func testCanStepBackIsIndependentOfStoredData() {
        // An empty sheet must still navigate; the clamp is a date rule, not a data rule.
        let now = Week.parseDate("2026-09-21")!
        XCTAssertTrue(Sheet.canStepBack(from: now, mode: .sliding, now: now))
    }

    // MARK: - Sheet: prune

    func testPruneKeepsABucketExactlySevenDaysOld() throws {
        let now = Week.parseDate("2026-09-21")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-14")!, text: "Exactly seven days")
        sheet.prune(now: now)
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-14")!]?.count, 1)
    }

    func testPruneDropsAnOlderBucket() throws {
        let now = Week.parseDate("2026-09-21")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-11")!, text: "Too old")
        sheet.prune(now: now)
        XCTAssertTrue(sheet.buckets.isEmpty)
    }

    func testPruneDropsDoneAndUnfinishedAlike() throws {
        let now = Week.parseDate("2026-09-21")!
        var sheet = Sheet.empty()
        let old = BucketKey("2026-09-11")!
        let item = try sheet.addItem(to: old, text: "Never did it")
        try sheet.addItem(to: old, text: "Did it")
        try sheet.toggleDone(sheet.buckets[old]![1].id)
        sheet.prune(now: now)
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.ideas.isEmpty, "prune must not rescue into ideas")
        XCTAssertFalse(sheet.ideas.contains(where: { $0.id == item.id }))
    }

    func testPruneJudgesAWeekendBucketByItsSunday() throws {
        // Sat 2026-09-12 / Sun 2026-09-13. Against a Sun 2026-09-20 now, the horizon is
        // 2026-09-13, so the bucket survives on the strength of its Sunday — judged by its key
        // it would already be gone.
        let now = Week.parseDate("2026-09-20")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-12")!, text: "Weekend")
        sheet.prune(now: now)
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-12")!]?.count, 1)
    }

    func testPruneKeepsIdeasAndFocus() throws {
        let now = Week.parseDate("2026-09-21")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-11")!, text: "Too old")
        sheet.addIdea(text: "Ideas never expire")
        sheet.setFocus("Focus never expires", for: Week.parseDate("2026-09-07")!)
        sheet.prune(now: now)
        XCTAssertEqual(sheet.ideas.count, 1)
        XCTAssertEqual(sheet.weeklyFocus.count, 1)
    }

    func testPruneKeepsTheFuture() throws {
        let now = Week.parseDate("2026-09-21")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-12-25")!, text: "Far ahead")
        sheet.prune(now: now)
        XCTAssertEqual(sheet.buckets.count, 1)
    }

    // MARK: - Legacy migration

    private var legacyJSON: Data {
        """
        {
            "weekStart": "2026-09-21",
            "days": {
                "mon": [{ "id": "550E8400-E29B-41D4-A716-446655440001", "text": "Monday thing", "done": true }],
                "fri": [{ "id": "550E8400-E29B-41D4-A716-446655440002", "text": "Friday thing", "done": false }],
                "wknd": [{ "id": "550E8400-E29B-41D4-A716-446655440003", "text": "Weekend thing", "done": false }]
            },
            "ideas": [{ "id": "550E8400-E29B-41D4-A716-446655440004", "text": "An idea", "done": false }],
            "reminder": "Rent, Tuesday",
            "notes": "Dropped on the floor."
        }
        """.data(using: .utf8)!
    }

    func testLegacyDaysBecomeDatedBuckets() throws {
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON)
        let sheet = try legacy.toSheet()
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-21")!]?.first?.text, "Monday thing")
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-25")!]?.first?.text, "Friday thing")
    }

    func testLegacyWeekendLandsOnTheSaturdayKey() throws {
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON)
        let sheet = try legacy.toSheet()
        let saturday = BucketKey("2026-09-26")!
        XCTAssertTrue(saturday.isWeekend)
        XCTAssertEqual(sheet.buckets[saturday]?.first?.text, "Weekend thing")
    }

    func testLegacyMigrationPreservesItemIDsAndDoneFlags() throws {
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON)
        let sheet = try legacy.toSheet()
        let monday = sheet.buckets[BucketKey("2026-09-21")!]!.first!
        XCTAssertEqual(monday.id, UUID(uuidString: "550E8400-E29B-41D4-A716-446655440001"))
        XCTAssertTrue(monday.done)
    }

    func testLegacyReminderBecomesTheWeeklyFocus() throws {
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON)
        let sheet = try legacy.toSheet()
        XCTAssertEqual(sheet.focus(for: Week.parseDate("2026-09-21")!), "Rent, Tuesday")
    }

    func testLegacyIdeasCarryOver() throws {
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON)
        let sheet = try legacy.toSheet()
        XCTAssertEqual(sheet.ideas.map(\.text), ["An idea"])
    }

    func testLegacyEmptyDaysProduceNoBuckets() throws {
        let json = """
        {
            "weekStart": "2026-09-21",
            "days": { "mon": [], "tue": [], "wed": [], "thu": [], "fri": [], "wknd": [] },
            "ideas": [],
            "reminder": ""
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: json)
        let sheet = try legacy.toSheet()
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.weeklyFocus.isEmpty, "an empty reminder should not create a focus entry")
    }

    func testLegacyToleratesMissingFields() throws {
        let json = """
        { "weekStart": "2026-09-21" }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: json)
        let sheet = try legacy.toSheet()
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.ideas.isEmpty)
    }

    func testLegacyUnparseableWeekStartThrows() {
        let json = """
        {
            "weekStart": "not-a-date",
            "days": { "mon": [{ "id": "550E8400-E29B-41D4-A716-446655440001", "text": "Precious", "done": false }] },
            "ideas": [],
            "reminder": "Keep me"
        }
        """.data(using: .utf8)!
        let legacy = try! JSONDecoder().decode(LegacyWeek.self, from: json)
        XCTAssertThrowsError(try legacy.toSheet(), "a file we cannot date must abort the migration, not return an empty sheet the caller would write back")
    }

    func testLegacyNonMondayWeekStartThrows() throws {
        // 2026-09-22 is a Tuesday. With that start, `fri` and `wknd` would both resolve to
        // Saturday 2026-09-26 and merge.
        let json = """
        {
            "weekStart": "2026-09-22",
            "days": {
                "fri": [{ "id": "550E8400-E29B-41D4-A716-446655440002", "text": "Friday", "done": false }],
                "wknd": [{ "id": "550E8400-E29B-41D4-A716-446655440003", "text": "Weekend", "done": false }]
            },
            "ideas": [],
            "reminder": ""
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: json)
        XCTAssertThrowsError(try legacy.toSheet())
    }

    func testLegacyOverCapDayOverflowsToIdeas() throws {
        // A well-formed file can still hold more than three items in a day. `validate()` moves the
        // excess to ideas, in reverse order because it pops from the end, and clears `done` on them.
        let json = """
        {
            "weekStart": "2026-09-21",
            "days": {
                "mon": [
                    { "id": "550E8400-E29B-41D4-A716-446655440010", "text": "Item 0", "done": true },
                    { "id": "550E8400-E29B-41D4-A716-446655440011", "text": "Item 1", "done": true },
                    { "id": "550E8400-E29B-41D4-A716-446655440012", "text": "Item 2", "done": true },
                    { "id": "550E8400-E29B-41D4-A716-446655440013", "text": "Item 3", "done": true },
                    { "id": "550E8400-E29B-41D4-A716-446655440014", "text": "Item 4", "done": true }
                ]
            },
            "ideas": [],
            "reminder": ""
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder().decode(LegacyWeek.self, from: json)
        let sheet = try legacy.toSheet()

        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-21")!]?.count, 3)
        XCTAssertEqual(sheet.ideas.map(\.text), ["Item 4", "Item 3"])
        XCTAssertTrue(sheet.ideas.allSatisfy { !$0.done }, "validate() clears done on overflowed items")
    }
}
