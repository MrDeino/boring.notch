---
status: partial
phase: 08-phase-b-live-data
source: [08-VERIFICATION.md]
started: 2026-10-14T13:17:00Z
updated: 2026-10-14T13:17:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Live updates from serve's stream
expected: With /api/events live, new chat rows, runs, usage and closed-notch wings update within ~1s without opening/closing the notch. Kill serve → offline within seconds; restart → streaming resumes within ~30s (polling meanwhile). With an old serve (no /api/events) the tab behaves as before Phase 8.
result: [pending]

### 2. Streaming caret
expected: While Claude is working and the newest row is prose, an orange 7×13 caret blinks after the last word; it disappears when a tool row appears or the turn ends.
result: [pending]

### 3. Inline ▸ diff
expected: "▸ diff" on Edit/Write/MultiEdit rows opens/closes the frame-12 diff card inline in the open notch without opening the terminal; tapping plain transcript still expands; same in the expanded column.
result: [pending]

### 4. Ghost text vs draft
expected: Serve's input.suggested=true shows as ghost text (Tab accepts locally); a typed terminal draft shows as a draft.
result: [pending]

### 5. ctx % and music
expected: The Running capsule shows "ctx N%" (orange at ≥80%); now-playing and music controls still work while the stream is connected.
result: [pending]

### 6. Prompt context while streaming
expected: A question/permission arriving during a stream shows the latest assistant prose above the card.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
