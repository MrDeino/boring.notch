---
quick: 261022-jie
---
# Background agents and monitors in the Orchestrator tab

Goal: show the chat's background agents/monitors (serve: GET /api/chat/agents, SSE `agents`/`agent`) in the tab. All fields optional; old serve = tab unchanged.

1. Model + pure helpers (`OrchestratorBackgroundModel.swift`), manager state `bgTasks` (poll + stream, cleared when the chat stops or goes offline), SSE cases.
2. "Background · N running" row under the deploy rows (spinner/eye/✓/✗ chips, finished dimmed); click opens a card over the tab (steps/events tail, running time, finished agent's report via `proseAttributed`); esc/outside click closes.
3. Closed notch: small blue dot while anything runs.
4. Synthetic fixture + unit test + snapshots; Debug and Release (ENABLE_HARDENED_RUNTIME=NO) builds into ./build.
