---
phase: quick-261014-tmq
plan: 01
subsystem: orchestrator-chat
tags: [swiftui, live-status, autoscroll]
key-files:
  modified:
    - boringNotch/Orchestrator/OrchestratorPure.swift
    - boringNotch/Orchestrator/OrchestratorModels.swift
    - boringNotch/Orchestrator/OrchestratorManager.swift
    - boringNotch/Orchestrator/OrchestratorChat.swift
    - boringNotch/Orchestrator/OrchestratorStatusCapsule.swift
    - boringNotch/Orchestrator/Snapshots/Snap.swift
  created:
    - boringNotch/Orchestrator/Tests/QuickTmqTests.swift
    - boringNotch/Orchestrator/Tests/fixtures/working-new.txt
metrics:
  tasks: 3
  completed: 2026-10-14
---

# Quick 261014-tmq Plan 01: live status row, segment, smart scroll

Three commits: the in-chat spinner row parses today's Claude Code format and honours serve's `live` flag; Chat|Runs is hidden above the open level; chat sticks to the bottom only while the user is there, with a "New messages" pill.

## Commits
- a14e923 fix: live status (both spinner formats, verb/elapsed/tokens, `live` flag, row "✻ Waddling · 0:35 · ↓ 2.3k tokens")
- 87c705f fix: hide Chat|Runs segment at expanded/terminal
- Task 3 commit (HEAD): feat: smart auto-scroll + pill

## Notes for Phase 8
`ChatResponse.live` and its lossy `init(from:)` extension, and `OrchestratorManager.chatLive`, already exist (08-01 should extend, not re-add). `apply` uses `liveStatusFor(screen:live:)`; `applyChat` must keep it in place of `parseLiveStatus`.

## Deviations
- [Rule 1] Geometry source: `onPreferenceChange` never received real values in the hosted window, so the content frame is read with `onChange(of: c.frame(in: .named(...)))` inside the background GeometryReader (as the plan first suggested). Coordinate space is on the ScrollViewReader's content ScrollView.
- [Rule 1] `onChange(of: pinKey)` also sets `unseen` when not stuck: the 12-row window can drop an old row so a new row leaves the height unchanged and the height rule alone misses it.
- The hit-test scroll check runs at the start of the open pass (before the composer/remount checks), because after the remount the hosted layout keeps changing size for over a second. The wheel event did not move the view, so the harness falls back to scrolling the clip view directly.

## Verification
swiftc harness OK; xcodebuild succeeded; run.sh normal (no FAILED), --hittest (scrolled-up kept, pill jumps, follows at bottom, segment true), --transition (both OK), --closed clean. PNGs 01, 43, 44, 45, 10, 02, 34, hittest-new-messages viewed.

## Known Stubs
None.

## Self-Check: PASSED
