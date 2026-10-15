---
quick_id: 261015-lrf
slug: composer-send-fails-retry
date: 2026-10-15
status: complete
---

# Composer send fails with Retry: fixed

## Root cause
Every composer send first clears Claude's input box (C-u) through `OrchestratorTranscriptStore.clearRealLine()`. That
posted to the store's own `base`/`session`, which were only set by `store.refresh(base:session:chatRunning:)`. With
the SSE stream connected and the chat running, chat payloads skip that refresh (`shouldFetchBlocks`), apart from a
payload carrying a new prompt. So a notch that connected its stream at launch had `base == nil`: `clearRealLine`
returned false, `sendText` gave up before posting, and the row went `.failed` (Retry). serve never saw a request,
which is why nothing arrived. Sends started working only after a question/permission prompt had appeared once
(that refresh set `base`). The confirm/timeout logic was not involved: a 200 already marks the row `.sent`, and
an unechoed sent row is dropped after 30 s, never failed.

## Fix
`clearRealLine()` uses `OrchestratorManager.baseURL` + `OrchestratorManager.shared.session`, the same as the text
POST. The store's `base`/`session` fields are gone (nothing else read them).

## Check
`ORCH_BASE=http://127.0.0.1:47999 boringNotch/Orchestrator/Snapshots/run.sh --sendmock` (new `SnapSend.swift` +
`Tests/send-mock.py`, the real store/manager send path with streaming simulated; never 4777):
- RED before the fix: idle and mid-turn rows `.failed`, nothing posted.
- GREEN after: idle -> C-u + text posted, `.sent`; mid-turn, no echo for 60 s -> never `.failed`; pending question
  card -> nothing typed while it's up, sent once it clears; serve 500 -> `.failed`, Retry after recovery -> `.sent`.
- swiftc unit harness OK; `run.sh --askmock` OK.
- Debug (`/tmp/notch-dd`) and Release with ENABLE_HARDENED_RUNTIME=NO (`/tmp/notch-rel`): BUILD SUCCEEDED.

Ran directly (no planner/executor agents): root cause was found while reading the code, so the fix is small.
Running notch (/tmp/notch-current) was not launched or quit. UAT: send from the notch composer while idle and mid-turn.
