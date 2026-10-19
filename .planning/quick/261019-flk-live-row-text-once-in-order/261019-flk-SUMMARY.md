---
status: complete
phase: quick-261019-flk
plan: 01
---

# Quick 261019-flk: live row shows each paragraph once, in order

## Causes (from the recording frames)
- "⏺ Ran N shell commands" summaries were read as prose elements (only `⏺ Tool(` counted as a tool).
- Head-cut merge and carried-over paragraphs were never re-checked against the transcript: duplicates of rows already shown (b).
- The 3 s end-of-turn drop fired between tool calls; once working again the screen re-created the row: vanish and reappear (a).

## Fix
- `isToolSummary` (screenLiveReply, screenLeadIn, and a paragraph filter).
- `nextLiveReply`: every result passes `liveParagraphs` (drops summaries, held paragraphs, repeats); paragraphs of the previous row above the screen text are carried over (`carriedOver`), also with a card up.
- Grace drop remembers the dropped paragraphs for the turn (`liveIgnored`), so the screen can't bring them back.
- Left: the live row still sits after the transcript rows, so prose that only exists live shows below tool rows that follow it.

## Verification
- QuickFlickerTests: 12-step synthetic turn (3+ text/tool cycles, Ran 1/2/3 lines, one card, lagging transcript) + golden `fixtures/flicker-sequence.golden.txt`; fails on the old code at step 3.
- Unit harness OK, run.sh OK (scene 69-live-reply-tools-expanded viewed), --idle OK, Debug and Release (ORCH_NO_SPARKLE, hardened runtime off) BUILD SUCCEEDED, Release at build/notch-rel/Clive.app.
