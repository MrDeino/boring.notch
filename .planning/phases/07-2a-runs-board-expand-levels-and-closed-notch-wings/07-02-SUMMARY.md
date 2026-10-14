---
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
plan: 02
subsystem: ui
tags: [swiftui, runs-board]
requires: [07-01]
provides: [OrchestratorRunsBoard, OrchestratorRunCard(run:compact:), OrchestratorAskInChatButton(run:)]
affects: [07-05]
key-files:
  modified: [boringNotch/Orchestrator/OrchestratorRunsBoard.swift]
requirements-completed: [RUN-01]
completed: 2026-10-14
---

# Phase 7 Plan 02: Runs board Summary

Frame 05 runs board: 196px run cards in a horizontal scroll (waiting first via `boardRuns`), a waiting card with the run's question and a tap-only, gated "Ask in chat" button, and the "✻ Orchestrator: ..." status row.

## What was built
- `OrchestratorRunCard(run:compact:)` inside `TimelineView(.periodic 30s)`; state dot/check, elapsed or stuck/failed label, short prompt, mono latest action; waiting gets orange inset ring; done/stopped at 75% opacity. Compact variant (for the rail in 07-05) fills width and omits the question/button. All server strings use `Text(verbatim:)`.
- `OrchestratorAskInChatButton`: sends `askInChatMessage(run)` only on tap; disabled while sending, while a prompt or options are live, and for 2s after sending. When the chat is stopped it reads "Start chat" and starts it. No Allow/Deny/resume controls.
- Board body replaced; Phase 4 list and `color(_:)` removed.

## Known limit
An unsent draft already typed in Claude Code's input box is prepended to the message (serve types then presses Enter).

## Deviations
None. Tasks 1 and 2 touch the same single file and were committed together (5f25360). Card width is written `.frame(width: compact ? nil : 196)`, so the plan's literal grep `width: 196` matches only via a trailing comment.

## Verification
BUILD SUCCEEDED (/tmp/notch-dd-p7); harness OK (/tmp/orch-test-p7). Button never tapped, no POSTs, app not launched.

## Shared-file edits (merge)
none

## Self-Check: PASSED
