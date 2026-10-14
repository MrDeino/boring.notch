---
phase: 03-compact-indicators-expand-down
plan: 02
subsystem: ui
tags: [swiftui, notch, wkwebview, expand]
requires: [03-01]
provides: [OrchestratorExpand, OrchestratorTerminalView, OrchestratorKeyGate]
key-files:
  created:
    - boringNotch/Orchestrator/OrchestratorExpand.swift
    - boringNotch/Orchestrator/OrchestratorTerminal.swift
  modified:
    - boringNotch/Orchestrator/OrchestratorPure.swift
    - boringNotch/Orchestrator/Tests/Phase3Tests.swift
    - boringNotch/Orchestrator/OrchestratorView.swift
    - boringNotch/Orchestrator/OrchestratorManager.swift
    - boringNotch/ContentView.swift
    - boringNotch/models/BoringViewModel.swift
    - boringNotch/components/Notch/BoringNotchSkyLightWindow.swift
    - boringNotch.xcodeproj/project.pbxproj
requirements-completed: [EXP-01, EXP-02, EXP-03]
duration: 15min
completed: 2026-10-14
---

# Phase 3 Plan 2: Expand-down Summary

Expand control grows the same notch window downward (top pinned) to a 28-line chat view with a live `/term/` WKWebView on top (created on expand, about:blank on collapse), and any outside click collapses and closes the notch.

## Commits
- 6c8239b: all three tasks in one commit (they share OrchestratorExpand.swift, OrchestratorPure.swift and pbxproj, so splitting would have left non-building commits).

## Notes / decisions
- While expanded, one balanced `SharingStateManager` begin/endInteraction pair makes `vm.close()` return early: hover exit and down-swipe do NOT close or collapse (intended). Collapse via the control, an outside click (collapse then `vm.close()`), tab switch (onDisappear) or notch close (notchOpen didSet).
- Size writes on collapse/reset only when `vm.notchState == .open`.
- Pure helpers needed `import CoreGraphics` for the swiftc harness.
- Harness prints OK; xcodebuild BUILD SUCCEEDED (/tmp/notch-dd-p3). App not launched; no requests to 127.0.0.1:4777; no `wantsKeyboard` added.

## Merge with Phase 2
- **BoringNotchSkyLightWindow.swift** (1 line): `canBecomeKey` is now `OrchestratorKeyGate.terminalWantsKey`. Phase 2 changes the same line to `OrchestratorManager.shared.wantsKeyboard`. Resolve to `override var canBecomeKey: Bool { OrchestratorManager.shared.wantsKeyboard || OrchestratorKeyGate.terminalWantsKey }`. `OrchestratorKeyGate` is a separate static (OrchestratorTerminal.swift); OrchestratorManager has no wantsKeyboard here.
- **OrchestratorView.swift** (+1): `.overlay { OrchestratorExpandOverlay() }` after the final `.padding(.horizontal, 8)` at end of body.
- **OrchestratorManager.swift**: `notchOpen` didSet expanded to multi-line, +`if !notchOpen { OrchestratorExpand.shared.reset() }`. Keep both statements on merge.
- **BoringViewModel.open()** (1 line): `notchSize = OrchestratorExpand.shared.openSize(for: screenUUID)`.
- **ContentView.swift** (1 changed line): maxHeight clamp is `windowSize.height + max(0, vm.notchSize.height - openNotchSize.height)`.
- **SharingStateManager**: counter shared with Phase 2's message box; both use balanced begin/end, they coexist.
- **Tests/main.swift**: untouched; Phase3Tests.swift gained asserts only.
- **pbxproj**: new IDs 0A1C...0303/0304 (file refs), 0313/0314 (build files).

## UAT (human)
- A1: typing in the terminal works with the non-activating panel (key without NSApp.activate); frontmost app keeps its menu bar.
- A2: second viewer shows "terminal in use" via innerText ("Reconnect"/"Connection Closed") detection; Retry works.
- Hover exit / down-swipe while expanded do not close the notch; expand grows down with top pinned; outside click (other app, desktop, panel margin) collapses and closes; closing notch/tab switch collapses; panel stops being key after collapse; music and closed-notch music activity unchanged; multi-display expands only the clicked screen.

## Deviations
None functionally; single combined commit (see above).

## Self-Check: PASSED
