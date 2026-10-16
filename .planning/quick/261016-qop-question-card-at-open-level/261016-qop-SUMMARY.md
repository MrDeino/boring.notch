---
quick_id: 261016-qop
status: complete
date: 2026-10-16
---

# Quick 261016-qop: question card at the open level

- `PromptCardController.sync` no longer calls `setLevel(.expanded)` for questions; the `raised` bookkeeping that collapsed it afterwards is gone. Open stays open, expanded stays expanded, closed opens to open. Closed-notch approval drop-down/attention path untouched.
- `QuestionCard` is compact at the open level: one-line rows (label + description), tighter padding. The list scrolls inside the card; keys unchanged.
- `run.sh --qlevel`: question arriving while open / expanded / closed (OK). Snapshot scenes 62 (3 options) and 63 (6 options) at open size. Unit tests, full snapshot run, Debug and Release builds pass.
- `--hittest` stalls after "scroll over text works" on this machine (before reaching its later passes); not related to this change, so the level check is its own flag.
