# Week Sheet

A macOS desktop widget that replaces the printed weekly planner sheet. It sits on your desktop behind all windows and looks like paper.

![Week Sheet screenshot](docs/Week%20Sheet-selection.png)

## What it does

- **6 columns** (Mon–Fri + merged Weekend), **3 slots per day** — 18 slots a week, hard cap
- **New Ideas** inbox for undecided items, shown as dashed-border chips
- **Weekly Focus** — one line, kept per calendar week (keyed by that week's Monday); navigate to another week and you see that week's own line
- **No weekly reset** — day items just age out once more than 7 days have passed; a weekend's items are graded by Sunday rather than Saturday, so they get the full week too
- **Follow Today** — a setting in the menu bar. Off (the default), the window starts on Monday; on, today sits in the second column. It decides only where the window lands when it snaps back to today, since navigation moves one column at a time either way
- **Two layouts** — vertical (default) and horizontal; switch anytime
- Lives on the desktop at 85% opacity; press **⌃⌥Space** (or use the menu bar icon) to enter edit mode

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| **⌃⌥Space** | Toggle edit mode |
| **⌃⌥M** | Hide / show sheet |
| **⌃⌥.** | Switch between vertical and horizontal layout |
| **⌃⌥←** | Step the window back one column |
| **⌃⌥→** | Step the window forward |
| **⌃⌥0** | Jump back to today, re-framed by the **Follow Today** setting |

**Follow Today** has no shortcut — it is a setting you pick once, so it lives only in the menu bar icon.

The header also carries **◀ ▶** arrows beside the date range, which do the same thing as the two step shortcuts. Like every other control, they respond only in edit mode.

Both step one column at a time whatever the setting, so a Monday-start window stops being Monday-aligned once you navigate; it re-aligns on the next jump back to today. Stepping back is capped by the retention window (see **Data Storage**): it stops once the next step would show a first column older than that horizon. The **◀** arrow dims when that happens, so the limit is visible rather than a control that quietly does nothing.

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

## Install as App (recommended)

Build a standalone `.app` bundle that runs without a terminal:

```bash
./build-app.sh
```

This installs `WeekSheet.app` to `~/Applications`. Open it from Finder or:

```bash
open ~/Applications/WeekSheet.app
```

Use the **Launch at Login** toggle in the menu bar icon to start automatically at boot.

## Build & Run (development)

For development, you can run directly from source:

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
    Sheet.swift              # Data model (Item, BucketKey, Sheet) + window/prune logic
    LegacyMigration.swift    # One-time decode of the pre-sliding week.json shape
    FileStore.swift          # JSON persistence: load/save + quarantining unreadable files
    SheetView.swift          # SwiftUI view + view model
    WindowController.swift   # Desktop-level window, hotkeys, edit mode
    StatusItem.swift         # Menu bar icon + launch-at-login toggle
  WeekSheetApp/
    main.swift                # App entry point (NSApplication, no Dock icon)
Tests/
  WeekSheetTests/
    SheetTests.swift          # Model logic tests
    FileStoreTests.swift      # Persistence, migration + quarantine tests
docs/
    weeksheet-spec-v1.md      # Full specification
```

## Data Storage

Week data is saved as JSON to `~/Library/Application Support/WeekSheet/week.json`. There's no reset and no history archive — day items are simply deleted once they're more than 7 days past their bucket's last day (a weekend bucket is judged by Sunday, so both its days get the full seven). If `week.json` can't be read — corrupted, or in a shape Week Sheet doesn't recognize — it's renamed to `week-unreadable-<date>.json` in the same folder rather than being overwritten, and the app starts fresh with an empty sheet; your original file is left in place to recover by hand.

## License

All rights reserved.
