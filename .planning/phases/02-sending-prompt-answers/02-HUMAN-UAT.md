---
status: pending
phase: 02-sending-prompt-answers
source: [02-02-PLAN.md]
started: 2026-10-14
updated: 2026-10-14
---

## How to run the built app

1. Quit the installed Boring Notch (menu bar icon -> Quit). Don't replace /Applications/boringNotch.app.
2. Start `node orch.js serve`, then `open "/tmp/notch-dd/Build/Products/Debug/Boring Notch.app"`
3. Ad-hoc builds can re-trigger macOS privacy prompts (TCC); that is not a regression.
4. When done, quit it and relaunch /Applications/boringNotch.app.

## Tests

### 1. Typing focus
expected: Click in another app and type: the notch never takes keystrokes. Click the message box: typing goes into it; the app in front stays in front (no app switch).
result: pending

### 2. Send
expected: Type a line, press Enter: it appears in the chat tail within ~2s, the box clears, and typing afterwards goes back to the app you were in.
result: pending

### 3. Keep-open
expected: While typing, move the pointer off the notch: it stays open. After Enter, Esc or clicking outside, it closes normally again (never stuck open).
result: pending

### 4. Prompt buttons
expected: Get the orchestrator to ask a question or permission prompt: numbered buttons appear; tap one: exactly that one digit is sent once (double-tap does not answer the next prompt).
result: pending

### 5. Esc
expected: With a prompt up, tap esc: the prompt is cancelled.
result: pending

### 6. End
expected: Tap End: "End chat? Yes / No" appears inline; No (or waiting ~4s) reverts; Yes stops the chat and "chat not running" + Start appears.
result: pending

### 7. Start
expected: Tap Start: the chat starts and its screen appears.
result: pending

### 8. Music
expected: Play a track: closed-notch music activity, open-notch artwork and play/pause/skip all work as before; Home tab unchanged.
result: pending

## Summary
total: 8
passed: 0
issues: 0
pending: 8

## Gaps
