---
phase: quick-261016-e1d
plan: 01
status: complete
commits: [4fa5094, 02ac712]
---

# Quick 261016-e1d: Live reply streaming Summary

While Claude writes a reply, the chat shows it growing as a plain-text row (read off serve's tmux `screen`), then swaps in place for the finished transcript block (no animation, no duplicate).

## What changed
- `OrchestratorTranscript.swift`: pure `screenLiveReply`, `mergeLiveReply`, `nextLiveReply`; shared `rejoinElement` / `proseKey` extracted from `screenLeadIn` / `heldLeadIn` (output unchanged, QuickJzdTests pass).
- `OrchestratorRunsPure.swift`: `pollInterval(... turnLive:)` = 0.5 s only for notch open + live turn.
- `OrchestratorManager.swift`: `liveReply`, `updateLiveReply()` (called at end of `applyChat`, cleared offline, 3 s end-of-turn grace), poll loop passes `turnLive` (Orchestrator tab shown + turn running).
- `OrchestratorChat.swift`: live row (`plain: true`, no markdown parsing, 20 000-char tail cap), `ingestBlocks` skips the slide animation while a live row shows and calls `updateLiveReply()`, single caret, pinKey, ModelSlice.
- Tests: `Tests/QuickE1dTests.swift` + fixtures `live-one/several/end.txt` (generated screens, 190-col chrome); snapshot scenes 60/61.

## Gates (real output)
- UNIT: `OK` (all suites incl. QuickE1dTests: one block, several blocks, 320-line reply through a 250-line capture, spinner old/new, question card, swap, end of turn, mergeLiveReply, pollInterval). Caveat: `runQuickMe4SelectionTest` (a real-AppKit focus test, `QuickMe4Tests.swift:81 focus opens the session once`) passed once during this run, then began failing on every later run, including on the pre-change baseline (HEAD~2 built separately). It depends on machine window/focus state, not this change. With only that one call removed from a temp copy of main.swift, the suite prints `OK`.
- SNAP: no `FAILED`; `OK: composer bottom padding 12 in 35 scenes`. Snapshot of the live row: `/tmp/notch-snapshots/60-live-reply-open.png` (and `/tmp/notch-snapshots/61-live-reply-expanded.png`): plain text row under the user message, caret on it, Working status row below. Scenes 58/59 not re-inspected visually (the question-card path is untouched; the live row is hidden while a prompt is up).
- IDLE: first run `FAIL: gate 4-log-then-notch-closes-then-reopen: interaction leaked (sessions=1)` (a window-timing gate unrelated to this change); second run `OK: idle`, third run `OK: idle`. Idle CPU: closed 0.1-0.5%, open-running 0.3%, expanded-running 0.4-0.7%, expanded-rich-tick 1.9%.
- Debug build: BUILD SUCCEEDED. Release build: BUILD SUCCEEDED, copied to `build/notch-rel/Clive.app`.

## Deviations
None to the plan. The idle gate's flakiness and the Me4 test environment failure are noted above, not fixed (out of scope).

## UAT
Run `build/notch-rel/Clive.app`, send the orchestrator a long question, and watch the reply grow in the Orchestrator tab and swap for the formatted block when it lands (no jump or slide).

## Known gaps
- Screen text is the rendered form: markdown markers appear only after the swap.
- Wide-glyph (CJK/emoji) wrap re-join can leave a stray line break.
- `mergeLiveReply` splices by first-line match (ponytail comment): a repeated first line can splice wrongly; anything scrolled off between two captures (>~250 lines in 0.5 s) is lost.

## Known Stubs
None.

## Self-Check: PASSED
Commits 4fa5094 and 02ac712 exist; graft/ and build/ not committed.
