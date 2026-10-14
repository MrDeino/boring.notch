---
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
fixed_at: 2026-10-14T00:00:00Z
review_path: .planning/phases/07-2a-runs-board-expand-levels-and-closed-notch-wings/07-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 7: Code Review Fix Report

**Fixed at:** 2026-10-14
**Source review:** .planning/phases/07-2a-runs-board-expand-levels-and-closed-notch-wings/07-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (CR-01, WR-01..WR-06; Info findings out of scope)
- Fixed: 7
- Skipped: 0

Verification: the swiftc harness prints OK, and the Debug `xcodebuild` (derived data `/tmp/notch-dd-p7`) reports BUILD SUCCEEDED. The app was not launched, so the UI fixes (WR-03, WR-06) and the keyboard fixes (CR-01, WR-04) still need checking by hand.

## Fixed Issues

### CR-01: ⌘↓ / ⌘↑ shortcuts never match
**Files modified:** `boringNotch/Orchestrator/OrchestratorRunsPure.swift`, `boringNotch/Orchestrator/OrchestratorExpand.swift`, `boringNotch/Orchestrator/Tests/Phase7Tests.swift`
**Commit:** c07157d
**Applied fix:** Added a pure `isCommandOnly(_ raw: UInt)` helper. It masks the raw flags to command, shift, control and option only, so numericPad, function and caps lock are ignored. The key monitor now calls `isCommandOnly(e.modifierFlags.rawValue)`. Harness cases cover ⌘ combined with numericPad and function, ⌘ with caps lock, and the rejected ⌘⇧, ⌘⌥ and ⌃⌘.
**Status:** fixed: requires human verification (press ⌘↓, ⌘↑, ⌘T and ⌘\ in the running app)

### WR-01: Rail auto-opens on reconnect and at launch
**Files modified:** `boringNotch/Orchestrator/OrchestratorRunsPure.swift`, `boringNotch/Orchestrator/OrchestratorExpanded.swift`, `boringNotch/Orchestrator/OrchestratorWings.swift`, `boringNotch/Orchestrator/Tests/Phase7Tests.swift`
**Commit:** 93a347d
**Applied fix:** Solved without changing the manager. A new pure `RunsBaseline` struct returns no baseline in three cases: before `hasLoaded`, while offline, and for the stale empty `runs` list seen right after offline. That list appears because the manager clears `offline` before it assigns the new runs. The rail and the wings model both use `combineLatest($runs, $offline, $hasLoaded)` with `RunsBaseline`. Harness cases cover launch, an offline blip, a reconnect with a run that is already waiting, and a genuinely empty list while online.
**Status:** fixed: requires human verification

### WR-02: Rail misses waiting runs before its state is first created
**Files modified:** `boringNotch/Orchestrator/OrchestratorWings.swift`
**Commit:** 699cc1d
**Applied fix:** `OrchestratorWingsModel.init` now runs `_ = OrchestratorRailState.shared`. The wings model is created eagerly by ContentView, so the rail now tracks its baseline from launch.

### WR-03: Wing spinner and glow stop after their first appearance
**Files modified:** `boringNotch/Orchestrator/OrchestratorWings.swift`
**Commit:** 01d2c32
**Applied fix:** Moved the ✻ spinner and the needs-you glow dot into private `WingSpinner` and `WingGlowDot` subviews, each with its own `@State`. The state is recreated every time the kind re-inserts them, so `repeatForever` starts again. I did not use the review's "reset to 0, then animate" variant, because inside one update SwiftUI merges 360→0→360 into no change.

### WR-04: Key monitor swallows shortcuts that do nothing
**Files modified:** `boringNotch/Orchestrator/OrchestratorExpand.swift`
**Commit:** b857fb2
**Applied fix:** `handle` now computes the target level and returns `false` (passing the event through) when it equals the current level. ⌘\ keeps its old behaviour. The `setLevel`, `back` and `transcriptTapped` signatures are unchanged.
**Status:** fixed: requires human verification

### WR-05: A run field with the wrong type takes the whole tab offline
**Files modified:** `boringNotch/Orchestrator/OrchestratorModels.swift`, `boringNotch/Orchestrator/Tests/Phase7Tests.swift`
**Commit:** 30b08f0
**Applied fix:** Gave `OrchestratorRun` explicit `CodingKeys` and a lenient `init(from:)`. Each field is decoded with `try?`, so a field of the wrong type becomes nil. `denials` is decoded as `[String?]` with the nulls removed, and an `activity` that fails to decode becomes nil. A harness case decodes a `StateResponse` containing a null denial, bad agents and a numeric `startedAt`. Element-by-element decoding of `StateResponse.runs` was not done, because it is outside `OrchestratorRun`. A run can now only fail to decode if it is not a JSON object.

### WR-06: Strip hover card drawn about 166pt left of the strip
**Files modified:** `boringNotch/Orchestrator/OrchestratorExpanded.swift`
**Commit:** 1a40edc
**Applied fix:** Changed the offset to `-(22 + 10)`, which puts the card 10pt left of its 22pt dot.
**Status:** fixed: requires visual check

## Shared-file edits (per MERGE-MAP)

- `boringNotch/Orchestrator/OrchestratorModels.swift`: changed inside `struct OrchestratorRun` only. Added a private `CodingKeys` enum and a custom `init(from:)`. Stored properties are unchanged, and `RunActivity`, `RunAgent` and `StateResponse` were not touched.
- No changes to `OrchestratorManager.swift`, `ContentView.swift`, `OrchestratorStatusCapsule.swift`, `project.pbxproj` or `Tests/main.swift`.

All other edits are in files Phase 7 owns: OrchestratorRunsPure, OrchestratorExpand, OrchestratorExpanded, OrchestratorWings and Tests/Phase7Tests.

---

_Fixed: 2026-10-14_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
