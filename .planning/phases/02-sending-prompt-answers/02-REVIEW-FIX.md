---
phase: 02-sending-prompt-answers
fixed_at: 2026-10-14T00:00:00Z
review_path: .planning/phases/02-sending-prompt-answers/02-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 8
skipped: 1
status: partial
---

# Phase 2: Code Review Fix Report

**Scope:** CR-01, WR-01 to WR-05, plus IN-01, IN-05 and IN-06. IN-02, IN-03 and IN-04 were left out by request.

## Fixed Issues

### CR-01: Typing mode can latch on with no release path
**Files:** `boringNotch/Orchestrator/OrchestratorView.swift`
**Commit:** e99e8a0
The window now comes from the view itself, through a tiny `WindowAnchor` NSViewRepresentable that reads `view.window`. This replaces the `NSApp.windows` mouse-position lookup. `startTyping()` returns if there is no window. If `makeKey()` did not make the panel key, it calls `endTyping()` again, so the notch can never be held open without the keyboard. Logic fix: requires human verification (UAT 1).

### IN-05: Deferred focus can re-focus after typing ended
**Files:** `boringNotch/Orchestrator/OrchestratorView.swift`
**Commit:** e99e8a0 (with CR-01)
The deferred `fieldFocused = true` now runs only while `manager.wantsKeyboard` is still true.

### WR-03: `canBecomeKey` uses one global flag for every per-display panel
**Files:** `boringNotch/Orchestrator/OrchestratorManager.swift`, `boringNotch/Orchestrator/OrchestratorView.swift`, `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`
**Commit:** 314b33e
The manager holds a `weak keyboardWindow`. It is set by `beginTyping(in:)` and cleared by `endTyping()`. The existing one-line hook is now `canBecomeKey { OrchestratorManager.shared.keyboardWindow === self }`. A view that does not own the session (because its `keyWindow` is nil) no longer ends another display's typing.

### WR-01: Focus loss inside a key panel never ends typing
**Files:** `boringNotch/Orchestrator/OrchestratorView.swift`
**Commit:** a8cbf77
Typing now ends when the field loses focus, and when the pointer leaves the Orchestrator view (`onHover(false)`). When typing ends, the interaction ends, which posts `sharingDidFinish`, so the notch closes normally once the pointer has left. There is no longer a "keep open while the pointer is away" window in which stray keystrokes or Enter could reach the chat. Logic fix: requires human verification (UAT 3).
**Orchestrator amendment:** the `onHover(false)` part was removed afterwards. It broke INT-06 (the notch must stay open while typing even if the pointer moves away). Clicking outside already makes the panel resign key, which ends typing, and so does focus loss.

### WR-04: `detectPrompt` can match a numbered draft in the input box
**Files:** `boringNotch/Orchestrator/OrchestratorModels.swift`, `boringNotch/Orchestrator/Tests/main.swift`
**Commit:** 35deea0
A match now also needs an "Esc to cancel" footer line after the last option. Both real fixtures have one, and the input box never does. I added the reviewer's two input-box screens and a no-footer case, and gave the synthetic `opts` screen a real footer. I checked that the old code returned 2 options for both reviewer screens. Logic fix: requires human verification (UAT 4).

### WR-05: Esc control is not debounced
**Files:** `boringNotch/Orchestrator/OrchestratorManager.swift`
**Commit:** 109685e
`pressEscape()` now ignores a press that comes within 1 s of the previous one.

### IN-01: `endTyping()` in the `notchOpen` didSet never runs while typing
**Files:** `boringNotch/Orchestrator/OrchestratorManager.swift`
**Commit:** 2bda5cd
I removed the line and added a comment saying that `OrchestratorView` owns typing teardown.

### IN-06: No way to type the answer after tapping "Type something."
**Files:** `boringNotch/Orchestrator/OrchestratorView.swift`
**Commit:** e9679f1
The "Type something." option no longer gets a button. The other options keep their real numbers.

## Skipped Issues

### WR-02: Keyboard handback relies on `activate()` of an already active app
**File:** `boringNotch/Orchestrator/OrchestratorView.swift:125-135`
**Reason:** This needs checking at runtime. The suggested fallback, `orderOut` + `orderFrontRegardless` on the SkyLight-delegated panel, could break its space delegation, and I can't test that without launching the app. WR-03 already ensures that, once typing ends, `canBecomeKey` is false for every panel. UAT 2 now checks the handback explicitly after both Enter and Esc. If it fails there, apply the fallback.
**Original issue:** `activate()` on the frontmost app may not take key focus back from the non-activating panel. The panel would then stay key with no first responder.

## Verification
- swiftc test script: OK
- xcodebuild Debug (ad-hoc): BUILD SUCCEEDED
- 02-HUMAN-UAT.md updated: tests 1 to 5. Changes: the rollback symptom, the two-display check, the handback after Esc, the pointer leaving now ends typing, "Type something." hidden, a numbered draft shows no buttons, and esc double-tap.

---

_Fixed: 2026-10-14_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
