# Sliding Week — Design

Date: 2026-09-21
Status: approved design, not yet planned

## Summary

Three requested changes turn out to be one change:

1. Remove the Notes box entirely.
2. Let the week slide day to day, so today's column is always the second one — configurable, with the fixed week as the default.
3. Remove the Monday 04:00 hard reset. Instead, delete day items more than a week old.

(2) and (3) are the same work. The Monday reset exists because the app stores exactly one
mutable `Week` and has to recycle it. Replace that with a date-keyed store and there is no
current-week state to reset: Monday rolling over, sliding mode, and manual date navigation
all become the same window function evaluated at different anchors.

## Current state

`Week` (Sources/WeekSheet/Week.swift) holds `weekStart: String`, `days: [Day: [Item]]`,
`ideas`, `reminder`, `notes`. `Day` is a fixed enum — `mon, tue, wed, thu, fri, wknd` — where
`wknd` merges Saturday and Sunday into one three-slot bucket.

`Week.needsReset` / `Week.reset` clear done items, sweep unfinished day items into `ideas`,
clear `reminder` and `notes`, and re-stamp `weekStart`. `FileStore.loadAndResetIfNeeded`
archives the outgoing week to `history/week-YYYY-MM-DD.json` (8 kept, never surfaced in UI).

`SheetView` iterates `Day.allCases` in exactly two places — `dayColumn` (L411) and `dayRow`
(L654) — and already derives every date label from `weekStart + offset`
(`horizontalDateLabel` L735, `dateLabelFor` L786, `todayDay` L802). Those helpers are the seam
this design cuts along.

## Decisions

Settled during brainstorming, recorded so the plan does not re-litigate them:

| Question | Decision |
|---|---|
| What "delete notes older than a week" means | Day items. An item is deleted 7 days after the last day of the bucket holding it. |
| Merged weekend | Kept. Six buckets spanning seven calendar days. |
| Window shape | Six buckets. Sliding puts today's bucket at slot 1 (second column). |
| Default mode | Fixed week (Monday-anchored). Sliding is opt-in. |
| Navigation | Manual stepping back and forward through dates, on both modes. |
| Slide-off behaviour | Items linger in storage past the window edge, then are deleted. No sweep into New Ideas. |
| Backward range | Clamped. The back action stops at the oldest surviving bucket — no empty columns. |
| Forward range | Unbounded. Items can be added to arbitrary future dates. |
| Reminder | Renamed "Weekly Focus". One per calendar week, keyed by Monday. Never pruned. |
| New Ideas | Unchanged. No expiry. |

## Model

`Week` becomes `Sheet`. Same file, same zero dependencies.

```swift
public struct BucketKey: Hashable, Comparable, Codable {
    /// ISO "yyyy-MM-dd", local time. A weekday bucket is keyed by its own date;
    /// the weekend bucket is keyed by its Saturday.
    public let id: String

    public static func containing(_ date: Date) -> BucketKey   // Sunday snaps back to Saturday
    public static func monday(of date: Date) -> BucketKey      // for weeklyFocus keys
    public var isWeekend: Bool
    public var firstDate: Date                                  // Saturday, for a weekend bucket
    public var lastDate: Date                                   // Sunday, for a weekend bucket
    public func stepped(by buckets: Int) -> BucketKey           // Mon -1 → previous Sat
}

public struct Sheet: Equatable, Codable {
    public static let maxItemsPerDay = 3
    public static let retentionDays = 7

    public var buckets: [BucketKey: [Item]]
    public var ideas: [Item]
    public var weeklyFocus: [BucketKey: String]   // keyed by the Monday of the week
}
```

`BucketKey` is a value type rather than a bare `String` so the Sunday-snaps-to-Saturday rule
lives in exactly one place and a view cannot construct a Sunday key. It stays in `Week.swift` —
no new file.

Swift only encodes a `Dictionary` as a JSON object when its key is `String` or `Int`; any other
key type encodes as an alternating array. So `Sheet` needs hand-written `init(from:)` and
`encode(to:)` that map `[BucketKey: [Item]]` to and from `[String: [Item]]` — the same trick
`Week` already uses for `[Day: [Item]]` (Week.swift L64-67, L78). Decoding also drops any key
that is not a valid bucket key, which is what makes an already-migrated file safe to reload.

`Item` is unchanged. Item dates are implied by the bucket that holds them; items carry no date
field of their own, so moving an item between days is still a dictionary move.

`Day` is deleted. Column identity becomes the slot index 0–5 plus the bucket key at that slot.

### Window function

```swift
public enum WindowMode: String, Codable { case week, sliding }

/// Exactly six bucket keys, oldest first.
public static func window(anchor: Date, mode: WindowMode) -> [BucketKey]
```

- `.week` — slot 0 is the Monday of the anchor's week. Slots are Mon, Tue, Wed, Thu, Fri, wknd.
  Byte-identical output to today's layout.
- `.sliding` — slot 0 is the bucket *before* the anchor's bucket, so the anchor's own bucket
  always lands at slot 1.

Because stepping is by bucket rather than by calendar day, today sits at slot 1 on every day of
the week, Sunday included:

```
anchor Mon → wknd | MON  | Tue | Wed | Thu | Fri
anchor Fri → Thu  | FRI  | wknd| Mon | Tue | Wed
anchor Sun → Fri  | WKND | Mon | Tue | Wed | Thu
```

On Sunday, slot 0 is Friday rather than Saturday, because Saturday shares today's bucket. That
is inherent to merging the weekend and is accepted.

### Prune

```swift
public mutating func prune(now: Date = Date())
```

Drops any bucket whose `lastDate` is more than `retentionDays` before the start of today. Using
`lastDate` rather than the key means the weekend bucket survives until its *Sunday* crosses the
horizon, so Sunday items get a full seven days and Saturday items get eight. The alternative —
testing the key — would silently cut Sunday items to six days.

Pruning deletes done and unfinished items alike. `ideas` and `weeklyFocus` are never pruned.

Runs on load and on the existing 60s tick, so the horizon advances while the app is open.

### Navigation clamp

```swift
public func canStepBack(from anchor: Date, mode: WindowMode, now: Date = Date()) -> Bool
```

False when the previous anchor's window would put slot 0 before the oldest surviving bucket.
The back action is disabled rather than showing empty columns. Forward is always allowed. A
"today" action resets the anchor to `Date()`.

### Weekly Focus

Read and written at `weeklyFocus[BucketKey.monday(of: anchor)]`. In sliding mode the six-bucket
window can straddle two calendar weeks; the focus shown follows the **anchor's** week, not the
window's span. Sliding mode's anchor is today unless the user has navigated, so this reads as
"this week's focus" in normal use.

### Validation

`validate()` is unchanged in intent, applied per bucket: any bucket over `maxItemsPerDay`
overflows its tail into `ideas` with `done` cleared, and every idea has `done == false`.

## Persistence

`week.json` keeps its name and location. New shape:

```json
{
  "buckets": { "2026-09-21": [ ... ], "2026-09-26": [ ... ] },
  "ideas": [ ... ],
  "weeklyFocus": { "2026-09-21": "Ship the sliding window" }
}
```

`FileStore.load()` gains a one-time migration. If the payload has a `buckets` key it decodes as
`Sheet`. Otherwise it decodes as the legacy shape and converts:

- each `days[day]` → bucket keyed by `weekStart + offset` (`wknd` → `weekStart + 5`, a Saturday)
- `ideas` carried across unchanged
- `reminder` → `weeklyFocus[weekStart]`
- `notes` dropped (already removed from the model by then; unknown JSON keys are ignored)

The converted `Sheet` is saved immediately, so migration runs once. Existing `history/*.json`
files are left on disk untouched — the app stops writing them but does not delete user data.

Removed from `FileStore`: `loadAndResetIfNeeded`, `archiveToHistory`, `pruneHistory`,
`maxHistoryFiles`, `historyURL`. Added: `loadAndPrune(now:)`.

## View

Both layouts iterate the window instead of the enum:

```swift
ForEach(Array(viewModel.window.enumerated()), id: \.element) { slot, key in
    dayColumn(key, isToday: key == BucketKey.containing(viewModel.today))
}
```

Column headers become computed from the key's weekday (`MON`…`FRI`, or `SAT/SUN` for a weekend
bucket) rather than literal text. In week mode they render in the same order as today, so the
design PNG still matches exactly. In sliding mode they rotate. Structure, spacing, and colours
are untouched, which keeps the `// UI STATUS: LOCKED` contract.

`horizontalDateLabel`, `dateLabelFor`, and `todayDay` collapse into label helpers on
`BucketKey`, which is where their date arithmetic already effectively lived.

Two footer strings hardcode the old rule — `"3/DAY · RESETS MON 04:00"` (L730) and
`"3 PER DAY · RESETS MON 04:00"` (L767). Both become `… · 7-DAY MEMORY`.

Drag-and-drop, `deleteItem`, `updateText`, `startAddingToDay`, and the undo record all take a
`BucketKey` where they took a `Day`. Mechanical, but it is most of the `SheetView` diff.

### Mode and navigation controls

Sliding mode is a `UserDefaults` flag under `"slidingMode"`, toggled by a hotkey and mirrored in
the `StatusItem` menu — exactly the pattern `horizontalMode` already uses
(`SheetView.swift:56`, `StatusItem.swift:48`). No settings screen.

Navigation is two hotkeys plus a "today" hotkey. The anchor is view state on `SheetViewModel`,
not persisted: relaunching always opens on today.

## Testing

`WeekTests` becomes `SheetTests`:

- `window` output for all seven weekdays × both modes, asserting today lands at slot 1 in
  sliding mode every time, Sunday included
- `BucketKey.containing` snapping Sunday to Saturday; `stepped(by:)` crossing Monday backwards
  into the previous weekend
- `prune` horizon, including the weekend-bucket edge case (Sunday keeps 7 days, Saturday 8) and
  the boundary exactly at the horizon
- `canStepBack` false at the oldest surviving bucket, true one step inside it
- `weeklyFocus` keyed by Monday, and read from the anchor's week when a sliding window straddles
  two weeks
- `validate` overflow into `ideas`
- migration from a legacy JSON fixture, asserting `wknd` lands on the Saturday key and
  `reminder` lands in `weeklyFocus`

`FileStoreTests`: round trip, legacy migration writes back once, no `history/` writes.

Deleted: `testResetClearsDoneKeepsUnfinished`, plus the four `notes` assertions across
`WeekTests` and `FileStoreTests`.

## Build order

Each step lands with green tests before the next begins.

1. **Remove Notes.** `Week.notes`, its `CodingKeys` case, encode/decode lines, `notesPanel`
   (SheetView L618), both layout call sites (L503, L721), and the `notes` assertions in tests.
   Independent of everything else, and it shrinks `SheetView` before the restructure.
2. **Model.** `BucketKey`, `Sheet`, `window`, `prune`, `canStepBack`, `validate`. Delete
   `Day`, `needsReset`, `reset`, `resetDate`. Unit-tested, no UI.
3. **FileStore.** Load/save `Sheet`, legacy migration, `loadAndPrune`. Drop the history and
   reset methods.
4. **View: week mode only.** Window function driving both layouts, computed headers, footer
   strings, `BucketKey` threaded through mutations and undo. Visual output must be
   indistinguishable from today — this step proves the restructure is invisible.
5. **Navigation.** Anchor stepping, back clamped, forward open, "today" snap, hotkeys.
6. **Sliding mode.** `UserDefaults` flag, hotkey, menu item. Small once step 4 exists.
7. **Weekly Focus.** Rename `reminder` in model and UI, key per Monday, render from the anchor's
   week.

## Out of scope

- No settings screen, onboarding, or empty states.
- No fourth slot; `maxItemsPerDay` stays 3.
- No dependencies.
- No surfaced history or archive browser. Backward navigation within the 7-day window is the
  only way to look at the past.
- No per-item timestamps beyond bucket membership.

## Risks

- **Step 4 is the dangerous one.** It touches locked views and rewrites every mutation path in
  `SheetView`. Visual parity against `docs/Week Sheet-selection.png` and
  `docs/Week Sheet horizontal mode.png` is the acceptance test.
- **Migration runs once against real user data.** It should be covered by a fixture test before
  it ships, and it must be a no-op on an already-migrated file.
- **Pruning deletes unfinished work.** The old reset rescued unfinished items into New Ideas;
  this design deliberately does not. Seven days of silence and an item is gone. That was the
  decision, but it is the change most likely to feel wrong in use.
