---
phase: 06-2a-prompt-cards-permission-decision-card-and-question-list
plan: 02
subsystem: prompt-card-ui
tags: [swiftui, prompt-card]
requires: [06-01]
provides: [PromptCardController, PermissionCard, QuestionCard]
key-files:
  modified: [boringNotch/Orchestrator/OrchestratorPromptCard.swift, boringNotch/Orchestrator/OrchestratorPromptParse.swift, boringNotch/Orchestrator/Tests/Phase6Tests.swift]
requirements: [PRM-02, PRM-03, PRM-05]
metrics:
  completed: 2026-10-14
---

# Phase 6 Plan 02: Permission card and question list Summary

Frame 03 permission card (shortLabel pills, full-label tooltips, esc-keycap deny that sends its real number) and frame 04 question list (highlight, scroll, Chat about this, esc), all answered through a refresh-then-compare stale-screen guard. Build SUCCEEDED, harness OK.

## PromptCardController API (06-03 extends this class)
`static let shared`; `@Published pressed: Int?`, `highlighted: Int?`, `flash: Bool`; `sync(_:vm:window:)` (resets highlight on new prompt, raises to `.expanded` for questions, records `raisedByCard`); private `promptChanged` restores `.open` only if card raised and level still `.expanded`; `choose(_:displayed:)`, `escape(displayed:)` via private `stillCurrent` (refresh, `promptIdentity` equal, not locked; flashes card on reject). The footer has a `Spacer` where 06-03 adds "Something else…".

## Deviations
- Tasks 1 and 2 landed in one commit (single file rewrite).
- `promptIdentity` (new `PromptIdentity` struct) added to OrchestratorPromptParse.swift (Phase 6 file) with a Phase6Tests assert, as the plan asked.
- R-07: no matchedGeometryEffect; offset/opacity spring appearance instead.
- `$prompt` sink hops via `DispatchQueue.main.async` because the publisher emits before the value is set.
- `grep "== displayed"` acceptance count not met literally; the comparison is `promptIdentity(cur) == promptIdentity(displayed)`.
- Spec gap: the shell shows the card instead of the transcript, so no transcript sits above the card.
- Known ceiling: `refresh()` returns early when a poll is in flight, so guard may use a up-to-2s-old screen (ponytail comment in code).

## Shared-file edits
none

## Self-Check: PASSED
