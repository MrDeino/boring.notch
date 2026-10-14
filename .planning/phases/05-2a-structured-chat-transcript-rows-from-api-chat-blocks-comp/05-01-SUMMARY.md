---
phase: 05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp
plan: 01
subsystem: orchestrator-chat
tags: [swift, pure-core, tdd, transcript]
requires: [phase-04 stubs]
provides: [ChatBlock decode/merge, parseInputLine, boxIsDraft, clearToCaret, parseIdleStatus, tool display helpers, proseAttributed]
affects: [05-02, 05-03]
key-files:
  created:
    - boringNotch/Orchestrator/Tests/fixtures/phase5-blocks.json
    - boringNotch/Orchestrator/Tests/fixtures/phase5-blocks-bare.json
  modified:
    - boringNotch/Orchestrator/OrchestratorTranscript.swift
    - boringNotch/Orchestrator/Tests/Phase5Tests.swift
decisions:
  - "boxIsDraft reads 'changed' as non-empty -> different non-empty; literal 'any change' would classify every arriving suggestion as a draft, contradicting R-04's ghost default."
metrics:
  tasks: 2
  completed: 2026-10-14
requirements: [CHAT-01, CHAT-02, CHAT-04]
---

# Phase 5 Plan 01: Transcript pure core Summary

Foundation-only transcript core: lossy `/api/chat/blocks` decoding, id merge with reset/discontinuity rules, input-box parsing, ghost-vs-draft heuristic, clear-to-caret, idle status line and tool display strings. Harness prints OK (61 asserts in Phase5Tests, earlier phases still pass).

PHASE4-PRECONDITION printed PHASE4-OK.

## Commits
- 334afab test(05-01): add failing transcript core asserts (RED; harness did not compile)
- 233bb15 feat(05-01): transcript pure core (GREEN)

## Final signatures
```swift
struct ChatDiffHunk: Decodable, Equatable { oldStart: Int?; newStart: Int?; lines: [String]? }
struct ChatBlock: Decodable, Equatable, Identifiable { enum Kind { user, tool, prose }; id: String; kind: Kind; text, name, target, result: String?; added, removed: Int?; diff: [ChatDiffHunk]? }
func decodeChatBlocks(_ data: Data) -> (running: Bool?, blocks: [ChatBlock])?
func mergeChatBlocks(_ existing: [ChatBlock], _ incoming: [ChatBlock], reset: Bool, cap: Int = 200) -> (blocks: [ChatBlock], appended: Bool)
func blocksDiscontinuous(sinceSent: Bool, incoming: [ChatBlock], existing: [ChatBlock]) -> Bool
func parseInputLine(screen: String) -> String?
func boxIsDraft(previous: String?, current: String?, wasDraft: Bool, editing: Bool) -> Bool
func clearToCaret(_ text: String, caretUTF16: Int?) -> String
func parseIdleStatus(screen: String) -> String?
func toolTargetDisplay(name: String?, target: String?) -> String
func toolResultDisplay(name: String?, result: String?, added: Int?) -> String?
func toolResultIsError(_ s: String?) -> Bool
func proseAttributed(_ s: String) -> AttributedString
```

## Deviations from Plan
- toolResultDisplay uses string suffix parsing instead of a Regex literal: bare `swiftc` (the MERGE-MAP harness) rejects `/.../` literals without an extra flag. Behaviour identical.
- The plan's automated verify path points at another worktree dir; ran in this worktree instead. Harness output dir /tmp/orch-test-p5 per instructions.

## Shared-file edits
None.

## Known Stubs
None.

## Self-Check: PASSED
