---
phase: 09-phase-b-approvals-closed-notch-approval-drop-down-global-sho
plan: 02
subsystem: orchestrator-notch
tags: [approvals, hotkeys, keyboardshortcuts]
requires: [09-01]
provides: [global approval hotkeys, OS fallback pure functions, approval answer mock round trip]
key-files:
  modified: [OrchestratorApproval.swift, OrchestratorPure.swift, Tests/Phase9Tests.swift, Tests/main.swift]
  created: [Tests/approval-mock.py]
requirements-completed: [APR-03]
completed: 2026-10-14
---

# Phase 9 Plan 02: Global approval hotkeys Summary

While an approval is pending, global Option+Return answers Allow and Option+Escape answers Deny through the existing `OrchestratorApprovalCenter.answer` -> `answerApproval` gate (fresh re-read, same id, prompt on screen, 3s ignore). On macOS 15.0/15.1 the combos are Ctrl+Option and the pill labels follow.

P9B2: 75ad50a7f7a1e308d8b2efa7affef1c4c3f85459

## Commits
- c3bf3fe test: failing fallback/label asserts (RED)
- b3a56e5 feat: `approvalNeedsCtrlFallback(major:minor:)`, `approvalKeyLabels(ctrl:)` (GREEN)
- 9237199 feat: hotkey names, one-time handlers, enable/disable on the deduplicated approval sink, OS-matched labels
- ee598f2 test: mock round trip

## Implementation
- All KeyboardShortcuts code sits in `#if !ORCH_SNAPSHOT` inside OrchestratorApproval.swift; names live there, so ShortcutConstants.swift and boringNotchApp.swift are untouched.
- Shortcut combos are re-set every launch to the OS-chosen combo; handlers installed once; keys start disabled and are enabled only while `approval != nil`.
- No new package, entitlement, permission, event tap or global monitor (diff vs P9B2 empty for entitlements, Info.plist, pbxproj, Shortcuts, boringNotchApp.swift).

## Mock round trip (extra, user-requested)
`Tests/approval-mock.py` (self-exits after 30s, port 47999, never 4777) is spawned and terminated by the harness under `ORCH_APPROVAL_MOCK=1`. The test mirrors `answerApproval` (fresh GET /api/chat, `approvalAnswer` gate, POST). Asserted: Allow posts `{"key":"1"}`, Deny posts `{"key":"Escape"}`, both with `x-orch: 1` and `Content-Type: application/json`; a changed approval id, no prompt on screen, and `approval: null` post nothing (log stays at 2 posts). Note: the mock mirrors the manager's gate sequence rather than driving `OrchestratorManager` (not in the swiftc harness).

## Verification
- swiftc harness OK; with ORCH_APPROVAL_MOCK=1 also OK. xcodebuild into /tmp/notch-dd: BUILD SUCCEEDED. Snapshot normal, --hittest, --transition, --closed all exit 0, no errors. closed-21 viewed: labels "Allow ⌥⏎" / "Deny ⌥⎋" unchanged (no 15.0/15.1 scene; that path is covered by the pure asserts).
- Nothing launched, nothing pushed, no POST to 4777. `lsof -i :47999` empty; one mock process left by a crashed first run was killed (my own).

## Deviations
None of rules 1-4. The first mock draft failed on my test fixture (screen lacked the footer line `detectPrompt` needs) and on `await` inside `precondition`; fixed in the test only.

## Known stubs
None. APR-04 (content-sized frame) is plan 03.

## Human UAT
Per plan `<human_uat>` (sandboxed ad-hoc build hotkey registration, no swallowing when idle, no permission dialog, music unaffected); not run here.

## Self-Check: PASSED
