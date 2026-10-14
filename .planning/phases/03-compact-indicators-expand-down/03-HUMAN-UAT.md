---
status: partial
phase: 03-compact-indicators-expand-down
source: [03-VERIFICATION.md]
started: 2026-10-14
updated: 2026-10-14
---

## How to run the built app

1. Quit the installed Boring Notch. Don't replace /Applications/boringNotch.app.
2. `open "/tmp/notch-dd-p3/Build/Products/Debug/Boring Notch.app"`
3. Ad-hoc builds may re-trigger macOS privacy prompts; grant them (not a regression).
4. Quit it when done and relaunch /Applications/boringNotch.app.

## Current Test

[awaiting human testing]

## Tests

### 1. Closed-notch usage hairline
expected: Thin bar along the bottom edge of the closed notch, width = max of 5h/7d usage; orange at >= 80%.
result: [pending]

### 2. Attention dot, including with music
expected: Small orange dot at the closed notch's top-right when a run is waiting or the chat shows a numbered prompt (appears within ~10s). It still shows while music plays; it doesn't clash with the visualizer; artwork and music layout are unchanged.
result: [pending]

### 3. Expand down
expected: The expand arrow at the bottom-right of the Orchestrator tab grows the same notch downward (top edge fixed) with a larger chat tail and the live terminal.
result: [pending]

### 4. Typing in the terminal
expected: Keystrokes reach the terminal while expanded. If another viewer holds the terminal, it shows "terminal in use" with Retry. Killing serve mid-session shows "terminal unavailable".
result: [pending]

### 5. Collapse and focus return
expected: The button, a click outside (desktop, another app, panel margin), leaving the tab, or closing the notch all collapse it to normal size. Typing goes back to the previously active app and the notch no longer takes keystrokes. Clicking into another app leaves that app in front. Reopening starts at normal size. Retry works after collapse and re-expand. While expanded, hover-exit and down-swipe deliberately don't close the notch.
result: [pending]

### 6. Multi-display (if used)
expected: Expanding on one display and clicking outside collapses and closes it. Known limitation: while any notch is expanded, notches on other displays don't hover-close.
result: [pending]

### 7. Music unchanged
expected: Playback controls, artwork, and closed-notch music activity work as before; hover/open/close on a normal notch behave as before.
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps
