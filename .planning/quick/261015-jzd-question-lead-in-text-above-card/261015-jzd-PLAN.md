---
phase: quick-261015-jzd
plan: 01
type: quick
---

# Quick 261015-jzd: Question lead-in text visible above the card

## Goal
While an AskUserQuestion (or permission) prompt is pending, the assistant text written just before it in the same turn is visible above the card.

## Findings (investigation before planning)
- serve (`orch.js` chatBlocks / blocksEvent) emits whatever is in the transcript JSONL; it does not hold blocks.
- Claude Code itself does not write the turn's pending assistant lines (thinking, text, tool_use) to the JSONL until the question is answered. Verified with a throwaway interactive Claude (haiku, private tmux socket): while the 2-question dialog was up the JSONL had the user message only; text + tool_use landed after Esc. Also visible in the orchestrator's own transcripts: assistant lines stamped 01:23:42 written after a 01:24:34 queue-operation.
- So /api/chat/blocks and the `blocks` SSE event cannot carry it; the text is only on serve's `screen` (tmux capture) as a `⏺` block above the dialog's top rule.
- Notch: questions auto-expand; the transcript above the card ends at the user's message; the open-level context strip uses `latestAssistantProse(store.blocks)` → nil or older prose.

## Tasks
1. Pure `screenLeadIn(screen:)` (OrchestratorTranscript.swift): the `⏺` prose block(s) right above the dialog top rule (skips the pending tool's own row, stops at a tool row / user echo / other element), CC's soft wraps re-joined by terminal width, blank lines kept as paragraphs. `heldLeadIn(screen:blocks:)`: that text unless the store already holds it (normalized prefix match).
2. Chat view: while a prompt is up, append the held lead-in as a prose row after the store blocks (expanded level: scrolls with the transcript, newest above the card). Open level: context strip shows `heldLeadIn ?? latestAssistantProse`, cap raised so a long lead-in scrolls; card buttons keep their room (notch grows via setFit).
3. Real fixture `Tests/fixtures/leadin-2q.txt` + QuickJzdTests; snapshot scenes 58/59 (long lead-in + 2 questions, open/expanded) using a held-store (no prose block) like the real case.
4. Unit harness, run.sh, Debug + Release (ENABLE_HARDENED_RUNTIME=NO) builds, retry on collision with run 29b9.

## Done when
Snapshot 58/59 show the lead-in above the 2-question card with all option buttons and the bottom row visible; unit harness OK; both builds succeed.
