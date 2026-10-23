---
quick: 261022-jie
status: complete
---
- New: `OrchestratorBackgroundModel.swift` (lenient `BgTask`, decode of array / `{agents:[…]}` / single object, ISO or epoch dates, sort, elapsed, recent steps), `OrchestratorBackground.swift` (row, chip, card, selection).
- Hooks (small): manager `bgTasks` + `loadBackground()` (GET /api/chat/agents while the chat runs and once per stream connect; 404/odd payload leaves the list alone), SSE `agents` (replace) / `agent` (upsert), `OrchestratorExpandedView` row, `OrchestratorView` card overlay sharing the run log's expand/esc handling, closed-notch blue dot beside the attention dot.
- Chat log untouched (no animations added; #30 plain-log behaviour kept).
- Tests: QuickBgTests (synthetic Tests/fixtures/bg-agents.json: running/done/failed agents, running/stopped monitors; lenient decode, ordering, elapsed, steps tail, SSE). Full unit harness OK (command now also needs OrchestratorAsk/KeyQueue/ComposerInput + OrchestratorBackgroundModel).
- Snapshots (run.sh, 52 scenes OK; --closed OK): 80-87 row/cards, closed-40..42 dot.
- Debug and Release (ENABLE_HARDENED_RUNTIME=NO) builds into ./build: BUILD SUCCEEDED. Not launched.
- Not checked: against real serve (endpoint is being built in parallel; field names/event names `agents`/`agent` are assumed from the brief); the spinner is an AppKit ProgressView.
