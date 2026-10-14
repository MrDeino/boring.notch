---
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
plan: 01
subsystem: ui
tags: [swift, pure-helpers, tdd, runs-board, wings]
requires:
  - phase: 04
    provides: ExpandLevel, pollInterval seam, Phase7Tests stub, harness
provides:
  - OrchestratorRun optional fields (startedAt, lastOutput, result, denials, latest, activity)
  - Pure helpers for run cards, levels, shortcuts, transition detection, wings
affects: [07-02, 07-03, 07-04, 07-05]
key-files:
  created: [boringNotch/Orchestrator/Tests/fixtures/phase7-state.txt]
  modified: [boringNotch/Orchestrator/OrchestratorModels.swift, boringNotch/Orchestrator/OrchestratorRunsPure.swift, boringNotch/Orchestrator/Tests/Phase7Tests.swift]
key-decisions:
  - "wingSideWidth needsYou text estimate is label.count*6.5+8 (not +16+8) so 'Bash?' stays at the specified 46pt side width"
requirements-completed: [RUN-01, RUN-02, RUN-04, RUN-05]
duration: 25min
completed: 2026-10-14
---

# Phase 7 Plan 01: Pure helpers Summary

All Phase 7 logic as tested pure functions plus the optional run fields; closed polling is now 3s while the chat runs.

## Gate (Phase 4)
All 13 greps returned 1; no renamed signatures.

## Helper signatures (OrchestratorRunsPure.swift)
- `parseRunDate(_: String?) -> Date?`
- `runElapsed(_ run:, now:) -> String`; `latestAction(_ run:, now:) -> String`
- `waitingQuestion(result: String?, denials: [String], cap: Int) -> String`; `askInChatMessage(_ run:) -> String`
- `boardRuns(_:limit:)`, `runShortID(_: String?)`, `boardStatusLine(runs:promptActive:liveText:chatRunning:)`
- `pollInterval(notchOpen:chatRunning:offline:)` (body: offline 10, open 2, closed+running 3, else 10)
- `enum LevelEvent {deeper, back, terminal}`, `nextLevel(_:_:)`, `expandedHeight(screenHeight:)`
- `enum OrchShortcut {deeper, back, terminal, toggleRail}`, `shortcut(keyCode:chars:commandOnly:)`
- `runStates(_:)`, `newlyWaiting(old:new:)`, `finishedTransition(old:new:) -> OrchestratorRun?`
- `enum WingKind {working, needsYou(String), finished(String)}`, `wingKind(needsYou:needsLabel:finishedProject:working:)`, `wingLabel(promptTitle:waitingDenials:)`, `wingSideWidth(_:notchWidth:)`

Models: `OrchestratorRun` gained six optional fields; `RunActivity`, `RunAgent` structs.

## Deviations from Plan
**[Plan inconsistency] wingSideWidth needsYou estimate.** The specified estimate (count*6.5+16+8 = 56.5 for "Bash?") contradicts the required 46 and 305 outer width. Used count*6.5+8 (40.5, so base 46 wins). Tracked by `// ponytail:` comment; UAT may tune.

Otherwise none. A single GET of /api/state confirmed field shapes; no POSTs.

## Verification
Harness prints OK (/tmp/orch-test-p7); xcodebuild BUILD SUCCEEDED (/tmp/notch-dd-p7). Commits: edde287 (test), a40a1ee (feat), c113205 (test), 2bc5dd5 (feat).

## Shared-file edits (merge)
- `boringNotch/Orchestrator/OrchestratorModels.swift`: six optional `let`s inside `OrchestratorRun` plus `RunActivity`/`RunAgent` below it (merge point: Phase 7 Models fields; others do not edit Models).
- `OrchestratorRunsPure.swift` `pollInterval` body only (Phase 7-owned file; call site in manager unchanged).

## Self-Check: PASSED
