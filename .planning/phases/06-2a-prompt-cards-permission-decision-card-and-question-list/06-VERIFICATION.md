---
phase: 06-2a-prompt-cards-permission-decision-card-and-question-list
verified: 2026-10-14T00:00:00Z
status: human_needed
score: 5/5 must-haves verified (automatable portion)
overrides_applied: 0
human_verification:
  - test: "Hover the notch over a live permission prompt; press 1-9 and esc"
    expected: "Hover takes keys after dwell; digit answers; esc denies; the chosen pill fills and others dim for 3s; stray keys within 300 ms of the key-take are ignored"
    why_human: "Needs a real panel, focus handoff and a real Claude Code prompt"
  - test: "Question prompt (single and multi-question) on screen"
    expected: "Frame 04 list: header tag, '1 of 2', wrapping question, default row highlighted, up/down/Return move and select only normal rows, notch grows via expand-down and scrolls on overflow, collapses when the prompt ends"
    why_human: "Visual and window-resize behaviour"
  - test: "'Something else...' free-text two-step (CR-01 UAT A1)"
    expected: "Option number is sent, the screen changes, then typed text plus Enter is sent once; if the select list stays unchanged the submit aborts with a flash and keeps text"
    why_human: "Depends on how real Claude Code redraws after 'Type something.'"
  - test: "'Chat about this' and key release after free-text editing ends with pointer outside (CR-02)"
    expected: "Chat sends its number; key-take is released 150 ms after editing ends with the pointer away"
    why_human: "Focus and pointer behaviour"
  - test: "Terminal-level key gate (WR-04) and multi-display (WR-06)"
    expected: "Digits typed into the terminal are not swallowed; card-raised panels collapse per display"
    why_human: "Real windows and displays"
  - test: "Visual fidelity to README frames 03/04, tooltips with full labels"
    expected: "Matches design"
    why_human: "Visual"
  - test: "Music regression: playback controls, artwork, closed-notch music activity"
    expected: "Unchanged"
    why_human: "Runtime behaviour"
---

# Phase 6: 2a Prompt Cards Verification Report

**Phase Goal:** Claude Code's permission and question prompts appear as designed decision cards the user can answer by click or key
**Re-verification:** No, initial verification

## Observable Truths (ROADMAP success criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | detectPrompt/detectPromptCard return title, purpose/body, kind, header, progress, verified on permission.txt / question.txt | VERIFIED (automated) | `OrchestratorPromptParse.swift` (192 lines) defines `detectPromptCard`, `promptIdentity`, `shortLabel`, roles (.deny/.freeText/.chat). Standalone swiftc harness incl. `Tests/Phase6Tests.swift` (132 lines) built and ran, printed `OK`. Fixtures present: permission.txt, question.txt plus phase6-* |
| 2 | Permission card (title, purpose, command block, shortened pills with full-label tooltip, deny right with esc), chosen pill fills / others dim for 3s lock | VERIFIED in code, visuals human | `OrchestratorPromptCard.swift`: `.help(item.label)` L348, `.help(body)` L317, `optionsLocked && pressed` dim L288, `.disabled(optionsLocked||sending)`. xcodebuild BUILD SUCCEEDED (reported, derived data /tmp/notch-dd-p6) |
| 3 | Question vertical list, grows via expand-down, scrolls | VERIFIED in code, visuals human | `OrchestratorExpand.shared.setLevel(.expanded ...)` L59, collapse to `.open` L46; list view in same file |
| 4 | 1-9 / esc while hovered; Something else sends number then text; Chat about this sends number | VERIFIED in code, runtime human | `NSEvent.addLocalMonitorForEvents(.keyDown)` L133 with gated key-take; `submitFreeText` L198; `footPill("Chat about this", key: chat.number)` L422 |
| 5 | Music unchanged | VERIFIED (static), runtime human | Diff touches no music files (see below) |

Score: 5/5 verified at the code level.

## Requirements Coverage

| ID | Source Plan | Status | Evidence |
|----|-------------|--------|----------|
| PRM-01 | 06-01 | SATISFIED | parser + tests pass |
| PRM-02 | 06-02 | SATISFIED (visual human) | permission card, lock dim, tooltips |
| PRM-03 | 06-02 | SATISFIED (visual human) | question list, setLevel expand/collapse |
| PRM-04 | 06-03 | SATISFIED (runtime human) | local key monitor, hover gate |
| PRM-05 | 06-02, 06-03 | SATISFIED (runtime human) | submitFreeText, Chat about this |

All five IDs appear in plan frontmatter and REQUIREMENTS.md (marked Complete); no orphaned requirements.

## Merge-Map Compliance

`git diff --name-only 5a22cc9..HEAD -- . ':!.planning'` lists exactly:
- boringNotch/Orchestrator/OrchestratorPromptCard.swift
- boringNotch/Orchestrator/OrchestratorPromptParse.swift
- boringNotch/Orchestrator/Tests/Phase6Tests.swift
- boringNotch/Orchestrator/Tests/fixtures/phase6-{edit,fetch,multiq-1,multiq-2}.txt

All Phase 6-owned per MERGE-MAP.md. No shared files and no music code touched (no diff outside `boringNotch/Orchestrator`). COMPLIANT.

## Review Fixes (06-REVIEW-FIX.md)

10 of 11 fixed (CR-01, CR-02, WR-02..WR-09), 1 skipped. Code spot-checks confirm the fixes are present (submitFreeText, stillCurrent with optionsLocked guard, 40-line scan, deny role by label). Harness passes with the added WR-08/WR-09 tests.
- WR-01 (stale-screen guard may compare against a screen up to ~2 s old; needs awaitable refresh in the shared `OrchestratorManager`): SKIPPED, known limitation, documented by a `ponytail:` comment. WARNING, not blocker. It needs a shared-file change, so it is a candidate for a merge-time or Phase 9 follow-up.
- CR-01 and WR-05 are flagged by the fixer as needing human verification on a real screen.

## Anti-Patterns

No TBD/FIXME/XXX/TODO markers in the three Phase 6 source files. No stubs found.

## Behavioral Spot-Checks

| Check | Result |
|-------|--------|
| swiftc harness (Models, Pure, Transcript, PromptParse, RunsPure, Tests/*) | PASS, prints OK |
| xcodebuild | BUILD SUCCEEDED on HEAD (supplied by caller, not rebuilt) |

## Gaps Summary

No automatable gaps. WR-01 is an accepted, documented limitation (warning). Status is human_needed because on-screen behaviour (hover keys, focus handoff, visuals, real prompts, free-text two-step, music) cannot be verified headlessly.

_Verifier: Claude (gsd-verifier)_
