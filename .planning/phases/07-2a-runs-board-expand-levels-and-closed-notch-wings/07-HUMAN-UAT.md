---
status: partial
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
source: [07-VERIFICATION.md]
started: 2026-10-14T05:21:06Z
updated: 2026-10-14T05:21:06Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Runs segment: open the notch on the Runs tab with live, waiting, stuck and finished runs
expected: 196px cards (dot, project, elapsed, prompt, mono latest action); waiting first, then running/stuck, then finished; waiting card has orange inset ring; scroll beyond three; bottom row reads 'Orchestrator: <status>'
result: [pending]

### 2. Tap 'Ask in chat' on a waiting card; stop the chat and look at the button
expected: One-line message naming run id, project, question appears in chat only on tap; button reads 'Start chat' when chat stopped and starts it; no Allow/Deny/resume anywhere
result: [pending]

### 3. Click transcript, then press cmd-Down, cmd-T, cmd-Up, Esc, cmd-backslash with the panel key; click outside
expected: open -> expanded (640x~440) -> terminal and back; one continuous spring, content cross-fades after ~120ms; pressing a shortcut that changes no level passes through; outside click closes; no stuck monitors or sharing state (CR-01, WR-04)
result: [pending]

### 4. Expanded view: conversation column, 178px rail with usage bars, Terminal cmd-T pill; terminal frame with toolbar; terminal in use / unavailable + Retry
expected: Matches frames 10 and 12; question card stays visible in the conversation column while a prompt is up
result: [pending]

### 5. Collapse the rail with the chevron buttons and cmd-backslash; relaunch; then let a run start waiting; hover a strip dot
expected: 30px strip with 22px circles, usage ring at bottom; collapsed state persists across relaunch; rail re-opens on a newly waiting run unless collapsed this session; no auto-open at launch or on reconnect (WR-01/02); hover card sits 10pt left of its dot (WR-06)
result: [pending]

### 6. Closed notch with music off: chat working, a prompt/waiting run, a run finishing
expected: Working wing (spinning star + m:ss), Needs you wing (pulsing orange dot + pill), Run finished wing (check + project) for 4s; spinner and glow restart on each re-appearance (WR-03); usage hairline stays; old corner dot hides during needs-you
result: [pending]

### 7. Closed notch with music playing
expected: Music live activity unchanged in layout and width; no wings; 7px orange dot just before the visualizer only when needs-you
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps
