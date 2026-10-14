---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: planned
stopped_at: Phases 4-7 planned (2a redesign); Phase 4 next, then 5/6/7 in parallel
last_updated: "2026-10-14T03:30:20.376Z"
last_activity: 2026-10-14 -- Phase 7 planning complete
progress:
  total_phases: 9
  completed_phases: 3
  total_plans: 20
  completed_plans: 6
  percent: 30
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-10-14)

**Core value:** Answer and steer the Claude Code orchestrator from the notch without switching to a terminal — and never break the music player doing it.
**Current focus:** Execute Phase 4 (2a Foundation), then Phases 5, 6, 7 in parallel; Phase 2/3 on-screen UAT still pending

## Current Position

Phase: 4 of 9 — 2a redesign planned (Phases 4–7 have checked plans; 8–9 not planned)
Plan: 2 of 2
Status: Ready to execute
Last activity: 2026-10-14 -- Phase 7 planning complete

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Roadmap]: 3 coarse phases; BLD-02/BLD-03 mapped to Phase 1 but every phase has a music-still-works criterion
- [Roadmap]: `detectPrompt(screen)` built in Phase 1 (pure fn + assert check); fixtures refined from real captures in Phase 2
- [Roadmap]: Phase 2 opens with the gated `canBecomeKey` spike
- [User 2026-10-14]: Closed-notch attention dot shows even while music plays (dot at notch edge alongside music); built in Phase 3, Phase 1 must expose `needsAttention` state independent of music

### Roadmap Evolution

- 2026-10-14: Phases 4–9 added for the 2a redesign (design handoff in `.planning/design/orchestrator-2a/`): 4 Foundation, 5 Structured chat, 6 Prompt cards, 7 Runs board/expand levels/wings, 8 Phase B live data, 9 Phase B approvals. Phases 5, 6, 7 will execute in parallel after Phase 4 (merge map: `.planning/design/orchestrator-2a/MERGE-MAP.md`).
- [User 2026-10-14]: Chat rows come from serve's transcript endpoint `GET /api/chat/blocks?since=<id>`, not screen parsing. Waiting run cards show the run's question and a button that sends that context into the orchestrator chat — no Allow/Deny/resume of runs from the notch.

### Pending Todos

None yet.

### Blockers/Concerns

- Key-window behaviour on macOS 26 implemented (gated canBecomeKey); runtime check pending in 02-HUMAN-UAT.md
- Real question/permission screens captured 2026-10-14 (Tests/fixtures)
- Tabs only render when Shelf is enabled (`BoringHeader.swift:19`) — document or add one hook (Phase 1)
- Ad-hoc rebuilds may reset TCC (looks like broken music); Sparkle auto-update could overwrite the fork

## Deferred Items

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| *(none)* | | | |

## Session Continuity

Last session: 2026-10-14T01:13:11.913Z
Stopped at: Phases 2 and 3 executed and merged; on-screen UAT pending
Resume file: None

### Quick Tasks Completed

| # | Description | Date | Directory |
|---|---|---|---|
| 261014-f03 | Orchestrator tab default, usage in header, roomier chat/runs | 2026-10-14 | .planning/quick/261014-f03-orch-tab-default-usage-topbar |
| 261014-f4d | Orchestrator chat-only body, runs panel behind header button (replaces gear) | 2026-10-14 | .planning/quick/261014-f4d-orchestrator-runs-toggle |
| 261014-gkq | Chat: strip TUI input box, app activation for typing, Start/End in header, tap chat to expand | 2026-10-14 | .planning/quick/261014-gkq-orch-chat-chrome-keyboard-layout |
