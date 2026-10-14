---
phase: 02-sending-prompt-answers
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - boringNotch/Orchestrator/OrchestratorModels.swift
  - boringNotch/Orchestrator/OrchestratorManager.swift
  - boringNotch/Orchestrator/OrchestratorView.swift
  - boringNotch/Orchestrator/Tests/main.swift
  - boringNotch/components/Notch/BoringNotchSkyLightWindow.swift
findings:
  critical: 1
  warning: 5
  info: 6
  total: 12
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-10-14
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

I reviewed the diff d7edeef..HEAD with the hooks it relies on: `SharingStateManager`, `BoringViewModel.open/close`, ContentView's hover-close and `sharingDidFinish` paths, and the per-screen window creation in `boringNotchApp.swift`. The POST builder and sender follow D-01..D-05, and the mock-server test never touches 4777. The option double-send guard works: there is a lock plus a generation counter, the `sending` guard, and an unlock when the prompt changes. `beginTyping` and `endTyping` are idempotent, so the shared interaction count cannot go out of balance. Calling `canBecomeKey` from AppKit is fine on the main actor, because NSWindow is `@MainActor` in the macOS 14+ SDK.

The weak spot is the typing lifecycle in the view. Typing mode is turned on before the code knows the panel actually became key. Nothing ends it when the field loses focus while the panel stays key. While it is on, the notch cannot close (`close()` returns early). There is one path where typing mode is on with no way out except a tab switch (CR-01). `detectPrompt` also got looser: lines that don't match no longer break a run, so a `────` separator no longer resets it. That opens a false positive from the input box (WR-04).

## Critical Issues

### CR-01: Typing mode can latch on with no release path, so the notch stays open

**File:** `boringNotch/Orchestrator/OrchestratorView.swift:115-123` (plus `:35-37`)
**Issue:** `startTyping()` calls `manager.beginTyping()` first. That increments `SharingStateManager.activeSessions`, so `preventNotchClose` becomes true. Only after that does it look for the window, with `NSApp.windows.first { … frame.contains(NSEvent.mouseLocation) }`, and call `w?.makeKey()` without checking the result. If `w` is nil, or the panel never becomes key, typing stays on with nothing to clear it:
- `keyWindow` is nil or never key, so the `didResignKeyNotification` handler never matches.
- The field can't take focus without a key window, so `onExitCommand` (Esc) and `onSubmit` can't fire.
- `BoringViewModel.close()` returns early while `preventNotchClose` is set, so `notchOpen` never goes false and `endTyping()` in its `didSet` never runs.

The notch then stays open over the menu bar until the user happens to switch tabs, or the chat stops, goes offline, or shows a prompt. How often this happens is unknown. The frame/mouse heuristic is fragile because the frame includes the shadow inset and there is one window per display. The SkyLight-space window has also not been checked for `makeKey` behaviour (that is still human UAT). Either way, "the notch must never get stuck open" is a hard requirement (D-08).
**Fix:** Commit typing only once the panel is actually key, and add a safety timeout:
```swift
private func startTyping() {
    guard let w = NSApp.windows.first(where: {
        $0 is BoringNotchSkyLightWindow && $0.isVisible && $0.frame.contains(NSEvent.mouseLocation)
    }) else { return }
    manager.beginTyping()            // canBecomeKey needs the flag first
    w.makeKey()
    guard w.isKeyWindow else { manager.endTyping(); return }
    keyWindow = w
    DispatchQueue.main.async { if manager.wantsKeyboard { fieldFocused = true } }
}
```
Also see WR-01 (focus loss). A better long-term fix is to get the hosting window from the view itself (a tiny `NSViewRepresentable` that reads `view.window`) rather than matching on mouse position.

## Warnings

### WR-01: Focus loss inside a key panel never ends typing, so keystrokes and Enter still go to the orchestrator

**File:** `boringNotch/Orchestrator/OrchestratorView.swift:35-41`, `:77`
**Issue:** D-08 says to "end on … focus loss". Typing currently ends only on resign-key, Esc, submit, disappear, chatRunning or offline changing, or a prompt appearing. Nothing watches `fieldFocused`. Suppose the field loses first responder while the panel stays key, for example because the user presses Tab. Then `typing` stays true, the notch can't close, and the panel keeps the keyboard. There is a related hazard. Typing mode does not end when the user simply moves the mouse away: the notch stays open (by design) and the panel stays key. The other app still looks frontmost, because the panel is non-activating. Anything the user types next, including Enter, goes into the notch draft and is sent to the live orchestrator chat. That is an unintended send to the real chat.
**Fix:** End typing whenever the field loses focus:
```swift
.onChange(of: fieldFocused) { _, f in if !f && manager.wantsKeyboard { stopTyping() } }
```
Consider ending typing on hover-exit when the draft is empty, or after a short idle timeout (e.g. 20 s with no edits), so the panel never keeps the keyboard unnoticed.

### WR-02: Keyboard handback relies on `activate()` of an app that is already active

**File:** `boringNotch/Orchestrator/OrchestratorView.swift:125-135`
**Issue:** The panel is non-activating, so `NSWorkspace.frontmostApplication` is already the active app. Calling `activate()` on an app that is already active is not documented to move key focus back from another process's panel. It may do nothing. In that case the notch panel stays key with no first responder (`makeFirstResponder(nil)`) after Enter or Esc, and the user's keystrokes beep until they click their window. When the orchestrator app *is* active (Settings window open), `front == .current` skips the handback entirely. Again the panel stays key, now with `canBecomeKey == false`, which does not remove key status. This is not verified at runtime, and it is the main thing the human UAT has to confirm.
**Fix:** In UAT, check that typing reaches the previous app straight after Enter and after Esc without clicking. If it doesn't, give up key in a way AppKit honours. One option is to `orderOut(nil)` and then `orderFrontRegardless()` the panel once `wantsKeyboard` is false, which makes the window server pick the next key window. Keep `activate()` only as a fallback.

### WR-03: `canBecomeKey` uses one global flag for every per-display panel

**File:** `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift:112`
**Issue:** With `showOnAllDisplays`, there is one `BoringNotchSkyLightWindow` per screen (`boringNotchApp.swift:496-501`). While `wantsKeyboard` is true, *every* notch panel can become key. Suppose the user types on display A and clicks notch B. B becomes key, so A resigns key and A's `stopTyping()` runs. But `keyWindow` (A) is no longer key, so the handback is skipped. B ends up key with `canBecomeKey == false` and swallows keystrokes. A second open `OrchestratorView` (B) also runs its own `onChange` → `stopTyping()` → `manager.endTyping()`, which ends A's typing session.
**Fix:** Store the panel that should be key instead of a Bool, and keep the existing-file hook to one line:
```swift
// manager: weak var keyboardWindow: NSWindow?   (set in startTyping, nil in endTyping)
override var canBecomeKey: Bool { OrchestratorManager.shared.keyboardWindow === self }
```

### WR-04: `detectPrompt` can match a numbered draft in the input box (separator no longer resets the run)

**File:** `boringNotch/Orchestrator/OrchestratorModels.swift:82-90`
**Issue:** Lines that don't match the option pattern now `continue` without resetting `run`, so `────` and `⏺ …` lines no longer break a sequence. The bottom-4 window only holds the input box lines. Claude Code echoes user input as `❯ text`, and in the fixtures the idle box is `❯\u{a0}draft`. So two cases trigger false-positive buttons:
- a multi-line draft typed directly in the terminal (`❯ 1. do X` / `  2. do Y`)
- Claude's list `1. …` directly above the box, followed by a draft `❯ 2. foo`, joined across the separator. A notch send can also be caught for 150 ms before the server's Enter.

The result is option buttons over an idle chat. That hides the message box (`bottomBar` only shows the TextField when `promptOptions` is empty), sets `needsAttention`, and tapping types a bare digit into the user's draft.
**Fix:** Require the marked option to belong to a run that is *not* inside the input box. For example, stop the scan at the input-box frame: if one of the last 4 lines is a `─` rule followed by a `❯` line, return `[]`. Or reset the run on lines that start with `❯` but don't match. Add the multi-line-draft screen as a test case:
```swift
precondition(detectPrompt(screen: "1. a\n" + "────\n❯ 2. foo\n────\n  ? for shortcuts\n").isEmpty)
precondition(detectPrompt(screen: "────\n❯\u{a0}1. do X\n  2. do Y\n────\n").isEmpty)
```

### WR-05: Esc control is not debounced, so a double tap sends two Escapes

**File:** `boringNotch/Orchestrator/OrchestratorView.swift:98-99`, `OrchestratorManager.swift:63`
**Issue:** The esc button is disabled only while `sending`, which covers one localhost request of a few ms. A double tap sends Escape twice. In Claude Code, Esc-Esc on the idle box opens the rewind/edit-previous picker, and Esc while working interrupts the run and then opens the picker. The option buttons got a lock for exactly this reason (D-13). Esc has none.
**Fix:** Give Escape the same short lock (a reuse of `optionsLocked` with a ~1 s timeout is enough), or ignore Esc presses within 750 ms of the previous one in `pressEscape()`.

## Info

### IN-01: `endTyping()` in the `notchOpen` didSet never runs while typing

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:25`
**Issue:** `BoringViewModel.close()` returns before setting `notchOpen = false` whenever `preventNotchClose` is true. That is always the case while typing, so this line can't run. It gives a false sense that closing the notch releases the keyboard. Release actually depends on the view's `onDisappear`.
**Fix:** Remove it, or add a comment saying the view owns teardown.

### IN-02: The End-confirm reset task can collapse a second confirm early

**File:** `boringNotch/Orchestrator/OrchestratorView.swift:105-108`
**Issue:** Tap End, then No, then End again within 4 s, and the first task resets `confirmEnd` early. The task is never cancelled. The stale task can only cancel the confirm (it never stops the chat by itself), so this is harmless.
**Fix:** Keep a generation counter like `lockGen`, or use `.task(id: confirmEnd)`.

### IN-03: A successful send can wipe text typed while the request was in flight

**File:** `boringNotch/Orchestrator/OrchestratorView.swift:141`
**Issue:** `draft = ""` runs after the await. If the user starts typing again before the response comes back, the new text is lost.
**Fix:** `if await manager.sendText(t), draft.trimmingCharacters(in: .whitespacesAndNewlines) == t { draft = "" }`, or clear the draft before sending and restore it on failure.

### IN-04: Send failures give no feedback

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:52-60`
**Issue:** Network errors, 400, 403, and the early `!sending` rejection all return `false` silently. The draft is kept, but the user can't tell that nothing was sent.
**Fix:** Publish a short-lived `lastError` string and show it in the bottom bar for a few seconds.

### IN-05: Deferred focus can re-focus the field after typing has ended

**File:** `boringNotch/Orchestrator/OrchestratorView.swift:122`
**Issue:** `DispatchQueue.main.async { fieldFocused = true }` runs unconditionally. If `stopTyping()` runs before it does (for example, a prompt appears in the same refresh), the field ends up focused while `wantsKeyboard` is false.
**Fix:** Guard it: `if manager.wantsKeyboard { fieldFocused = true }`. This is already included in the CR-01 fix.

### IN-06: After tapping "Type something." there is no way to type the answer

**File:** `boringNotch/Orchestrator/OrchestratorView.swift:72-97`
**Issue:** The free-text option keeps the prompt on screen, so `promptOptions` stays non-empty and the message box stays hidden. The user has to go to the terminal. This is listed as deferred in CONTEXT, but tapping the button now leaves the UI at a dead end.
**Fix:** Hide that option's button for now, or show the message box when the selected option label is "Type something.".

---

_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
