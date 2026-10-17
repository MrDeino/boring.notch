# Quick 261017-wng: closed-notch wing clears when runs finish

- Finished-wing queue moved into pure `FinishedWings` (OrchestratorRunsPure.swift); `OrchestratorWingsModel` uses it.
- The model keeps the runs as published (`$runs` fires in willSet, when `manager.runs` was still stale) and derives working count, timing and the waiting label from them; the 4s expiry always recomputes. The manager's own publish still recomputes for chat status, prompt and attention.
- Test: `QuickWingsTests` drives running→done for one run, then several finishing together: working clears, each finished wing shows once.
- Checks: unit harness OK; Debug and Release (ORCH_NO_SPARKLE, hardened runtime off) BUILD SUCCEEDED; `--closed` passes. `--idle` fails on window-size gates (4/5-log-*) intermittently, identically on the unmodified HEAD; no CPU gate failed.
- Root cause not reproduced live; the stale-read ordering above is the one found by reading.
