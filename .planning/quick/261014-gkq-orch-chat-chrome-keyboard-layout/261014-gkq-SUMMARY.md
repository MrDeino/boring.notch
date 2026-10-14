---
status: complete
quick_id: 261014-gkq
---
# Summary

- `chatTail` drops Claude Code's input box (rule → `❯` line → closing rule → status lines, i.e. from the box's top rule down) and every `───` rule line, incl. titled ones. A live prompt (no closing rule under `❯ 1.`) stays. Fixture `Tests/fixtures/inputbox.txt` (user's real screen tail) → nothing kept; conversation above it kept.
- Keyboard root cause: the notch is a `.nonactivatingPanel` (level mainMenu+3, in a private CGS space) of an accessory-policy app that is never activated. `makeKey()` alone didn't route keystrokes to it, and `startTyping` checked `isKeyWindow` synchronously right after `makeKey()`, ending the session immediately when the panel wasn't key yet — the click looked dead. Fix: `OrchestratorKeyGate.activate()` remembers the frontmost app and activates ours while the box/terminal has focus; `restore()` hands focus back on Enter/Esc/inside click; a click in another app doesn't refocus. Key is re-asserted after activation; typing only gives up if the panel still isn't key after 600 ms. Terminal uses the same gate.
- Layout: message box full width; prompt row = options + esc; Start/End icon (`OrchestratorChatButton`, play/stop) in the header beside the runs button, End keeps Yes/No; expand arrow and `WindowAccessor` removed.
- Clicking the chat lines expands to the terminal; outside click collapses (unchanged).

Checks: swiftc harness OK (new fixture included); xcodebuild into /tmp/notch-dd BUILD SUCCEEDED. Not launched; on-screen check pending the user.
