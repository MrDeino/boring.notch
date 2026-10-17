---
quick_id: 261017-dpl
status: complete
date: 2026-10-17
---

# Quick 261017-dpl: Deploy wing and row — Summary

- **Model:** `StateResponse.deploys: [Deploy]?` (nil on an old serve; a malformed entry is dropped, a malformed `deploys` never fails the state). SSE `deploy` accepts a bare array, `{"deploys":[…]}` or one deploy object (upsert by project).
- **Closed notch:** building -> "project · #N deploying…" + elapsed; building -> live -> 6 s "project · #N live ✓"; failed "project · #N ✗ deploy failed" stays until the notch is opened, the row is clicked, or the next deploy starts. Deploys already finished at the first load show nothing. Needs-you beats finished-run beats deploy beats the working count. Closed polling stays at 3 s while a deploy builds.
- **Open notch:** `OrchestratorDeployRows` above the chat column: up to 2 lines (building, then the newest finished within 10 min); click opens `url` (http/https only). Hidden while a prompt card shows, offline, or on the terminal.
- Files: OrchestratorModels, OrchestratorRunsPure (DeployWings, wingKind), OrchestratorStream, OrchestratorManager, OrchestratorWings, OrchestratorExpanded, Tests, Snapshots. No new app-target files.

Checks: unit harness OK, also with `ORCH_DEPLOY_MOCK=1` (HTTP round trip against Tests/deploy-mock.py); Debug and Release (`./build`, ORCH_NO_SPARKLE, hardened runtime off) BUILD SUCCEEDED, Release copied to `./build/notch-rel/Clive.app`; `run.sh`, `--closed` (centre ok for every deploy wing) and `--idle` pass (closed 0.1-0.4%). Snapshots inspected: closed-31/34/36, 67.
