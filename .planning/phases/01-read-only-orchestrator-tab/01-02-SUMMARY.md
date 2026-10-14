---
phase: 01-read-only-orchestrator-tab
plan: 02
subsystem: orchestrator-tab
tags: [swiftui, models, prompt-detection]
requires: [01-01]
provides: [runs strip, 5h/7d usage bars, detectPrompt, OrchestratorManager.needsAttention]
key-files:
  modified:
    - boringNotch/Orchestrator/OrchestratorModels.swift
    - boringNotch/Orchestrator/Tests/main.swift
    - boringNotch/Orchestrator/OrchestratorManager.swift
    - boringNotch/Orchestrator/OrchestratorView.swift
decisions:
  - "needsAttention = any run waiting OR chat prompt detected; reads no music/tab/notch state"
  - "detectPrompt format is assumed (numbered options with a marker glyph, 2+ options); refine in Phase 2 from real captures"
metrics:
  completed: 2026-10-14
  tasks: 2
---

# Phase 1 Plan 02: Runs, usage, attention Summary

Orchestrator tab now shows up to 3 runs (live first), 5h/7d usage bars with reset times beside the chat tail; manager fetches /api/chat and /api/state concurrently (GET only) and exposes `promptOptions` and `needsAttention`.

## Commits
- test(01-02): failing state model / detectPrompt tests
- feat(01-02): state models, stripRuns, detectPrompt
- feat(01-02): runs strip, usage bars, needsAttention

## Verification
- xcodebuild ad-hoc: BUILD SUCCEEDED; swiftc test: OK
- Only files under boringNotch/Orchestrator touched; no music code, no POST/httpMethod.
- Live `GET /api/state` returned JSON (serve running).

## Deviations from Plan
None.

## Known Stubs
None.

## Manual run instructions (for the user)
1. Quit the installed Boring Notch (menu bar > Quit). Do not delete /Applications/boringNotch.app.
2. `open "/tmp/notch-dd/Build/Products/Debug/Boring Notch.app"`
3. Open the notch, pick Orchestrator: chat tail, up to 3 runs, 5h/7d bars; updates about every 2s.
4. Stop `node orch.js serve`: tab shows "orchestrator offline" within seconds; restart and it recovers.
5. Play music: Home controls and closed-notch activity should be unchanged (an ad-hoc rebuild may reset macOS privacy grants; re-grant if prompted).
6. Quit it and relaunch the installed app.

## Self-Check: PASSED
