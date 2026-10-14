---
phase: quick-261014-tmq
plan: 03
subsystem: orchestrator-chat
tags: [swiftui, transcript, tool-rows]
key-files:
  modified:
    - boringNotch/Orchestrator/OrchestratorTranscript.swift
    - boringNotch/Orchestrator/OrchestratorChat.swift
    - boringNotch/Orchestrator/Tests/QuickTmqTests.swift
    - boringNotch/Orchestrator/Snapshots/Snap.swift
metrics:
  tasks: 2
  completed: 2026-10-14
---

# Quick 261014-tmq Plan 03: CLI-like tool rows

Tool blocks with serve's `description` render as label + dim chip/target line + ⎿ result; pulsing dot and shimmering label while running; green/red dot on completion. No description -> today's layout.

## Commit
- feat(quick-tmq-03) (one commit for both tasks; see git log)

## Design
- `ChatBlock.description` lossy decode; `toolDescription(_:)` = first non-empty trimmed line, tools only.
- Shimmer extracted to `OrchShimmer` / `orchShimmer()`; live status row uses it (one TimelineView). Dot pulse via `OrchPulse` (described, running rows only). `dot(_:)` animates colour changes.
- Edit rows keep `+a -r ▸ diff` on the dim line; expanded diff card branch untouched.

## Deviations
- [Rule 1] First render had the dot above the label for completed rows (selectable text had no baseline guide); added `.baselineAligned()` to the label.
- Tasks 1 and 2 committed together (plan allows it); RED step not committed separately.

## Verification
swiftc harness OK; BUILD SUCCEEDED; run.sh normal (no FAILED), --hittest OK, --transition OK, --closed clean. Viewed 46/47 (ok, error, Edit +3 -1, pending grey dot, null/missing description fallback). Scene 15 byte-identical; 16/23 differ only by run-card clock text.

## Human UAT
Watch a live tool call in the real notch: pulse + shimmer, then green dot and ⎿ result.

## Known Stubs
None.

## Self-Check: PASSED
