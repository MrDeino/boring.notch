---
status: partial
phase: 04-2a-foundation-tokens-view-split-status-capsule-header-status
source: [04-03-PLAN.md]
started: 2026-10-14
updated: 2026-10-14
---

## How to run the built app

1. Quit the installed Boring Notch. Don't replace /Applications/boringNotch.app.
2. `open "/tmp/notch-dd/Build/Products/Debug/Boring Notch.app"`
3. Ad-hoc builds may re-trigger macOS privacy prompts; grant them (not a regression).
4. Quit it when done and relaunch /Applications/boringNotch.app.

## Current Test

[awaiting human testing]

## Tests

### 1. Header fit
expected: On the Orchestrator tab, tab icons + "Chat | Runs N" fit left of the hardware notch without clipping (TabButton padding 5); capsule sits right, before battery.
result: [pending]

### 2. Segment
expected: Runs count turns orange when a run is waiting, gray otherwise, hidden at 0; segment disappears offline and on Home/Shelf tabs; tapping Runs shows the runs board, Chat returns.
result: [pending]

### 3. Capsule variants
expected: Connecting at launch, Idle with ring when the chat is idle, Running while Claude works ("✻ … esc to interrupt" on screen), Needs you on a prompt or waiting run, Stopped after End, Offline with serve stopped; label cross-fades; ring orange at >= 80% 5h usage.
result: [pending]

### 4. Status menu
expected: Opens under the capsule inside the notch (not a separate window), fits within the 190px notch, content dims to 35%; usage rows show percent + reset; Open terminal opens the terminal; Interrupt sends one Escape (double-click within 1s sends one); End asks End/Cancel and reverts after 4s; Start chat when stopped; outside tap / capsule re-tap / tab change / notch close close it. From Home tab, capsule tap switches to Orchestrator and opens the menu.
result: [pending]

### 5. States
expected: Stopped screen copy, white Start chat pill, "N runs still active · see Runs" switches to Runs; Offline copy + mono chip + "Retrying every 10s" and reconnects within ~10s of starting serve; Connecting skeleton bars + composer pill on first open.
result: [pending]

### 6. Regression
expected: Message box typing still takes the keyboard and sends; prompt option buttons + esc with 3s lock; tapping the transcript opens the terminal and outside click collapses; closed-notch attention dot and usage hairline; typing then opening the menu releases the keyboard.
result: [pending]

### 7. Music unchanged (BLD-02)
expected: Now-playing, play/pause/skip, artwork and the closed-notch music live activity behave as before.
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps
