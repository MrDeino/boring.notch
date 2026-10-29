---
quick_id: 261029-ey6
status: complete
---

# 261029-ey6: Orchestrator tab survives a slow or briefly unreachable serve

Root cause: every send or answer ran `refresh(fresh: true)`. That GETs /api/state with a 3 s / 5 s timeout, and a busy serve takes 2-10 s, so the request timed out. `applyOffline()` then wiped the prompt card, runs and live reply and showed the full-screen Offline view. Separately, every SSE connection's first blocks event replaced the chat, and three failed block fetches swapped the rows for the chatTail fallback (the flicker).

Changed:
- Manager session now 20 s request / 30 s resource. A refused connection still fails at once.
- Offline only before the first load, or after 3+ failures over 30 s (`goesOffline`). Until then `reconnecting` keeps everything on screen and the capsule shows "Reconnecting".
- `postCode` handles every POST. A refused connection (never reached serve) is the only case resent automatically. Composer rows wait while stale and are requeued when refused. A typed card answer waits with "Waiting for the orchestrator…" and goes once serve is back. Stale data never counts as landed or moved.
- SSE connects with `?since=<last block id>` and appends (`ingestSince`, shared with polling). The poll's full resync merges unless our last block is gone. Failed block fetches keep the rows we hold.
- Tests: QuickSlowTests (pure). Snapshots `--slowmock` against Tests/slow-mock.py on 47999: 10 s /api/state stays online; with serve killed the chat and card stay and the typed answer waits; with serve back the answer is posted exactly once; a stream reconnect sends since=p2 and the chat never shrank.
- Regressions: harness OK; sendmock, keymock, askmock, default snapshots OK.

Audit (ponytail), applied on these paths: dropped the `postKey` wrapper (the queue calls `postCode`) and the unused `limit:` parameter on `streamHealthy`.
Not applied (off path): unused tokens in OrchestratorTokens.swift (`R.dropdown`, `R.pill28`, `S.padTop`, `S.padH`, `S.padBottom`, `S.gapL`, about 6 lines).

Builds: Debug `build/Build/Products/Debug/Clive.app`; Release (ENABLE_HARDENED_RUNTIME=NO) `build/notch-rel/Clive.app`. Both BUILD SUCCEEDED.
