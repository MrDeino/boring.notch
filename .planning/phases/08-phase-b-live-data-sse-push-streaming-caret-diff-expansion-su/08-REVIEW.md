---
phase: 08-phase-b-live-data-sse-push-streaming-caret-diff-expansion-su
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - boringNotch.xcodeproj/project.pbxproj
  - boringNotch/Orchestrator/OrchestratorChat.swift
  - boringNotch/Orchestrator/OrchestratorManager.swift
  - boringNotch/Orchestrator/OrchestratorModels.swift
  - boringNotch/Orchestrator/OrchestratorStatusCapsule.swift
  - boringNotch/Orchestrator/OrchestratorStream.swift
  - boringNotch/Orchestrator/Snapshots/Snap.swift
  - boringNotch/Orchestrator/Tests/Phase8Tests.swift
  - boringNotch/Orchestrator/Tests/main.swift
findings:
  critical: 0
  warning: 5
  info: 3
  total: 8
status: issues_found
---

# Phase 8: Code Review Report

**Reviewed:** 2026-10-14
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

No crashes or security problems found. The stream lifecycle is mostly sound: the group cancels the sibling task, `streaming` is reset by `defer`, and there is only one stream task and one poll task. The real defects are interleaving races in `applyChat` and a caret that is not repositioned when text changes. Nothing was built or run. The concurrency findings come from reading the code.

## Structural Findings (fallow)

None provided.

## Narrative Findings (AI reviewer)

## Warnings

### WR-01: Stale applyChat can overwrite a newer prompt (SSE vs poll/refresh(fresh:) interleave)

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:236-258`
**Issue:** `applyChat` now suspends (`await ...refresh`) between computing `po`/`pc`/`s` and publishing `promptOptions`/`prompt`/`liveStatus`/`chatLive`.
- Whenever `newPrompt` is true, or the poll path runs, the suspension happens at an actor-reentrant point.
- Two other callers can run `applyChat` concurrently with the SSE loop. One is the poll `load()`, which is gated only by `streaming` at loop-top, so a poll already in flight when the stream connects still finishes. The other is `post*`/`pressKeys` → `refresh(fresh: true)`, which is not gated by `streaming` at all.
- The older call can resume after a newer SSE `chat` event has applied. It then writes its older `prompt`/`promptOptions` over the fresh state. The result is a stale or resurrected prompt card, or one that disappears until the next change. Serve only re-sends `chat` when its JSON changes, so the wrong state can persist.
- `chatRunning`, `screen` and `contextPercent` are written before the await, so the same stale call also rolls those back.

**Fix:** Serialise `applyChat` with a monotonic token, or skip stale results.
```swift
private var applySeq = 0
private func applyChat(_ r: ChatResponse) async {
    applySeq += 1; let mine = applySeq
    ... // sync part
    if shouldFetchBlocks(...) { await ...refresh(...) }
    guard mine == applySeq else { return } // a newer chat payload already applied
    ... // publish prompt/liveStatus/chatLive
}
```
Alternatively, when `streaming`, make `load()`/`refresh(fresh:)` feed only through one serial path.

### WR-02: Caret not repositioned when text changes without a layout pass

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:1010-1032` (position set only in `layout()`), `:1139-1150` (`apply`)
**Issue:** The caret position is computed only in `layout()`. `caretOn`'s `didSet` sets `needsLayout` only when the flag toggles. While streaming, `apply` calls `textStorage.setAttributedString(text)` on every update, but nothing marks the view for layout.
- If the new text grows within the same frame (a wrapped paragraph whose last line gets longer, or a multiline row where the height is unchanged), AppKit may not call `layout()`. The caret then sits at the old end of text until the frame changes.
- `lineFragmentUsedRect(forGlyphAt:)` can also read stale layout if glyphs are not yet laid out for the container.
- Related: the blink animation is added only on first attach, so toggling Reduce Motion mid-run is not honoured. This is minor.

**Fix:** In `apply`, after replacing the storage text, add `if v.caretOn { v.needsLayout = true }`. In `layout()`, call `lm.ensureLayout(for: tc)` before reading rects.

### WR-03: Dead/hung stream is not guaranteed to be torn down; polling stays gated

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:174-211`
**Issue:** The watchdog only wins if the `for try await line in bytes.lines` child responds to cancellation. `withTaskGroup` waits for all children after `cancelAll()`.
- If `AsyncBytes` iteration does not abort promptly on a silently dead socket, `runStream` does not return. `streaming` stays true and polling and the notch-open refresh stay suppressed (`start()` loop and `notchOpen.didSet`). The UI then shows frozen data, with no `offline` flip, until the 45 s request timeout.
- The behaviour is stated as 20 s fallback in D-02, so the fallback is not guaranteed.
- The watchdog's `guard let self` plus the `try? Task.sleep` loop is fine.

**Fix:** Set `streaming = false` directly in the watchdog when it trips, before `group.next()` returns. The `defer` also covers normal exit, and the poll loop then resumes immediately. Optionally keep a handle to the URLSession data task, or use a per-stream `URLSession` that is `invalidateAndCancel()`ed on watchdog trip, so the iterator is guaranteed to terminate.

### WR-04: SSE `chat` with `running == false` triggers a redundant double teardown and ignores pending

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:187-190` with `OrchestratorChat.swift:73-78`
**Issue:** `applyChat` already fetches and clears blocks when `running` is false, because `shouldFetchBlocks` returns true. The handler then calls `ingestBlocks(running: false, [], reset: true)` again. Both paths clear `blocks` and set `needsFull`/`fallback`, so it is harmless. It is redundant, though, and it makes a network GET `/api/chat/blocks` per stop event, which is only to be overwritten. Also, while chat is down no `blocks` event may arrive, so a later start has the `first`/`reset` assumption (`first` is per connection, not per chat session) resting on serve sending `reset:true` after a restart. If serve sends a plain delta with no reset after a restart, stale rows from the old transcript could merge. The store was cleared by the stop path, so risk is low but the dependency on serve is unstated.
**Fix:** Drop the extra `ingestBlocks` in the handler, or skip the GET in `applyChat` when `running == false`. Reset `first = true` when a `chat` event flips `running` false to true.

### WR-05: Stream/poll tasks are never cancelled and `start()` can leak the stream on repeat calls

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:139-166`
**Issue:** There is no `stop()` that cancels `pollTask`/`streamTask`. Both are guarded against duplicates only by `== nil`. Today `start()` is called once (`boringNotchApp.swift:283`), so this is latent. The stream retry loop catches errors silently (`catch {}` in the child) and retries every fixed 30 s with no jitter and no logging. Both make a persistent failure invisible. Also, the 30 s retry sleep means that after a brief server restart the app polls for up to 30 s instead of reconnecting quickly.
**Fix:** Add `stop()` that cancels and nils both tasks. Reconnect fast (for example 2 s) after a stream that was previously healthy, and back off to 30 s only after consecutive failures.

## Info

### IN-01: Tool row diff toggle state persists across expand/collapse

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:715-722, 906`
**Issue:** `diffOpen` is kept when the transcript expands, so after collapsing back the inline card reappears open. The header button in the expanded card folds `folded`, while in the non-expanded one it clears `diffOpen`; the two states are inconsistent. Tap isolation looks correct: the card and the toggle button both swallow the tap, so they do not reach the container's `expandChat`.
**Fix:** Optional. Unify into one state or reset `diffOpen` when `expanded` changes.

### IN-02: Magic numbers and silent decode failures in SSE parser

**File:** `boringNotch/Orchestrator/OrchestratorStream.swift:42,48`
**Issue:** `2_000_000` and the 20 s limit are inline. A malformed event is dropped via `try?` with no signal, so a serve schema drift would look like a silent stall until the watchdog does not trip, because pings keep the stream "healthy".
**Fix:** Name the constants. Consider counting consecutive decode failures and dropping to polling.

### IN-03: Snapshot global mutable state in production source

**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:706-708`
**Issue:** `var orchSnapDiffOpen` is a global gated by `ORCH_SNAPSHOT`, so it is not compiled into release builds. It is fine, but it is a global mutable var read in a `@State` initialiser. This is test scaffolding embedded in the view.
**Fix:** None required.

---

_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
