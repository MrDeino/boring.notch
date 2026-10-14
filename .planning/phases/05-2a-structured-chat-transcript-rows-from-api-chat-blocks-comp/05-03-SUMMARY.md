---
phase: 05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp
plan: 03
subsystem: orchestrator-chat
tags: [swift, swiftui, composer]
requires: [05-01, 05-02]
provides: [frame 02/02b composer, ghost suggestion, Tab/right/ctrl-U monitor, line-cleared tag, terminal draft pull-in]
key-files:
  modified:
    - boringNotch/Orchestrator/OrchestratorChat.swift
  created:
    - .planning/phases/05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp/05-HUMAN-UAT.md
requirements: [CHAT-03, CHAT-04]
metrics:
  tasks: 2
  completed: 2026-10-14
---

# Phase 5 Plan 03: Composer and message box Summary

Frame 02 pill composer with ghost suggestion (Tab/right accept), ctrl-U clear with "line cleared" tag, terminal-draft pull-in, and C-u before every send. Build SUCCEEDED, harness OK.

BASE (HEAD before this plan): 58577032c35cf7848b8693d24e01d7ee97889090

## Commits
- 7a0ca86 feat(05-03): composer, ghost, key monitor, line cleared tag (tasks 1 and 2 code, one file)
- docs commit: 05-HUMAN-UAT.md and this summary

## Intended change to moved typing code
submit()'s Task is now `Task { await store.clearRealLineIfNeeded(); if await manager.sendText(t) { draft = ""; fromTerminal = false } }`. startTyping/stopTyping/key-gate untouched (the TextField modifiers were re-indented inside the new pill, same content). The original `onChange(of: fieldFocused)` is kept; a second one handles the monitor and pull-in.

## Key monitor
Local keyDown monitor, installed on focus, removed on blur and onDisappear, filtered to `fieldFocused` and `event.window === keyWindow`. Key codes: Tab 48 and right arrow 124 (no modifiers, only while the ghost suggestion is showing) post `Tab`; U 32 with exactly control clears to the caret and posts `C-u`. Everything else passes through.

## Unverified
On-device key handling (Tab reaching the monitor in the non-activating panel, caret reachability via NSTextView, shimmer, ghost layout) is unverified until 05-HUMAN-UAT.md passes. No app launched, no POSTs made.

## Deviations
- PHASE4-PRECONDITION grep for `init(showComposer: Bool = true)` is stale (init now has extra parameters from 05-02); Phase 4 code is present, so proceeded.
- Verify paths pointed at another worktree; ran here. Harness output /tmp/orch-test-p5, DerivedData /tmp/notch-dd-p5.
- Tasks 1 and 2 touch the same file and were committed together.

## Shared-file edits
None.

## Known Stubs
None.

## Self-Check: PASSED
