---
quick: 261022-brief
status: complete
---
- `scanPrompt` now reports which lines followed a blank line; `detectPromptCard` adds `questionBlocks` (`briefBlocks`, OrchestratorAsk.swift) next to the unchanged one-line `question` (used for identity).
- `briefBlocks`: paragraphs, list items, bold ALL-CAPS labels; screen text joins wrapped lines (previous line near the longest line's width) and keeps short-line breaks; real-newline text (answered box) keeps every break.
- `BriefText` view (OrchestratorPromptCard.swift) renders them; the question card puts the question in its own scroll box (max 150 pt, gives way first when short on room) so the options keep theirs. The answered-question box uses `BriefText` too.
- Tests: QuickAskTests with synthetic fixture `question-brief.txt`; unit harness OK. Snapshots 65/66 (open, expanded) inspected: options visible; `--cardfit` OK. Debug and Release (ENABLE_HARDENED_RUNTIME=NO) builds succeeded into ./build. Not launched.
- Known limit: wrapped vs hard-broken screen lines is a width heuristic (ponytail comment in briefBlocks).
