---
phase: 09-phase-b-approvals-closed-notch-approval-drop-down-global-sho
plan: 01
subsystem: orchestrator-notch
tags: [approvals, closed-notch, sse, swiftui]
requires: [phase-08 applyChat/SSE stream]
provides: [OrchestratorApproval model, approvalAnswer gate, OrchestratorApprovalCenter + panel]
affects: [ContentView, OrchestratorManager, OrchestratorStream]
key-files:
  created: [boringNotch/Orchestrator/OrchestratorApproval.swift, boringNotch/Orchestrator/Tests/Phase9Tests.swift, boringNotch/Orchestrator/Tests/fixtures/phase9-chat.json]
  modified: [OrchestratorModels.swift, OrchestratorPure.swift, OrchestratorManager.swift, OrchestratorStream.swift, OrchestratorTokens.swift, OrchestratorCompact.swift, ContentView.swift, project.pbxproj, Snapshots/SnapClosed.swift, Tests/main.swift]
requirements-completed: [APR-01, APR-02]
duration: ~25 min
completed: 2026-10-14
---

# Phase 9 Plan 01: Approval drop-down Summary

A pending `approval` from serve (GET /api/chat or the SSE `approval` event) drops down the 460px frame 00 panel on the closed notch, over music. Allow, Deny and More... are answered through the existing POST /api/chat {key} path behind an id and prompt freshness gate.

P9BASE: 593efa8c0ac9be636c46f957a4e720a1bedcb870

## Commits
- 67f75e8 test(09-01): failing approval decode, gate and SSE asserts (RED)
- eb04c2b feat: model, pure gate (`approvalAnswer`, `visibleApproval`, `approvalCommandLine`), SSE event (GREEN)
- 2d2d222 feat: manager state, `answerApproval`, stream case
- bf3f4cd feat: OrchestratorApproval.swift (center + panel), pbxproj, token, indicator guard, ContentView hooks
- 222a89a test: closed-notch snapshot scenes 20-24

## Adaptations to the current code
- `ChatResponse` already had a custom `init(from:)` (Phase 8); extended it with `approval`/`hasApproval`, lossy (`try?`), so a malformed approval never fails the chat decode. `OrchestratorApproval.init(from:)` requires `id` and is lenient on the rest.
- Approval flows through the existing `applyChat` (applied synchronously before its blocks await, so a later payload with `applySeq` ordering wins) and the existing `runStream` switch. No second decoder or state model. Absent key on a running chat leaves the value alone; `running == false`, offline and chat-not-running clear it.
- Manager clears `rawApproval` too on offline.
- The music branch in ContentView already carries a `(musicManager.isPlaying || wings.kind == nil)` clause from quick tasks; it is untouched. The approval branch sits before it, so it replaces music and wings while shown. `wings.shiftX` resets to 0 through OrchestratorWingsView's existing `onDisappear` (snapshot 21/22: shift=0.0).
- Harness file list includes OrchestratorStream.swift. SSE parser asserts (valid, `null`, malformed, missing id) are in Phase9Tests.
- Snapshot scenes: `--closed` gained 20-24 (music before, approval bare, approval over music, cleared, music after), using a replica that follows ContentView's branch order; window size is per-shot so earlier shots are unchanged.

## ContentView diff vs P9BASE (verbatim)
```
+    @ObservedObject private var approvals = OrchestratorApprovalCenter.shared
-                : cornerRadiusInsets.closed.bottom
+                : (approvals.approval != nil && vm.notchState == .closed ? OT.R.approvalPanel : cornerRadiusInsets.closed.bottom)
+                      } else if vm.notchState == .closed && !vm.hideOnClosed && approvals.approval != nil {
+                          OrchestratorApprovalPanel(onMore: { OrchestratorManager.shared.showRunsBoard = false; coordinator.currentView = .orchestrator; doOpen() })
+                  approvals.approval == nil,
```

## Verification
- swiftc harness: OK. xcodebuild into /tmp/notch-dd: BUILD SUCCEEDED. Snapshot normal, --hittest, --transition, --closed all exit 0; viewed closed-21/22/24 PNGs (panel matches frame 00: orange dot, title, tool, mono block, three pills, 22 radius; music live activity returns after clear).
- No POST was sent anywhere (no mock needed: answer path is covered by pure gate asserts). Nothing launched or left running; `lsof -i :47999` empty. MediaControllers, managers and boringNotchApp.swift unchanged vs P9BASE.
- GET /api/chat against serve was not needed beyond the contract fixture; phase9-chat.json is derived from the 09-CONTEXT contract.

## Deviations
None of rules 1-4. Notes: Task 1's feat commit briefly left the app target non-exhaustive on the new stream case until the next commit (harness-only compile at that point).

## Known stubs
None. Hotkeys (APR-03) and content-sized frame (APR-04) are plans 02/03.

## Human UAT
Per plan `<human_uat>` (needs serve `approval` support or a local stub); not run here.

## Self-Check: PASSED
