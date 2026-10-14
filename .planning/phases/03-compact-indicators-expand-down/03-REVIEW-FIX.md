---
phase: 03-compact-indicators-expand-down
fixed_at: 2026-10-14T00:00:00Z
review_path: .planning/phases/03-compact-indicators-expand-down/03-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
---

# Phase 3: Code Review Fix Report

**Fixed at:** 2026-10-14
**Source review:** .planning/phases/03-compact-indicators-expand-down/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 7 (CR-01, CR-02, WR-01 to WR-05). IN-03 was also fixed because it was trivial.
- Fixed: 7 (+ IN-03)
- Skipped: 0

Verification: the swiftc harness (`xcrun swiftc OrchestratorModels.swift OrchestratorPure.swift Tests/Phase3Tests.swift Tests/main.swift`) prints OK, and the xcodebuild Debug ad-hoc build (/tmp/notch-dd-p3) succeeded after every fix. The app was not launched, /term was not loaded, and no requests were made to 127.0.0.1:4777.

## Fixed Issues

### CR-01: `reset()` shrinks the window but leaves `vm.notchSize` expanded
**Files modified:** `boringNotch/Orchestrator/OrchestratorExpand.swift`
**Commit:** 3b5d596
**Applied fix:** `reset()` now sets `vm.notchSize = openNotchSize` for each expanded vm whose `notchState == .open`. The closed size is left alone.

### CR-02: `resignKey()` called directly
**Files modified:** `boringNotch/Orchestrator/OrchestratorExpand.swift`, `boringNotch/Orchestrator/OrchestratorTerminal.swift`
**Commit:** 2d481c8
**Status:** fixed: requires human verification (UAT)
**Applied fix:**
- Both `resignKey()` calls are gone.
- `expand()` records `NSWorkspace.shared.frontmostApplication`, unless that is our own app.
- New `OrchestratorExpand.releaseKey(_:refocus:)` clears the key gate. If the window is key, it also calls `makeFirstResponder(nil)` and `previousApp?.activate()`.
- `releaseKey` is called from `finish()` (collapse and reset) and from `dismantleNSView`.
- Outside clicks seen by the global monitor (another app) pass `refocus: false`, so the clicked app keeps focus. Local-monitor clicks (panel margin) refocus.
- `NSApp.activate` is never called.
- UAT: after collapse, typing goes to the previously frontmost app. After an outside click into app C, C stays frontmost.

### WR-01: Expand button centred
**Files modified:** `boringNotch/Orchestrator/OrchestratorExpand.swift`
**Commit:** 465e14b
**Applied fix:** `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)` is added after the `WindowAccessor` background. Only the button gets a hit shape. The empty frame area and the accessor NSView (still button-sized) don't cover the chat when collapsed.

### WR-02: Shared `shrinkTask`
**Files modified:** `boringNotch/Orchestrator/OrchestratorExpand.swift`
**Commit:** 93e2f19
**Applied fix:** `shrinkTasks: [Key: Task]`. `expand`, `collapse` and `reset` cancel only that key's task.

### WR-03: Keyed by screenUUID; global keep-open
**Files modified:** `boringNotch/Orchestrator/OrchestratorExpand.swift`, `boringNotch/models/BoringViewModel.swift`
**Commit:** 6375915
**Status:** fixed: requires human verification (multi-display)
**Applied fix:**
- State is keyed by `ObjectIdentifier(vm)`.
- `openSize(for:)` now takes the view model. The `BoringViewModel.open()` hook is still one line: `openSize(for: self)`.
- `collapseIfOutside` collapses every outside notch first, then closes them in a second loop.
- Not changed: sub-point 2. `SharingStateManager` keep-open is app-wide, so while screen A is expanded, screen B can't hover-close. Fixing that needs a change in upstream `SharingStateManager`, so it is accepted as a known limitation.

### WR-04: Collapse control hidden when offline
**Files modified:** `boringNotch/Orchestrator/OrchestratorExpand.swift`
**Commit:** 3f3c135
**Applied fix:** The button now shows when `isExp || (manager.hasLoaded && !manager.offline)`.

### WR-05: Terminal state polled only 5 s; matched any "Reconnect"
**Files modified:** `boringNotch/Orchestrator/OrchestratorPure.swift`, `boringNotch/Orchestrator/OrchestratorTerminal.swift`, `boringNotch/Orchestrator/Tests/Phase3Tests.swift`
**Commit:** 099d104
**Status:** fixed: requires human verification (ttyd DOM)
**Applied fix:**
- The poll runs while the terminal is shown: first check after 1 s, then every 2 s. It is cancelled in `dismantleNSView` and stops on inUse/unavailable.
- The JS no longer reads `body.innerText`. It returns the text of leaf `div`s outside `.xterm-rows`/`.xterm-accessibility`, or null before `.xterm` exists. ttyd's overlay div has no class.
- The pure function is now `terminalState(overlayText:previous:)`:
  - It matches whole lines only: `Connection Closed`, or a line ending in `to Reconnect`.
  - A close before the terminal ever connected maps to `.inUse`. A close after it connected maps to `.unavailable` (dropped session).
- Test asserts are updated: "foo Reconnect bar" and "the Connection Closed early" are now `.connected`.
- UAT: a second viewer still shows "terminal in use", and killing serve mid-session shows "terminal unavailable".

### IN-03 (Info, trivial): Teardown comment and delegate
**Files modified:** `boringNotch/Orchestrator/OrchestratorTerminal.swift`
**Commit:** 4932d61
**Applied fix:** `navigationDelegate = nil` in `dismantleNSView`, and the comment now says that `about:blank` is best effort and the slot is really freed on dealloc.

## Not addressed (Info, out of scope)
- IN-01: the key gate is still global. Merge note: the OR'd `canBecomeKey` stays the same, and `releaseKey` clears `terminalWantsKey` for all panels.
- IN-02: the runs strip is hidden while expanded.
- IN-04: the dot may overlap the visualizer. This needs a visual check.

## Merge with Phase 2 (changes to existing/upstream lines)
- `boringNotch/models/BoringViewModel.swift` `open()`: the hook line changed from `openSize(for: screenUUID)` to `notchSize = OrchestratorExpand.shared.openSize(for: self)`. This is the only change to an upstream file.
- `OrchestratorView.swift`, `OrchestratorManager.swift`, `ContentView.swift` and `BoringNotchSkyLightWindow.swift`: unchanged by these fixes.

---

_Fixed: 2026-10-14_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
