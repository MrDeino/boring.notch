---
quick_id: 261014-gkq
type: quick
---
# Quick 261014-gkq: Orchestrator chat — strip TUI chrome, fix typing, rework layout, tap-to-expand

1. `chatTail` (OrchestratorModels.swift): drop Claude Code's bottom input block (rule line whose next line starts with `❯`, through the end) and every remaining full-width `─` rule line (incl. ones with a session title at the right end). Add the user's screen tail as `Tests/fixtures/inputbox.txt`; harness asserts nothing of it survives and that preceding conversation lines do.
2. Keyboard: the notch is a non-activating panel of an accessory app that never activates, and `startTyping` cancelled itself when `isKeyWindow` wasn't true synchronously. `OrchestratorKeyGate.activate()/restore()` remembers the frontmost app, activates us while the box or terminal has focus, and hands focus back on Enter/Esc/inside-click; a click in another app doesn't refocus. Unconfirmed key is checked after a beat instead of immediately.
3. Layout: message box full width; prompt row = options + esc; Start/End become a small icon (`OrchestratorChatButton`) in the header next to the runs button, End keeps Yes/No confirm; expand arrow removed.
4. Tap on the chat lines expands to the terminal; outside click collapses (unchanged).

Verify: swiftc harness OK; xcodebuild into /tmp/notch-dd BUILD SUCCEEDED.
