---
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
plan: 05
subsystem: ui
tags: [swift, expanded-view, runs-rail, defaults]
requires:
  - phase: 07-02
    provides: OrchestratorRunCard compact
  - phase: 07-04
    provides: level machine, terminal panel, key monitor
provides:
  - expanded view (conversation column + runs rail/strip + Terminal pill)
  - persisted rail collapse with auto re-open
key-files:
  modified: [boringNotch/Orchestrator/OrchestratorExpanded.swift, boringNotch/Orchestrator/OrchestratorExpand.swift]
requirements-completed: [RUN-03, RUN-04, RUN-02]
completed: 2026-10-14
---

# Phase 7 Plan 05: Expanded view and runs rail Summary

Frame 12/12b: conversation column (terminal / offline / stopped / prompt card / chat) beside a 178px runs rail or 30px strip with hover peek, usage bars, Terminal pill, 120ms cross-fade; Command-backslash wired.

## Notes
- Terminal pill sits at the bottom of the rail column (R-07 fallback; no composer-only view exists).
- `OrchestratorRailState` keeps its own waiting baseline sink (duplicate of the wings idea) so it does not depend on 07-03. "Session" = app launch. Auto-open never writes Defaults.
- Defaults key `orchRunsRailCollapsed` is declared in OrchestratorExpanded.swift (not Constants.swift).
- `OrchestratorExpandOverlay` deleted; `.onDisappear { expand.reset() }` moved to the expanded view. Key monitor swallows backslash when level != .open.
- Both tasks went in one commit (single file pair, built together).

## Merge risks
Conversation column is ~420px wide with the rail open (Phase 5 rows / Phase 6 card designed for ~612px). Grep for `OrchestratorExpandOverlay` after merging 5 and 6.

## Deviations from Plan
None. BUILD SUCCEEDED (/tmp/notch-dd-p7), harness OK. Footprint gate: only ContentView, BoringHeader, TabButton outside Orchestrator/. No POSTs, no app launch, /term not loaded.

## Commits
See git log: feat(07-05) expanded view.

## Shared-file edits (merge)
none (OrchestratorExpanded.swift and OrchestratorExpand.swift are Phase 7-owned).

## Self-Check: PASSED
