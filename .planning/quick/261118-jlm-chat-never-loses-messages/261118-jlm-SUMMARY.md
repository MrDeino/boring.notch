---
quick_id: 261118-jlm
status: complete
commit: 979a400
---

# Quick 261118-jlm: chat never loses, reorders or drops messages

Fixes audit B1-B4 (top 10 #1, #2, #3, #8).

- **B1 late full fetch:** the store snapshots its blocks before each full GET. `mergeFullFetch` treats the result as a /clear only if it lacks the snapshot's last block; blocks the stream added or updated during the GET keep their newer copy (a finished tool no longer goes back to "running").
- **B2 gap fill:** `mergeChatBlocks` inserts each unknown block after the incoming block before it (a leading one before the first held block it precedes), so `[A, C] + [A, B, C]` gives `[A, B, C]`.
- **B3 mid-turn send:** `reconcilePending(idleSince:)`. A `.sent` row is never dropped while a turn is live (working, or a card up). The 30 s starts at the later of send and turn end. After that it is still dropped silently (kept for slash commands, whose block text differs). The upgrade is serve echoing a client id.
- **B4 running:false:** no path clears the blocks any more. The stream's extra clear is gone, `refresh` only sets `needsFull`, and a stopped chat keeps its rows (the next session's full fetch replaces them as a /clear). When `running` goes false→true while streaming, `applyChat` refreshes. A pending full resync runs even with the notch closed.

Checks: the swiftc harness prints OK, with the new `Tests/QuickJlmTests.swift` (synthetic blocks). Debug and Release (`ENABLE_HARDENED_RUNTIME=NO`, ad-hoc) BUILD SUCCEEDED into `./build/dd-Debug` and `./build/dd-Release`.

Harness files: Models, Pure, Transcript, PromptParse, RunsPure, Ask, Stream, BackgroundModel, KeyQueue, ComposerInput + `Tests/*.swift`.

## Check by hand
1. Answer a prompt card while a full fetch is slow. The prose Claude writes right after it stays.
2. Send a message while a long turn runs (>30 s). The row stays "sent" until the turn ends, then becomes the real user row in order.
3. Stop the chat (or wait for a serve hiccup). The history stays visible. Start it again: the history reloads. A new session replaces the old rows.
4. /clear: the old rows are replaced, not merged.

## Follow-up: long drafts in the composer (commit after 62cfcb6)

`TextField(axis: .vertical).lineLimit(1...5)` clipped the first lines of a long draft with no way to scroll to them. `OrchestratorComposerField` now wraps an uncapped field in a `ScrollView` that grows with the text up to 8 lines (`maxHeight` 128 pt), then scrolls. On every selection change of the focused field editor (typing, arrows, click, paste) and after each height change, `scrollCaretIntoView` scrolls the caret's line into the ScrollView. The field editor's own scrolling stops at the field. Submit, Esc and focus handling are unchanged.

Test: `Tests/QuickGrowTests.swift` (real AppKit, offscreen panel): types 20 lines; the box caps at 8 lines, the caret stays visible at the end, and moving it to the start scrolls line 1 back into view. Harness OK; Debug and Release BUILD SUCCEEDED in ./build.

Note: the snapshot harness (`run.sh`, scene 38) has no real NSScrollView, so it draws the overflowing text unclipped. Judge this in the app, not in that PNG.

### Check by hand
1. Paste a 20-line message. The box grows to about 8 lines, then scrolls. The scroll wheel reaches line 1.
2. Keep typing at the end. The caret line stays visible.
3. ⌘↑ (or click line 1 after scrolling up), then select and edit the first words.
4. Enter still sends, and Shift/Option-Enter behave as before. Esc still leaves typing. The notch grows with the box and shrinks back after sending.
5. Check the expanded level too, and the "from terminal ·" label lining up with the first line.
