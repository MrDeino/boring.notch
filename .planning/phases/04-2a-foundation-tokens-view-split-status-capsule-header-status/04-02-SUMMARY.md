---
phase: 04-2a-foundation-tokens-view-split-status-capsule-header-status
plan: 02
subsystem: ui
tags: [swiftui, view-split, states]
requires: [04-01]
provides: [OrchestratorChatView, OrchestratorPromptCard, OrchestratorRunsBoard, state screens, thin shell]
affects: [04-03, 05, 06, 07]
key-files:
  created: []
  modified: [OrchestratorView, OrchestratorChat, OrchestratorPromptCard, OrchestratorRunsBoard, OrchestratorStates, OrchestratorExpanded]
requirements-completed: [FND-02, FND-06, FND-07]
duration: 10min
completed: 2026-10-14
---

# Phase 4 Plan 02: View split Summary

Today's OrchestratorView split into Chat (typing/key-gate moved verbatim), PromptCard, RunsBoard and States files; the shell is a state switch plus the expand-level hook.

## Commits
- 7e007c8 feat(04-02): view split, states, thin shell (both tasks in one commit)

## Verification
BUILD SUCCEEDED (/tmp/notch-dd); harness prints OK; only files under boringNotch/Orchestrator/ changed; no POST, no app launched.

## Deviations from Plan
None, except Tasks 1 and 2 were committed together in one commit.

## Accepted behaviour changes
- Switching to Runs unmounts the chat (onDisappear ends typing; an unsent draft is lost).
- A level change remounts the chat view.
- "1 run still active" pluralisation.
- The prompt card replaces the transcript while manager.prompt != nil (plan revision).

## API contract additions (binding for Phases 5-7)
- OrchestratorChat.swift: `struct OrchestratorChatView: View` with explicit `init(showComposer: Bool = true)`. Renders the transcript (tap -> `OrchestratorExpand.shared.transcriptTapped(vm:window:)`) and, when showComposer, the composer. It does NOT render the prompt card. Phase 5 keeps the name and init (add only defaulted parameters).
- OrchestratorView.swift (Phase 4 only): `struct WindowAnchor: NSViewRepresentable { let view: NSView }` (internal; Phase 5 must not redeclare it); `struct OrchestratorTabContent: View` (parameterless) = state switch: `!hasLoaded` -> Connecting; `offline` -> Offline; `showRunsBoard` -> RunsBoard; `!chatRunning` -> Stopped; `prompt != nil` -> OrchestratorPromptCard() (replaces transcript); else OrchestratorChatView(). `OrchestratorView` renders `OrchestratorExpandedView()` when `expand.level(for: vm) != .open`, else `OrchestratorTabContent()`.
- OrchestratorPromptCard: parameterless, reads OrchestratorManager.shared. Phase 6 replaces the body.
- OrchestratorRunsBoard: parameterless. Phase 7 replaces the body.
- OrchestratorStates.swift: OrchestratorConnectingView, OrchestratorOfflineView, OrchestratorStoppedView (parameterless).
- OrchestratorExpandedView: parameterless; Phase 4 body = `OrchestratorTabContent().overlay { OrchestratorExpandOverlay() }`. Phase 7 replaces it.
- Deviation from MERGE-MAP order: runs board is checked before stopped.

## Known Stubs
None new. The old header controls (OrchestratorRunsButton, OrchestratorChatButton, OrchestratorUsageBadge) remain in OrchestratorView.swift until 04-03.

## Self-Check: PASSED
