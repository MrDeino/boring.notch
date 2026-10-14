---
status: partial
phase: 06-2a-prompt-cards-permission-decision-card-and-question-list
source: [06-VERIFICATION.md]
started: 2026-10-14
updated: 2026-10-14
---

## How to run the built app

1. Quit the installed Boring Notch. Don't replace /Applications/boringNotch.app.
2. `open "/tmp/notch-dd-p6/Build/Products/Debug/Boring Notch.app"` (or the merged build after 5/6/7 merge)
3. Ad-hoc builds may re-trigger macOS privacy prompts; grant them (not a regression).
4. Quit it when done and relaunch /Applications/boringNotch.app.

## Current Test

[awaiting human testing]

## Tests

### 1. Permission card + hover keys on a live permission prompt
expected: Frame 03 card (title, purpose, `$` command, pills, red Deny with esc keycap on the right, full-label tooltips). Hover ~0.3s takes keys; 1-9 answers; esc denies; chosen pill fills, others dim; keys within 300 ms of the key-take are ignored; pointer exit hands focus back (cmd-Tab, cmd-C still work).
result: [pending]

### 2. Question prompt (single and multi-question)
expected: Frame 04 list: header tag, "1 of 2" / "2 of 2", wrapping question, default row highlighted; up/down/Return move and select only normal rows; notch grows via expand-down, scrolls on overflow, collapses when the prompt ends; Q2 answerable by key without moving the mouse.
result: [pending]

### 3. "Something else…" free-text two-step (CR-01, assumption A1)
expected: Option number is sent, the screen changes, then the text + Enter is sent once. If the select list stays unchanged the submit aborts with a flash and keeps the text.
result: [pending]

### 4. "Chat about this" and key release after free-text editing (CR-02)
expected: Chat sends its number; key-take is released ~150 ms after editing ends with the pointer away.
result: [pending]

### 5. Terminal key gate (WR-04) and multi-display (WR-06)
expected: Digits typed into the terminal are not swallowed; card-raised panels collapse per display.
result: [pending]

### 6. Real prompt fixtures
expected: GET /api/chat on real Edit/Write, WebFetch, MCP and multi-question prompts parses the same as the synthetic phase6-* fixtures (replace them with real captures).
result: [pending]

### 7. Music regression
expected: Now-playing, controls, artwork and closed-notch music activity unchanged.
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps
