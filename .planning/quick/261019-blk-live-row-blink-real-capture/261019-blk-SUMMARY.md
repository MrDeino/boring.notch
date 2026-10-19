---
status: complete
phase: quick-261019-blk
plan: 01
---

# Quick 261019-blk: live row stops blinking, checked against a real recorded turn

## Method
A replay harness (kept outside the repo, with the recording) fed 241 polls of a real turn through `nextLiveReply` plus the manager's end-of-turn grace, and counted per paragraph how often it vanished then reappeared. The recording is private and is not in the repo; only synthetic fixtures are.

## Causes (found in the recorded frames)
1. Claude Code blinks the `⏺` of a running tool. On the "off" frames the tool header (`  Running 1 shell command…`, `  Ran 2 shell commands`, `  Bash(...)`) is indented with no marker, so it was read as a continuation of the prose above. With a `⎿` line under it the whole prose element then looked like a tool and disappeared; without one, the summary text was glued onto the paragraph.
2. A question card whose footer wraps (typing in the free-text option adds "ctrl+g to edit in Vim", pushing "Esc to cancel" onto a second line) did not parse as a card. The row then counted as idle and the 3 s end-of-turn grace dropped the lead-in and the paragraphs above it while the card was still up.

## Fix
- `screenLines` (OrchestratorTranscript.swift): marker-less tool headers get their `⏺` back before the element split (used by `screenLeadIn` and `screenLiveReply`).
- `scanPrompt`: the "Esc to cancel" footer is matched on the joined trailing lines.
- `liveEndDue`: the grace only runs with the input box back on screen, so no dialog shape can let it drop the row. Manager uses it for both the start and the timer's re-check.

## Counts on the recording (vanish-then-reappear / duplicated polls / summary shown as prose)
- Transcript empty: before 5 / 0 / 0, after 0 / 0 / 0 (the old row also lost the lead-in permanently once the card's grace ran).
- Transcript lagging 4 polls: before 1 / 0 / 0, after 0 / 0 / 0. Lag 0: 0 / 0 / 0 both.
- Duplicates and visible "Ran N" lines were not in this recording with the #26 code; the unit test shows the glue on the old code (blink frame 0).

## Verification
- QuickBlinkTests (synthetic frames of those shapes; fails on the old code), existing QuickFlickerTests golden unchanged. Unit harness OK, run.sh OK, --idle OK, Debug and Release (ORCH_NO_SPARKLE, hardened runtime off) BUILD SUCCEEDED, Release at build/notch-rel/Clive.app.
