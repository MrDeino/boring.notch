---
phase: 09-phase-b-approvals-closed-notch-approval-drop-down-global-sho
verified: 2026-10-14T00:00:00Z
status: human_needed
score: 4/4 must-haves verified in code; on-screen behaviour unverified
human_verification:
  - test: "Serve end-to-end: trigger a real permission prompt in the orchestrator chat with the hook live, notch closed"
    expected: "Frame 00 panel drops down (orange dot, 'Orchestrator wants to run', tool, mono command, Allow/Deny/More...). Live GET /api/chat already returns an `approval` key (currently null), but no pending approval was available to observe a populated object."
    why_human: "Needs a real pending approval; verifier may not POST or launch the app"
  - test: "Press Option-Return / Option-Escape in another app while an approval is pending (ad-hoc signed sandboxed build); also confirm both combos are free in other apps when nothing is pending, and no permission dialog appears"
    expected: "Allow/Deny answers without focusing the notch; on macOS 15.0/15.1 the labels and combos are Ctrl-Option"
    why_human: "Carbon hotkey delivery under sandbox cannot be checked without running the app"
  - test: "Open/expand/terminal/collapse the notch, quick re-expand, multi-display"
    expected: "Continuous spring, top edge never slides, window shrinks about 0.65s after collapse, drop-down not clipped"
    why_human: "Real window resize timing (syncWindow) is only covered by snapshot harness, not real windows"
  - test: "Play music, trigger approval, answer it"
    expected: "Drop-down shows over music; music live activity and sizing return unchanged; hovering the drop-down does not hover-open the notch"
    why_human: "Visual and runtime behaviour"
  - test: "Allow when option 1 is not plain Yes, and stale approval id"
    expected: "Allow opens the notch on the prompt card; no keypress sent for a stale id"
    why_human: "Needs live prompt (mock script boringNotch/Orchestrator/Tests/approval-mock.py exists)"
---

# Phase 9: Phase B Approvals Verification Report

**Phase Goal:** User can approve or deny the orchestrator's tool calls from a closed-notch drop-down or global shortcut, and the panel sizes itself to its content.
**Re-verification:** No, initial.

## Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Hook posts approvals to serve; notch learns without screen parsing | VERIFIED (notch side) | `OrchestratorApproval` model decoded from GET /api/chat (`hasApproval` gate, Manager:296) and SSE `approval` event (Stream:53, Manager:229). Never derived from screen. Live serve GET /api/chat already has an `approval` key (null now). Hook script and /api/hook live in the orchestrator repo, out of this phase's scope per 09-CONTEXT. |
| 2 | Closed notch drops down 460px panel with copy, command block, Allow/Deny/More... | VERIFIED in code | `OrchestratorApprovalPanel` (title, tool, mono block, three 30px pills); hosted in ContentView:295 before the music branch; 22 radius at :59; hover-open suppressed at :539; More... opens Orchestrator tab. Snapshots reportedly viewed. |
| 3 | Option-Return / Option-Escape answer globally, sandbox-safe | VERIFIED in code | KeyboardShortcuts (already a dependency, Carbon hotkeys) names + `onKeyDown` -> `answer(allow:)`; `enable` only while `approval != nil`, `disable` otherwise; Ctrl-Option fallback via `approvalNeedsCtrlFallback`. Runtime delivery needs human check. |
| 4 | Panel frame follows content; music unaffected | VERIFIED in code | `syncWindow` is the single `setFrame` site, driven by `.onChange(of: vm.notchSize)` (ContentView:211), uses `panelSize` / `pinnedFrame`, grow-now/shrink-after-650ms; floor is windowSize so music states stay 640x210. |

Plan-level truths (answer gate on fresh id plus plain "Yes", 3s ignore window, Deny = Escape, hotkey failure only logs) are implemented in `answerApproval` / `approvalAnswer` (Manager:65, Pure:133) and covered by Phase9Tests.

## Automated checks
- swiftc harness (all listed files plus Tests/*.swift): compiled, ran, output "OK", zero "fail" lines.
- `OrchestratorApproval.swift` is in project.pbxproj (4 references); no new entitlements or packages; boringNotchApp.swift untouched.
- Live GET 127.0.0.1:4777/api/chat: keys running, screen, live, input, context, approval (approval null).
- xcodebuild not re-run by me; SUMMARYs claim BUILD SUCCEEDED (unverified by me).

## Requirements Coverage

| ID | Plan | Status | Evidence |
|----|------|--------|----------|
| APR-01 | 09-01 | SATISFIED (notch side) | approval via API/stream, no screen inference |
| APR-02 | 09-01 | SATISFIED in code, visual UAT pending | panel + ContentView hook |
| APR-03 | 09-02 | SATISFIED in code, runtime UAT pending | KeyboardShortcuts enable/disable |
| APR-04 | 09-03 | SATISFIED in code, runtime UAT pending | single sizer syncWindow |

No orphaned requirements: REQUIREMENTS.md maps APR-01..04 to Phase 9 and all four are claimed by plans.

## Anti-Patterns
No TBD/FIXME/XXX found in the phase's approval files on inspection. No stubs: panel, center and manager gate are substantive and wired.

## Gaps Summary
No code gaps found. All SUMMARYs state human UAT was not run; real-window sizing, hotkey delivery under sandbox, and a populated live `approval` have not been observed. Hence `human_needed`.
