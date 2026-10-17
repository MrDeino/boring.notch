---
quick_id: 261017-dpl
date: 2026-10-17
---

# Quick 261017-dpl: Deploy wing and row

Goal: show a project deploy (building, live, failed) from the notch, from serve's optional `deploys` in GET /api/state and the SSE `deploy` event.

- Decode `deploys` as optional and lenient (old serve works).
- `DeployWings` (pure): building wing, 6 s live flash, failed sticky until click / notch open / next deploy. Priority: needs-you > finished run > deploy > working count.
- Open notch: `OrchestratorDeployRows` (recent deploys, click opens `url`).
- Tests: Tests/QuickDeployTests.swift (+ Tests/deploy-mock.py with `ORCH_DEPLOY_MOCK=1`); snapshots closed-30..38 (`run.sh --closed`) and 66..68.
