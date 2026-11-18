---
quick_id: 261118-jlt
type: quick
status: complete
---

# Quick 261118-jlt: notch opens and closes predictably

Fix audit findings A1-A4 (`.planning/audits/2026-11-clive-audit.md`).

## Tasks
1. **A1 lock/sleep/display change.** `AppDelegate.closeNotches()` (expand reset, end typing, close every view model) runs at the top of `cleanupWindows` and on `willSleep`; `didWake` runs `adjustWindowPosition` + `setupDragDetectors`; a new panel calls `OrchestratorExpand.syncWindow(window:now:)` right after `contentView` is set.
2. **A2 back from expanded.** `setLevel(.open)` sets a 1.2 s per-vm hold (`holdsOpen`) before collapsing; the `.sharingDidFinish` and hover-exit closes skip while held; hover-enter, `close()` and `reset()` clear it. The outside-click path calls `collapse` directly, so it still closes.
3. **A3 per-screen open state.** `close()` on a closed view model only refreshes sizes. A weak set of open view models drives `OrchestratorManager.notchOpen` ("any open"); tab / lastUsedView / sneak peek change only when the last open notch closes.
4. **A4 chat-box drop.** Composer `onDrop` sets `vm.dropEvent`; its targeted flag is mirrored into a new `vm.composerDropTargeting`, OR-ed into `anyDropZoneTargeting`.

## Verify
- swiftc harness prints OK (new `QuickJltTests.swift`).
- Snapshot default, `--transition`, `--idle` OK.
- Debug and Release (`ENABLE_HARDENED_RUNTIME=NO`) build into `./build`.
