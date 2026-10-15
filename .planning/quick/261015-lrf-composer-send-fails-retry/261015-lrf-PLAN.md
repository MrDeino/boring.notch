---
quick_id: 261015-lrf
slug: composer-send-fails-retry
date: 2026-10-15
mode: quick
---

# Composer send fails with Retry while serve answers 200

## Root cause
`OrchestratorTranscriptStore.clearRealLine()` (the C-u that runs before every composer send) posts to the store's
own `base`/`session`, which are only set inside `store.refresh(base:session:chatRunning:)`. While the SSE stream is
up and the chat is running, `shouldFetchBlocks` skips that refresh (blocks arrive as events) except when a new prompt
appears, so in a notch that connected its stream at launch `base` stays nil. `clearRealLine` then returns false,
`sendText` cancels before posting anything, and the row turns `.failed` (Retry). Nothing reaches serve, which matches
"message didn't arrive". Not the confirm logic: a 200 already marks the row `.sent`; reconcile only drops a sent row
after 30 s, never fails it.

## Task 1: fix
- `clearRealLine()` posts with `OrchestratorManager.baseURL` + `OrchestratorManager.shared.session` (the same base and
  session as the text POST). Drop the store's unused `base`/`session` fields.

## Task 2: mock-serve check (never 4777)
- `Tests/send-mock.py` on 47999: GET /api/chat (settable), /api/state, /api/chat/blocks (never echoes), POST /api/chat
  logged, `__set`/`__fail` controls; self-exits.
- `run.sh --sendmock` (`Snapshots/SnapSend.swift`), using the real store/manager send path:
  1. idle send -> C-u then text posted, row `.sent`
  2. mid-turn send, no echo for 60 s -> row never `.failed`
  3. pending question card -> no text posted while the card is up, sent once it clears (nothing lost)
  4. serve 500 -> row `.failed` (Retry); Retry after serve recovers -> `.sent`
  RED before the fix (case 1 fails), GREEN after.

## Verify
swiftc harness OK; `run.sh --sendmock` OK; Release (ENABLE_HARDENED_RUNTIME=NO) + Debug builds succeed.
