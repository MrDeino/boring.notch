---
quick_id: 261118-jlm
mode: quick
---

# Quick 261118-jlm: chat never loses, reorders or drops messages

Fix audit findings B1, B2, B3, B4 (.planning/audits/2026-11-clive-audit.md, top-10 #1, #2, #3, #8).

## Task 1: pure logic (OrchestratorTranscript.swift, OrchestratorStream.swift) + tests
- `mergeChatBlocks`: insert an unknown block after the incoming block before it (leading one before the first held incoming block, else append), so a filled gap lands in place (B2).
- New `mergeFullFetch(current:snapshot:incoming:)`: /clear only when the fetch lacks the snapshot's last block (taken before the await); blocks the stream added or changed during the fetch win (B1).
- `reconcilePending(idleSince:)`: no stale drop while a turn is live; 30 s counts from the later of send and turn end (B3).
- `shouldFetchBlocks(cameBack:)`: running false→true while streaming fetches (B4).
- Tests: `Tests/QuickJlmTests.swift`, synthetic blocks.

## Task 2: wiring (OrchestratorChat.swift, OrchestratorManager.swift)
- Store: snapshot before each full fetch → `ingestFull` uses `mergeFullFetch`; running:false never clears blocks, only sets `needsFull`; a pending resync runs with the notch closed; `noteTurn(live:)` tracks `idleSince`.
- Manager: drop the stream's extra clear on `running:false`; `cameBack` refresh; `updateLiveReply` feeds `noteTurn(live: working || card up)`.

Verify: swiftc harness prints OK; Debug and Release (ENABLE_HARDENED_RUNTIME=NO) build into ./build.
