---
phase: 08-phase-b-live-data-sse-push-streaming-caret-diff-expansion-su
plan: 03
subsystem: orchestrator-notch
tags: [caret, diff, streaming]
requires: [08-01, 08-02]
provides: [caretVisible, shouldFetchBlocks, inline diff toggle, streaming caret]
key-files:
  modified: [OrchestratorStream.swift, OrchestratorChat.swift, OrchestratorManager.swift, Tests/Phase8Tests.swift, Snapshots/Snap.swift]
requirements-completed: [LIVE-02, LIVE-03]
completed: 2026-10-14
---

# Phase 8 Plan 03: Caret and inline diff Summary

Live prose shows a blinking 7x13 accent caret after its last glyph, "▸ diff" toggles the existing diff card inline in the open chat, and a new prompt arriving over SSE now fetches blocks before it is published.

## Commits
- 87b32d2: `caretVisible` (pure, harness-tested; serve `live` wins, nil falls back to the working status), caret in `OrchestratorSelectableTextView`, "▸ diff" Button toggle + inline card, scenes 50-52
- ac5e685: fix: `shouldFetchBlocks(streaming:running:newPrompt:)`; `applyChat` computes the prompt first and awaits a blocks GET when a chat event carries a new prompt while streaming (the blocks event could otherwise arrive after the card)

## Decisions and adaptations
- No second card or classifier: `diffRows`/`diffCard` reused. Plan's `classifyDiffLine` and diff tokens skipped (YAGNI, existing code covers them).
- Per-row `@State diffOpen`; toggle on both the described and plain tool rows (sits on the dim line with +a −r). Header tap collapses. Inline card lines use a no-op click and the card swallows taps, so neither opens the terminal; drag-select inside lines still works. Edit/Write/MultiEdit with non-empty diff only; others keep the inert label.
- Caret: the prose row is an NSTextView, so the caret is a CALayer inside it, placed after the last laid-out glyph (end of the last visible line, so it follows truncation too). Blink is a CABasicAnimation 1 <-> 0.2 over 0.5 s autoreverse; static with Reduce Motion; never touches the text storage so selection survives. Shown only when the block is the newest row and no pending rows exist.
- Snapshot-only `orchSnapDiffOpen` hook (under `#if ORCH_SNAPSHOT`) to render the open state.

## Verification
- swiftc harness OK; xcodebuild BUILD SUCCEEDED (/tmp/notch-dd); snapshot normal, --hittest, --transition, --closed pass. Viewed 50 (caret after "diff card."), 51 (collapsed "▸ diff" on the Edit row), 52 (card open inline, red/green/context lines).
- No POSTs, no SSE tests, app not launched.

## Deviations
None beyond the adaptations above.

## Human UAT
1. While Claude is working and its newest row is prose, the orange 7x13 caret blinks at the end of it; it disappears when a tool row appears or the turn ends; static with Reduce Motion.
2. On an Edit row, tap "▸ diff": the card opens inline (red/green/grey lines, header ▾ Edit file +N −N); tap the header or "▾ diff" to collapse. Neither tap opens the terminal or changes expand level; tapping plain transcript still does.
3. Same in the expanded column (⌘↓). Rows without diff data show +N −N and no toggle.
4. Question/permission appearing during a stream shows its context rows above the card.
5. Music: now-playing and controls unaffected.

## Self-Check: PASSED
