# Sliding Week Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single mutable `Week` and its Monday 04:00 reset with a date-keyed bucket store rendered through a window function, so the sheet can stay on a fixed week, slide so today is always the second column, and navigate through dates — while items older than a week are deleted.

**Architecture:** Storage becomes `Sheet`, a dictionary of `BucketKey → [Item]` where a `BucketKey` is an ISO date and the weekend is one bucket keyed by its Saturday. The view renders six bucket keys produced by `Sheet.window(anchor:mode:)`. There is no current-week state, so there is nothing to reset: Monday rolling over, sliding mode, and manual navigation are the same function at different anchors. Old buckets are deleted by `prune`, not recycled.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, XCTest, Carbon (`RegisterEventHotKey`). Zero external dependencies.

**Spec:** `docs/superpowers/specs/2026-09-21-sliding-week-design.md`

## Global Constraints

Copied from the spec and `docs/CLAUDE.md`. Every task's requirements implicitly include these.

- **Never add a dependency.** `Package.swift` has zero and stays that way.
- **Never add a fourth slot.** `maxItemsPerDay` is 3, permanently.
- Platform floor is `.macOS(.v13)`, swift-tools-version 5.9. Do not raise either.
- Dates are ISO 8601 `yyyy-MM-dd`, local time, `Locale(identifier: "en_US_POSIX")`.
- Every rule lives in the model, not the view.
- No settings screen, onboarding, empty-state illustration, or loading state. Configuration is a `UserDefaults` flag plus a hotkey plus a `StatusItem` menu item — the pattern `horizontalMode` already uses.
- Views marked `// UI STATUS: LOCKED` do not change structure, spacing, or colours. Recomputing a label's *source* is allowed; changing the string it produces in week mode is not.
- Test command: `swift test`. Single test: `swift test --filter <TestClass>/<testName>`.
- Baseline before Task 1: 37 tests, 0 failures.

## Plan deviations from the spec

Three refinements, each an implementation detail the spec left open:

1. The spec's step 2 ("Model") is split into Tasks 2–4 here: `BucketKey`, then `Sheet`, then the window/prune/navigation maths. Each carries its own test cycle.
2. `canStepBack` is a **static** on `Sheet`, not an instance method. Clamping against the retention horizon rather than against stored buckets means an empty sheet still allows navigation; an instance method reading `buckets` would disable the back action whenever the past happened to be empty.
3. `Sheet` coexists with `Week` from Task 3 until Task 7 deletes `Week`. `FileStore` therefore gains temporarily-named `loadSheet` / `loadSheetAndPrune` in Task 6, renamed to `load` / `loadAndPrune` in Task 7 once the `Week` overloads are gone. This keeps every task compiling and independently reviewable.

---

## File Structure

| File | Responsibility after this plan |
|---|---|
| `Sources/WeekSheet/Sheet.swift` | Renamed from `Week.swift` in Task 7. `Item`, `BucketKey`, `WindowMode`, `SheetError`, `Sheet` — model plus all date maths. |
| `Sources/WeekSheet/LegacyMigration.swift` | **New.** `LegacyWeek` decode-only shape and `toSheet()`. Self-contained so it can be deleted outright once no installs remain on the old format. |
| `Sources/WeekSheet/FileStore.swift` | Load/save `Sheet`, run the one-time migration, prune on load. Loses all history and reset methods. |
| `Sources/WeekSheet/SheetView.swift` | `SheetViewModel` gains `anchor` and `windowMode`; both layouts iterate the window. |
| `Sources/WeekSheet/WindowController.swift` | Four new hotkeys: back, forward, today, sliding-mode toggle. |
| `Sources/WeekSheet/StatusItem.swift` | One new menu item for the sliding-mode toggle. |
| `Tests/WeekSheetTests/SheetTests.swift` | Renamed from `WeekTests.swift` in Task 7. Model, window, prune, navigation. |
| `Tests/WeekSheetTests/FileStoreTests.swift` | Round trip, migration, prune-on-load. Loses history tests. |
| `docs/CLAUDE.md` | Code-shape line updated for the renamed files. |

---

## Task 1: Remove the Notes box

Idea 1 in isolation. No dependency on anything else, and it shrinks `SheetView` before the restructure touches it.

This task deletes a feature, so it is not red-green. It adds one regression guard that must pass *before and after* the deletion — proving a `week.json` written by the old build still loads — then removes the field and its assertions.

**Files:**
- Modify: `Sources/WeekSheet/Week.swift` (remove `notes` from the struct, `CodingKeys`, `empty`, `init(from:)`, `encode(to:)`, `reset`)
- Modify: `Sources/WeekSheet/SheetView.swift` (remove `editingNotes`, `startEditingNotes`, `updateNotes`, `notesPanel`, its two call sites, the key-handler reference, `cancelEditing`, and `Week.mock`'s `notes`)
- Test: `Tests/WeekSheetTests/WeekTests.swift`, `Tests/WeekSheetTests/FileStoreTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Week` without `notes`. `Week.empty(weekStart:)` and `Week(weekStart:days:ideas:reminder:)` — the initialiser loses its `notes:` argument.

- [ ] **Step 1: Write the regression guard**

Add to `Tests/WeekSheetTests/WeekTests.swift`, inside the `// MARK: - Codable` section:

```swift
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
```

- [ ] **Step 2: Run it and confirm it passes on the current code**

Run: `swift test --filter WeekTests/testDecodesLegacyFileWithNotesKey`
Expected: PASS. It pins behaviour that must survive the deletion; if it fails now, stop — something else is wrong.

- [ ] **Step 3: Remove `notes` from the model**

In `Sources/WeekSheet/Week.swift`, delete the `public var notes: String` declaration, then apply these five edits.

The initialiser:

```swift
    public init(weekStart: String, days: [Day: [Item]], ideas: [Item], reminder: String) {
        self.weekStart = weekStart
        self.days = days
        self.ideas = ideas
        self.reminder = reminder
    }
```

`empty`:

```swift
    public static func empty(weekStart: String) -> Week {
        Week(
            weekStart: weekStart,
            days: Dictionary(uniqueKeysWithValues: Day.allCases.map { ($0, [Item]()) }),
            ideas: [],
            reminder: ""
        )
    }
```

`CodingKeys` — dropping the case is what makes the decoder ignore a stale `notes` key:

```swift
    private enum CodingKeys: String, CodingKey {
        case weekStart, days, ideas, reminder
    }
```

Delete the `notes = try container.decodeIfPresent(...)` line from `init(from:)` and the `try container.encode(notes, forKey: .notes)` line from `encode(to:)`.

`reset` loses its last argument:

```swift
        return Week(
            weekStart: Self.mondayOfWeek(containing: now),
            days: Dictionary(uniqueKeysWithValues: Day.allCases.map { ($0, [Item]()) }),
            ideas: newIdeas,
            reminder: ""
        )
```

- [ ] **Step 4: Remove the Notes UI**

In `Sources/WeekSheet/SheetView.swift`:

Delete `@Published var editingNotes = false` (L39), the whole `startEditingNotes()` and `updateNotes(_:)` methods (L196–202), and the whole `notesPanel` computed property (L618–648).

`startEditingReminder` drops its `editingNotes` reset:

```swift
    func startEditingReminder() { editingReminder = true; editingID = nil; selectedID = nil; addingDay = nil; addingIdea = false }
```

`cancelEditing` likewise:

```swift
    func cancelEditing() { editingID = nil; addingDay = nil; addingIdea = false; editingReminder = false; selectedID = nil }
```

The key handler's comment and guard lose Notes:

```swift
            // Reminder gets typed keys (incl. Space); Esc still leaves edit mode.
            if self.editingReminder && event.keyCode != 53 { return event }
```

`bottom` loses the `VStack` that existed only to stack two panels:

```swift
    private var bottom: some View {
        HStack(alignment: .top, spacing: 16) {
            ideasPanel
            reminderPanel
        }
    }
```

`sidebar` loses its middle entry:

```swift
    private var sidebar: some View {
        VStack(spacing: 12) {
            ideasPanel
            reminderPanel
        }
    }
```

And `Week.mock` loses its last argument:

```swift
        reminder: "Rent, Tuesday"
    )
```

- [ ] **Step 5: Remove the stale assertions**

In `Tests/WeekSheetTests/WeekTests.swift` delete these four lines:
- `XCTAssertEqual(week.notes, "")` in `testEmptyWeek`
- `week.notes = "Some notes"` and `XCTAssertEqual(newWeek.notes, "")` in `testResetClearsDoneKeepsUnfinished`
- `week.notes = "Keep it simple"` in `testCodableRoundTrip`

In `testDecodesIdeaWithoutDoneField`, drop the `"notes": ""` line from the JSON literal (and the trailing comma on the line before it).

In `Tests/WeekSheetTests/FileStoreTests.swift` delete `week.notes = "Notes here"` and `XCTAssertEqual(loaded.notes, "Notes here")` from `testSaveAndLoad`.

- [ ] **Step 6: Run the whole suite**

Run: `swift test`
Expected: PASS, 38 tests (37 baseline + the new guard), 0 failures.

- [ ] **Step 7: Build the app target too**

Run: `swift build`
Expected: no errors. The tests do not compile `SheetView.swift`'s SwiftUI bodies fully, so this catches a missed `notesPanel` reference.

- [ ] **Step 8: Commit**

```bash
git add Sources/WeekSheet/Week.swift Sources/WeekSheet/SheetView.swift Tests/WeekSheetTests/WeekTests.swift Tests/WeekSheetTests/FileStoreTests.swift
git commit -m "Remove the Notes box

Notes was free text with no logic and no place in the sliding-window
model. Dropping the CodingKeys case makes the decoder ignore the key, so
an existing week.json still loads."
```

---

## Task 2: `BucketKey`

The unit of storage. Sunday belongs to the weekend bucket keyed by its Saturday, and that rule lives here so nothing else can get it wrong.

Note for the implementer: `Calendar.component(.weekday,)` returns 1 for Sunday and 7 for Saturday, regardless of `firstWeekday`.

**Files:**
- Modify: `Sources/WeekSheet/Week.swift` (add `BucketKey` above `Week`)
- Test: `Tests/WeekSheetTests/WeekTests.swift`

**Interfaces:**
- Consumes: `Week.parseDate(_:)` and `Week.formatDate(_:)`, existing statics on `Week`.
- Produces:
  - `BucketKey.init?(_ id: String)` — nil for a non-date; snaps a Sunday to its Saturday
  - `BucketKey.containing(_ date: Date) -> BucketKey`
  - `BucketKey.monday(of date: Date) -> BucketKey`
  - `BucketKey.id: String`, `.firstDate: Date`, `.lastDate: Date`, `.isWeekend: Bool`
  - `BucketKey.stepped(by n: Int) -> BucketKey`
  - `BucketKey.headerLabel: String`, `.compactDateLabel: String`, `.wideDateLabel: String`
  - Conformances: `Hashable`, `Comparable` (chronological), `Codable` (a bare JSON string)

Reference dates used throughout the tests below, verified against the calendar:
`2026-09-14` Mon · `2026-09-18` Fri · `2026-09-19` Sat · `2026-09-20` Sun · `2026-09-21` Mon · `2026-09-22` Tue · `2026-09-25` Fri · `2026-09-26` Sat · `2026-09-27` Sun · `2026-09-28` Mon.

- [ ] **Step 1: Write the failing tests**

Add a new section at the end of `Tests/WeekSheetTests/WeekTests.swift`, before the closing brace:

```swift
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
```

- [ ] **Step 2: Run them and verify they fail**

Run: `swift test --filter WeekTests/testSundaySnapsBackToItsSaturday`
Expected: FAIL — compile error, `cannot find 'BucketKey' in scope`.

- [ ] **Step 3: Implement `BucketKey`**

Insert in `Sources/WeekSheet/Week.swift`, immediately after the `Day` enum:

```swift
/// One column of the sheet. A weekday bucket is keyed by its own date; Saturday and Sunday
/// share one bucket, keyed by the Saturday. Constructing a key is the only way to apply that
/// rule, so nothing downstream can accidentally address a Sunday.
public struct BucketKey: Hashable, Comparable, Codable {
    /// ISO "yyyy-MM-dd", local time.
    public let id: String

    private init(unchecked id: String) { self.id = id }

    public init?(_ id: String) {
        guard let date = Week.parseDate(id) else { return nil }
        self = Self.containing(date)
    }

    public static func containing(_ date: Date) -> BucketKey {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        // .weekday is 1 for Sunday and 7 for Saturday whatever firstWeekday is set to.
        if cal.component(.weekday, from: day) == 1 {
            return BucketKey(unchecked: Week.formatDate(cal.date(byAdding: .day, value: -1, to: day)!))
        }
        return BucketKey(unchecked: Week.formatDate(day))
    }

    /// The Monday of the week containing `date`. Used to key the weekly focus.
    public static func monday(of date: Date) -> BucketKey {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return BucketKey(unchecked: Week.formatDate(cal.date(from: comps)!))
    }

    public var isWeekend: Bool { Calendar.current.component(.weekday, from: firstDate) == 7 }

    public var firstDate: Date { Week.parseDate(id)! }

    /// The last calendar day this bucket covers — the Sunday, for a weekend bucket.
    public var lastDate: Date {
        isWeekend ? Calendar.current.date(byAdding: .day, value: 1, to: firstDate)! : firstDate
    }

    /// Steps by whole buckets, not days, so Friday +1 is the weekend and the weekend +1 is Monday.
    public func stepped(by n: Int) -> BucketKey {
        var result = self
        var remaining = n
        while remaining > 0 { result = result.next; remaining -= 1 }
        while remaining < 0 { result = result.previous; remaining += 1 }
        return result
    }

    private var next: BucketKey {
        // Leaving the weekend bucket means clearing both of its days.
        let step = isWeekend ? 2 : 1
        return Self.containing(Calendar.current.date(byAdding: .day, value: step, to: firstDate)!)
    }

    private var previous: BucketKey {
        // Monday steps back onto Sunday, which `containing` snaps to its Saturday.
        Self.containing(Calendar.current.date(byAdding: .day, value: -1, to: firstDate)!)
    }

    // MARK: Labels

    /// Column header: MON…FRI, or WKND. Matches the strings the old `Day` rawValues produced.
    public var headerLabel: String {
        if isWeekend { return "WKND" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE"
        return f.string(from: firstDate).uppercased()
    }

    /// Vertical layout's label: "21", or "26/27" for a weekend.
    public var compactDateLabel: String {
        let cal = Calendar.current
        if isWeekend {
            return "\(cal.component(.day, from: firstDate))/\(cal.component(.day, from: lastDate))"
        }
        return String(format: "%02d", cal.component(.day, from: firstDate))
    }

    /// Horizontal layout's label: "21 SEP", or "26-27 SEP" for a weekend. The month is the
    /// Saturday's, so a weekend spanning a month boundary reads "31-1 OCT" — as it did before.
    public var wideDateLabel: String {
        let cal = Calendar.current
        let monthF = DateFormatter()
        monthF.locale = Locale(identifier: "en_US_POSIX")
        monthF.dateFormat = "MMM"
        if isWeekend {
            let month = monthF.string(from: firstDate).uppercased()
            return "\(cal.component(.day, from: firstDate))-\(cal.component(.day, from: lastDate)) \(month)"
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM"
        return f.string(from: firstDate).uppercased()
    }

    // MARK: Conformances

    public static func < (lhs: BucketKey, rhs: BucketKey) -> Bool { lhs.id < rhs.id }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let key = BucketKey(raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Not an ISO yyyy-MM-dd date: \(raw)"
            ))
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(id)
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test`
Expected: PASS, 58 tests (38 + 20 new), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WeekSheet/Week.swift Tests/WeekSheetTests/WeekTests.swift
git commit -m "Add BucketKey

One column of the sheet, keyed by ISO date. Sunday snaps to its Saturday
so the weekend stays a single bucket, and stepping walks buckets rather
than days: Friday +1 is the weekend, the weekend +1 is Monday."
```

---

## Task 3: `Sheet` model

The store, alongside `Week` rather than replacing it. `Week` still backs the view until Task 7, so both types compile for the next four tasks.

**Files:**
- Modify: `Sources/WeekSheet/Week.swift` (add `WindowMode`, `SheetError`, `Sheet`)
- Test: `Tests/WeekSheetTests/WeekTests.swift`

**Interfaces:**
- Consumes: `Item`, `BucketKey`, `Week.parseDate`, `Week.formatDate`.
- Produces:
  - `enum WindowMode: String, Codable { case week, sliding }`
  - `enum SheetError: Error, Equatable { case dayFull(BucketKey), itemNotFound(UUID) }`
  - `Sheet.maxItemsPerDay: Int` (3), `Sheet.retentionDays: Int` (7)
  - `Sheet.buckets: [BucketKey: [Item]]`, `.ideas: [Item]`, `.weeklyFocus: [BucketKey: String]`
  - `Sheet.empty() -> Sheet`
  - `Sheet.validate()`, `.addItem(to:text:) throws -> Item`, `.toggleDone(_:) throws`, `.deleteItem(_:) throws`, `.moveItem(_:to:at:) throws`, `.moveToIdeas(_:) throws`, `.addIdea(text:) -> Item`, `.removeIdea(_:) throws`
  - `Sheet.focus(for anchor: Date) -> String`, `.setFocus(_:for:)`
  - `Codable`, with `buckets` and `weeklyFocus` as JSON objects

- [ ] **Step 1: Write the failing tests**

Append to `Tests/WeekSheetTests/WeekTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them and verify they fail**

Run: `swift test --filter WeekTests/testSheetAddItem`
Expected: FAIL — compile error, `cannot find 'Sheet' in scope`.

- [ ] **Step 3: Implement `WindowMode`, `SheetError` and `Sheet`**

Append to `Sources/WeekSheet/Week.swift`:

```swift
public enum WindowMode: String, Codable {
    /// Six buckets starting at the Monday of the anchor's week.
    case week
    /// Six buckets starting one bucket before the anchor's, so the anchor sits in slot 1.
    case sliding
}

public enum SheetError: Error, Equatable {
    case dayFull(BucketKey)
    case itemNotFound(UUID)
}

/// Everything the sheet stores. There is no "current week": buckets are addressed by date and
/// the view decides which six to render, so nothing here has to be reset when Monday arrives.
public struct Sheet: Equatable, Codable {
    public static let maxItemsPerDay = 3
    public static let retentionDays = 7

    public var buckets: [BucketKey: [Item]]
    public var ideas: [Item]
    /// Keyed by the Monday of the week it belongs to.
    public var weeklyFocus: [BucketKey: String]

    public init(buckets: [BucketKey: [Item]], ideas: [Item], weeklyFocus: [BucketKey: String]) {
        self.buckets = buckets
        self.ideas = ideas
        self.weeklyFocus = weeklyFocus
    }

    public static func empty() -> Sheet {
        Sheet(buckets: [:], ideas: [], weeklyFocus: [:])
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case buckets, ideas, weeklyFocus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Swift encodes a Dictionary as a JSON object only when its key is String or Int, so
        // both maps are stored string-keyed and re-keyed here. An unparseable key is dropped.
        let rawBuckets = try container.decodeIfPresent([String: [Item]].self, forKey: .buckets) ?? [:]
        var decodedBuckets: [BucketKey: [Item]] = [:]
        for (raw, items) in rawBuckets {
            guard let key = BucketKey(raw) else { continue }
            decodedBuckets[key, default: []].append(contentsOf: items)
        }
        buckets = decodedBuckets

        ideas = try container.decodeIfPresent([Item].self, forKey: .ideas) ?? []

        let rawFocus = try container.decodeIfPresent([String: String].self, forKey: .weeklyFocus) ?? [:]
        var decodedFocus: [BucketKey: String] = [:]
        for (raw, text) in rawFocus {
            guard let key = BucketKey(raw) else { continue }
            decodedFocus[key] = text
        }
        weeklyFocus = decodedFocus
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Dictionary(uniqueKeysWithValues: buckets.map { ($0.key.id, $0.value) }), forKey: .buckets)
        try container.encode(ideas, forKey: .ideas)
        try container.encode(Dictionary(uniqueKeysWithValues: weeklyFocus.map { ($0.key.id, $0.value) }), forKey: .weeklyFocus)
    }

    // MARK: - Validation

    public mutating func validate() {
        // Sorted so overflow lands in `ideas` in a deterministic order.
        for key in buckets.keys.sorted() {
            var items = buckets[key, default: []]
            while items.count > Self.maxItemsPerDay {
                var overflow = items.removeLast()
                overflow.done = false
                ideas.append(overflow)
            }
            if items.isEmpty {
                buckets.removeValue(forKey: key)
            } else {
                buckets[key] = items
            }
        }
        for i in ideas.indices { ideas[i].done = false }
    }

    // MARK: - Bucket items

    @discardableResult
    public mutating func addItem(to key: BucketKey, text: String) throws -> Item {
        guard buckets[key, default: []].count < Self.maxItemsPerDay else {
            throw SheetError.dayFull(key)
        }
        let item = Item(text: text)
        buckets[key, default: []].append(item)
        return item
    }

    public mutating func toggleDone(_ itemID: UUID) throws {
        // `Array(...)` throughout: these loops mutate `buckets`, so they must not iterate a
        // keys view over the dictionary they are changing.
        for key in Array(buckets.keys) {
            if let idx = buckets[key]?.firstIndex(where: { $0.id == itemID }) {
                buckets[key]![idx].done.toggle()
                return
            }
        }
        if ideas.contains(where: { $0.id == itemID }) { return }
        throw SheetError.itemNotFound(itemID)
    }

    public mutating func deleteItem(_ itemID: UUID) throws {
        for key in Array(buckets.keys) {
            if let idx = buckets[key]?.firstIndex(where: { $0.id == itemID }) {
                buckets[key]!.remove(at: idx)
                if buckets[key]!.isEmpty { buckets.removeValue(forKey: key) }
                return
            }
        }
        if let idx = ideas.firstIndex(where: { $0.id == itemID }) {
            ideas.remove(at: idx)
            return
        }
        throw SheetError.itemNotFound(itemID)
    }

    public mutating func moveItem(_ itemID: UUID, to key: BucketKey, at position: Int) throws {
        let target = buckets[key, default: []]
        let isInTarget = target.contains(where: { $0.id == itemID })
        let effectiveCount = isInTarget ? target.count - 1 : target.count
        guard effectiveCount < Self.maxItemsPerDay else {
            throw SheetError.dayFull(key)
        }

        var found: Item?
        for k in Array(buckets.keys) {
            if let idx = buckets[k]?.firstIndex(where: { $0.id == itemID }) {
                found = buckets[k]!.remove(at: idx)
                if buckets[k]!.isEmpty, k != key { buckets.removeValue(forKey: k) }
                break
            }
        }
        if found == nil, let idx = ideas.firstIndex(where: { $0.id == itemID }) {
            found = ideas.remove(at: idx)
        }
        guard let item = found else { throw SheetError.itemNotFound(itemID) }

        let pos = min(position, buckets[key, default: []].count)
        buckets[key, default: []].insert(item, at: pos)
    }

    public mutating func moveToIdeas(_ itemID: UUID) throws {
        for key in Array(buckets.keys) {
            if let idx = buckets[key]?.firstIndex(where: { $0.id == itemID }) {
                var item = buckets[key]!.remove(at: idx)
                if buckets[key]!.isEmpty { buckets.removeValue(forKey: key) }
                item.done = false
                ideas.append(item)
                return
            }
        }
        if ideas.contains(where: { $0.id == itemID }) { return }
        throw SheetError.itemNotFound(itemID)
    }

    // MARK: - Ideas

    @discardableResult
    public mutating func addIdea(text: String) -> Item {
        let item = Item(text: text)
        ideas.append(item)
        return item
    }

    public mutating func removeIdea(_ itemID: UUID) throws {
        guard let idx = ideas.firstIndex(where: { $0.id == itemID }) else {
            throw SheetError.itemNotFound(itemID)
        }
        ideas.remove(at: idx)
    }

    // MARK: - Weekly focus

    public func focus(for anchor: Date) -> String {
        weeklyFocus[BucketKey.monday(of: anchor)] ?? ""
    }

    public mutating func setFocus(_ text: String, for anchor: Date) {
        let key = BucketKey.monday(of: anchor)
        if text.isEmpty {
            weeklyFocus.removeValue(forKey: key)
        } else {
            weeklyFocus[key] = text
        }
    }
}
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test`
Expected: PASS, 80 tests (58 + 22 new), 0 failures. Counts here are package-wide (`WeekTests` plus `FileStoreTests`), not per-file.

- [ ] **Step 5: Commit**

```bash
git add Sources/WeekSheet/Week.swift Tests/WeekSheetTests/WeekTests.swift
git commit -m "Add the Sheet model

Buckets addressed by BucketKey, plus ideas and a per-Monday weekly
focus. Lives alongside Week for now; the view still uses Week until the
window function exists."
```

---

## Task 4: Window, prune, navigation clamp

Pure date maths, the part that makes the reset unnecessary.

**Files:**
- Modify: `Sources/WeekSheet/Week.swift` (extend `Sheet`)
- Test: `Tests/WeekSheetTests/WeekTests.swift`

**Interfaces:**
- Consumes: `BucketKey`, `WindowMode`, `Sheet.retentionDays`.
- Produces:
  - `Sheet.window(anchor: Date, mode: WindowMode) -> [BucketKey]` — always exactly 6, oldest first
  - `Sheet.steppedAnchor(_ anchor: Date, by n: Int, mode: WindowMode) -> Date`
  - `Sheet.canStepBack(from anchor: Date, mode: WindowMode, now: Date = Date()) -> Bool`
  - `Sheet.prune(now: Date = Date())` (mutating)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/WeekSheetTests/WeekTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them and verify they fail**

Run: `swift test --filter WeekTests/testWeekModeWindowIsMondayThroughWeekend`
Expected: FAIL — compile error, no `window` member on `Sheet`.

- [ ] **Step 3: Implement the maths**

Append inside `Sheet` in `Sources/WeekSheet/Week.swift`, after the weekly-focus section:

```swift
    // MARK: - Window

    /// The six buckets to render. Week mode starts at the anchor's Monday; sliding mode starts
    /// one bucket earlier than the anchor's own, which puts the anchor in slot 1 on every day of
    /// the week — Sunday included, because Sunday shares Saturday's bucket.
    public static func window(anchor: Date, mode: WindowMode) -> [BucketKey] {
        let start: BucketKey
        switch mode {
        case .week:
            start = BucketKey.monday(of: anchor)
        case .sliding:
            start = BucketKey.containing(anchor).stepped(by: -1)
        }
        return (0..<6).map { start.stepped(by: $0) }
    }

    /// Moves the anchor by `n` steps — a whole week in week mode, a single bucket in sliding mode.
    public static func steppedAnchor(_ anchor: Date, by n: Int, mode: WindowMode) -> Date {
        switch mode {
        case .week:
            return Calendar.current.date(byAdding: .day, value: 7 * n, to: anchor) ?? anchor
        case .sliding:
            return BucketKey.containing(anchor).stepped(by: n).firstDate
        }
    }

    /// Whether stepping back once would still land inside the retention horizon. Deliberately a
    /// date rule rather than a data rule: an empty past must still be navigable.
    public static func canStepBack(from anchor: Date, mode: WindowMode, now: Date = Date()) -> Bool {
        guard let horizon = Self.horizon(now: now) else { return false }
        let previous = steppedAnchor(anchor, by: -1, mode: mode)
        guard let slotZero = window(anchor: previous, mode: mode).first else { return false }
        return slotZero.lastDate >= horizon
    }

    // MARK: - Prune

    /// Deletes every bucket that ended more than `retentionDays` ago. Judging by the bucket's
    /// last day, not its key, is what gives Sunday items a full seven days.
    public mutating func prune(now: Date = Date()) {
        guard let horizon = Self.horizon(now: now) else { return }
        buckets = buckets.filter { $0.key.lastDate >= horizon }
    }

    private static func horizon(now: Date) -> Date? {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -retentionDays, to: cal.startOfDay(for: now))
    }
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test`
Expected: PASS, 98 tests (80 + 18 new), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WeekSheet/Week.swift Tests/WeekSheetTests/WeekTests.swift
git commit -m "Add the window function, prune and the navigation clamp

Six buckets from an anchor and a mode. Sliding mode steps by bucket, not
by day, so the anchor sits in slot 1 on Sunday too. Prune judges a
bucket by its last day so Sunday items get the full seven."
```

---

## Task 5: Legacy migration

Converting the old `week.json` in its own file, so it can be deleted whole once no installs remain on the old format.

**Files:**
- Create: `Sources/WeekSheet/LegacyMigration.swift`
- Test: `Tests/WeekSheetTests/WeekTests.swift`

**Interfaces:**
- Consumes: `Item`, `BucketKey`, `Sheet`, `Week.parseDate`.
- Produces: `LegacyWeek: Decodable` (internal) with `toSheet() throws -> Sheet`. It throws rather than degrading, because Task 6's caller writes the result back over `week.json`: a file we cannot interpret must abort the migration and leave the original on disk. Task 6's call site already spells `try`, so it needs no change, and Task 7's `(try? store.loadAndPrune()) ?? .empty()` degrades to an empty in-memory sheet without ever reaching `save()`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/WeekSheetTests/WeekTests.swift`:

```swift
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
        let sheet = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON).toSheet()
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-21")!]?.first?.text, "Monday thing")
        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-25")!]?.first?.text, "Friday thing")
    }

    func testLegacyWeekendLandsOnTheSaturdayKey() throws {
        let sheet = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON).toSheet()
        let saturday = BucketKey("2026-09-26")!
        XCTAssertTrue(saturday.isWeekend)
        XCTAssertEqual(sheet.buckets[saturday]?.first?.text, "Weekend thing")
    }

    func testLegacyMigrationPreservesItemIDsAndDoneFlags() throws {
        let sheet = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON).toSheet()
        let monday = sheet.buckets[BucketKey("2026-09-21")!]!.first!
        XCTAssertEqual(monday.id, UUID(uuidString: "550E8400-E29B-41D4-A716-446655440001"))
        XCTAssertTrue(monday.done)
    }

    func testLegacyReminderBecomesTheWeeklyFocus() throws {
        let sheet = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON).toSheet()
        XCTAssertEqual(sheet.focus(for: Week.parseDate("2026-09-21")!), "Rent, Tuesday")
    }

    func testLegacyIdeasCarryOver() throws {
        let sheet = try JSONDecoder().decode(LegacyWeek.self, from: legacyJSON).toSheet()
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
        let sheet = try JSONDecoder().decode(LegacyWeek.self, from: json).toSheet()
        XCTAssertTrue(sheet.buckets.isEmpty)
        XCTAssertTrue(sheet.weeklyFocus.isEmpty, "an empty reminder should not create a focus entry")
    }

    func testLegacyToleratesMissingFields() throws {
        let json = """
        { "weekStart": "2026-09-21" }
        """.data(using: .utf8)!
        let sheet = try JSONDecoder().decode(LegacyWeek.self, from: json).toSheet()
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
        let items = (0..<5).map {
            "{ \"id\": \"550E8400-E29B-41D4-A71644665544000\($0)\", \"text\": \"Item \($0)\", \"done\": true }"
        }.joined(separator: ", ")
        let json = """
        {
            "weekStart": "2026-09-21",
            "days": { "mon": [\(items)] },
            "ideas": [],
            "reminder": ""
        }
        """.data(using: .utf8)!
        let sheet = try JSONDecoder().decode(LegacyWeek.self, from: json).toSheet()

        XCTAssertEqual(sheet.buckets[BucketKey("2026-09-21")!]?.count, 3)
        XCTAssertEqual(sheet.ideas.map(\.text), ["Item 4", "Item 3"])
        XCTAssertTrue(sheet.ideas.allSatisfy { !$0.done }, "validate() clears done on overflowed items")
    }
```

- [ ] **Step 2: Run them and verify they fail**

Run: `swift test --filter WeekTests/testLegacyDaysBecomeDatedBuckets`
Expected: FAIL — compile error, `cannot find 'LegacyWeek' in scope`.

- [ ] **Step 3: Create the migration**

Create `Sources/WeekSheet/LegacyMigration.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test`
Expected: PASS, 108 tests (98 + 7 new, plus the 3 added by this task's fix round for the two throw paths and the over-cap day), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WeekSheet/LegacyMigration.swift Tests/WeekSheetTests/WeekTests.swift
git commit -m "Add the legacy week.json migration

Weekday keys become dates off the stored Monday, wknd lands on the
Saturday key, and reminder becomes that week's focus. Self-contained so
it can be deleted whole later."
```

---

## Task 6: `FileStore` reads and writes `Sheet`

Added alongside the `Week` methods, which Task 7 removes. The temporary names exist only so both models can coexist for one task.

**Files:**
- Modify: `Sources/WeekSheet/FileStore.swift`
- Test: `Tests/WeekSheetTests/FileStoreTests.swift`

**Interfaces:**
- Consumes: `Sheet`, `LegacyWeek`.
- Produces: `FileStore.loadSheet() throws -> Sheet`, `FileStore.save(_ sheet: Sheet) throws`, `FileStore.loadSheetAndPrune(now: Date = Date()) throws -> Sheet`. All three are renamed in Task 7; nothing outside `FileStore` calls them until then.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/WeekSheetTests/FileStoreTests.swift`, before the closing brace:

```swift
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
```

- [ ] **Step 2: Run them and verify they fail**

Run: `swift test --filter FileStoreTests/testSaveAndLoadSheet`
Expected: FAIL — compile error, no `loadSheet` member on `FileStore`.

- [ ] **Step 3: Add the `Sheet` methods**

Append inside `FileStore` in `Sources/WeekSheet/FileStore.swift`, after `save(_ week: Week)`:

```swift
    // MARK: - Sheet

    public func loadSheet() throws -> Sheet {
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

    public func loadSheetAndPrune(now: Date = Date()) throws -> Sheet {
        var sheet = try loadSheet()
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
```

- [ ] **Step 4: Run the tests and verify they pass**

Run: `swift test`
Expected: PASS, 117 tests (108 + 9 new), 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Sources/WeekSheet/FileStore.swift Tests/WeekSheetTests/FileStoreTests.swift
git commit -m "Teach FileStore to read and write Sheet

Migrates a legacy week.json on first load and writes it back in the new
shape, so the conversion runs once. Prunes on load and persists the
result. Temporary loadSheet naming while Week still exists."
```

---

## Task 7: Switch the view to the window — week mode only

The risk task. It rewrites every mutation path in `SheetView` and deletes `Week`, and its acceptance test is that **nothing visible changes**: with `windowMode == .week` and the anchor on today, the sheet must render exactly as it does now.

**Files:**
- Modify: `Sources/WeekSheet/SheetView.swift`
- Rename: `Sources/WeekSheet/Week.swift` → `Sources/WeekSheet/Sheet.swift`, and delete `Week`, `Day`, `WeekError` from it
- Rename: `Tests/WeekSheetTests/WeekTests.swift` → `Tests/WeekSheetTests/SheetTests.swift`
- Modify: `Sources/WeekSheet/FileStore.swift` (drop the `Week` methods, rename the `Sheet` ones)
- Modify: `Tests/WeekSheetTests/FileStoreTests.swift` (drop the `Week` and history tests)
- Modify: `Sources/WeekSheetApp/main.swift` (delete its `_ = try? store.loadAndPrune()` line)
- Modify: `docs/CLAUDE.md`

**Interfaces:**
- Consumes: everything from Tasks 2–6.
- Produces:
  - `SheetViewModel.sheet: Sheet`, `.anchor: Date`, `.windowMode: WindowMode`, `.window: [BucketKey]`
  - `SheetViewModel.addingBucket: BucketKey?`, `.shakingBucket: BucketKey?`, `UndoInfo.bucket: BucketKey?`
  - `SheetViewModel.addItem(to key: BucketKey, text: String)`, `.startAddingToBucket(_:)`, `.moveItemToBucket(_:bucket:position:)`, `.pruneIfNeeded()`
  - `FileStore.load() throws -> Sheet`, `.loadAndPrune(now:) throws -> Sheet`
  - `Sheet.mock`

- [ ] **Step 1: Move the date helpers off `Week` and delete the old model**

`git mv Sources/WeekSheet/Week.swift Sources/WeekSheet/Sheet.swift`, then in the renamed file:

Delete the `Day` enum, the `WeekError` enum, and the entire `Week` struct.

Move `Week`'s four date statics onto `Sheet` — `dateFormatter`, `parseDate`, `formatDate`, and `mondayOfWeek(containing:)` — verbatim except for dropping `resetDate`. `mondayOfWeek` stays because `BucketKey.monday(of:)` and the tests read better with it available:

```swift
    // MARK: - Date helpers

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    public static func parseDate(_ string: String) -> Date? {
        dateFormatter.date(from: string)
    }

    public static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
```

Then replace every `Week.parseDate` / `Week.formatDate` reference inside `BucketKey` with `Sheet.parseDate` / `Sheet.formatDate`.

- [ ] **Step 2: Rename the test file and fix its references**

```bash
git mv Tests/WeekSheetTests/WeekTests.swift Tests/WeekSheetTests/SheetTests.swift
```

Rename the class to `SheetTests`. Delete every test that exercises the old model — all of them above the `// MARK: - BucketKey` section, plus `testDecodesLegacyFileWithNotesKey`, `testMondayOfWeek`, `testMondayOfWeekOnMonday`, `testMondayOfWeekOnSunday`. Replace every remaining `Week.parseDate` with `Sheet.parseDate`.

In `Tests/WeekSheetTests/FileStoreTests.swift`, delete `testLoadReturnsEmptyWhenNoFile`, `testSaveAndLoad`, `testLoadValidatesOverflow`, `testLoadAndResetNotNeeded`, `testLoadAndResetPerformsReset`, `testResetCreatesHistoryFile`, and `testPruneKeepsOnly8`. Replace every `Week.parseDate` with `Sheet.parseDate` and every `loadSheet` / `loadSheetAndPrune` with `load` / `loadAndPrune`.

- [ ] **Step 3: Strip `FileStore` down to the `Sheet` API, and drop the app's eager load**

`Sources/WeekSheetApp/main.swift` calls `store.loadAndResetIfNeeded()` in `applicationDidFinishLaunching`, so the build cannot compile once that method goes. Delete the line rather than translating it: its result was already discarded, the very next statement constructs `WindowController(store:)` whose `SheetViewModel(store:)` performs the same load, and `FileStore` holds no cache. The line existed only to force the Monday reset before the window appeared, which is the thing this plan removes. Translating it to `loadAndPrune` would buy two file reads and two JSON decodes on every launch for no benefit.



In `Sources/WeekSheet/FileStore.swift` delete `load() throws -> Week`, `save(_ week: Week)`, `loadAndResetIfNeeded`, `archiveToHistory`, `pruneHistory`, the `historyURL` property, and the `maxHistoryFiles` constant. Then rename `loadSheet` to `load` and `loadSheetAndPrune` to `loadAndPrune`.

- [ ] **Step 4: Rewrite the view model**

In `Sources/WeekSheet/SheetView.swift`, replace the stored properties and lifecycle of `SheetViewModel`:

```swift
public final class SheetViewModel: ObservableObject {
    @Published var sheet: Sheet
    @Published var isEditMode = false
    @Published var selectedID: UUID?
    @Published var editingID: UUID?
    @Published var addingBucket: BucketKey?
    @Published var addingIdea = false
    @Published var editingReminder = false
    @Published private(set) var undoState: UndoInfo?
    @Published var shakingBucket: BucketKey?
    @Published var isHorizontalMode: Bool
    /// Which six buckets to render. Week mode until Task 8 adds the toggle.
    @Published var windowMode: WindowMode = .week
    /// The date the window is built around. View state — never persisted, so a relaunch
    /// always opens on today.
    @Published var anchor = Date()
    /// Start of the current day. Published so the sheet redraws when the date rolls over.
    @Published private(set) var today = Calendar.current.startOfDay(for: Date())

    let store: FileStore
    private var eventMonitor: Any?
    private var undoTimer: Timer?
    private var tickTimer: Timer?
    private var wakeObserver: Any?

    struct UndoInfo { let item: Item; let bucket: BucketKey?; let position: Int }

    var window: [BucketKey] { Sheet.window(anchor: anchor, mode: windowMode) }

    public init(store: FileStore) {
        self.store = store
        self.isHorizontalMode = UserDefaults.standard.bool(forKey: "horizontalMode")
        self.sheet = (try? store.loadAndPrune()) ?? .empty()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // .common so the tick still fires while a menu or window drag runs a tracking loop.
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
        // Timers are coalesced across sleep; catch up as soon as the machine wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.tick()
        }
    }
```

In `deinit`, change `resetTimer?.invalidate()` to `tickTimer?.invalidate()`.

Replace `save()`, `tick()` and `checkReset()`:

```swift
    private func save() { try? store.save(sheet) }

    /// Rolls the highlighted day forward at midnight and drops buckets past the horizon.
    func tick() {
        let start = Calendar.current.startOfDay(for: Date())
        if start != today { today = start }
        pruneIfNeeded()
    }

    func pruneIfNeeded() {
        let countBefore = sheet.buckets.count
        sheet.prune()
        if sheet.buckets.count != countBefore { save() }
    }
```

Replace every remaining `week` with `sheet`, `Week.maxItemsPerDay` with `Sheet.maxItemsPerDay`, and `WeekError` with `SheetError`. The methods whose signatures change:

```swift
    func addItem(to key: BucketKey, text: String) {
        addingBucket = nil
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        _ = try? sheet.addItem(to: key, text: t)
        save()
    }

    func deleteItem(_ id: UUID) {
        var foundItem: Item?
        var foundBucket: BucketKey?
        var foundPos = 0
        for key in Array(sheet.buckets.keys) {
            if let idx = sheet.buckets[key]?.firstIndex(where: { $0.id == id }) {
                foundItem = sheet.buckets[key]![idx]; foundBucket = key; foundPos = idx; break
            }
        }
        if foundItem == nil, let idx = sheet.ideas.firstIndex(where: { $0.id == id }) {
            foundItem = sheet.ideas[idx]; foundPos = idx
        }
        guard let item = foundItem else { return }
        try? sheet.deleteItem(id)
        if selectedID == id { selectedID = nil }
        save()
        undoTimer?.invalidate()
        undoState = UndoInfo(item: item, bucket: foundBucket, position: foundPos)
        undoTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.undoState = nil }
        }
    }

    func undo() {
        guard let info = undoState else { return }
        undoTimer?.invalidate()
        undoState = nil
        if let bucket = info.bucket {
            let items = sheet.buckets[bucket, default: []]
            if items.count < Sheet.maxItemsPerDay {
                sheet.buckets[bucket, default: []].insert(info.item, at: min(info.position, items.count))
            } else {
                sheet.ideas.append(info.item)
            }
        } else {
            sheet.ideas.insert(info.item, at: min(info.position, sheet.ideas.count))
        }
        save()
    }

    func updateText(_ id: UUID, newText: String) {
        editingID = nil
        let t = newText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        for key in Array(sheet.buckets.keys) {
            if let idx = sheet.buckets[key]?.firstIndex(where: { $0.id == id }) {
                sheet.buckets[key]![idx].text = t; save(); return
            }
        }
        if let idx = sheet.ideas.firstIndex(where: { $0.id == id }) {
            sheet.ideas[idx].text = t; save()
        }
    }

    func select(_ id: UUID?) {
        if editingID != nil { editingID = nil }
        selectedID = id
        if addingBucket != nil { addingBucket = nil }
        if addingIdea { addingIdea = false }
    }

    func startAddingToBucket(_ key: BucketKey) {
        guard sheet.buckets[key, default: []].count < Sheet.maxItemsPerDay else { return }
        addingBucket = key; editingID = nil; selectedID = nil
    }

    func moveItemToBucket(_ id: UUID, bucket: BucketKey, position: Int) {
        do {
            try sheet.moveItem(id, to: bucket, at: position)
            save()
        } catch SheetError.dayFull {
            shakingBucket = bucket
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if self?.shakingBucket == bucket { self?.shakingBucket = nil }
            }
        } catch {}
    }
```

`startEditingReminder` and `cancelEditing` swap `addingDay` for `addingBucket`, and the key handler's guard swaps `self.addingDay != nil` for `self.addingBucket != nil`.

`updateReminder` keeps its name in this task and is renamed in Task 9. For now it writes through the focus API so nothing depends on a `reminder` field that no longer exists:

```swift
    func updateReminder(_ text: String) {
        editingReminder = false
        sheet.setFocus(text.trimmingCharacters(in: .whitespaces), for: anchor)
        save()
    }
```

- [ ] **Step 5: Rewrite the two column builders**

In `Sources/WeekSheet/SheetView.swift`:

```swift
    private var dayColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(viewModel.window, id: \.self) { key in
                dayColumn(key).frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayColumn(_ key: BucketKey) -> some View {
        let items = viewModel.sheet.buckets[key, default: []]
        let isToday = (key == BucketKey.containing(viewModel.today))
        let isShaking = viewModel.shakingBucket == key

        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(isToday ? todayBar : Color.clear).frame(height: 2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(key.headerLabel).font(headerFont)
                Text(key.compactDateLabel).font(smallMono)
            }
            .foregroundColor(isToday ? todayGreen : .black.opacity(0.65))
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(isShaking ? Color.red.opacity(0.12) : Color.clear)
            .cornerRadius(3)

            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading, spacing: 0) {
                    if i < items.count {
                        if viewModel.editingID == items[i].id {
                            InlineTextField(
                                text: items[i].text,
                                onCommit: { viewModel.updateText(items[i].id, newText: $0) },
                                onCancel: { viewModel.editingID = nil }
                            ).frame(height: 28)
                        } else {
                            itemSlot(items[i])
                        }
                    } else if viewModel.addingBucket == key && i == items.count {
                        InlineTextField(
                            text: "",
                            onCommit: { viewModel.addItem(to: key, text: $0) },
                            onCancel: { viewModel.addingBucket = nil }
                        ).frame(height: 28)
                    } else {
                        Rectangle().fill(Color.clear).frame(height: 28)
                            .contentShape(Rectangle())
                            .onTapGesture { viewModel.startAddingToBucket(key) }
                    }
                    Rectangle().fill(ruleColor).frame(height: 1)
                }
                .padding(.horizontal, 8)
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    handleDrop(providers, to: key, at: i)
                }
            }
        }
        .background(isToday ? todayTint : Color.clear)
        .modifier(ShakeEffect(shaking: isShaking))
    }

    private func handleDrop(_ providers: [NSItemProvider], to key: BucketKey, at position: Int) -> Bool {
        guard viewModel.isEditMode else { return false }
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let uuidString = string as? String, let id = UUID(uuidString: uuidString) else { return }
            DispatchQueue.main.async { self.viewModel.moveItemToBucket(id, bucket: key, position: position) }
        }
        return true
    }
```

And the horizontal pair, changed the same way:

```swift
    private var dayRows: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.window, id: \.self) { key in
                dayRow(key)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func dayRow(_ key: BucketKey) -> some View {
        let items = viewModel.sheet.buckets[key, default: []]
        let isToday = (key == BucketKey.containing(viewModel.today))
        let isShaking = viewModel.shakingBucket == key

        HStack(alignment: .top, spacing: 0) {
            Rectangle().fill(isToday ? todayBar : Color.clear).frame(width: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(key.headerLabel).font(headerFont)
                Text(key.wideDateLabel).font(smallMono)
            }
            .foregroundColor(isToday ? todayGreen : .black.opacity(0.65))
            .frame(width: 70, alignment: .leading)
            .padding(.vertical, 8).padding(.leading, 8)
            .background(isShaking ? Color.red.opacity(0.12) : Color.clear)
            .cornerRadius(3)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<3, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 0) {
                        if i < items.count {
                            if viewModel.editingID == items[i].id {
                                InlineTextField(
                                    text: items[i].text,
                                    onCommit: { viewModel.updateText(items[i].id, newText: $0) },
                                    onCancel: { viewModel.editingID = nil }
                                ).frame(height: 28)
                            } else {
                                itemSlot(items[i])
                            }
                        } else if viewModel.addingBucket == key && i == items.count {
                            InlineTextField(
                                text: "",
                                onCommit: { viewModel.addItem(to: key, text: $0) },
                                onCancel: { viewModel.addingBucket = nil }
                            ).frame(height: 28)
                        } else {
                            Rectangle().fill(Color.clear).frame(height: 28)
                                .contentShape(Rectangle())
                                .onTapGesture { viewModel.startAddingToBucket(key) }
                        }
                        Rectangle().fill(ruleColor).frame(height: 1)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        handleDrop(providers, to: key, at: i)
                    }
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
        }
        .background(isToday ? todayTint : Color.clear)
        .modifier(ShakeEffect(shaking: isShaking))
    }
```

- [ ] **Step 6: Replace the date helpers and footers**

Delete `weekStartDate`, `horizontalDateLabel`, `dateLabelFor` and `todayDay` from `SheetView`. Replace `dateRangeText` — in week mode the window spans Monday to Sunday, so this produces the same string it did before:

```swift
    private var dateRangeText: String {
        guard let first = viewModel.window.first, let last = viewModel.window.last else { return "" }
        let s = first.firstDate, e = last.lastDate
        let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "d"
        let mf = DateFormatter(); mf.locale = Locale(identifier: "en_US_POSIX"); mf.dateFormat = "MMM"
        let sm = mf.string(from: s).uppercased(), em = mf.string(from: e).uppercased()
        if sm == em { return "\(df.string(from: s)) \u{2013} \(df.string(from: e)) \(sm)" }
        return "\(df.string(from: s)) \(sm) \u{2013} \(df.string(from: e)) \(em)"
    }
```

Both footers lose the rule that no longer exists — `horizontalFooter`'s right-hand text becomes `"3/DAY \u{00B7} 7-DAY MEMORY"` and `footer`'s becomes `"3 PER DAY \u{00B7} 7-DAY MEMORY"`.

Replace the remaining `viewModel.week.ideas` references in `ideasPanel` with `viewModel.sheet.ideas`, and `reminderPanel`'s three `viewModel.week.reminder` reads with `viewModel.sheet.focus(for: viewModel.anchor)`.

- [ ] **Step 7: Replace the mock**

Replace the `extension Week` block at the end of the file:

```swift
// MARK: - Mock data

extension Sheet {
    static let mock: Sheet = {
        var sheet = Sheet(
            buckets: [
                BucketKey("2026-09-21")!: [Item(text: "Ship spec v0.1", done: true), Item(text: "Call with Ana")],
                BucketKey("2026-09-22")!: [Item(text: "Rewrite onboarding copy")],
                BucketKey("2026-09-23")!: [Item(text: "Dentist, 14:30"), Item(text: "Invoice August"), Item(text: "Read Nagel essay")],
                BucketKey("2026-09-24")!: [Item(text: "Widget window layer"), Item(text: "Groceries")],
                BucketKey("2026-09-25")!: [Item(text: "Week review")],
                BucketKey("2026-09-26")!: [Item(text: "Bike to the reservoir")]
            ],
            ideas: [
                Item(text: "Look into SMAppService"),
                Item(text: "Cancel the storage unit"),
                Item(text: "Birthday present for M."),
                Item(text: "Fix the bathroom light")
            ],
            weeklyFocus: [:]
        )
        sheet.setFocus("Rent, Tuesday", for: Sheet.parseDate("2026-09-21")!)
        return sheet
    }()
}
```

- [ ] **Step 8: Run the tests**

Run: `swift test`
Expected: PASS. The count drops sharply — 117 from Task 6 minus however many old-model tests Step 2 deletes. Do not treat any particular number as the target: what matters is 0 failures, every surviving test still meaningful, and no remaining reference to `Week`. Report the number you land on.

- [ ] **Step 9: Confirm `Week` is gone**

Run: `grep -rn '\bWeek\b' Sources Tests --include=*.swift | grep -v WeekSheet`
Expected: no output. Matches on the module name `WeekSheet`, the target directory, and `WeekSheetTests` are fine and are what the filter removes.

- [ ] **Step 10: Build and run the app, and compare against the design PNGs**

Run: `swift build && swift run WeekSheetApp`

This is the acceptance test for the whole task. Check against `docs/Week Sheet-selection.png` and `docs/Week Sheet horizontal mode.png`:
- six columns headed MON TUE WED THU FRI WKND, in that order
- the date under each header matches the current week; the weekend shows two days
- today's column has the green bar, green text and tint
- the header's date range reads the same as before
- ⌃⌥. still switches layout; both layouts look unchanged apart from the footer text
- add, edit, delete, undo, drag between columns, and drag to New Ideas all still work
- if a `week.json` from before this branch exists, its items are on the right dates and its old reminder now shows in the Reminder panel

Stop and fix before committing if any of these differ.

- [ ] **Step 11: Update the code-shape note**

In `docs/CLAUDE.md`, first fix the `What this is` paragraph, which still lists a feature that no longer exists. Replace "one 'New Ideas' inbox, one Reminder line, one Notes box" with "one 'New Ideas' inbox, one Weekly Focus line". Task 1 deleted the Notes box and Task 10 renames Reminder, so leaving this sentence would have the project's own instruction file describing two things that are gone.

Then replace the `Code shape` bullet that names `Week.swift` so it names the current files:

```markdown
- `Sheet.swift` (model), `LegacyMigration.swift`, `FileStore.swift`, `WindowController.swift`, `StatusItem.swift`, `SheetView.swift` + small subviews. Resist creating more files than the feature needs.
- Timestamps and dates in ISO 8601, local time. A `BucketKey` is a weekday's own date, or the Saturday of a weekend bucket.
```

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "Render the sheet from a window over dated buckets

Both layouts now iterate Sheet.window(anchor:mode:) instead of
Day.allCases, and Week, Day, WeekError and the reset are gone. Week mode
on today's anchor renders exactly what the fixed week did, so this is a
restructure with no visible change."
```

---

## Task 8: Date navigation

Stepping the anchor, clamped backwards.

**Files:**
- Modify: `Sources/WeekSheet/SheetView.swift` (view model actions)
- Modify: `Sources/WeekSheet/WindowController.swift` (three hotkeys)
- Test: `Tests/WeekSheetTests/SheetTests.swift`

**Interfaces:**
- Consumes: `Sheet.steppedAnchor`, `Sheet.canStepBack`.
- Produces: `SheetViewModel.stepBack()`, `.stepForward()`, `.goToToday()`, `.canStepBack: Bool`; `WindowController.stepBack()`, `.stepForward()`, `.goToToday()` as `@objc`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/WeekSheetTests/SheetTests.swift`:

```swift
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
```

- [ ] **Step 2: Run them and verify they fail**

Run: `swift test --filter SheetTests/testForwardThenBackReturnsToTheSameWindow`
Expected: FAIL. If these pass immediately, the Task 4 maths already covers them — record that and move to Step 3 rather than inventing a failure.

- [ ] **Step 3: Add the view-model actions**

Append to `SheetViewModel` in `Sources/WeekSheet/SheetView.swift`, after `toggleLayoutMode`:

```swift
    // MARK: Navigation

    var canStepBack: Bool { Sheet.canStepBack(from: anchor, mode: windowMode) }

    func stepBack() {
        guard canStepBack else { return }
        anchor = Sheet.steppedAnchor(anchor, by: -1, mode: windowMode)
        cancelEditing()
    }

    func stepForward() {
        anchor = Sheet.steppedAnchor(anchor, by: 1, mode: windowMode)
        cancelEditing()
    }

    func goToToday() {
        anchor = Date()
        cancelEditing()
    }
```

- [ ] **Step 4: Register the hotkeys**

In `Sources/WeekSheet/WindowController.swift`, add three refs beside `layoutHotKeyRef`:

```swift
    private var backHotKeyRef: EventHotKeyRef?
    private var forwardHotKeyRef: EventHotKeyRef?
    private var todayHotKeyRef: EventHotKeyRef?
```

Unregister them in `deinit` alongside the existing three:

```swift
        if let ref = backHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = forwardHotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = todayHotKeyRef { UnregisterEventHotKey(ref) }
```

Add the actions after `toggleLayoutMode()`:

```swift
    @objc public func stepBack() { viewModel.stepBack() }
    @objc public func stepForward() { viewModel.stepForward() }
    @objc public func goToToday() { viewModel.goToToday() }
```

Register them at the end of `registerHotKey()`, following the existing calls:

```swift
        RegisterEventHotKey(
            UInt32(kVK_LeftArrow), modifiers,
            EventHotKeyID(signature: sig, id: 4),
            GetApplicationEventTarget(), 0,
            &backHotKeyRef
        )

        RegisterEventHotKey(
            UInt32(kVK_RightArrow), modifiers,
            EventHotKeyID(signature: sig, id: 5),
            GetApplicationEventTarget(), 0,
            &forwardHotKeyRef
        )

        RegisterEventHotKey(
            UInt32(kVK_ANSI_0), modifiers,
            EventHotKeyID(signature: sig, id: 6),
            GetApplicationEventTarget(), 0,
            &todayHotKeyRef
        )
```

And route them in `hotKeyHandler`'s switch:

```swift
        case 4: controller.stepBack()
        case 5: controller.stepForward()
        case 6: controller.goToToday()
```

- [ ] **Step 5: Run the tests**

Run: `swift test`
Expected: PASS, Task 7's total plus the 2 tests added here, 0 failures.

- [ ] **Step 6: Verify in the app**

Run: `swift build && swift run WeekSheetApp`

- ⌃⌥→ moves the window one week forward; the header's date range follows and today's green highlight disappears once the window no longer contains today
- ⌃⌥← moves back
- ⌃⌥← twice from today does nothing the second time — the clamp. Confirm the window does not move rather than showing empty columns
- ⌃⌥0 snaps back to this week
- items added to a future week persist: navigate forward, add an item, ⌃⌥0, navigate forward again, and it is still there

- [ ] **Step 7: Commit**

```bash
git add Sources/WeekSheet/SheetView.swift Sources/WeekSheet/WindowController.swift Tests/WeekSheetTests/SheetTests.swift
git commit -m "Add date navigation

Control-option arrows step the anchor, control-option-0 snaps to today.
Back stops at the retention horizon so navigation never walks into
columns whose items have been deleted."
```

---

## Task 9: Sliding mode

The configuration. Small, because Task 7 made the window a function of the mode.

**Files:**
- Modify: `Sources/WeekSheet/SheetView.swift`
- Modify: `Sources/WeekSheet/WindowController.swift`
- Modify: `Sources/WeekSheet/StatusItem.swift`

**Interfaces:**
- Consumes: `WindowMode`, `SheetViewModel.windowMode`.
- Produces: `SheetViewModel.toggleWindowMode()`; `WindowController.toggleWindowMode()` as `@objc`; `UserDefaults` key `"slidingMode"`.

- [ ] **Step 1: Persist the mode**

In `Sources/WeekSheet/SheetView.swift`, replace the hardcoded `windowMode` declaration:

```swift
    /// Which six buckets to render. Persisted the same way isHorizontalMode is.
    @Published var windowMode: WindowMode
```

Initialise it in `init(store:)`, next to `isHorizontalMode`:

```swift
        self.windowMode = UserDefaults.standard.bool(forKey: "slidingMode") ? .sliding : .week
```

And add the toggle beside `toggleLayoutMode`:

```swift
    func toggleWindowMode() {
        windowMode = (windowMode == .sliding) ? .week : .sliding
        UserDefaults.standard.set(windowMode == .sliding, forKey: "slidingMode")
        // The anchor means different things in the two modes; today is the only safe common
        // ground, and it is where the user expects to land after switching.
        goToToday()
    }
```

- [ ] **Step 2: Add the hotkey**

In `Sources/WeekSheet/WindowController.swift`, add the ref:

```swift
    private var windowModeHotKeyRef: EventHotKeyRef?
```

Unregister it in `deinit`:

```swift
        if let ref = windowModeHotKeyRef { UnregisterEventHotKey(ref) }
```

Add the action:

```swift
    @objc public func toggleWindowMode() { viewModel.toggleWindowMode() }
```

Register it at the end of `registerHotKey()`:

```swift
        RegisterEventHotKey(
            UInt32(kVK_ANSI_Slash), modifiers,
            EventHotKeyID(signature: sig, id: 7),
            GetApplicationEventTarget(), 0,
            &windowModeHotKeyRef
        )
```

Route it in `hotKeyHandler`:

```swift
        case 7: controller.toggleWindowMode()
```

- [ ] **Step 3: Add the menu item**

In `Sources/WeekSheet/StatusItem.swift`, insert after the `layoutItem` block and before `menu.addItem(.separator())`:

```swift
        let windowModeItem = NSMenuItem(
            title: UserDefaults.standard.bool(forKey: "slidingMode") ? "Fixed Week" : "Sliding Days",
            action: #selector(toggleWindowModeFromMenu),
            keyEquivalent: ""
        )
        windowModeItem.target = self
        windowModeItem.keyEquivalentModifierMask = [.control, .option]
        windowModeItem.keyEquivalent = "/"
        menu.addItem(windowModeItem)
```

And add the handler beside `toggleLayoutFromMenu`:

```swift
    @objc private func toggleWindowModeFromMenu() {
        windowController.toggleWindowMode()
        statusItem.menu = buildMenu()
    }
```

- [ ] **Step 4: Run the tests**

Run: `swift test`
Expected: PASS, the same count as Task 8, 0 failures. No new tests here — the window maths for both modes is already covered by Task 4, and this task only wires a flag to it.

- [ ] **Step 5: Verify in the app**

Run: `swift build && swift run WeekSheetApp`

- ⌃⌥/ switches to sliding: today moves to the **second** column, with yesterday's bucket first
- the headers rotate — on a Wednesday they read TUE WED THU FRI WKND MON
- quit and relaunch: the mode is remembered
- the menu bar item's title flips between "Sliding Days" and "Fixed Week"
- in sliding mode, ⌃⌥← and ⌃⌥→ move one bucket at a time, not one week
- on a Saturday or Sunday, today's bucket is still the second column and reads WKND

- [ ] **Step 6: Commit**

```bash
git add Sources/WeekSheet/SheetView.swift Sources/WeekSheet/WindowController.swift Sources/WeekSheet/StatusItem.swift
git commit -m "Add sliding window mode

Control-option-slash puts today in the second column instead of
anchoring on Monday, persisted in UserDefaults like the layout mode.
The window function already handled both; this only picks one."
```

---

## Task 10: Reminder becomes Weekly Focus

The rename, last because it is cosmetic once the per-Monday storage exists — which it has since Task 3.

**Files:**
- Modify: `Sources/WeekSheet/SheetView.swift`
- Test: `Tests/WeekSheetTests/SheetTests.swift`

**Interfaces:**
- Consumes: `Sheet.focus(for:)`, `Sheet.setFocus(_:for:)`.
- Produces: `SheetViewModel.editingFocus: Bool`, `.startEditingFocus()`, `.updateFocus(_:)`; `SheetView.focusPanel`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/WeekSheetTests/SheetTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it**

Run: `swift test --filter SheetTests/testFocusFollowsTheAnchorsWeekNotTheWindowSpan`
Expected: PASS — `focus(for:)` already keys off the anchor. This test pins that choice against a future refactor that might key off the window instead. If it fails, `focus(for:)` is wrong; fix it before renaming anything.

- [ ] **Step 3: Rename in the view model**

In `Sources/WeekSheet/SheetView.swift`, rename `editingReminder` to `editingFocus` throughout `SheetViewModel` — the declaration, `startEditingReminder`, `cancelEditing`, and the key handler's guard and its comment:

```swift
    @Published var editingFocus = false
```

```swift
    func startEditingFocus() { editingFocus = true; editingID = nil; selectedID = nil; addingBucket = nil; addingIdea = false }

    func updateFocus(_ text: String) {
        editingFocus = false
        sheet.setFocus(text.trimmingCharacters(in: .whitespaces), for: anchor)
        save()
    }
```

```swift
            // The focus line gets typed keys (incl. Space); Esc still leaves edit mode.
            if self.editingFocus && event.keyCode != 53 { return event }
```

- [ ] **Step 4: Rename the panel**

Replace `reminderPanel` with `focusPanel`, changing only the header string and the bindings:

```swift
    private var focusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WEEKLY FOCUS").font(headerFont).foregroundColor(.black.opacity(0.6))
            ZStack(alignment: .leading) {
                Text(viewModel.sheet.focus(for: viewModel.anchor).isEmpty ? " " : viewModel.sheet.focus(for: viewModel.anchor))
                    .font(bodyFont).foregroundColor(bodyText)
                    .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
                    .opacity(viewModel.editingFocus ? 0 : 1)
                if viewModel.editingFocus && viewModel.isEditMode {
                    InlineTextField(
                        text: viewModel.sheet.focus(for: viewModel.anchor),
                        onCommit: { viewModel.updateFocus($0) },
                        onCancel: { viewModel.editingFocus = false }
                    ).frame(maxWidth: .infinity)
                }
            }
            .padding(6).background(Color.white.opacity(0.5)).cornerRadius(3)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(greenPanel).cornerRadius(4)
        .contentShape(Rectangle())
        .onTapGesture {
            if viewModel.isEditMode && !viewModel.editingFocus { viewModel.startEditingFocus() }
        }
    }
```

Update the two references: `bottom` and `sidebar` each use `focusPanel` in place of `reminderPanel`.

- [ ] **Step 5: Run the tests**

Run: `swift test`
Expected: PASS, Task 9's count plus the 1 test added here, 0 failures.

- [ ] **Step 6: Verify in the app**

Run: `swift build && swift run WeekSheetApp`

- the green panel reads WEEKLY FOCUS
- type a focus, then ⌃⌥→ to next week: the panel is empty. ⌃⌥← back: the text is there again
- in sliding mode, anchoring on a Monday still shows *this* week's focus even though the first column belongs to last week
- quit and relaunch: the focus for the current week is still there

- [ ] **Step 7: Commit**

```bash
git add Sources/WeekSheet/SheetView.swift Tests/WeekSheetTests/SheetTests.swift
git commit -m "Rename Reminder to Weekly Focus

One line per calendar week, keyed by its Monday, so navigating shows
that week's focus. Never pruned."
```

---

## Out of scope

Confirmed with the spec; do not add these even if a task seems to invite them.

- No settings screen. The two modes are `UserDefaults` flags reached by hotkey and menu.
- No history browser or archive view. Backward navigation inside the 7-day window is the only way to see the past.
- Do not delete an existing `history/` directory from disk. Task 7 removes the code that writes it; the files already there are the user's data and stay where they are.
- No sweep of unfinished items into New Ideas when a bucket ages out — pruning deletes them. This is the deliberate behaviour change; do not soften it.
- No expiry on New Ideas or on the weekly focus.
- No per-item timestamps beyond bucket membership.
- No new footer hints for the navigation hotkeys. The footers are at their width already; `README.md` documents keyboard shortcuts and is the place for them if the user asks.
- No fourth slot. No dependencies.
