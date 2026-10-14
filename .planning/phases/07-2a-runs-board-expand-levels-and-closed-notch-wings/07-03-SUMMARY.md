---
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
plan: 03
subsystem: ui
tags: [swift, swiftui, wings, closed-notch]
requires: [07-01]
provides: [closed-notch wings, music needs-you dot, 26px expanded radius]
key-files:
  modified: [boringNotch/Orchestrator/OrchestratorWings.swift, boringNotch/Orchestrator/OrchestratorCompact.swift, boringNotch/ContentView.swift]
requirements-completed: [RUN-05, RUN-02]
completed: 2026-10-14
---

# Phase 7 Plan 03: Wings Summary

Closed-notch wings (working, needs-you, finished 4s) from a Combine-driven model that publishes only `kind`, music wins by chain order, plus the 26px expanded bottom radius.

## What was built
- `OrchestratorWingsModel` (sinks on manager.$runs+$offline for finished detection with baseline reset when offline; objectWillChange for recompute), `OrchestratorWingsView`, `OrchestratorMusicNeedsDot`.
- Corner dot in OrchestratorClosedIndicators hides when a needs-you wing or the music live activity shows. Hairline untouched. OrchestratorManager untouched.

## Deviations from Plan
None. Build uses /tmp/notch-dd-p7 per the run constraints (not p7-03).

## Verification
BUILD SUCCEEDED; harness OK; ContentView numstat 5 added / 1 deleted; only deleted line is the opened.bottom operand; manager and music code untouched. Not run visually (app not launched).

## Shared-file edits (merge)
- `boringNotch/ContentView.swift` (Phase 7-only merge point), four hooks: property `wings` after `coordinator`; `else if ... wings.kind != nil { OrchestratorWingsView() }` between music and face branches; radius operand in `currentNotchShape`; `.overlay(alignment: .leading)` on the music visualizer container. Final diff:

```diff
diff --git a/boringNotch/ContentView.swift b/boringNotch/ContentView.swift
index 3d33d27..1b4e606 100644
--- a/boringNotch/ContentView.swift
+++ b/boringNotch/ContentView.swift
@@ -19,6 +19,7 @@ struct ContentView: View {
     @ObservedObject var webcamManager = WebcamManager.shared
 
     @ObservedObject var coordinator = BoringViewCoordinator.shared
+    @ObservedObject private var wings = OrchestratorWingsModel.shared
     @ObservedObject var musicManager = MusicManager.shared
     @ObservedObject var batteryModel = BatteryStatusViewModel.shared
     @ObservedObject var brightnessManager = BrightnessManager.shared
@@ -53,7 +54,7 @@ struct ContentView: View {
         NotchShape(
             topCornerRadius: topCornerRadius,
             bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
-                ? cornerRadiusInsets.opened.bottom
+                ? (vm.notchSize.height > openNotchSize.height + 1 ? OT.R.notchExpanded : cornerRadiusInsets.opened.bottom)
                 : cornerRadiusInsets.closed.bottom
         )
     }
@@ -291,6 +292,8 @@ struct ContentView: View {
                       } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                           MusicLiveActivity()
                               .frame(alignment: .center)
+                      } else if vm.notchState == .closed && !vm.hideOnClosed && !coordinator.expandingView.show && wings.kind != nil {
+                          OrchestratorWingsView()
                       } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                           BoringFaceAnimation()
                        } else if vm.notchState == .open {
@@ -482,6 +485,7 @@ struct ContentView: View {
                 ),
                 alignment: .center
             )
+            .overlay(alignment: .leading) { OrchestratorMusicNeedsDot().offset(x: -8) }
         }
         .frame(
             height: vm.effectiveClosedNotchHeight,
```

## Commits
cf7b7cf (wings model/views, compact), c85e485 (ContentView hooks)

## Self-Check: PASSED
