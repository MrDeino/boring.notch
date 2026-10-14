---
phase: 03-compact-indicators-expand-down
reviewed: 2026-10-14T12:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - boringNotch/ContentView.swift
  - boringNotch/Orchestrator/OrchestratorCompact.swift
  - boringNotch/Orchestrator/OrchestratorExpand.swift
  - boringNotch/Orchestrator/OrchestratorManager.swift
  - boringNotch/Orchestrator/OrchestratorPure.swift
  - boringNotch/Orchestrator/OrchestratorTerminal.swift
  - boringNotch/Orchestrator/OrchestratorView.swift
  - boringNotch/Orchestrator/Tests/Phase3Tests.swift
  - boringNotch/Orchestrator/Tests/main.swift
  - boringNotch/components/Notch/BoringNotchSkyLightWindow.swift
  - boringNotch/models/BoringViewModel.swift
findings:
  critical: 2
  warning: 5
  info: 4
  total: 11
status: issues_found
---

# Phase 3: Code Review Report

**Reviewed:** 2026-10-14
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

Reviewed the Phase 3 diff from `ac68084` (closed-notch indicators, expand-down, ttyd terminal, key gate). What holds up:
- SharingStateManager begin/end is balanced. There is one `beginInteraction` per inserted key in `expand`, and exactly one `endInteraction` per removed key in `finish`.
- `pinnedFrame` keeps the top edge fixed.
- `isOutsideNotch` uses screen coordinates (`NSEvent.mouseLocation`) for both the local and the global monitor. Clicks on the header/tab bar and on the collapse button land inside the notch rect, so they do not collapse.
- The music layout is untouched: the ContentView clamp adds `max(0, notchSize.height - 190)`, which is 0 unless the notch is expanded, and the closed overlay has `allowsHitTesting(false)` and no layout effect.
- The expanded overlay does grow: the greedy `Color.black` fills `OrchestratorView`, which fills `mainLayout`'s `notchSize.height` frame.

Problems: tab-switching while expanded leaves the notch drawn at expanded height inside a shrunk window. Collapse never really gives up key-window status, because it calls `resignKey()` directly. The expand button is centred rather than bottom-trailing. Several multi-screen paths can leave windows tall or leak the keep-open session.

## Critical Issues

### CR-01: `reset()` shrinks the window but leaves `vm.notchSize` expanded (tab switch while expanded)

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:58-66` (triggered from `:167` `.onDisappear { expand.reset() }`)
**Issue:** While expanded, the header tab bar stays clickable and is inside the notch rect, so no collapse happens. Switching to Home/Shelf removes `OrchestratorView`, and `onDisappear` calls `reset()`. `reset()` shrinks the window to `windowSize.height` but never sets `vm.notchSize` back to `openNotchSize`. So the open notch keeps rendering at 190+300 pt. `mainLayout.frame(height: vm.notchSize.height)` and the ContentView `maxHeight` both still use the tall size, so the content (including the music player on Home) is clipped by the 210 pt window. The bottom corners and the content below about 190 pt disappear. `isMouseHovering` also still uses the tall rect. It only recovers when the notch closes. `coordinator.currentView` is shared, so this hits every screen at once.
**Fix:** Restore the size in `reset()` for open notches:
```swift
for k in Array(expanded) {
    let win = windows[k]?.w
    let vm = vms[k]?.vm
    finish(k)
    if let vm, vm.notchState == .open { vm.notchSize = openNotchSize }
    if let win { win.setFrame(pinnedFrame(current: win.frame, newHeight: windowSize.height), display: true) }
}
```

### CR-02: `resignKey()` is called directly, so the panel stays key after collapse and swallows keystrokes

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:102`, `boringNotch/Orchestrator/OrchestratorTerminal.swift:31`
**Issue:** `NSWindow.resignKey()` is a notification hook ("never invoke this method directly"). Calling it does not change which window the window server treats as key. After `makeKey()` in `didFinish`, the non-activating panel holds keyboard focus. When the user collapses with the control (mouse still in the notch, no click into another app), the panel stays key. Typing then goes to the panel, whose WKWebView first responder is gone, so the keystrokes are lost or beep. This continues after the notch closes, until the user clicks into another window. Setting the gate back to `false` does not help: `canBecomeKey` is only checked when something tries to make the window key, not to give it up.
**Fix:** Hand focus back explicitly. At expand time, remember the previously focused app and reactivate it on collapse, and clear the first responder:
```swift
// expand():
previousApp = NSWorkspace.shared.frontmostApplication
// finish(k):
if let w = windows[k]?.w, w.isKeyWindow {
    w.makeFirstResponder(nil)
    previousApp?.activate()
}
```
Delete both `resignKey()` calls. This needs a runtime check, because focus behaviour of non-activating panels can only be confirmed by hand.

## Warnings

### WR-01: Expand button is centred over the chat, not bottom-trailing

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:129-165`, `boringNotch/Orchestrator/OrchestratorView.swift:31`
**Issue:** `.overlay { OrchestratorExpandOverlay() }` uses the default `.center` alignment. When collapsed, the overlay's `ZStack` holds only the button, so the ZStack is button-sized and gets centred over the chat tail. `ZStack(alignment: .bottomTrailing)` only aligns children inside the ZStack. The button only reaches the corner once `Color.black` makes the ZStack fill (expanded). It covers chat text, and it will cover Phase 2's centred prompt buttons after the merge.
**Fix:** Add `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)` to the ZStack, or use `.overlay(alignment: .bottomTrailing)`. An empty frame adds no hit area.

### WR-02: One shared `shrinkTask` across screens leaves windows tall

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:12, 33, 48-54, 60`
**Issue:** `collapse` on screen B, `expand` on any screen, or `reset()` within 450 ms of collapsing screen A cancels A's pending shrink. A's window then stays at windowSize+300 indefinitely. `expand` only resizes from the current frame, and nothing else shrinks it. It is a transparent tall panel hanging below the notch.
**Fix:** Keep the shrink tasks per key (`[String: Task<Void, Never>]`), and cancel only `shrinkTasks[k]` in `expand`/`collapse`/`reset`.

### WR-03: Expansion is keyed by `screenUUID` and the keep-open is global, which breaks on screen changes and multiple screens

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:19, 38, 87-96`; `boringNotch/boringNotchApp.swift:529`
**Issue:**
1. In single-display mode, `adjustWindowPosition` reassigns `vm.screenUUID` (and sets `vm.notchSize` to the closed size) when the selected screen changes. An expanded entry under the old UUID is orphaned: `isExpanded(vm)` returns false, the button shows "expand", and pressing it begins a second interaction. `preventNotchClose` then stays true until an outside click or a tab switch (`reset`).
2. `beginInteraction` is app-wide, so while screen A is expanded, screen B's notch can't close on hover-out at all.
3. In `collapseIfOutside` with two expanded screens, the first `vm.close()` is still blocked by the other screen's session. That notch stays open while the second one closes.

**Fix:** Key by `ObjectIdentifier(vm)` instead of `screenUUID`. In `collapseIfOutside`, collapse all outside screens first, then close them in a second loop.

### WR-04: Collapse control disappears while expanded if the orchestrator goes offline

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:155`
**Issue:** The button only renders when `manager.hasLoaded && !manager.offline`. If the poll flips to offline while expanded (serve restarted), the collapse control vanishes. The notch is held open by the interaction. The only way out is an outside click, which also closes the notch, or a tab switch, which hits CR-01.
**Fix:** `if isExp || (manager.hasLoaded && !manager.offline) { … }`.

### WR-05: "In use"/disconnect detection only runs for the first 5 s and matches any "Reconnect" text

**File:** `boringNotch/Orchestrator/OrchestratorTerminal.swift:68-77`, `boringNotch/Orchestrator/OrchestratorPure.swift:29-32`
**Issue:** The poll stops after 5 checks. If ttyd's socket drops later (serve restart, ttyd killed, slot taken), the dead terminal stays on screen with no "unavailable" fallback, and the key gate stays true. Also, `body.innerText` containing "Reconnect" or "Connection Closed" anywhere (for example terminal text, if xterm's DOM or accessibility renderer is active) is treated as "in use" and tears down a working session.
**Fix:** Keep polling every 1–2 s for as long as the view exists (it is cancelled in `dismantleNSView`). Read only ttyd's overlay element, e.g. `document.querySelector('.xterm-overlay')?.innerText ?? ''`, rather than the whole body.

## Info

### IN-01: Key gate is global across all notch panels

**File:** `boringNotch/Orchestrator/OrchestratorTerminal.swift:6-8`, `boringNotch/Orchestrator/OrchestratorExpand.swift:101`
**Issue:** While screen A's terminal is connected, every notch panel can become key. Collapsing screen B sets the gate back to false while A is still connected. This is harmless today, but it matters for the Phase 2 merge (the OR'd gate).
**Fix:** Track the gate per window, or accept it and note it in the merge notes.

### IN-02: The expanded overlay hides the runs strip

**File:** `boringNotch/Orchestrator/OrchestratorExpand.swift:131`
**Issue:** The opaque `Color.black` and the WKWebView cover `OrchestratorView`'s runs overlay. The header Runs button toggles `showRuns` with no visible effect while expanded.
**Fix:** Collapse when the runs strip is toggled, or put the runs overlay above the expand overlay.

### IN-03: Teardown relies on WKWebView deallocation, not the `about:blank` load

**File:** `boringNotch/Orchestrator/OrchestratorTerminal.swift:29`
**Issue:** SwiftUI releases the view right after `dismantleNSView`, so the `about:blank` navigation may never start. Releasing ttyd's slot actually depends on WebKit closing the page on dealloc, which it normally does. The comment overstates what the load guarantees.
**Fix:** Optionally call `nsView.navigationDelegate = nil`, and correct the comment. Check at runtime that expand → collapse → expand reconnects without "in use".

### IN-04: The attention dot may overlap the music live activity's visualizer

**File:** `boringNotch/Orchestrator/OrchestratorCompact.swift:14-16`
**Issue:** The dot sits 10 pt from the trailing edge and 5 pt from the top. When `MusicLiveActivity` widens the chin, that is where the spectrum square is drawn. D-01 allows the dot alongside music, but this should get a visual check so the visualizer is not obscured.
**Fix:** Check by eye with music playing. If they overlap, nudge the dot to `.padding(.trailing, 4)`.

---

_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
