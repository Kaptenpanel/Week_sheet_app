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

    /// The same end-to-end property as above, for the other route into a destroyed original: a
    /// migration whose write fails. Makes the store's directory read-only after seeding a legacy
    /// file, so the read succeeds and the subsequent writes do not.
    func testAnEditAfterAFailedMigrationWriteCannotDestroyTheOriginal() throws {
        let tmp = scratchDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
            try? FileManager.default.removeItem(at: tmp)
        }

        // The only copy of the user's items, in the legacy shape.
        let legacy = """
        {
            "weekStart": "2026-09-21",
            "days": { "mon": [{ "id": "550E8400-E29B-41D4-A716-446655440001", "text": "Monday thing", "done": false }] },
            "ideas": [],
            "reminder": "Rent"
        }
        """.data(using: .utf8)!
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try legacy.write(to: tmp.appendingPathComponent("week.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: tmp.path)

        // The read succeeds and the migration converts it in memory, even though the migration
        // write, the backup copy and the save below all fail against the read-only directory.
        let viewModel = makeViewModel(tmp)
        XCTAssertEqual(viewModel.sheet.buckets[BucketKey("2026-09-21")!]?.first?.text, "Monday thing",
                       "the migrated sheet must load despite the failed write")

        // ...and starts typing into it, which saves — and fails, silently.
        viewModel.addItem(to: BucketKey("2026-09-22")!, text: "Should not persist")

        // The original legacy bytes must still be exactly what is on disk.
        let written = try Data(contentsOf: tmp.appendingPathComponent("week.json"))
        XCTAssertEqual(written, legacy, "a failed save must leave week.json exactly as it was")
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
    // place, so it is not duplicated here. It ticks 2026-09-27 (Sunday) to 2026-09-28 (the
    // following Monday), whose windows start seven days apart, so unlike the two tests below in
    // their earlier form it cannot pass by coincidence regardless of which real weekday the
    // suite runs on.

    /// Uses `stepForward()`: it needs no `now` argument to unclamp, so it is the simplest way to
    /// exercise `followsToday` becoming false. The clamped case (`stepBack`) is covered on its
    /// own below, now that `canStepBack`/`stepBack` take an injectable date.
    ///
    /// The probe tick is 14 days out, not "tomorrow": `Calendar.current.date(byAdding: .day,
    /// value: 1, to: Date())` lands in the same ISO week as `Date()` on six real-world weekdays
    /// out of seven, so a same-week probe cannot tell a still-tracking anchor from a correctly
    /// frozen one -- the bug this test exists to catch would pass unnoticed most days. An exact
    /// multiple of 7 always shifts the ISO week by that many days, so it can never coincide with
    /// `navigated`'s week by weekday-dependent accident.
    func testTickDoesNotMoveTheWindowAtMidnightAfterTheUserHasNavigated() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        viewModel.stepForward()
        let navigated = viewModel.window

        let twoWeeksOut = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        viewModel.tick(now: twoWeeksOut)

        XCTAssertEqual(viewModel.window, navigated,
                       "midnight must not yank the window back to today once the user has navigated")
    }

    /// See the comment on the previous test for why the probe is a week out rather than
    /// "tomorrow": that avoids the same same-ISO-week coincidence, here between the anchor
    /// `goToToday()` resets to (today) and the tick's target (also usually today's week).
    func testGoToTodayRestoresFollowingTheCalendar() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        viewModel.stepForward()
        viewModel.goToToday()

        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        viewModel.tick(now: nextWeek)

        XCTAssertEqual(viewModel.window, Sheet.window(anchor: nextWeek, mode: .week),
                       "goToToday must restore the follow-the-calendar behaviour")
    }

    /// 2026-09-21 is a Monday: stepping the anchor back a week lands the target week's Monday
    /// exactly on the 7-day retention horizon, so the back-step is allowed. See
    /// `testCanStepBackOneWeekButNotTwo` for the `Sheet`-level version of this same fact.
    func testStepBackFromAMondayAnchorMovesTheWindowAndStopsFollowingToday() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let monday = Sheet.parseDate("2026-09-21")!
        viewModel.anchor = monday

        viewModel.stepBack(now: monday)

        XCTAssertEqual(viewModel.window.first?.id, "2026-09-14",
                       "a permitted back-step must move the window one week earlier")

        // `followsToday` is private; observe its effect instead -- a tick that crosses a day
        // boundary must not snap the window back to today now that the user has navigated. The
        // probe is two weeks past the new anchor so the comparison cannot coincide by accident
        // (see the multiple-of-7 note above).
        let navigated = viewModel.window
        let twoWeeksOut = Calendar.current.date(byAdding: .day, value: 14, to: monday)!
        viewModel.tick(now: twoWeeksOut)
        XCTAssertEqual(viewModel.window, navigated, "stepBack must clear followsToday")
    }

    /// 2026-09-22 is a Tuesday: stepping the anchor back a week would land the target week's
    /// Monday one day past the 7-day retention horizon, so the back-step is refused. This
    /// asymmetry with the Monday case above is a consequence of the retention horizon, not a
    /// bug -- week mode only permits a back-step on the one day a week the target week's Monday
    /// is still in range.
    func testStepBackFromATuesdayAnchorIsRefusedByTheRetentionHorizon() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let tuesday = Sheet.parseDate("2026-09-22")!
        viewModel.anchor = tuesday
        let before = viewModel.window

        viewModel.stepBack(now: tuesday)

        XCTAssertEqual(viewModel.window, before, "a refused back-step must not move the window")

        // `followsToday` is private; observe its effect instead -- since nothing navigated, a
        // tick crossing a day boundary must still move the window with the calendar.
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: tuesday)!
        viewModel.tick(now: nextWeek)
        XCTAssertNotEqual(viewModel.window, before,
                          "with the back-step refused, followsToday must still be true")
    }

    /// Regression: removing `cancelEditing()` from the navigation actions left the focus field
    /// open across navigation (unlike a bucket-item field, it is not torn down, since its mount
    /// condition is just `editingFocus && isEditMode`). If `updateFocus` read `anchor` at
    /// commit time, text typed for one week could land on whichever week the user had since
    /// navigated to. `startEditingFocus` must bind the destination when editing begins instead.
    func testFocusCommitsToTheWeekItWasOpenedForEvenAfterNavigatingAway() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let monday = Sheet.parseDate("2026-09-21")!
        viewModel.anchor = monday

        viewModel.startEditingFocus()
        viewModel.stepForward() // anchor moves a week later; the field stays open

        viewModel.updateFocus("Typed while looking at a different week")

        XCTAssertEqual(viewModel.sheet.focus(for: monday), "Typed while looking at a different week",
                       "the text must land on the week the user was editing")
        XCTAssertEqual(viewModel.sheet.focus(for: viewModel.anchor), "",
                       "the week now on screen must be untouched")
    }

    /// `editingFocusAnchor` is private, so this observes it through `updateFocus`'s fallback
    /// instead: if `cancelEditingFocus()` failed to clear it, a later `updateFocus` reached without
    /// an intervening `startEditingFocus()` would still resolve to the cancelled week, not the one
    /// currently on screen.
    func testCancelingFocusEditClearsTheBoundAnchor() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let monday = Sheet.parseDate("2026-09-21")!
        viewModel.anchor = monday

        viewModel.startEditingFocus()
        viewModel.cancelEditingFocus()
        XCTAssertFalse(viewModel.editingFocus, "cancelling must leave edit mode")

        viewModel.stepForward() // anchor moves away from the week the cancelled edit was opened for
        viewModel.updateFocus("Committed after a cancel, with no new startEditingFocus")

        XCTAssertEqual(viewModel.sheet.focus(for: viewModel.anchor),
                       "Committed after a cancel, with no new startEditingFocus",
                       "with the anchor cleared, this commit must fall back to the week now on screen")
        XCTAssertEqual(viewModel.sheet.focus(for: monday), "",
                       "the cancelled week must be untouched by a later, unrelated commit")
    }

    /// Regression: `selectedID` used to die with `cancelEditing()` on every navigation. Without
    /// that, it survives, and `deleteItem`/`toggleDone` search every bucket rather than just the
    /// window -- so a stale selection lets Space/Delete reach an item that is no longer on screen.
    /// The second assertion is the one that matters: it pins the hazard `deleteItem` shares with
    /// `toggleDone`, not just the flag that happens to cause it.
    func testNavigatingClearsAStaleSelectionSoToggleDoneCannotReachIt() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let monday = Sheet.parseDate("2026-09-21")!
        viewModel.anchor = monday
        let tuesday = BucketKey("2026-09-22")!
        let item = try viewModel.sheet.addItem(to: tuesday, text: "Off screen after navigating")
        viewModel.select(item.id)

        viewModel.stepForward()

        XCTAssertNil(viewModel.selectedID, "navigation must clear a stale selection")

        viewModel.toggleDone()
        XCTAssertEqual(viewModel.sheet.buckets[tuesday]?.first(where: { $0.id == item.id })?.done, false,
                       "toggleDone must not be able to reach an item that is no longer on screen")
    }

    /// Regression: `editingID`/`addingBucket` used to die with `cancelEditing()` on every
    /// navigation. Without that, `installKeyHandler`'s guard (`if self.editingID != nil ||
    /// self.addingBucket != nil ...`) keeps skipping Space/Delete/Escape after the field that set
    /// them has already been unmounted, leaving the keyboard dead until the user clicks elsewhere.
    func testNavigatingClearsAStaleBucketItemEdit() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let monday = Sheet.parseDate("2026-09-21")!
        viewModel.anchor = monday
        let tuesday = BucketKey("2026-09-22")!
        let item = try viewModel.sheet.addItem(to: tuesday, text: "Mid-edit")
        viewModel.startEditing(item.id)
        viewModel.addingBucket = BucketKey("2026-09-23")!

        viewModel.stepForward()

        XCTAssertNil(viewModel.editingID, "navigation must clear a stale item edit")
        XCTAssertNil(viewModel.addingBucket, "navigation must clear a stale add-to-bucket")
    }

    /// The asymmetry with the two tests above is deliberate, not an oversight: `addingIdea`'s
    /// field is not window-gated (ideas are not tied to a bucket), so it stays mounted across a
    /// navigation and still holds whatever the user has typed. A future tidy-up that folds this
    /// into `clearWindowBoundEditingState()` "for consistency" would silently discard that text --
    /// this test exists to catch exactly that.
    func testNavigatingDoesNotClearAnInProgressIdea() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        viewModel.startAddingIdea()
        viewModel.stepForward()

        XCTAssertTrue(viewModel.addingIdea, "an in-progress idea must survive navigation, not be discarded")
    }

    /// Regression: `editingID` is not purely bucket-item state -- double-tapping an idea chip also
    /// routes through `startEditing`, and `ideasPanel` is not window-gated, so that field is still
    /// mounted and still holds the user's typed text after navigation. Round 2's unconditional
    /// `editingID = nil` would unmount it and lose the rename with no recovery, the same mistake
    /// round 1 fixed for the focus field, reintroduced through a different vector.
    func testNavigatingDoesNotDisturbAnInProgressIdeaRename() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let idea = viewModel.sheet.addIdea(text: "Rename me")
        viewModel.startEditing(idea.id)

        viewModel.stepForward()

        XCTAssertEqual(viewModel.editingID, idea.id,
                       "an in-progress idea rename must survive navigation, not be discarded")
    }

    /// Companion to the rename test above: an idea chip's selection is likewise still visible
    /// after navigation (ideas aren't tied to a bucket), so clearing it would deselect something
    /// the user can still see for no benefit -- unlike a bucket item's selection, nothing reachable
    /// from the keyboard becomes unsafe by leaving it set.
    func testNavigatingDoesNotClearASelectedIdeaChip() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let idea = viewModel.sheet.addIdea(text: "Keep me selected")
        viewModel.select(idea.id)

        viewModel.stepForward()

        XCTAssertEqual(viewModel.selectedID, idea.id,
                       "a selected idea chip is still visible after navigation and must stay selected")
    }

    /// Regression: `goToToday()` had no equivalent of `stepBack`'s "did anything actually change"
    /// guard, so pressing it while already viewing today's week -- a redundant press, or simply
    /// opening the app fresh -- cleared an in-progress edit that was never unmounted, because the
    /// window never moved.
    func testGoToTodayLeavesAnEditAloneWhenTheWindowDoesNotMove() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let tuesday = BucketKey("2026-09-22")!
        let item = try viewModel.sheet.addItem(to: tuesday, text: "Mid-edit")
        viewModel.startEditing(item.id)

        viewModel.goToToday() // no prior navigation -- the window cannot have moved

        XCTAssertEqual(viewModel.editingID, item.id,
                       "goToToday must not clear an edit when the window did not actually move")
    }

    // MARK: - Sliding mode

    /// Regression: `clearWindowBoundEditingState()` used `window != before` as a proxy for "did
    /// this id's bucket leave the window". That proxy is exact in week mode, where a step replaces
    /// every key, but a single sliding step keeps five of the six buckets -- so the old proxy would
    /// have deselected an item that is still plainly on screen. `dropEditingStateOutsideTheWindow()`
    /// checks membership directly, so this case -- unreachable before sliding mode existed -- must
    /// now survive.
    func testSlidingModeKeepsAStillVisibleSelectionAfterOneStep() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)
        viewModel.windowMode = .sliding
        viewModel.anchor = Sheet.parseDate("2026-09-22")! // Tuesday

        let thursday = BucketKey("2026-09-24")!
        let item = try viewModel.sheet.addItem(to: thursday, text: "Still on screen after one step")
        viewModel.select(item.id)

        viewModel.stepForward()

        XCTAssertTrue(viewModel.window.contains(thursday),
                      "sanity: Thursday's bucket survives a single sliding step")
        XCTAssertEqual(viewModel.selectedID, item.id,
                       "a selection whose bucket is still in the window must survive navigation")
    }

    /// Companion to the test above: a sliding step still drops a selection whose bucket actually
    /// scrolled off the front of the window, same as week mode has always done.
    func testSlidingModeDropsASelectionThatSlidOffTheWindow() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)
        viewModel.windowMode = .sliding
        viewModel.anchor = Sheet.parseDate("2026-09-22")! // Tuesday

        let monday = BucketKey("2026-09-21")!
        let item = try viewModel.sheet.addItem(to: monday, text: "Scrolled off after one step")
        viewModel.select(item.id)

        viewModel.stepForward()

        XCTAssertFalse(viewModel.window.contains(monday),
                       "sanity: Monday's bucket is the one a forward step drops")
        XCTAssertNil(viewModel.selectedID, "a selection whose bucket left the window must still be cleared")
    }

    /// `followsToday` was only ever exercised in week mode, since `windowMode` was hardcoded until
    /// this task. Mirrors `testTickDoesNotMoveTheWindowAtMidnightAfterTheUserHasNavigated` and
    /// `testGoToTodayRestoresFollowingTheCalendar`, but in sliding mode, where a day rolling over
    /// moves the window by one bucket rather than by a week.
    func testFollowsTodayGovernsTheSlidingWindowAcrossADayRollover() {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)
        viewModel.windowMode = .sliding

        viewModel.stepForward()
        let navigated = viewModel.window

        let twoWeeksOut = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
        viewModel.tick(now: twoWeeksOut)
        XCTAssertEqual(viewModel.window, navigated,
                       "midnight must not yank the sliding window back to today once the user has navigated")

        viewModel.goToToday()
        let nextWeek = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        viewModel.tick(now: nextWeek)
        XCTAssertEqual(viewModel.window, Sheet.window(anchor: nextWeek, mode: .sliding),
                       "goToToday must restore the sliding window's tracking of the calendar")
    }

    /// Regression guard for the subtlety in `toggleWindowMode()`: it resets the anchor to today via
    /// `goToToday()`, so a naive `window != before` guard inside `goToToday()` would capture
    /// `before` *after* `windowMode` had already changed -- comparing the new mode's window against
    /// itself at nearly the same instant, which is equal almost always, since the anchor did not
    /// move. That would silently skip the clear precisely when the mode switch is what moved a
    /// bucket out from under a selection, not a navigation. Built from `Date()`-relative days so it
    /// does not depend on which real weekday the suite runs on.
    func testTogglingWindowModeDropsStateForABucketTheShapeChangeRemoved() throws {
        let tmp = scratchDirectory()
        defer {
            try? FileManager.default.removeItem(at: tmp)
            UserDefaults.standard.removeObject(forKey: "slidingMode")
        }
        let viewModel = makeViewModel(tmp)

        let mondayOfThisWeek = BucketKey.monday(of: Date()).firstDate
        let fridayOfThisWeek = Calendar.current.date(byAdding: .day, value: 4, to: mondayOfThisWeek)!
        let nextMonday = BucketKey.containing(Calendar.current.date(byAdding: .day, value: 3, to: fridayOfThisWeek)!)

        viewModel.windowMode = .sliding
        viewModel.anchor = fridayOfThisWeek
        let item = try viewModel.sheet.addItem(to: nextMonday, text: "Reached only by the sliding shape")
        viewModel.select(item.id)

        XCTAssertTrue(viewModel.window.contains(nextMonday),
                      "sanity: a Friday sliding anchor reaches one bucket into next week")

        viewModel.toggleWindowMode()

        XCTAssertEqual(viewModel.windowMode, .week)
        XCTAssertFalse(viewModel.window.contains(nextMonday),
                       "sanity: the toggle's own window no longer reaches that Monday")
        XCTAssertNil(viewModel.selectedID,
                     "the mode switch must drop selection for a bucket its own shape change removed")
    }

    /// Regression: `tick()` moves `anchor` directly when `followsToday` is true and the day rolls
    /// over, but never called the clearing helper -- neither before this task nor after. In week
    /// mode that only matters on a Sunday-to-Monday roll; in sliding mode the window can move
    /// every single night, so a selection left over from the evening before would dead-zone the
    /// key handler or let Delete reach an item no longer on screen. `tomorrow` is derived from the
    /// next bucket rather than "+1 calendar day" so this does not depend on which real weekday the
    /// suite runs on (a raw +1 day can land in the same bucket as today, across the Saturday/Sunday
    /// fold).
    func testTickAtMidnightDropsAStaleSelectionThatSlidOffTheWindow() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)
        viewModel.windowMode = .sliding
        // followsToday is true by default -- the view model has never navigated.

        let leavingBucket = viewModel.window[0] // slot 0: one bucket behind today's own.
        let item = try viewModel.sheet.addItem(to: leavingBucket, text: "Selected the night before")
        viewModel.select(item.id)

        let tomorrow = BucketKey.containing(Date()).stepped(by: 1).firstDate
        viewModel.tick(now: tomorrow)

        XCTAssertFalse(viewModel.window.contains(leavingBucket),
                       "sanity: a day's rollover must drop slot 0's bucket in sliding mode")
        XCTAssertNil(viewModel.selectedID,
                     "a midnight rollover that follows today must drop a selection whose bucket left the window")
    }

    /// Mirror of the test above: a midnight rollover must not clear a selection whose bucket is
    /// still on screen the next day.
    func testTickAtMidnightKeepsAStillVisibleSelection() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)
        viewModel.windowMode = .sliding

        let stayingBucket = viewModel.window[3] // slot 3: still three buckets ahead after one step.
        let item = try viewModel.sheet.addItem(to: stayingBucket, text: "Still on screen the next day")
        viewModel.select(item.id)

        let tomorrow = BucketKey.containing(Date()).stepped(by: 1).firstDate
        viewModel.tick(now: tomorrow)

        XCTAssertTrue(viewModel.window.contains(stayingBucket),
                      "sanity: slot 3's bucket must still be in view after one day's rollover")
        XCTAssertEqual(viewModel.selectedID, item.id,
                       "a midnight rollover must not clear a selection whose bucket is still in the window")
    }

    // MARK: - Prune vs. a parked window

    /// Regression: `prune` removes whole buckets, and `pruneIfNeeded` runs on every tick
    /// regardless of `followsToday`. With `followsToday == false` -- the user navigated and
    /// parked -- the window is frozen while `now` keeps advancing, so nothing about the window
    /// array itself changes when the retention horizon finally passes the parked bucket. The old
    /// `bucketHolding(id) == nil` check conflated "pruned" with "is an idea" (both read as "not in
    /// a bucket"), so a pruned item's dangling id was never cleared. `isVisible` checks the fact
    /// -- still in a bucket, and that bucket still in the window -- rather than that proxy.
    func testPruningAParkedWindowsBucketDropsTheSelectionInIt() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        viewModel.stepForward() // any step sets followsToday = false, on any real weekday or mode
        viewModel.anchor = Sheet.parseDate("2026-01-05")! // frozen here; followsToday stays false

        let bucket = viewModel.window[0]
        let item = try viewModel.sheet.addItem(to: bucket, text: "Parked and about to be pruned")
        viewModel.select(item.id)

        let windowBefore = viewModel.window
        let farFuture = Sheet.parseDate("2026-06-01")! // well past the 7-day retention horizon
        viewModel.tick(now: farFuture)

        XCTAssertEqual(viewModel.window, windowBefore,
                       "sanity: a parked window must not itself move on tick")
        XCTAssertNil(viewModel.sheet.buckets[bucket], "sanity: the bucket must actually have been pruned")
        XCTAssertNil(viewModel.selectedID,
                     "a selection whose bucket was pruned out from under a parked window must be cleared")
    }

    /// Companion to the test above: this is the case that made `bucketHolding(id) == nil` look
    /// like a safe stand-in for "not visible" in the first place, so it needs pinning under the
    /// new check too -- pruning an unrelated bucket must not disturb a selected idea, which is
    /// never window-bound and so always visible.
    func testPruningDoesNotDisturbASelectedIdea() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        viewModel.stepForward()
        viewModel.anchor = Sheet.parseDate("2026-01-05")!

        let bucket = viewModel.window[0]
        _ = try viewModel.sheet.addItem(to: bucket, text: "Unrelated to the idea, pruned anyway")
        let idea = viewModel.sheet.addIdea(text: "Still visible no matter what prunes")
        viewModel.select(idea.id)

        let farFuture = Sheet.parseDate("2026-06-01")!
        viewModel.tick(now: farFuture)

        XCTAssertNil(viewModel.sheet.buckets[bucket], "sanity: the unrelated bucket must actually have been pruned")
        XCTAssertEqual(viewModel.selectedID, idea.id,
                       "pruning a bucket must not disturb a selected idea, which is never window-bound")
    }

    /// Found while auditing every way an id's view can stop being on screen for the two tests
    /// above: `deleteItem` cleared `selectedID` when it matched but left a matching `editingID`
    /// dangling. Unreachable via the current UI (the key handler blocks Delete while `editingID`
    /// is set, and an idea's delete affordance is replaced by its own edit field while editing),
    /// but nothing in `deleteItem` itself enforces that -- and unlike a merely-pruned id, this one
    /// can't wait for the next drop to notice: a dangling `editingID` dead-zones the key handler
    /// the instant it happens, not just once some later event reveals it.
    func testDeletingTheItemCurrentlyBeingEditedClearsEditingIDToo() throws {
        let tmp = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let viewModel = makeViewModel(tmp)

        let bucket = viewModel.window[0]
        let item = try viewModel.sheet.addItem(to: bucket, text: "Being edited when deleted")
        viewModel.startEditing(item.id)

        viewModel.deleteItem(item.id)

        XCTAssertNil(viewModel.editingID, "deleting the item currently being edited must clear editingID")
        XCTAssertNil(viewModel.selectedID, "deleting the item currently being edited must clear selectedID too")
    }

    func testFocusFollowsTheAnchorsWeekNotTheWindowSpan() {
        // A sliding window anchored on Monday reaches back into the previous week; the focus
        // shown must be the anchor's, not slot 0's.
        var sheet = Sheet.empty()
        let thisMonday = Sheet.parseDate("2026-09-21")!
        let lastMonday = Sheet.parseDate("2026-09-14")!
        sheet.setFocus("This week", for: thisMonday)
        sheet.setFocus("Last week", for: lastMonday)

        let window = Sheet.window(anchor: thisMonday, mode: .sliding)
        XCTAssertEqual(window[0].id, "2026-09-19", "slot 0 is in the previous week")
        XCTAssertEqual(sheet.focus(for: thisMonday), "This week")
    }
}
