---
status: complete
phase: quick-261015-hm7
plan: 01
---

# Quick 261015-hm7: Readable approvals, AskUserQuestion card

AskUserQuestion approvals no longer show the Allow/Deny drop-down: the approval center publishes `approval = nil` and bumps `cardRequest` once per id, so the notch opens on the Orchestrator tab and the existing Phase 6 question card answers it. Other approvals render through a pure `approvalSummary` (Bash: description + monospace command; Read/Edit/Write/MultiEdit/NotebookEdit: verb + path; others: sorted `key: value` lines, regex fallback for serve's 300-char-truncated JSON).

Commit: single code commit on orch/261015024049-30cc (feat(quick-hm7)).

## Verification
- Unit harness: OK (QuickHm7Tests included). Note: the harness command in the plan also needs OrchestratorStream.swift in the swiftc file list (Phase8Tests uses shouldFetchBlocks).
- `run.sh --askmock`: `posts: ["{\"key\":\"2\"}", "{\"key\":\"1\"}", "{\"key\":\"Tab\"}"]` then `OK: askmock` (question detected, no drop-down, cardRequest +1 once, second refresh no bump, Bash approval still shows drop-down). It asserts the POST bodies only; header checks (x-orch, content type) are covered by the existing POST path tests.
- `run.sh --closed`: passes; `ask: approval==nil true cardRequest+1`. Default `run.sh`: `OK: composer bottom padding 12 in 33 scenes`.
- PNGs viewed and readable: closed-25 (description + mono command), 26 (key: value, no braces), 27 ("Edit file" + path), 28 (music, no drop-down), 50-ask-1q (Fruit chip, question, options with descriptions, Something else), 51-ask-2q-multiselect (Fruit/Color/Submit chips, checkboxes, Next). Panels fit the 190pt replica; no height change needed.
- Debug (/tmp/notch-dd): ** BUILD SUCCEEDED **. Release (/tmp/notch-rel, ENABLE_HARDENED_RUNTIME=NO, ORCH_NO_SPARKLE): ** BUILD SUCCEEDED **.

## Known gaps / side effects
- Edit/Write diff or size is not available: serve's approval payload only carries tool / command (= file_path) / description, not old_string/new_string/content. Showing it needs an orch.js change in the orchestrator repo.
- Side effect: a question now opens the notch on the Orchestrator tab (replacing the closed music live activity; music keeps playing). Not done while the notch is hidden (hideOnClosed); such a question is not re-requested later (ponytail comment in ContentView), the needs-you wing and hover-open still reach it.

## Deviations
- [Rule 3] Snap.swift `fixture()` made non-private so SnapClosed/SnapAsk can share it.
- Unit harness file list extended with OrchestratorStream.swift (see above).

## Files
Modified: ContentView.swift (guard), OrchestratorApproval.swift, OrchestratorPure.swift, Snapshots/Snap.swift, Snapshots/SnapClosed.swift, Tests/main.swift. Created: Snapshots/SnapAsk.swift, Tests/QuickHm7Tests.swift.
