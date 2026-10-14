---
phase: 04-2a-foundation-tokens-view-split-status-capsule-header-status
plan: 03
subsystem: ui
tags: [swiftui, header, status-menu]
requires: [04-01, 04-02]
provides: [OrchestratorHeaderSegment, OrchestratorHeaderTrailing, OrchestratorStatusCapsule, OrchestratorUsageRing, OrchestratorStatusMenu]
affects: [05, 07]
key-files:
  modified: [OrchestratorStatusCapsule.swift, OrchestratorView.swift, BoringHeader.swift, TabButton.swift]
requirements-completed: [FND-01, FND-02, FND-03, FND-04, FND-05]
duration: 10min
completed: 2026-10-14
---

# Phase 4 Plan 03: Status capsule, header segment, status menu Summary

Chat | Runs N segment, six-variant status capsule with 5h usage ring, and an in-notch status menu replace the old usage badge, Start/End and Runs buttons (deleted).

## Commits
- 5cff198 feat(04-03): both tasks in one commit

## Verification
BUILD SUCCEEDED (/tmp/notch-dd); harness OK. Upstream diff: BoringHeader.swift (+2/-3), TabButton.swift (+1/-1) only; ContentView and music files untouched. No POST, no app launched, nothing pushed.

## API contract additions (binding for Phase 7)
- OrchestratorStatusCapsule.swift: `struct OrchestratorHeaderSegment: View` (parameterless), `struct OrchestratorHeaderTrailing: View` (parameterless; body = `OrchestratorStatusCapsule()`; Phase 7 adds the collapse button here), `struct OrchestratorStatusCapsule: View`, `struct OrchestratorUsageRing: View { let fraction: Double; let high: Bool }`, `struct OrchestratorStatusMenu: View { let openTerminal: () -> Void }`.
- OrchestratorView.swift shell: `@State private var anchor = NSView()` + `.background(WindowAnchor(view: anchor))`; menu Open terminal calls `OrchestratorExpand.shared.setLevel(.terminal, vm: vm, window: anchor.window)`.

## Decisions
- TabButton padding 15 -> 5 (exception to D-06 per MERGE-MAP amendment).
- Capsule tap from another tab jumps to Orchestrator and opens the menu.
- Stopped wins over Needs you (D-04 order, via manager.capsuleStatus).
- Capsule is inert while connecting/offline.
- Menu row padding kept at vertical 3 / horizontal 8, usage bar gap 3px; actual fit within the 190px notch is unverified on screen (see UAT 4).

## Deviations from Plan
Tasks 1 and 2 committed together. Build path /tmp/notch-dd used instead of /tmp/notch-dd-p4 per instructions.

## Known Stubs
None.

## Self-Check: PASSED
