---
quick_id: 261017-key
status: complete
date: 2026-10-17
---

# Quick 261017-key: question card taps are instant and queued

- `OrchestratorKeyQueue.swift`: `PromptKeyQueue` (single sender, FIFO, flushes on a failed send, `settle()`), `promptMismatches` (ticks vs screen). `OrchestratorManager.postKey` sends one key outside the `sending` window, so rows no longer dim/lock while keys go out.
- `PromptCardController`: `toggle` ticks optimistically and enqueues; `reconcile` re-reads up to 4x (250 ms) after the drain, then shows the screen's truth plus "Re-synced: a tap didn't register" if a key was lost. `answer` (Next/Submit/single-select/tabs) settles the queue first, verifies the ticks, and does not send Tab on a mismatch. Esc flushes the queue. "Didn't go through" stays for failed sends and a prompt that never moved on. Permission cards, Esc, separator and wing fixes untouched.
- Pace: back-to-back, each POST waits for serve's 200 (no extra gap). Against the mock (40 ms latency) keys arrive ~85-95 ms apart, in order. The real TUI's limit was not measured here; if it ever drops keys, reconcile catches it, and a gap can be added in `PromptKeyQueue.run`.
- Checks: unit tests (QuickKeyQueueTests), `run.sh --keymock` (3 rapid taps -> keys 1,2,3 in order and all ticked; swallowed key -> screen truth + notice; Next waits, Tab last with both ticked; Next after a lost tick sends no Tab), `run.sh`, `--cardfit`, `--qlevel`, `--idle` OK; Debug and Release builds pass. Fixtures synthetic.

## Follow-up: click outside the controls expands (open level)

- `expandsOnTap()` (OrchestratorExpanded.swift): a plain `Button` in the background that calls `transcriptTapped` with the panel from its own window anchor. Applied to the open-level column while a card is up, the card VStack, the tab row, the question's scroll content and the permission command box. Option rows, chips, footer buttons and the text field keep their own taps, so they answer and do not expand; the card stays up and working in the expanded layout.
- It is a Button, not `onTapGesture`: a bare tap gesture on empty space beside the question's AppKit scroll view never fired in the harness (Buttons did). `grow` needs a window, so the modifier carries its own anchor.
- Test: `run.sh --cardclick` (ORCH_BASE=http://127.0.0.1:47999, Tests/key-mock.py): option clicks send their key and do not expand; clicks on the title, the tab row's empty space and the gap above the question expand with the card still up and send nothing; chip and Next still answer. Stable over repeated runs. The permission card shares the modifier but has no click probe (the mock serves a question).
- `QuickMe4Tests` "focus opens the session once" fails in this environment on the previous commit as well (key-window state), unrelated to this change.
