---
phase: 09-phase-b-approvals-closed-notch-approval-drop-down-global-sho
plan: 03
subsystem: orchestrator-notch
tags: [sizing, panel, expand]
requires: [09-02]
provides: [one window sizer driven by vm.notchSize]
key-files:
  modified: [OrchestratorExpand.swift, OrchestratorPure.swift, Tests/Phase9Tests.swift, ContentView.swift]
requirements-completed: [APR-04]
completed: 2026-10-14
---

# Phase 9 Plan 03: One panel sizer Summary

The notch panel now follows `vm.notchSize` through one function, `OrchestratorExpand.syncWindow(vm:window:now:)`, which is the only caller of `setFrame`.

P9B3: cb98d8aa4f7f4ecbac6b4bdd2742e37ab819baaa. Commit: 3121105.

## Adaptation to s3q
The plan predated s3q (which already had `expandedSize`, `pinnedFrame(newSize:)`, `setFit`, widening window). Instead of the plan's `panelHeight`/`fit(vm:window:)`/`extra` removal (no `extra` exists any more), I consolidated:
- Pure: `panelSize(notch:base:openHeight:)` = width `max(base.width, notch.width)`, height via the existing `windowHeight`. Asserted for closed, stock open, 150 drop-down, 440, and 850x540 (stock cases stay 640x210).
- `syncWindow`: grow now (either axis, top and centre pinned via `pinnedFrame`), shrink after 650ms re-reading the current target; `now: true` for reset.
- `animate(vm,to:)` = spring on `vm.notchSize`, then `syncWindow`, so the window is tall before the first frame. Used by `grow`, `collapse`, `setFit`.
- ContentView: one line, `.onChange(of: vm.notchSize) { syncWindow(vm:) }`, covering open/close/other changes (idempotent with the immediate call).
- Removed: three `setFrame` sites (grow, setFit grow+shrink Task, collapse shrink Task, reset x2), the duplicate shrink Tasks. The fit/setFit/openSize/level APIs are unchanged. The plan's name `fit(vm:window:)` was not used (collides with the existing `fit(_ source:vm:)`).

## Left as is
The grow-frame left-edge clipping from s3q-02: this consolidation does not change how the column width follows the animated shape, so it is not fixed and no leftmost-margin check was added; it needs judging in the running app.

## Verification
swiftc harness OK; xcodebuild BUILD SUCCEEDED (/tmp/notch-dd); snapshot normal, --hittest (draft survives, OK), --transition (top edge pinned; content present in every live frame OK), --closed all exit 0; rail x=660 y=53 unchanged. Viewed 30-notes-expanded, 39-expanded-composer-multiline, closed-21-approval-bare: fine. The harness builds its own windows, so `syncWindow` itself (real resize/shrink timing) is only covered by UAT.

## Deviations
None of rules 1-4 beyond the adaptation above. RED/GREEN split skipped for the pure function (single commit; assertions added together with it).

## Human UAT
Plan `<human_uat>` items 1-6 (continuous spring, top edge not sliding, window shrinks ~0.65s after collapse, quick re-expand, music unchanged, drop-down not clipped, multi-display): not run here.

## Known stubs
None.

## Self-Check: PASSED
