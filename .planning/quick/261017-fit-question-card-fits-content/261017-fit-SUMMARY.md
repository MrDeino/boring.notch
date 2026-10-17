---
quick_id: 261017-fit
status: complete
date: 2026-10-17
---

# Quick 261017-fit: question/permission card grows the notch to its content

- At the open level a question or permission card now measures its scroll content once per change (content + fixed chrome, independent of the spring) and asks `OrchestratorExpand.setFit("card", …)` for the extra height; the existing top-pinned spring does the grow. Open width unchanged; expanded layout untouched (the card asks 0 there).
- `fitHeight`: the card adds to the lead-in's fit (both are measured against the zero-fit open notch); cap is `promptCardMaxHeight` (screen − 80, never below the expanded height); past it the card scrolls.
- Question rows no longer use the one-line compact layout (the notch grows instead); permission commands show in full (scrolling only past the cap) instead of the first line.
- Shrinks on answer/submit/Esc (card disappears → fit 0) and follows multi-question next/review steps.
- `promptCardBase` (136) is the card region height at the zero-fit open notch; `run.sh --cardfit` fails if the notch drifts from the card's reported need.
- Checks: unit tests (QuickCardFitTests), `run.sh` snapshots (62 3 options 287 pt, 63 6 options 443 pt, 64 7 long options capped at 820 pt, 65 permission long command 276 pt), `--cardfit`, `--qlevel`, `--idle`, `--frames` OK; Debug and Release builds pass. Fixtures are synthetic.
