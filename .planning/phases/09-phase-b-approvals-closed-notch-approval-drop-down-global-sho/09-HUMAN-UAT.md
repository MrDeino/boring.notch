---
status: partial
phase: 09-phase-b-approvals
source: [09-VERIFICATION.md]
started: 2026-10-14T13:45:01Z
updated: 2026-10-14T13:45:01Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Real approval end to end
expected: With the orchestrator's PermissionRequest hook live, a permission prompt in the orchestrator chat populates `approval` on /api/chat and drops the frame 00 panel down from the closed notch (Allow ⌥⏎ / Deny ⌥⎋ / More…); it closes when answered here or in the terminal.
result: [pending]

### 2. Global hotkeys
expected: In the sandboxed ad-hoc build, ⌥⏎/⌥⎋ answer from another app while the approval is visible (closed drop-down, or notch open on the Orchestrator tab); they are free in other apps when nothing is pending or the approval isn't visible; no permission dialog. On macOS 15.0/15.1 the combos are ⌃⌥ and the pills say so.
result: [pending]

### 3. Content-sized panel
expected: Open/expand/collapse/notes/composer growth resize the real window with one spring, top edge pinned, shrink ~0.65s after collapse; works on a second display.
result: [pending]

### 4. Music
expected: With music playing, an approval drops down over it; after it clears the music live activity and controls return unchanged.
result: [pending]

### 5. Allow edge cases
expected: Allow when option 1 isn't a plain Yes opens the prompt card (More… path) instead of sending; a stale approval id sends nothing.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
