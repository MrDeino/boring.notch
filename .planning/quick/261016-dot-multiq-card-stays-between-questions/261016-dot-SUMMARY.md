---
status: complete
---
# Quick 261016-dot: multi-question card stays mounted between questions

Added pure `hidesOnAnswer` (OrchestratorPromptParse.swift); `PromptCardController.answer` skips `dismissed` and `release()` when the answer leads to another step (q1->q2->q3->review, Tab/BTab). Single-question, permission, review Submit/Cancel unchanged. Parser untouched.
Gates: unit harness (plain and mock env) OK; snapshot run.sh OK (33 scenes); Debug and Release BUILD SUCCEEDED; Release copied to build/notch-rel/Clive.app (adhoc).
Deviations: none.
