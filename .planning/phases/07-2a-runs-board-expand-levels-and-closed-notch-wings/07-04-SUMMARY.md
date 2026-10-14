---
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
plan: 04
subsystem: ui
tags: [swift, expand-levels, terminal, key-monitor]
requires:
  - phase: 07-01
    provides: nextLevel, expandedHeight, shortcut helpers
provides:
  - open/expanded/terminal level machine with 0.4/0.82 spring
  - framed terminal panel (frame 10)
  - header collapse button
key-files:
  modified: [boringNotch/Orchestrator/OrchestratorExpand.swift, boringNotch/Orchestrator/OrchestratorTerminal.swift, boringNotch/Orchestrator/OrchestratorStatusCapsule.swift]
requirements-completed: [RUN-02, RUN-03]
duration: 15min
completed: 2026-10-14
---

# Phase 7 Plan 04: Expand levels and framed terminal Summary

Level machine with idempotent `setLevel`, command-key shortcuts through a local monitor, framed terminal panel and a header collapse button.

## Final Expand API (OrchestratorExpand)
- `level(for:)`, `setLevel(_:vm:window:)` (no-op at current level; nil window falls back to tracked window), `back(_:)`, `transcriptTapped(vm:window:)` (now `.expanded`), `register(vm:anchor:)`, `collapse`, `reset`, `releaseKey`, `isExpanded`, `openSize(for:)`.
- Height = `expandedHeight(screenHeight:)`; spring response 0.4 / damping 0.82 both ways; shrink delay 650ms. Begin/end interaction and monitors only in grow/finish (one each).

## Shortcut limits
Command-down, up, T, backslash are handled by a local keyDown monitor, so they work only while the notch panel is key (typing in the composer or in the terminal). A level change remounts the chat and ends typing. Esc is never intercepted. Backslash (rail toggle) returns the event unhandled; Plan 05 adds it. No Accessibility permission used.

## Behaviour change
Transcript tap now expands (440pt) instead of opening the terminal; terminal via Command-T or Open terminal.

## Deviations from Plan
None. Verification used /tmp/notch-dd-p7 and /tmp/orch-test-p7 per the hard constraints; BUILD SUCCEEDED, harness OK. Terminal never instantiated, no POSTs.

## Commits
40cea79 (level machine), d67c6e5 (terminal panel, header button).

## Shared-file edits (merge)
- `OrchestratorStatusCapsule.swift`: only `OrchestratorHeaderTrailing` changed (declared header merge point).
- Others (Expand, Terminal) are Phase 7-owned; public API names unchanged.

## Self-Check: PASSED
