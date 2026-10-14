---
phase: 06-2a-prompt-cards-permission-decision-card-and-question-list
plan: 01
subsystem: prompt-parser
tags: [swift, parser, tdd]
requires: [phase-04]
provides: [detectPromptCard enriched, shortLabel, moveHighlight, promptKey]
affects: [OrchestratorPromptParse.swift, Tests/Phase6Tests.swift]
key-files:
  created: [Tests/fixtures/phase6-multiq-1.txt, phase6-multiq-2.txt, phase6-edit.txt, phase6-fetch.txt]
  modified: [boringNotch/Orchestrator/OrchestratorPromptParse.swift, boringNotch/Orchestrator/Tests/Phase6Tests.swift]
requirements: [PRM-01]
metrics:
  completed: 2026-10-14
---

# Phase 6 Plan 01: Prompt parser Summary

`detectPromptCard(screen:)` now returns title/purpose/body, question, described items with roles, the highlighted option, chip header and "n of m" progress, plus pure helpers `shortLabel`, `moveHighlight`, `promptKey`; swiftc harness prints OK.

## Commits
- ce04e01 synthetic fixtures
- b401913 RED tests
- af18336 GREEN implementation (also contains a small fix to the test helper's `promptKey` wrapper: `kind:` made a labelled arg)

## Final signatures (06-02/06-03 code against these)
```swift
struct PromptCardOption: Equatable { enum Role { case normal, deny, freeText, chat }
  let number: Int; let label: String; var detail: String? = nil; var role: Role = .normal }
// PromptCard additions: var question: String? = nil; var items: [PromptCardOption] = []; var highlighted: Int? = nil
func shortLabel(_ label: String) -> String
func moveHighlight(_ current: Int?, by delta: Int, in numbers: [Int]) -> Int?
enum PromptKey: Equatable { case answer(Int), escape, up, down, select, pass }
func promptKey(keyCode: UInt16, characters: String?, commandLike: Bool, editingText: Bool, kind: PromptCard.Kind, numbers: Set<Int>) -> PromptKey
```
Notes: `shortLabel` truncation (22 chars) applies only to the unmatched fallback; rule outputs like "Always in /tmp/notch-fixture.WJuB" are returned whole. Deny role is assigned among `.normal` items only. Private `scanPrompt` is shared by `detectPrompt` (window 25) and the card (window 40).

## Phase 4 gate
All greps passed (PromptCard 1, detectPromptCard 1, setLevel 1, level(for vm 1, ExpandLevel 1, OrchestratorPromptCard 1, WindowAnchor non-private, enum OT 1, runPhase6Tests 1 in both files, manager hook 1); harness OK before changes.

## ASSUMED synthetic fixtures needing real captures at UAT
phase6-multiq-1, phase6-multiq-2 (chip line layout, ☒/✔ glyphs), phase6-edit (Edit diff body dropping heuristic), phase6-fetch.

## Deviations from Plan
None of substance.

## Shared-file edits
none

## Self-Check: PASSED
