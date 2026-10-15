---
phase: 08-phase-b-live-data-sse-push-streaming-caret-diff-expansion-su
plan: 02
subsystem: orchestrator-notch
tags: [sse, streaming, polling-fallback]
requires: [08-01]
provides: [SSELineParser, OrchestratorStreamEvent, streamHealthy, store.ingestBlocks, manager.streaming]
affects: [08-03]
key-files:
  created: []
  modified: [OrchestratorStream.swift, Tests/Phase8Tests.swift, OrchestratorManager.swift, OrchestratorChat.swift, Snapshots/Snap.swift]
requirements-completed: [LIVE-01]
completed: 2026-10-14
---

# Phase 8 Plan 02: SSE stream with polling fallback Summary

The manager consumes `GET /api/events` (state / chat / blocks events) through the same apply path as polling; 404, connection failure or 20 s without a line drops back to polling within ~2 s, with a fixed 30 s stream retry.

## Commits
- 68ea715: SSELineParser (dispatch on `data:` using last `event:`, blank lines never seen), OrchestratorStreamEvent, streamHealthy + harness asserts
- 4a91eba: `store.ingestBlocks(running:blocks:reset:)` (refresh now ends in it; calls `reconcile()` so pending rows clear on the SSE path, `reset` keeps `pending`), manager stream Task (own 45 s session, watchdog via task group), polling and notch-open refresh gated on `streaming`
- cfbf018: snapshot scenes 48/49 for the Running capsule "ctx 38%" and orange "ctx 86%" (needed a `calm` scene flag: no waiting runs, `live: true`)

## Adaptations vs the plan
- `applyChat` is async (08-01): in the stream path it skips the store's block fetch while `streaming && running`; blocks come from `blocks` events. A stopped chat (`running == false`) still clears rows via `ingestBlocks`.
- Chat event applies screen/input/prompt; ordering vs the `blocks` event is serve's choice. Blocks are ingested before a prompt only within `applyChat`'s own polling path.
- `refresh(fresh:)` after send/answer and the 2 s optimistic re-check still GET /api/chat + /api/state (not gated), so they see a fresh screen while streaming. Poll interval still counts running runs.
- Smart scroll untouched (view-level): reset events replace rows via the same `blocks` publish; pending rows and scroll stick logic are unchanged.
- `Manager.baseURL` is overridable via `ORCH_BASE` under `#if ORCH_SNAPSHOT` only, to test against a mock server.
- No caret scene: caret is 08-03's work; only the ctx capsule scenes were added.
- Build into /tmp/notch-dd.

## Verification
- swiftc harness OK; xcodebuild BUILD SUCCEEDED; snapshot normal, --hittest, --transition, --closed pass; scenes 48/49 viewed (Running | ctx 38% grey, ctx 86% orange).
- Mock SSE server on 47999 (self-exiting, then confirmed `lsof -i :47999` empty), consumer compiled via snapshot flags: 404 -> polling (loaded at 0.3 s); stream connected at 30.3 s (retry): runs=1, ctx 42, blocks ["1"]; second blocks event appended ["1","2"]; after silence the watchdog dropped streaming at ~23 s (5 s tick) and polling resumed (runs cleared by poll).
- `/api/events` on live serve 4777: GET returned 200 (stream is live; timed out by curl -m 3 as expected). No POSTs; app not launched.

## Deviations
None beyond the adaptations above.

## Human UAT
1. Today's serve (no /api/events): tab behaves as before Phase 8.
2. With /api/events: new chat rows appear within ~1 s without opening/closing the notch; runs/usage update; closed-notch wings stay live.
3. Kill serve while streaming: tab goes offline within a few seconds; restart: online again, streaming resumes within ~30 s.
4. Music: now-playing and controls unaffected while the stream is connected.

## Self-Check: PASSED
