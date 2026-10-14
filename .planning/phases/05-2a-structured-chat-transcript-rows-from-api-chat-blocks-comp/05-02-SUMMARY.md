---
phase: 05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp
plan: 02
subsystem: orchestrator-chat
tags: [swift, swiftui, transcript]
requires: [05-01]
provides: [OrchestratorTranscriptStore body, frame 01 rows, live status row]
affects: [05-03]
key-files:
  modified:
    - boringNotch/Orchestrator/OrchestratorChat.swift
requirements: [CHAT-01, CHAT-02, CHAT-05]
metrics:
  tasks: 2
  completed: 2026-10-14
---

# Phase 5 Plan 02: Transcript store and rows Summary

OrchestratorTranscriptStore now fetches `/api/chat/blocks` (since-merge by id), falls back non-fatally to chatTail, and the chat view renders frame 01 rows plus a ticking, shimmering status row. Build SUCCEEDED, harness OK.

BASE (HEAD before this plan): 98b372fbb1a204d0e5eae9de365e56dfc46cfaff

## Commits
- eee9dc8 feat(05-02): transcript store fetches and merges chat blocks
- 848d940 feat(05-02): frame 01 transcript rows, live status row, insert motion

## Store public members (for 05-03)
`blocks`, `fallback`, `inputLine`, `boxIsDraft`, `idleStatus` (all `@Published private(set)`), `postKey(_:)`, `clearRealLineIfNeeded()`, `refresh(base:session:screen:chatRunning:)` (signature unchanged).

## Decisions
- Status row copy is the README's literal "✻ Working · m:ss" (not the spinner verb in `status.text`); just "✻ Working" when elapsed is nil.
- No blocks fetch while the notch is closed (the open transition triggers a refresh); full resync on first fetch and every 15th open poll.
- Only appended rows animate (spring 0.3/0.85); resets and in-place updates are plain.
- Blocks failures only set `fallback`; the manager's offline flag is never touched.

## Deviations from Plan
- [Rule 3] The store property `boxIsDraft` shadows the global function inside the class, so a private file-level wrapper `globalBoxIsDraft(...)` calls it.
- Plan's verify path pointed at another worktree; ran here. Harness output in /tmp/orch-test-p5, DerivedData /tmp/notch-dd-p5.
- Shimmer is visual-only and unverified on screen (no app launch allowed); on-device check belongs to 05-HUMAN-UAT.md.

## Shared-file edits
None.

## Known Stubs
None.

## Self-Check: PASSED
