# Week Sheet

A macOS desktop widget that replaces the printed weekly planner sheet. It sits on your desktop behind all windows and looks like paper.

![Week Sheet screenshot](docs/Week%20Sheet-selection.png)

## What it does

- **6 columns** (Mon–Fri + merged Weekend), **3 slots per day** — 18 slots a week, hard cap
- **New Ideas** inbox for undecided items, shown as dashed-border chips
- **Reminder** (one line) and **Notes** (free text) panels
- **Weekly reset** every Monday at 04:00 — done items cleared, unfinished items move to New Ideas, previous week archived to history
- **Two layouts** — vertical (default) and horizontal; switch anytime
- Lives on the desktop at 85% opacity; press **⌃⌥Space** (or use the menu bar icon) to enter edit mode

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| **⌃⌥Space** | Toggle edit mode |
| **⌃⌥M** | Hide / show sheet |
| **⌃⌥.** | Switch between vertical and horizontal layout |

## Interactions (edit mode)

| Action | How |
|---|---|
| Add item | Click an empty line, type, press Return |
| Add idea | Click `+` in the New Ideas header |
| Move | Drag any item between day slots and New Ideas |
| Done | Select an item, press Space (strikethrough) |
| Delete | Select an item, press ⌫ (2-second undo toast) |
| Edit text | Double-click an item |
| Leave edit mode | Press Esc or click outside the sheet |

All shortcuts also available from the menu bar icon.

## Requirements

- macOS 13+
- Swift 5.9+
- Zero external dependencies

## Build & Run

```bash
swift build
swift run WeekSheetApp
```

## Run Tests

```bash
swift test
```

## Project Structure

```
Sources/
  WeekSheet/
    Week.swift             # Data model (Item, Day, Week) + reset logic
    FileStore.swift         # JSON persistence + weekly history archival
    SheetView.swift         # SwiftUI view + view model
    WindowController.swift  # Desktop-level window, hotkey, edit mode
    StatusItem.swift        # Menu bar icon + launch-at-login toggle
  WeekSheetApp/
    main.swift              # App entry point (NSApplication, no Dock icon)
Tests/
  WeekSheetTests/
    WeekTests.swift         # Model logic tests
    FileStoreTests.swift    # Persistence + reset tests
docs/
    weeksheet-spec-v1.md    # Full specification
```

## Data Storage

Week data is saved as JSON to `~/Library/Application Support/WeekSheet/week.json`. On weekly reset, previous weeks are archived to a `history/` subdirectory (last 8 kept).

## License

All rights reserved.
