import XCTest
@testable import WeekSheet

final class SheetTests: XCTestCase {

    // MARK: - BucketKey

    func testWeekdayBucketKeysItself() {
        let tue = Sheet.parseDate("2026-09-22")!
        XCTAssertEqual(BucketKey.containing(tue).id, "2026-09-22")
        XCTAssertFalse(BucketKey.containing(tue).isWeekend)
    }

    func testSaturdayIsAWeekendBucket() {
        let sat = Sheet.parseDate("2026-09-26")!
        let key = BucketKey.containing(sat)
        XCTAssertEqual(key.id, "2026-09-26")
        XCTAssertTrue(key.isWeekend)
    }

    func testSundaySnapsBackToItsSaturday() {
        let sun = Sheet.parseDate("2026-09-27")!
        let key = BucketKey.containing(sun)
        XCTAssertEqual(key.id, "2026-09-26")
        XCTAssertTrue(key.isWeekend)
    }

    func testWeekendBucketSpansTwoDays() {
        let key = BucketKey("2026-09-26")!
        XCTAssertEqual(key.firstDate, Sheet.parseDate("2026-09-26")!)
        XCTAssertEqual(key.lastDate, Sheet.parseDate("2026-09-27")!)
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
        XCTAssertEqual(BucketKey.monday(of: Sheet.parseDate("2026-09-23")!).id, "2026-09-21")
        XCTAssertEqual(BucketKey.monday(of: Sheet.parseDate("2026-09-21")!).id, "2026-09-21")
        XCTAssertEqual(BucketKey.monday(of: Sheet.parseDate("2026-09-27")!).id, "2026-09-21")
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

    func testSheetToggleDoneNoOpOnIdea() throws {
        var sheet = Sheet.empty()
        let idea = sheet.addIdea(text: "Maybe")
        try sheet.toggleDone(idea.id)
        XCTAssertFalse(sheet.ideas[0].done)
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

    func testSheetDeleteFromIdeas() throws {
        var sheet = Sheet.empty()
        let idea = sheet.addIdea(text: "Nope")
        try sheet.deleteItem(idea.id)
        XCTAssertTrue(sheet.ideas.isEmpty)
    }

    func testSheetDeleteThrowsForUnknownID() {
        var sheet = Sheet.empty()
        let unknown = UUID()
        XCTAssertThrowsError(try sheet.deleteItem(unknown)) { error in
            XCTAssertEqual(error as? SheetError, .itemNotFound(unknown))
        }
    }

    func testSheetMoveItemBetweenBuckets() throws {
        var sheet = Sheet.empty()
        let item = try sheet.addItem(to: mon, text: "Slides")
        try sheet.moveItem(item.id, to: wknd, at: 0)
        XCTAssertTrue(sheet.buckets[mon, default: []].isEmpty)
        XCTAssertEqual(sheet.buckets[wknd]?.first?.text, "Slides")
    }

    func testSheetMoveFromIdeasToBucket() throws {
        var sheet = Sheet.empty()
        let idea = sheet.addIdea(text: "Promote")
        try sheet.moveItem(idea.id, to: mon, at: 0)
        XCTAssertTrue(sheet.ideas.isEmpty)
        XCTAssertEqual(sheet.buckets[mon]?.first?.text, "Promote")
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

    func testSheetMoveToIdeasNoOpWhenAlreadyIdea() throws {
        var sheet = Sheet.empty()
        let idea = sheet.addIdea(text: "Stay")
        try sheet.moveToIdeas(idea.id)
        XCTAssertEqual(sheet.ideas.count, 1)
    }

    func testSheetRemoveIdea() throws {
        var sheet = Sheet.empty()
        let idea = sheet.addIdea(text: "Someday")
        try sheet.removeIdea(idea.id)
        XCTAssertTrue(sheet.ideas.isEmpty)
    }

    func testSheetRemoveIdeaThrowsForBucketItem() throws {
        var sheet = Sheet.empty()
        let item = try sheet.addItem(to: mon, text: "Bucket task")
        XCTAssertThrowsError(try sheet.removeIdea(item.id))
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
        let wed = Sheet.parseDate("2026-09-23")!
        sheet.setFocus("Ship the window", for: wed)
        XCTAssertEqual(sheet.weeklyFocus[BucketKey("2026-09-21")!], "Ship the window")
        XCTAssertEqual(sheet.focus(for: Sheet.parseDate("2026-09-27")!), "Ship the window")
    }

    func testFocusIsEmptyForAnUntouchedWeek() {
        let sheet = Sheet.empty()
        XCTAssertEqual(sheet.focus(for: Sheet.parseDate("2026-09-21")!), "")
    }

    func testSettingEmptyFocusRemovesIt() {
        var sheet = Sheet.empty()
        let mondayDate = Sheet.parseDate("2026-09-21")!
        sheet.setFocus("Something", for: mondayDate)
        sheet.setFocus("", for: mondayDate)
        XCTAssertTrue(sheet.weeklyFocus.isEmpty)
    }

    // MARK: - Sheet: Codable

    func testItemDecodesWithoutADoneField() throws {
        let json = """
        { "id": "550E8400-E29B-41D4-A716-446655440000", "text": "No done field" }
        """.data(using: .utf8)!
        let item = try JSONDecoder().decode(Item.self, from: json)
        XCTAssertEqual(item.text, "No done field")
        XCTAssertFalse(item.done, "a missing done key must decode as false, not fail the decode")
    }

    func testSheetCodableRoundTrip() throws {
        var sheet = Sheet.empty()
        try sheet.addItem(to: mon, text: "Monday thing")
        try sheet.addItem(to: wknd, text: "Weekend thing")
        sheet.addIdea(text: "An idea")
        sheet.setFocus("Rent", for: Sheet.parseDate("2026-09-21")!)

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
        let wed = Sheet.parseDate("2026-09-23")!
        let keys = Sheet.window(anchor: wed, mode: .week).map(\.id)
        XCTAssertEqual(keys, [
            "2026-09-21", "2026-09-22", "2026-09-23",
            "2026-09-24", "2026-09-25", "2026-09-26"
        ])
    }

    func testWeekModeWindowIsStableAcrossTheWholeWeek() {
        let expected = Sheet.window(anchor: Sheet.parseDate("2026-09-21")!, mode: .week)
        for day in ["2026-09-22", "2026-09-25", "2026-09-26", "2026-09-27"] {
            XCTAssertEqual(Sheet.window(anchor: Sheet.parseDate(day)!, mode: .week), expected, day)
        }
    }

    func testWeekModeHeadersReadMonThroughWknd() {
        let keys = Sheet.window(anchor: Sheet.parseDate("2026-09-21")!, mode: .week)
        XCTAssertEqual(keys.map(\.headerLabel), ["MON", "TUE", "WED", "THU", "FRI", "WKND"])
    }

    func testSlidingModePutsTheAnchorInSlotOneEveryDay() {
        // Mon 21 through Sun 27 — one full cycle, weekend included.
        for day in ["2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24",
                    "2026-09-25", "2026-09-26", "2026-09-27"] {
            let date = Sheet.parseDate(day)!
            let keys = Sheet.window(anchor: date, mode: .sliding)
            XCTAssertEqual(keys.count, 6, day)
            XCTAssertEqual(keys[1], BucketKey.containing(date), day)
        }
    }

    func testSlidingModeWindowOnMonday() {
        let keys = Sheet.window(anchor: Sheet.parseDate("2026-09-21")!, mode: .sliding).map(\.id)
        XCTAssertEqual(keys, [
            "2026-09-19", "2026-09-21", "2026-09-22",
            "2026-09-23", "2026-09-24", "2026-09-25"
        ])
    }

    func testSlidingModeWindowOnSundayStartsAtFriday() {
        // Saturday shares Sunday's bucket, so slot 0 falls back to Friday.
        let keys = Sheet.window(anchor: Sheet.parseDate("2026-09-27")!, mode: .sliding).map(\.id)
        XCTAssertEqual(keys, [
            "2026-09-25", "2026-09-26", "2026-09-28",
            "2026-09-29", "2026-09-30", "2026-10-01"
        ])
    }

    func testWindowIsAlwaysSixDistinctBuckets() {
        for mode in [WindowMode.week, .sliding] {
            for day in ["2026-09-21", "2026-09-26", "2026-09-27", "2026-12-31"] {
                let keys = Sheet.window(anchor: Sheet.parseDate(day)!, mode: mode)
                XCTAssertEqual(keys.count, 6)
                XCTAssertEqual(Set(keys).count, 6, "\(mode) \(day)")
            }
        }
    }

    // MARK: - Sheet: anchor stepping

    func testWeekModeAnchorStepsAWholeWeek() {
        let mon = Sheet.parseDate("2026-09-21")!
        let back = Sheet.steppedAnchor(mon, by: -1, mode: .week)
        XCTAssertEqual(Sheet.window(anchor: back, mode: .week).first?.id, "2026-09-14")
        let forward = Sheet.steppedAnchor(mon, by: 1, mode: .week)
        XCTAssertEqual(Sheet.window(anchor: forward, mode: .week).first?.id, "2026-09-28")
    }

    func testSlidingModeAnchorStepsOneBucket() {
        let mon = Sheet.parseDate("2026-09-21")!
        let back = Sheet.steppedAnchor(mon, by: -1, mode: .sliding)
        XCTAssertEqual(BucketKey.containing(back).id, "2026-09-19")
        let forward = Sheet.steppedAnchor(mon, by: 1, mode: .sliding)
        XCTAssertEqual(BucketKey.containing(forward).id, "2026-09-22")
    }

    // MARK: - Sheet: navigation clamp

    func testCanStepBackOneWeekButNotTwo() {
        let now = Sheet.parseDate("2026-09-21")!
        XCTAssertTrue(Sheet.canStepBack(from: now, mode: .week, now: now))
        let oneBack = Sheet.steppedAnchor(now, by: -1, mode: .week)
        XCTAssertFalse(Sheet.canStepBack(from: oneBack, mode: .week, now: now))
    }

    func testCanStepBackStopsAtTheRetentionHorizon() {
        let now = Sheet.parseDate("2026-09-21")!
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
        let now = Sheet.parseDate("2026-09-21")!
        XCTAssertTrue(Sheet.canStepBack(from: now, mode: .sliding, now: now))
    }

    // MARK: - Sheet: prune

    func testPruneKeepsABucketExactlySevenDaysOld() throws {
        let now = Sheet.parseDate("2026-09-21")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-14")!, text: "Exactly seven days")
        sheet.prune(now: now)
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-14")!]?.count, 1)
    }

    func testPruneDropsAnOlderBucket() throws {
        let now = Sheet.parseDate("2026-09-21")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-11")!, text: "Too old")
        sheet.prune(now: now)
        XCTAssertTrue(sheet.buckets.isEmpty)
    }

    func testPruneDropsDoneAndUnfinishedAlike() throws {
        let now = Sheet.parseDate("2026-09-21")!
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
        let now = Sheet.parseDate("2026-09-20")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-12")!, text: "Weekend")
        sheet.prune(now: now)
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-12")!]?.count, 1)
    }

    func testPruneKeepsIdeasAndFocus() throws {
        let now = Sheet.parseDate("2026-09-21")!
        var sheet = Sheet.empty()
        try sheet.addItem(to: BucketKey("2026-09-11")!, text: "Too old")
        sheet.addIdea(text: "Ideas never expire")
        sheet.setFocus("Focus never expires", for: Sheet.parseDate("2026-09-07")!)
        sheet.prune(now: now)
        XCTAssertEqual(sheet.ideas.count, 1)
        XCTAssertEqual(sheet.weeklyFocus.count, 1)
    }

    func testPruneKeepsTheFuture() throws {
        let now = Sheet.parseDate("2026-09-21")!
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
        XCTAssertEqual(sheet.focus(for: Sheet.parseDate("2026-09-21")!), "Rent, Tuesday")
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

    // MARK: - SheetViewModel

    /// A view model over a throwaway store. The caller owns the directory and must remove it.
    private func makeViewModel(_ tmp: URL) -> SheetViewModel {
        SheetViewModel(store: FileStore(baseURL: tmp))
    }

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("WeekSheetViewModel-\(UUID().uuidString)")
    }

    /// The end-to-end property the quarantine exists for, spanning `FileStore.load`, the view
    /// model's `try?` fallback and `save()`: a file the app cannot interpret still costs the user
    /// nothing. Any one of those three links breaking loses their items, so this asserts on the
    /// bytes rather than on a file merely existing.
    func testAnEditAfterAnUnreadableFileCannotDestroyTheOriginal() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }

        // The only copy of the user's items, in a shape nothing can interpret.
        let precious = """
        {
            "weekStart": "not-a-date",
            "days": { "mon": [{ "id": "550E8400-E29B-41D4-A716-446655440001", "text": "Precious", "done": false }] },
            "ideas": [],
            "reminder": "Keep me"
        }
        """.data(using: .utf8)!
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try precious.write(to: tmp.appendingPathComponent("week.json"))

        // The view model swallows the throw and degrades to an empty sheet, so the user is shown
        // a blank week...
        let viewModel = makeViewModel(tmp)
        XCTAssertTrue(viewModel.sheet.buckets.isEmpty, "an uninterpretable file must not load")

        // ...and starts typing into it, which saves.
        viewModel.addItem(to: BucketKey("2026-09-22")!, text: "Typed over the top")
        XCTAssertFalse(viewModel.sheet.buckets.isEmpty, "the edit should have been applied")

        // That save really did land on week.json — the hazard is not hypothetical.
        let written = try Data(contentsOf: tmp.appendingPathComponent("week.json"))
        XCTAssertNotEqual(written, precious, "week.json was overwritten, as the user's edit must")

        // And the original survived it, byte for byte.
        let quarantined = try FileManager.default
            .contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("week-unreadable-") }
        XCTAssertEqual(quarantined.count, 1, "expected exactly one quarantined file")
        XCTAssertEqual(try quarantined.first.map { try Data(contentsOf: $0) }, precious,
                       "the user's only copy must survive the save byte-for-byte")
    }

    func testUndoRestoresADeletedItemToItsOwnBucket() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let tuesday = BucketKey("2026-09-22")!
        let thursday = BucketKey("2026-09-24")!
        // Delete the first of three: appending on undo would put it back in the wrong place, so
        // this distinguishes "restored at its position" from "restored into the bucket".
        let a = try viewModel.sheet.addItem(to: tuesday, text: "A")
        try viewModel.sheet.addItem(to: tuesday, text: "B")
        try viewModel.sheet.addItem(to: tuesday, text: "C")
        try viewModel.sheet.addItem(to: thursday, text: "Elsewhere")

        viewModel.deleteItem(a.id)
        XCTAssertEqual(viewModel.sheet.buckets[tuesday]?.map(\.text), ["B", "C"])

        viewModel.undo()
        XCTAssertEqual(viewModel.sheet.buckets[tuesday]?.map(\.text), ["A", "B", "C"],
                       "undo must restore to its own bucket, at its old position")
        XCTAssertEqual(viewModel.sheet.buckets[thursday]?.map(\.text), ["Elsewhere"],
                       "and must not land in some other bucket")

        // Deleting the last item drops the bucket, so undo has to recreate it.
        let friday = BucketKey("2026-09-25")!
        let solo = try viewModel.sheet.addItem(to: friday, text: "Solo")
        viewModel.deleteItem(solo.id)
        XCTAssertNil(viewModel.sheet.buckets[friday], "an emptied bucket is dropped")

        viewModel.undo()
        XCTAssertEqual(viewModel.sheet.buckets[friday]?.map(\.text), ["Solo"],
                       "undo must recreate the bucket deleting emptied")
    }

    func testMovingToAFullBucketIsRefusedAndShakesIt() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let full = BucketKey("2026-09-22")!
        let source = BucketKey("2026-09-23")!
        try viewModel.sheet.addItem(to: full, text: "A")
        try viewModel.sheet.addItem(to: full, text: "B")
        try viewModel.sheet.addItem(to: full, text: "C")
        let fourth = try viewModel.sheet.addItem(to: source, text: "D")

        viewModel.moveItemToBucket(fourth.id, bucket: full, position: 0)

        XCTAssertEqual(viewModel.sheet.buckets[full]?.map(\.text), ["A", "B", "C"],
                       "a full bucket must refuse a fourth item")
        XCTAssertEqual(viewModel.sheet.buckets[source]?.map(\.text), ["D"],
                       "and the refused item must stay where it was")
        XCTAssertEqual(viewModel.shakingBucket, full)
    }

    func testTickMovesTheWindowWhenTheWeekRollsOver() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("WeekSheetTick-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = SheetViewModel(store: FileStore(baseURL: tmp))

        // Sunday still belongs to the week that starts on the 21st.
        viewModel.tick(now: Sheet.parseDate("2026-09-27")!)
        XCTAssertEqual(viewModel.window.first?.id, "2026-09-21")

        // Crossing into Monday must move the window, or the sheet shows a finished week with
        // nothing highlighted.
        viewModel.tick(now: Sheet.parseDate("2026-09-28")!)
        XCTAssertEqual(viewModel.window.first?.id, "2026-09-28")
        XCTAssertEqual(BucketKey.containing(viewModel.today), BucketKey("2026-09-28")!)
    }

    // MARK: - Navigation sequences

    func testForwardThenBackReturnsToTheSameWindow() {
        let anchor = Sheet.parseDate("2026-09-21")!
        for mode in [WindowMode.week, .sliding] {
            let start = Sheet.window(anchor: anchor, mode: mode)
            let forward = Sheet.steppedAnchor(anchor, by: 1, mode: mode)
            let back = Sheet.steppedAnchor(forward, by: -1, mode: mode)
            XCTAssertEqual(Sheet.window(anchor: back, mode: mode), start, "\(mode)")
        }
    }

    func testForwardNavigationIsNeverClamped() {
        let now = Sheet.parseDate("2026-09-21")!
        var anchor = now
        for _ in 0..<50 { anchor = Sheet.steppedAnchor(anchor, by: 1, mode: .sliding) }
        XCTAssertEqual(Sheet.window(anchor: anchor, mode: .sliding).count, 6)
    }

    // `testTickMovesTheWindowWhenTheWeekRollsOver` above already covers "midnight moves the
    // window when the user has not navigated" -- confirmed still passing with `followsToday` in
    // place, so it is not duplicated here.

    /// Uses `stepForward()`, not `stepBack()`: the view model's `canStepBack` clamps against the
    /// real wall clock (`Sheet.canStepBack` defaults `now` to `Date()`), so a back-step's success
    /// depends on which real-world weekday the suite happens to run on. Forward navigation is
    /// never clamped, which exercises the same `followsToday` path without that flakiness.
    func testTickDoesNotMoveTheWindowAtMidnightAfterTheUserHasNavigated() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        viewModel.stepForward()
        let navigated = viewModel.window

        // Cross a day boundary while the user is looking at a week they deliberately chose.
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        viewModel.tick(now: tomorrow)

        XCTAssertEqual(viewModel.window, navigated,
                       "midnight must not yank the window back to today once the user has navigated")
    }

    func testGoToTodayRestoresFollowingTheCalendar() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        viewModel.stepForward()
        viewModel.goToToday()

        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        viewModel.tick(now: tomorrow)

        XCTAssertEqual(viewModel.window, Sheet.window(anchor: tomorrow, mode: .week),
                       "goToToday must restore the follow-the-calendar behaviour")
    }
}
