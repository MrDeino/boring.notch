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
