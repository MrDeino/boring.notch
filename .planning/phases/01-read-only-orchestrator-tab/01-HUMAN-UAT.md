---
status: passed
phase: 01-read-only-orchestrator-tab
source: [01-VERIFICATION.md]
started: 2026-10-14
updated: 2026-10-14
---

## How to run the built app

1. Quit the installed Boring Notch (menu bar icon → Quit). Don't replace /Applications/boringNotch.app.
2. `open "/tmp/notch-dd/Build/Products/Debug/Boring Notch.app"`
3. Ad-hoc builds can re-trigger macOS privacy prompts (TCC). If music info is missing, grant the prompts; that is not a regression.
4. When you're done, quit it and relaunch /Applications/boringNotch.app.

## Tests

### 1. Orchestrator tab layout
expected: The opened notch shows an Orchestrator tab (terminal icon). It shows the chat tail on the left, 5h/7d usage bars with reset times on the right, and up to 3 runs underneath, all fitting the 640x190 notch.
result: passed (user checked the running build 2026-10-14)

### 2. Offline and recovery
expected: With `orch.js serve` stopped, the tab shows "orchestrator offline" with the 127.0.0.1:4777 hint within a few seconds. It recovers on its own when serve returns.
result: passed (user checked the running build 2026-10-14)

### 3. Polling cadence
expected: About a 2s refresh while the notch is open and about 10s while closed.
result: passed (user checked the running build 2026-10-14)

### 4. Music and Shelf unchanged
expected: Playback controls, artwork and closed-notch music activity work as before. With Shelf disabled, the tab bar shows Home and Orchestrator (when "always show tabs" is on, the default) and no Shelf tab.
result: passed (user checked the running build 2026-10-14)

## Summary
total: 4
passed: 4
issues: 0
pending: 0

## Gaps
