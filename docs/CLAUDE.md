# CLAUDE.md — Week Sheet

Read `weeksheet-spec-v1.md` before anything. The design PNG is the pixel target.

## What this is
A macOS desktop widget. One week, 6 columns × 3 slots, one "New Ideas" inbox, one Reminder line, one Notes box. Swift + SwiftUI + AppKit. Zero dependencies. That is the whole product.

## Scope discipline
- Work only on the task you were given. One build-order step per task.
- Modify only the files named in the task. If a file isn't listed, don't touch it.
- Noticed something else? Write it to `PENDING.md`. Do not fix it now.
- Before any task touching 3+ files, list every file you will create/modify/delete and wait for approval.
- Never add a dependency. Never add a fourth slot. Never add a feature from the "out of scope" list, even as a stub.

## UI discipline
- The PNG wins over your taste. Match it.
- Views marked `// UI STATUS: LOCKED` do not change structure, spacing, or colours when data is wired in.
- No loading states, empty-state illustrations, onboarding, or settings screens unless the task says so.

## Code shape
- `Week.swift` (model), `FileStore.swift`, `WindowController.swift`, `StatusItem.swift`, `SheetView.swift` + small subviews. Resist creating more files than the feature needs.
- Timestamps and dates in ISO 8601, local time. `weekStart` is always a Monday.
- Every rule in the spec's "The rules" section is enforced in the model, not the view.

## When unsure
Ask before acting. Prefer doing less. A smaller diff that asks a question beats a bigger diff that guesses.
