---
phase: 05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - boringNotch/Orchestrator/OrchestratorTranscript.swift
  - boringNotch/Orchestrator/OrchestratorChat.swift
  - boringNotch/Orchestrator/Tests/Phase5Tests.swift
findings:
  critical: 2
  warning: 7
  info: 6
  total: 15
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-10-14
**Depth:** standard (plus a read-only look at the callers in OrchestratorManager.swift / OrchestratorModels.swift and at serve's `chatBlocks` in orch.js, to check what `since` means)
**Files Reviewed:** 3
**Status:** issues_found

## Summary

The pure core (decode, merge, parsers) is tidy and well tested. The key monitor's lifecycle is sound: it is installed on focus, removed on blur and on onDisappear, and filtered to `fieldFocused` and the typing panel, so it doesn't swallow keys in other windows or tabs, and it can't affect music. The risky part is the composer's interaction with the real Claude Code input box. `C-u` is treated as "clear the box", but it is a kill-to-line-start. It is posted outside the manager's `sending` gate, and it fires regardless of whose text is in the box. Tab is also posted to the live session, which isn't needed. On the transcript side, serve's `since` falls back to the last 80 blocks when the id is unknown, so after `/clear` the new conversation is appended to the old one instead of replacing it.

## Critical Issues

### CR-01: "C-u before send" does not guarantee an empty box, so a corrupted message can be sent

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:80-82, 336`; `boringNotch/Orchestrator/OrchestratorTranscript.swift:96-103`
**Issue:** `clearRealLineIfNeeded()` posts a single `C-u` and then `sendText` types the notch text into the box. In Claude Code's input, Ctrl-U deletes from the cursor back to the start of the *current line*. It does not clear the whole buffer. So:
- If the real box holds a multi-line draft (shift-enter or `\` newlines), only the last line is removed. `parseInputLine` joins all lines with spaces (lines 96-103), so the app can't tell. The earlier lines stay and are sent together with the notch text.
- If the terminal cursor is not at the end of the line (the user arrowed left in the terminal), the text after the cursor stays. The notch text is inserted in front of it, and the combined string is sent with Enter.

In both cases the orchestrator receives a message the user never wrote. Nothing checks for this.
**Fix:** Check that the box is empty before typing. A minimal version re-reads the screen after the clear and aborts if anything is left:
```swift
func clearRealLineIfNeeded(base: URL, session: URLSession) async -> Bool {
    guard let l = inputLine, !l.isEmpty else { return true }
    await postKey("C-u")
    // re-fetch /api/chat and confirm the box is now empty
    guard let (d, _) = try? await session.data(from: base.appendingPathComponent("api/chat")),
          let r = try? JSONDecoder().decode(ChatResponse.self, from: d) else { return false }
    return (parseInputLine(screen: r.screen ?? "") ?? "").isEmpty
}
// submit(): if await store.clearRealLineIfNeeded(...) { if await manager.sendText(t) { ... } }
```
Another option is to add an end-of-buffer key (for example `C-e` repeated, or a dedicated serve "clear box" action) to `allowedKeys` and send it before `C-u`.

### CR-02: Pressing Enter while another POST is in flight wipes the terminal line and sends nothing

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:182, 332-337` (with `OrchestratorManager.swift:66`)
**Issue:** The send button is disabled while `manager.sending`, but `.onSubmit { submit() }` is not gated. `submit()` runs `store.clearRealLineIfNeeded()`, which calls `sendOrchestratorPost` directly and so bypasses the manager's `sending` guard. It then calls `manager.sendText(t)`, and `post()` returns `false` straight away because `sending` is true (for example, `pressOption`'s POST or a previous send is still running). Result: `C-u` has already destroyed whatever was in the real box (possibly a terminal draft the user typed), the message is not sent, and typing has already been stopped. The same ungated path can also slip a `C-u` in between another in-flight key sequence.
**Fix:** Gate `submit()` on `manager.sending`, and run the clear and the send as one manager operation under the same `sending` flag:
```swift
private func submit() {
    let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, !manager.sending else { stopTyping(); return }
    ...
}
// and in OrchestratorManager: func sendReplacingBox(_ s: String, clear: Bool) async -> Bool
// { guard !sending ...; sending = true; if clear { post C-u }; post text }
```

## Warnings

### WR-01: Ctrl-U in the notch always posts `C-u` to the real terminal, even when there is no box or the text there isn't the notch's

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:273-277`
**Issue:** The monitor posts `C-u` on every Ctrl-U, without the `inputLine` check that `clearRealLineIfNeeded` uses. The notch field and the real box are separate buffers, so clearing the notch text also kills an unrelated draft the user typed in the terminal. It also fires when `inputLine == nil`, meaning no input box is on screen (rewind picker after Esc-Esc, `/resume` list, any other TUI screen), and the key goes into whatever has focus there. The hint says "⌃U clear line", which reads as the notch line.
**Fix:** Clear only the notch field locally. If the real box has to be cleared at all, do it only when its content belongs to the notch:
```swift
if event.keyCode == 32, mods == .control {
    ...
    if fromTerminal, let l = store.inputLine, !l.isEmpty { Task { await store.postKey("C-u") } }
```

### WR-02: Tab/right-arrow accept posts `Tab` to the live Claude session, which isn't needed and can have side effects

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:267-271`
**Issue:** The accept already copies the suggestion into `draft`, and every send clears the real box first. So the posted `Tab` only changes the real session. `suggestion` comes from a poll up to 2s old (10s when the notch was just opened), and it is a heuristic (see IN-04). If the box text is not really a suggestion, for example text the user just typed or pasted in the terminal, Tab triggers Claude Code's own Tab action on real content (autocomplete or a mode toggle, depending on version). This is a POST fired by a local keystroke with no user-visible effect.
**Fix:** Drop the `Task { await store.postKey("Tab") }` line. The accept is purely local, and the send path already handles the real box.

### WR-03: After `/clear` or a new transcript, the new conversation is appended after the old one

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:47-48, 62-63`; `boringNotch/Orchestrator/OrchestratorTranscript.swift:75-80`
**Issue:** serve's `chatBlocks` (orch.js:536-539) returns the last 80 blocks when the `since` id is not found. Right after `/clear` the new transcript has fewer than 80 blocks, so `blocksDiscontinuous` returns false (`count >= 80` fails). `mergeChatBlocks` then appends the new conversation to the stale one, with animation. From then on `since` is the new last id, so it stays mixed until the `polls % 15` full resync (and `polls` only advances while the notch is open). The ponytail comment says `/clear` is "invisible" to `since`, but in fact it is mis-merged.
**Fix:** A since-response that shares no id with `existing` and is non-empty already shows that `since` was not found. Serve always includes the tool run ending at `since`, and when `since` is found and nothing is new it returns `[]`. Drop the `>= 80` condition:
```swift
func blocksDiscontinuous(sinceSent: Bool, incoming: [ChatBlock], existing: [ChatBlock]) -> Bool {
    guard sinceSent, !incoming.isEmpty else { return false }
    let have = Set(existing.map(\.id))
    return !incoming.contains { have.contains($0.id) }
}
```
Caveat: if `since` is a prose block, found, and followed by new blocks, the response does not include it, so a stricter signal is needed. Have serve echo `sinceFound: Bool` (or return the `since` block itself) and reset when it is false. Add a test for the fewer-than-80, unknown-since case.

### WR-04: Terminal draft not pulled into the field is silently destroyed on send

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:251-257, 80-82, 336`
**Issue:** The pull-in only happens on focus, and only if `draft.isEmpty` and `store.boxIsDraft` are both true at that moment. If the notch field already held text, or the user typed in the terminal after focusing, the terminal draft is never shown in the field. Every send still runs `clearRealLineIfNeeded`, which kills it. The user loses text they typed elsewhere, with no indication.
**Fix:** When `store.boxIsDraft && !fromTerminal && store.inputLine nonEmpty` at submit time, don't clear silently. Either prepend or show the terminal draft and require a second Enter, or skip the send and show a "terminal has a draft" tag. At minimum, gate the clear on `fromTerminal || !store.boxIsDraft`.

### WR-05: A single failed blocks fetch flips the whole transcript to chatTail lines, which flickers

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:49-54`
**Issue:** Any one failure (3s timeout, a transient 500 while serve re-reads the 4 MB transcript, or a decode miss) sets `fallback = true`. The view then swaps from structured rows to raw chatTail lines, and back on the next success 2s later. Blocks already held are still valid.
**Fix:** Only fall back when there are no blocks, or after N consecutive failures:
```swift
failures += 1
if blocks.isEmpty || failures >= 3, !fallback { fallback = true }
return
// on success: failures = 0
```

### WR-06: `decodeChatBlocks` accepts any JSON object as a valid empty response

**File:** `boringNotch/Orchestrator/OrchestratorTranscript.swift:49-58`
**Issue:** `ChatBlocksEnvelope` has both fields optional, so `{}`, `{"error":"..."}` or any other object decodes successfully as `(nil, [])`. On a full fetch this resets `blocks` to `[]` and sets `fallback = false`, so the pane goes blank instead of falling back to chatTail. An older serve or proxy that answers 200 with an error object will show an empty transcript.
**Fix:** Require the `blocks` key: `guard let b = e.blocks else { return nil }` (or make `blocks` non-optional in the envelope).

### WR-07: Reset path keeps duplicate ids, which breaks `ForEach` identity

**File:** `boringNotch/Orchestrator/OrchestratorTranscript.swift:65, 27-28`; `OrchestratorChat.swift:119`
**Issue:** `mergeChatBlocks(reset: true)` returns `incoming` unchanged. The non-reset path de-duplicates by id, but the reset path (which handles every full fetch) does not. Duplicate ids can come from repeated JSONL lines, for example after resume or compaction copies history. Integer and string ids also collide: `7` and `"7"` both become `"7"`. `ForEach(store.blocks.suffix(maxRows))` then has duplicate IDs, which SwiftUI treats as undefined behaviour (rows dropped or mis-animated).
**Fix:** Run the reset path through the same de-dup: `if reset { return (Array(mergeChatBlocks([], incoming, reset: false).blocks.suffix(cap)), false) }`.

## Info

### IN-01: Unused `name` parameter
**File:** `boringNotch/Orchestrator/OrchestratorTranscript.swift:131`
**Issue:** `toolTargetDisplay(name:target:)` never reads `name`. **Fix:** Drop it, or use it.

### IN-02: "Tab accept" chip shows when Tab can't work
**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:226`
**Issue:** The accessory shows whenever `suggestion != nil`, but the monitor only exists while `fieldFocused`. When the field is not focused, the hint is false. **Fix:** Add `manager.wantsKeyboard` to the condition.

### IN-03: "▸ diff" looks clickable but has no action
**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:376`
**Issue:** It looks like a disclosure control but does nothing (diff hunks are decoded and never shown). **Fix:** Hide it until the diff view lands.

### IN-04: Draft heuristic misreads the first terminal keystrokes as a suggestion
**File:** `boringNotch/Orchestrator/OrchestratorTranscript.swift:109-114`
**Issue:** Box text seen for the first time is always classed as a suggestion, so a short word or a paste typed in the terminal within one poll is offered as ghost text. The same happens to a draft restored after a prompt card (`inputLine` goes nil and then reappears). This is acknowledged as Phase A, but it is also what makes WR-02 and WR-04 risky. **Fix:** Phase 8's `suggested` flag. Until then, avoid irreversible actions based on it.

### IN-05: Chat stop doesn't reset `fallback`/`polls`
**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:35-38`
**Issue:** `blocks = []` but `fallback` can stay `false`, so a restarted chat briefly shows an empty pane instead of chatTail until the first fetch. **Fix:** Set `fallback = true` there too.

### IN-06: Store merge/reset decisions are untested
**File:** `boringNotch/Orchestrator/Tests/Phase5Tests.swift:40-57`
**Issue:** Tests cover the pure helpers but not the cases above: unknown `since` with fewer than 80 blocks, `{}` envelope, duplicate ids in a reset, and Read with an empty result giving "1 line" (`toolResultDisplay`, lines 141-143). **Fix:** Add one assert per case once the fixes land.

---

_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
