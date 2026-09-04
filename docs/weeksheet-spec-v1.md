# Week Sheet — Spec v1.0 (build-ready)

A macOS desktop widget that replaces the printed weekly planner sheet. It sits on the desktop behind all windows and looks like paper. Hard-capped day slots are the product; everything else is deliberately dumb.

Design reference: `Week_Sheet-selection.png` (pixel target). Source inspiration: Alpino weekly planner.

## Layout (locked to the design)

```
┌─────────────────────────────────────────────────────────────┐
│ WEEK SHEET   31 AUG – 6 SEP                        EDIT MODE │
├──────┬──────┬──────┬──────┬──────┬──────────────────────────┤
│ MON  │ TUE  │ WED  │ THU  │ FRI  │ WKND 5/6                 │  ← 6 columns
│ 3 slots each, ruled lines, today column tinted + top bar    │
├─────────────────────────────┬───────────────────────────────┤
│ NEW IDEAS  4            [+] │ REMINDER !   (one line)       │
│ chips: italic, grey, ×      ├───────────────────────────────┤
│                             │ NOTES        (ruled, ~5 lines)│
├─────────────────────────────┴───────────────────────────────┤
│ CLICK A LINE · DRAG TO MOVE · SPACE = DONE · ⌫ = DELETE ·   │
│ ESC = LEAVE                        3 PER DAY · RESETS MON 04:00 │
└─────────────────────────────────────────────────────────────┘
```

- **6 columns**: Mon–Fri, then one merged **WKND** column (Sat+Sun). 3 slots each. That's 18 slots a week, full stop.
- **New Ideas** = the inbox. Unlimited. Items render as dashed-border chips with an `×`. Header shows the count.
- **Reminder** = one free-text line. **Notes** = free text, ~5 ruled lines. No logic on either; they're paper.
- Footer left: interaction hints. Footer right: the two rules, always visible.
- Today's column: faint green tint + 2px top bar. Only colour on the sheet.

## The rules

1. A day holds **3 items**. Dropping on a full day is refused (short shake). No swap, no overflow, no "just this once."
2. New Ideas items are undecided. Two actions: drag into a day, or `×`.
3. **Reset: Monday 04:00.** Done items cleared. Unfinished day items → New Ideas. Reminder and Notes cleared. Previous week written to history.
4. Nothing carries forward automatically. Ever.

## Window behaviour

| State | Level | Input |
|---|---|---|
| Background (default) | `CGWindowLevelForKey(.desktopWindow)` | `ignoresMouseEvents = true`. Rendered at 85% opacity. |
| Edit mode | `.floating`, window is key | Full input. "EDIT MODE" label shown top-right. |

- Enter edit mode: menu bar item (NSStatusItem) or `⌃⌥Space` (`RegisterEventHotKey`).
- Leave: `Esc`, or click outside the sheet.
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`. `LSUIElement = true` (no Dock icon).
- Launch at login: `SMAppService.mainApp.register()`. Toggle in the status menu.
- Window frame persisted. Default: centred, 60% screen width, aspect from the design.

## Interactions (edit mode only)

| Action | How |
|---|---|
| Add to a day | Click an empty ruled line → inline text field. `Return` commits; empty cancels. |
| Add a new idea | `+` in New Ideas header, or start typing when the panel is focused. |
| Move | Drag any item to any slot or to New Ideas. Full day → refused with shake. |
| Done | `Space` on a selected day item. Strikethrough, 50% opacity. Ideas can't be "done". |
| Delete | `⌫` on selected item, or `×` on a chip. 2-second undo toast. |
| Edit text | Double-click. |
| Reminder / Notes | Click, type. Plain text. |

Keyboard focus moves with `Tab`/arrows between columns and slots; not required for v1.0 but leave room.

## Data

Single file: `~/Library/Application Support/WeekSheet/week.json`

```json
{
  "weekStart": "2026-08-31",
  "days": {
    "mon": [{ "id": "uuid", "text": "Call with Ana", "done": false }],
    "tue": [], "wed": [], "thu": [], "fri": [], "wknd": []
  },
  "ideas": [{ "id": "uuid", "text": "Cancel the storage unit" }],
  "reminder": "Rent, Tuesday",
  "notes": "Cap of 3 is the product.\nDon't add a fourth slot."
}
```

- Atomic write on every change. Validate `days[*].count <= 3` on load; if violated (hand-edited file), overflow moves to `ideas`.
- On launch and on a 60s timer: if `now >= nextMonday04:00(weekStart)`, run the reset before rendering.
- History: on reset, copy the old file to `history/week-YYYY-MM-DD.json`. Keep 8. Not surfaced in UI.

## Visual spec

- Paper: `#F4F1EA`-ish off-white, 1px hairline rules under each slot, a faint left margin line.
- Type: monospace for headers/labels/footer (SF Mono), humanist sans for item text (SF Pro / system).
- New Ideas panel: warm tint. Reminder: green tint. Notes: cool tint. All ≤ 6% saturation — they read as paper stock, not UI.
- Only animation: refused-drop shake (≤ 200ms). Honour Reduce Motion (no shake, just a flash of the column header).
- Dark mode: **not in v1.0.** Paper is paper.

## Tech

- Swift 5.9+, macOS 13+. SwiftUI for the sheet body, AppKit for the window and status item.
- Zero dependencies. One `Codable` model, one `FileStore`, one `WindowController`.
- Target: < 900 lines. If it passes 1200, something has been over-built.

## Out of scope (v1.0)

Windows, iOS, sync, notifications, recurring items, Calendar/Reminders import, themes, dark mode, multiple sheets, history UI, any AI.

## Build order (hand to the coder agent one task at a time)

1. **Model + FileStore** — `Week` model, load/save, reset rule, validation. Unit-tested. No UI.
2. **Window shell** — desktop-level NSWindow, status item, edit-mode toggle, hotkey, launch-at-login. Renders a coloured rectangle.
3. **Static sheet** — SwiftUI layout matching the PNG with mock data. No interaction. Pixel review before continuing.
4. **Editing** — inline add, done, delete, undo toast. No drag yet.
5. **Drag & drop** — between slots and New Ideas, cap enforcement, shake.
6. **Reminder / Notes / polish** — free-text fields, today tint, footer, opacity in background mode.

Each step ships as a working app. Do not start step N+1 until step N is reviewed.
