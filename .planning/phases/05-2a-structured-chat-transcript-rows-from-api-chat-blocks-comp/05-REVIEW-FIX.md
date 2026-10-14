---
phase: 05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp
fixed_at: 2026-10-14T00:00:00Z
review_path: .planning/phases/05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp/05-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 7
skipped: 2
status: partial
---

# Phase 5: Code Review Fix Report

**Fixed at:** 2026-10-14
**Source review:** .planning/phases/05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9 (CR + WR)
- Fixed: 7
- Skipped: 2 (WR-01 and WR-02 conflict with locked decision D-10)

All fixes are in Phase 5 files only (OrchestratorChat.swift, OrchestratorTranscript.swift, Tests/Phase5Tests.swift). The test binary prints OK, and xcodebuild (derived data /tmp/notch-dd-p5) ends with BUILD SUCCEEDED.

## Fixed Issues

### CR-01: "C-u before send" does not guarantee an empty box

**Files modified:** `boringNotch/Orchestrator/OrchestratorChat.swift`
**Commit:** 16d2d20
**Status:** fixed: requires human verification
**Applied fix:** `clearRealLineIfNeeded()` now reads a fresh `/api/chat` screen instead of the inputLine from the last poll, which can be up to 2s old. If the box has text, it posts `C-u` once, then re-reads the screen every 150ms, up to 5 times. It returns false if the box is still not empty, and in that case `submit` does not send and keeps the notch draft. If no box is on screen (nil), it sends as before.

### CR-02: Enter during another POST wipes the line and sends nothing

**Files modified:** `boringNotch/Orchestrator/OrchestratorChat.swift`
**Commit:** dd43f35
**Applied fix:** I didn't touch the manager. The fix is a new `store.submit(_:)` that runs clear and send as one operation. It has its own `submitting` flag and refuses to start while `manager.sending` is true. It also checks `manager.sending` again after the clear. The view's `submit()` ignores Enter while `manager.sending || store.submitting`, matching the disabled send button. The send button is now also disabled while `store.submitting`. One gap is left, marked with a ponytail comment: a manager POST that starts between the C-u and the text still drops the send (the draft is kept). Closing it needs one manager operation, which can be done once the manager file is free to edit.

### WR-03: After /clear the new conversation is appended to the old one

**Files modified:** `boringNotch/Orchestrator/OrchestratorTranscript.swift`, `boringNotch/Orchestrator/OrchestratorChat.swift`, `boringNotch/Orchestrator/Tests/Phase5Tests.swift`
**Commit:** 00c55cc
**Status:** fixed: requires human verification
**Applied fix:** `blocksDiscontinuous` no longer requires 80 blocks: any non-empty since-response that shares no id with what we hold counts. I did not use the review's suggestion to reset straight away. Serve leaves out a found non-tool `since` block (orch.js `chatBlocks`), so after a user or prose block every normal new turn also has no overlap, and an immediate reset would wipe the history. The store now does one full fetch instead: if that fetch still contains our last block id, it merges normally (animated append); otherwise it resets. Tests: the old assertion "79 blocks, no overlap → false" now expects true for a 3-block no-overlap response, and a new assertion checks that an empty response gives false. The 15-poll full resync (R-02) stays, for a /clear that has no new blocks yet.

### WR-04: Terminal draft not pulled into the field is destroyed on send

**Files modified:** `boringNotch/Orchestrator/OrchestratorChat.swift`
**Commit:** 935d791
**Status:** fixed: requires human verification
**Applied fix:** If the box holds a terminal draft (`store.boxIsDraft`) that wasn't pulled in (`!fromTerminal`), Enter or Send no longer sends. Instead it puts the terminal draft in front of the notch text, shows the "from terminal · " prefix (D-09), keeps typing, and waits for a second Enter.

### WR-05: One failed blocks fetch flips the transcript to chatTail

**Files modified:** `boringNotch/Orchestrator/OrchestratorChat.swift`
**Commit:** 42ab111
**Applied fix:** Fetch failures now go through `fetchFailed()`. This falls back to chatTail straight away when there are no blocks yet (D-03 still holds before serve has the endpoint), and otherwise only after 3 consecutive failures. A successful fetch resets the counter.

### WR-06: `decodeChatBlocks` accepts any JSON object

**Files modified:** `boringNotch/Orchestrator/OrchestratorTranscript.swift`, `boringNotch/Orchestrator/Tests/Phase5Tests.swift`
**Commit:** 2ac9689
**Applied fix:** The envelope must now contain `blocks`, so `{}` and `{"error":…}` decode to nil and the view falls back. Bare arrays are still accepted. Tests: `{}` and `{"error":"boom"}` → nil.

### WR-07: Reset path keeps duplicate ids

**Files modified:** `boringNotch/Orchestrator/OrchestratorTranscript.swift`, `boringNotch/Orchestrator/Tests/Phase5Tests.swift`
**Commit:** 8ae3662
**Applied fix:** A reset now goes through the same id de-dup as the append path (`mergeChatBlocks([], incoming, reset: false, cap:)`). Test: resetting with `[t1, p1, t1r]` gives `["t1", "p1"]`, and t1 is updated in place.

## Skipped Issues

### WR-01: Ctrl-U always posts C-u to the real terminal

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:273-277`
**Reason:** Conflicts with locked decision D-10: "⌃U clears from cursor to line start locally AND POSTs `{key:"C-u"}`". The proposed fix (clear only locally, post only for a pulled-in terminal draft) changes designed behaviour. This needs a design decision; one option is to post only when `store.inputLine != nil`, so the key never goes into a picker screen.
**Original issue:** The notch field and the real box are separate buffers. ⌃U can kill an unrelated terminal draft, and it fires even when no input box is on screen.

### WR-02: Tab accept posts Tab to the live session

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:267-271`
**Reason:** Conflicts with locked decision D-10: "Tab or → accepts: fill the field and POST `{key:"Tab"}`". This needs a design decision before the POST is dropped.
**Original issue:** The posted Tab only changes the real session. Because the suggestion is a heuristic and can be up to 2s old, Tab can act on real text in the box.

---

_Fixed: 2026-10-14_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
