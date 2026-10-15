---
phase: 08-phase-b-live-data-sse-push-streaming-caret-diff-expansion-su
plan: 01
subsystem: orchestrator-notch
tags: [serve-contract, chat, capsule]
requires: []
provides: [ChatResponse.input/context/hasInputKey, resolveInput, applyScreen, manager.contextPercent]
affects: [08-02, 08-03]
key-files:
  created: [boringNotch/Orchestrator/OrchestratorStream.swift, boringNotch/Orchestrator/Tests/Phase8Tests.swift]
  modified: [OrchestratorModels.swift, OrchestratorManager.swift, OrchestratorChat.swift, OrchestratorStatusCapsule.swift, project.pbxproj, MERGE-MAP.md]
requirements-completed: [LIVE-04, LIVE-05]
completed: 2026-10-14
---

# Phase 8 Plan 01: input flag and context percent Summary

Serve's `input {text,suggested}` now drives the composer ghost/draft state (heuristic only when the key is absent), and `context.percent` shows as "ctx N%" in the Running capsule.

## Commits
- 3240c9a: ChatResponse input/context (lossy decode, hasInputKey), resolveInput, Phase8Tests, pbxproj entry
- 79408ea: split apply path (applyState / applyChat), store.applyScreen, capsule ctx label

## Adaptations vs the plan
- `ChatResponse.live` and `liveStatusFor(screen:live:)` already existed (quick tmq); extended the existing struct/extension rather than re-adding. `liveStatusFor` keeps serve `live` priority.
- `applyChat` is `async` (not synchronous): it publishes screen/input, then awaits the blocks ingest, then publishes the prompt, preserving "blocks ingested before a prompt is published". 08-02 can reuse it; SSE blocks events still need their own ingest path and a pending reconcile after each (store.reconcile exists).
- `refresh(base:session:chatRunning:)` lost its `screen:` param; the globalBoxIsDraft wrapper was removed.
- No change to refresh(fresh:), the 2s optimistic re-check or poll interval; Tab/arrow/Ctrl-U untouched.
- Build in /tmp/notch-dd (per orchestrator instructions), not -p8.

## Verification
swiftc harness OK (with OrchestratorStream.swift); xcodebuild BUILD SUCCEEDED; snapshot normal, --hittest, --transition, --closed all pass. No new PNG scene for the ctx label added; no POSTs, app not launched.

## Deviations
None beyond the adaptations above.

## Human UAT
1. With today's serve: composer ghost text, "from terminal" draft pull-in, Tab accept and Ctrl-U behave as before; capsule shows ctx only if serve sends context.
2. With the new serve: a suggestion shows as ghost; a typed terminal draft shows "from terminal"; capsule reads "Running | ctx N%", orange at >= 80%.
3. Music: now-playing and controls still work with the notch on the Orchestrator tab.

## Self-Check: PASSED
