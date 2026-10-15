---
quick_id: 261015-me4
slug: type-to-focus-composer-first-gesture-sel
date: 2026-10-15
status: complete
---

# Type-to-focus composer, first-gesture selection, send retry

## What changed
- **Send retry.** `orchestratorPostData(for:session:)` in `OrchestratorModels.swift` wraps every POST to serve
  (`sendOrchestratorPost`, so text/keys/C-u/start/stop/notes, and `uploadOrchestratorImage`). If the connection
  drops before any response (`networkConnectionLost`, `cannotConnectToHost`, `notConnectedToInternet`), it waits
  250 ms and retries once on a throwaway `URLSession` with the same configuration, so it can't reuse a dead
  keep-alive connection. It never retries after an HTTP response (409/4xx/5xx) or a timeout.
- **First-gesture selection.** The composer's TextField is now always mounted (`OrchestratorComposerField`, new
  file `OrchestratorComposerInput.swift`). It used to be a `Text` with a tap overlay while idle, so the first click
  only mounted the field. Now a click focuses the field in the non-key panel, and a drag or double-click selects
  right away. Gaining focus calls `startTyping()` (key gate, activation), which keeps the selection. A tap behind
  the field (the pill's padding) still starts typing.
- **Type-to-focus.** The chat view installs a local keyDown monitor while the composer is shown. Pure
  `typeToFocusText(characters:modifierFlags:context:)` decides. A printable key (option allowed) is appended to the
  draft, typing starts, and the caret moves to the end. That happens only when the notch is open or expanded on the
  Orchestrator tab, the app is active, this panel is key, and none of these is focused: the composer, ttyd, notes or
  the card's text field. With a question card showing, every key passes, so digits still pick options. ⌘ and ⌃
  combos (⌃U), Esc, Tab, Return, Delete, arrow and function keys, and dead keys pass unchanged. It is a local monitor,
  so another frontmost app's keys never reach it.

## Checks
Harness (now also compiles `OrchestratorComposerInput.swift`):
`xcrun swiftc -o build/orch-test boringNotch/Orchestrator/{OrchestratorModels,OrchestratorPure,OrchestratorTranscript,OrchestratorPromptParse,OrchestratorRunsPure,OrchestratorStream,OrchestratorComposerInput}.swift boringNotch/Orchestrator/Tests/*.swift`
- `./build/orch-test` → OK. `ORCH_RETRY_MOCK=1 ORCH_APPROVAL_MOCK=1 ./build/orch-test` → OK.
- QuickMe4Tests covers the following:
  - type-to-focus: letters, shift, space, option, digits without a card; the closed / other-app-frontmost /
    not-key / other-tab / composer-, terminal- or other-text-focused cases; digit with a card showing; ⌘C, ⌘\,
    ⌃U, Esc, Tab, Return, Delete, arrows, dead key.
  - first-gesture selection: real AppKit events on an offscreen gated non-key panel with no cursor movement.
    Double-click selects "foo" and a drag selects from 0. Focus opens the session once and the panel becomes key.
    Caret-to-end works.
  - retry: `retry-mock.py` on 47998 drops the first connection. The text POST and the image upload return 200
    after 2 connections, and 500 and 409 each arrive exactly once.
  - The UI test runs last in `main.swift`: once AppKit has spun the main run loop, a later `await` makes the
    async-main drain exit the process.
- RED, each change reverted on its own: no retry → `dropped first connection: nil`; old Text swap → `composer field
  not mounted while idle`; type-to-focus off → precondition at the first case.
- xcodebuild Debug (`-derivedDataPath ./build`) and Release (`ENABLE_HARDENED_RUNTIME=NO`, `ORCH_NO_SPARKLE`, ad-hoc,
  copied to `./build/notch-rel`): BUILD SUCCEEDED.

Ran directly (no planner/executor agents). The running notch (/tmp/notch-current) was not touched. Nothing launched.
UAT, which can't be checked headless:
- Expand, click the transcript, then type a letter: it lands in the composer.
- Double-click or drag in an idle composer that has a draft: the text is selected.
- Restart serve, then send: it goes through with no "Couldn't send".
