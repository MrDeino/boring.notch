---
status: complete
phase: quick-261015-jzd
plan: 01
---

# Quick 261015-jzd: Question lead-in text above the card

## Where it was lost
Neither serve nor the notch: **Claude Code itself** doesn't write the turn's pending assistant lines (thinking, text, tool_use) to the session JSONL until the prompt is answered.
- Reproduced with a throwaway interactive Claude (haiku, private tmux socket `-L jzd`, temp dir, removed afterwards): while a 2-question AskUserQuestion was up, the JSONL held only the user message; the text + tool_use lines landed after Esc (stamped 04:29:47/48, written at 04:30:03).
- Same in the orchestrator's own transcripts: e.g. e332d852 has text stamped 01:23:42 + AskUserQuestion 01:23:48 written after a queue-operation at 01:24:34 (the answer time).
- So serve's `/api/chat/blocks` and the `blocks` SSE event (both read the JSONL) can't carry it. serve's `screen` (tmux capture) does: the text is the `⏺` block above the dialog's top rule.

No orch.js change is required. Optional serve-side alternative (not done): a `leadIn` field in `/api/chat` / the `chat` event, computed from the same capture with the same rule as `screenLeadIn`, so other clients (the web page) get it too.

## Fix (notch)
- `screenLeadIn(screen:)` (OrchestratorTranscript.swift): the `⏺` prose block(s) right above the dialog; skips the pending tool's own row, stops at another tool row / the ❯ echo / any other column-0 element; soft wraps re-joined by terminal width (rule length), blank lines kept as paragraphs. `heldLeadIn` returns it only while the store doesn't hold that prose (normalized 40-char prefix match), so it vanishes when the real block arrives.
- Expanded (questions always auto-expand): the lead-in is the newest prose row of the transcript above the card — same styling, scrolls with the chat, stick-to-bottom keeps it next to the card. Chat slice now also observes `$prompt`.
- Open (permission cards): the context strip shows `heldLeadIn ?? latestAssistantProse` (still 3 lines, scrollable). Column slice observes the screen lead-in only while a prompt is up.

## Verification
- Unit harness (Models, Pure, Transcript, PromptParse, RunsPure, Stream + Tests): OK, incl. QuickJzdTests on the real capture `fixtures/leadin-2q.txt` and the synthetic `leadin-long-2q.txt`.
- `run.sh`: `OK: composer bottom padding 12 in 33 scenes`. Viewed 58-ask-leadin-long-2q (5-paragraph brief, scrolled to its end, Fruit/Color/Submit chips, both options, Something else / Chat about this / esc visible) and 59-ask-leadin-real-2q (real capture: user bubble, then the lead-in incl. LEADIN-END paragraph, then the card). Both use a held store (no prose block), as in reality.
- Debug (/tmp/notch-dd): BUILD SUCCEEDED. Release (/tmp/notch-rel, ENABLE_HARDENED_RUNTIME=NO, ORCH_NO_SPARKLE): BUILD SUCCEEDED. No collision with 29b9 this time (retry loop was in place).
- The user's running notch was not launched or quit; the cursor was not moved; graft/ cache removed.

## Known gaps
- Screen text is the rendered form: markdown markers (bold, code) are gone until the real block arrives after the answer.
- Wrap re-join counts Characters; wide glyphs (CJK/emoji) can leave a stray line break (ponytail comment).
- The `⏺` lead-in must be inside serve's 200-line capture; a lead-in longer than that is cut at the top.
- Synthetic fixtures with "⏺ Asking one question" above the dialog (scenes 34/35/42) now show that line as a lead-in row; real Claude Code doesn't draw it.

## Files
Modified: OrchestratorTranscript.swift, OrchestratorChat.swift, OrchestratorExpanded.swift, Snapshots/Snap.swift, Tests/main.swift. Created: Tests/QuickJzdTests.swift, Tests/fixtures/leadin-2q.txt, Tests/fixtures/leadin-long-2q.txt.
