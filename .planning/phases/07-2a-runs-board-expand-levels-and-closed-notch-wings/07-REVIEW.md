---
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - boringNotch/ContentView.swift
  - boringNotch/Orchestrator/OrchestratorCompact.swift
  - boringNotch/Orchestrator/OrchestratorExpand.swift
  - boringNotch/Orchestrator/OrchestratorExpanded.swift
  - boringNotch/Orchestrator/OrchestratorModels.swift
  - boringNotch/Orchestrator/OrchestratorRunsBoard.swift
  - boringNotch/Orchestrator/OrchestratorRunsPure.swift
  - boringNotch/Orchestrator/OrchestratorStatusCapsule.swift
  - boringNotch/Orchestrator/OrchestratorTerminal.swift
  - boringNotch/Orchestrator/OrchestratorWings.swift
  - boringNotch/Orchestrator/Tests/Phase7Tests.swift
findings:
  critical: 1
  warning: 6
  info: 6
  total: 13
status: issues_found
---

# Phase 7: Code Review Report

**Reviewed:** 2026-10-14
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

I reviewed the diff `5a22cc9..HEAD` for the runs board, expand levels, terminal panel, rail and wings. I also checked the code it calls in `OrchestratorManager.swift`, `OrchestratorView.swift`, `OrchestratorChat.swift` and serve's `/api/state` shape in `orch.js`, all read-only.

What checks out:
- **Music:** the wings branch comes after `MusicLiveActivity` in the closed-notch chain, so music still wins. The needs-you dot is a hit-test-disabled overlay that does not change layout. `ContentView` observes only `OrchestratorWingsModel.kind`, not the manager.
- **No POST without a tap:** the only new POSTs (`sendText` and `startChat` in `OrchestratorAskInChatButton`) run from a Button action. Keyboard shortcuts, wings and the rail never POST.
- **Lifetimes:** the key monitor is installed once in the singleton's `init`, captures `self` weakly and never stacks, so it does not leak. Combine sinks are stored on singletons. The finished-wing `Task` is guarded by a generation counter.

What is broken: ⌘↓ and ⌘↑ can never fire, the rail's waiting baseline is reset wrongly after every offline blip, and the wing animations stop after the first time they appear.

## Critical Issues

### CR-01: ⌘↓ / ⌘↑ shortcuts never match, because arrow keys carry the `.numericPad` and `.function` flags

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:66` (with `OrchestratorRunsPure.swift:142-149`)
**Issue:** `cmd` is computed as `modifierFlags.intersection(.deviceIndependentFlagsMask) == .command`. AppKit always sets `.numericPad` and `.function` on arrow-key events, and both flags are inside `deviceIndependentFlagsMask`. So for ⌘↓ the flags are `[.command, .numericPad, .function]` ≠ `.command`, `shortcut(...)` returns nil, and `.deeper`/`.back` never trigger. This breaks the RUN-02 keyboard triggers, and the header button's help text ("⌘↑") advertises a shortcut that doesn't work. Caps Lock also breaks ⌘T and ⌘\ the same way. The pure tests pass because they hand `commandOnly: true` straight in, so they never exercise the flag logic.
**Fix:**
```swift
let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
let cmd = flags == .command
```
Add one harness case for the flag logic, for example by moving the mask into a pure `isCommandOnly(_ raw: UInt)` helper and asserting `[.command, .numericPad, .function]` is true.

## Warnings

### WR-01: Rail auto-opens on reconnect (and at launch) for runs that were already waiting

**File:** `boringNotch/Orchestrator/OrchestratorExpanded.swift:23-30`, `OrchestratorRunsPure.swift:157-160`
**Issue:** The baseline is meant to be `nil` until the first real runs arrive. But when `refresh()` fails, the manager sets `offline = true` and then `runs = []`. When it reconnects, it sets `offline = false` before assigning the new runs. `combineLatest` therefore emits `([], false)`, which sets `previous = [:]`. The next emission then treats every run that is already waiting as newly waiting: `newlyWaiting(old: [:], …)` is true, and the test at Phase7Tests.swift:101 asserts this. As a result, any 3s timeout or serve restart pops open a rail the user collapsed. The same happens at launch, because `runs` starts as `[]` with `offline == false`.
**Fix:** Ignore emissions until the manager has loaded, and don't seed the baseline from an empty list right after offline. For example:
```swift
m.$runs.combineLatest(m.$offline, m.$hasLoaded).sink { runs, offline, loaded in
    guard loaded, !offline else { self.previous = nil; return }
    ...
}
```
Do the same in `OrchestratorWingsModel.runsChanged`. It is harmless there today, but it is the same bug.

### WR-02: Rail misses waiting runs that start before the rail state is first created

**File:** `boringNotch/Orchestrator/OrchestratorExpanded.swift:15`
**Issue:** `OrchestratorRailState.shared` is created lazily, the first time `OrchestratorExpandedView` appears or ⌘\ is pressed. Its first emission takes the current runs as the baseline. If the rail was collapsed in a previous launch and a run starts waiting before the user first expands the notch, it is never seen as newly waiting, and the rail stays collapsed. That breaks RUN-04 for the first expand of each launch.
**Fix:** Create it eagerly next to the wings model, for example `_ = OrchestratorRailState.shared` in `OrchestratorWingsModel.init`, together with the WR-01 fix.

### WR-03: Wing spinner and glow stop animating after their first appearance

**File:** `boringNotch/Orchestrator/OrchestratorWings.swift:63-64, 85, 89`
**Issue:** `spin` and `glow` are `@State` on `OrchestratorWingsView`. That view stays mounted while `kind` goes `.working → .needsYou → .working`, because the ContentView branch is `wings.kind != nil` throughout. When the ✻ or the dot is re-inserted, `onAppear` sets `spin = 360` or `glow = true`, which are the values they already hold. With no change, `repeatForever` never restarts, so the spinner sits still and the needs-you dot stops pulsing.
**Fix:** Reset before animating:
```swift
.onAppear { spin = 0; withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spin = 360 } }
// and: glow = false; withAnimation(...) { glow = true }
```
Or move each into its own small subview so its state is recreated.

### WR-04: The key monitor swallows shortcuts that do nothing

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:78-87`
**Issue:** `handle` returns `true` for `.back` at `.open`, `.deeper` at `.terminal` and `.terminal` at `.terminal`, even though `setLevel` exits early on its `target == cur` guard. The local monitor then drops the event. Once CR-01 is fixed, ⌘↑ in the chat composer at level `.open` (the normal "move to start" shortcut) is eaten for nothing. ⌘↓ and ⌘T are also eaten inside the ttyd terminal.
**Fix:** Return whether the level actually changed:
```swift
let next = sc == .back ? nextLevel(cur, .back) : sc == .deeper ? nextLevel(cur, .deeper) : .terminal
guard next != cur else { return false }
setLevel(next, vm: vm, window: window); return true
```

### WR-05: Any new run field with the wrong type takes the whole tab offline

**File:** `boringNotch/Orchestrator/OrchestratorModels.swift:42-60`
**Issue:** Phase 7 adds six run fields, including nested arrays (`denials: [String]?`, `activity.agents: [RunAgent]?`). Serve builds `denials` as `permission_denials.map(d => d.tool_name)` (orch.js:153), so a missing `tool_name` produces a JSON `null` inside the array. That fails the `[String]` decode, which fails `StateResponse`. `refresh()`'s `catch` then sets `offline = true` and clears `runs` and the prompt, so one odd run hides the chat and every question card. This goes against the project rule that server additions or omissions must never break decoding.
**Fix:** Decode `denials` as `[String?]?` and `compactMap` it, or give `OrchestratorRun` a lenient `init(from:)` using `try?` per field. Also consider decoding `runs` element by element, so one bad run is dropped instead of the whole state.

### WR-06: The strip's hover card is drawn about 166pt left of the strip

**File:** `boringNotch/Orchestrator/OrchestratorExpanded.swift:121-124`
**Issue:** The overlay is `alignment: .topTrailing` on a 22pt circle. That already lines the 178pt card's trailing edge up with the circle's trailing edge. Adding `.offset(x: -(178 + 10))` then moves it another 188pt left, leaving a 166pt gap, so the card floats in the middle of the conversation column, away from the dot it describes. The math appears to assume leading alignment. I haven't checked this visually, because the app wasn't run.
**Fix:** `.offset(x: -(22 + 10))`, which puts the card 10pt left of the circle.

## Info

### IN-01: The wing label takes the first word of the prompt title
**File:** `boringNotch/Orchestrator/OrchestratorRunsPure.swift:177`
**Issue:** A title like "Do you want to proceed?" becomes "Do?". **Fix:** Only use the first word when it is a known tool name, otherwise fall back to "Needs you".

### IN-02: `jsonField` unescapes in the wrong order
**File:** `boringNotch/Orchestrator/OrchestratorRunsPure.swift:45`
**Issue:** `\\n` (an escaped backslash followed by n) is turned into a space before `\\\\` is handled, so a path or command containing a literal `\n` is shown wrong. This only affects display. **Fix:** Unescape `\\\\` with a placeholder first, or decode the captured value with `JSONSerialization` after closing the quote.

### IN-03: `askInChatMessage` lists the denials twice
**File:** `boringNotch/Orchestrator/OrchestratorRunsPure.swift:100-101`
**Issue:** With no `?` in the result you get "Needs permission: Bash (denied: Bash)". **Fix:** Skip the suffix when `waitingQuestion` already fell back to the permission text.

### IN-04: `dotCovered` assumes the music live activity is visible
**File:** `boringNotch/Orchestrator/OrchestratorCompact.swift:12-15`
**Issue:** During a battery expanding view or an inline HUD, `MusicLiveActivity` (and the dot on it) is hidden, but the corner dot stays suppressed, so needs-you briefly shows nowhere. **Fix:** Reuse ContentView's music-branch condition (`!expandingView.show || type == .music`).

### IN-05: Wings ignore the zero-height closed notch and the chin width
**File:** `boringNotch/ContentView.swift:295`, `ContentView.swift:62-82`
**Issue:** The wings branch doesn't check `effectiveClosedNotchHeight > 0`, unlike `OrchestratorClosedIndicators`, and `computedChinWidth` doesn't know about the wider wing layout. **Fix:** Add the height guard. Leave the chin as is unless hover misbehaves.

### IN-06: The terminal toolbar labels are misleading
**File:** `boringNotch/Orchestrator/OrchestratorTerminal.swift:119-121`
**Issue:** It says "keyboard captured" even in the unavailable or in-use state. The "Collapse ⌃" glyph reads as the Control key, but the shortcut is ⌘↑. **Fix:** Show the capture text only while `termState == .connected`, and use "Collapse ⌘↑" or a chevron image.

---

_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
