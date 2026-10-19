---
status: complete
phase: quick-261019-k0i
plan: 01
---

# Quick 261019-k0i: chat shows all assistant text

## Where text was hidden
- `rows` hid the live-reply row while `prompt != nil`; the separate lead-in row vanished when the card closed, before the transcript block existed.
- `nextLiveReply` dropped the row whenever the screen showed no prose (card closed, text scrolled off), even if the transcript lacked it.
- Dedupe (`heldLeadIn`, `screenLiveReply`) compared a 40-char prefix against the whole turn's prose, so an earlier block opening the same way hid new text.
- Left as is (by design): compact open level clamps prose to 4 lines (click expands), user rows show one line, tool rows are compact, rows window (12 open / 60 expanded).

## Fix
- `nextLiveReply(..., cardUp:)`: with a card up the row is the screen lead-in (else what it was); the separate lead-in row is gone, one row serves before/during/after. Caret off while a card is up; the 3 s end-of-turn drop waits for the card.
- Screen empty but transcript lacks the text: keep the unheld paragraphs of the row.
- `proseHeld`: head and tail of each paragraph must match inside one block of the turn.

## Verification
- Unit harness OK (new QuickAllTextTests: single `leadin-1q` synthetic + multi `leadin-2q`, before/during/after, repaint, answered/cancelled, same-opener, multi-paragraph; QuickJzd/QuickE1d adjusted to full-text blocks).
- run.sh OK (39 scenes; 59-ask-leadin-real-2q viewed: lead-in once above the card); --idle OK (one flaky window-size FAIL in gate 4/5 on the first run, baseline passes, two reruns pass).
- Debug and Release (ORCH_NO_SPARKLE, hardened runtime off) BUILD SUCCEEDED; Release copied to build/notch-rel/Clive.app.
