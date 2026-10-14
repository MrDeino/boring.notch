---
phase: 03-compact-indicators-expand-down
plan: 01
subsystem: ui
tags: [swiftui, notch, indicators]
requires: []
provides:
  - OrchestratorClosedIndicators (attention dot + usage hairline on closed notch)
  - usageFraction pure helper (OrchestratorPure.swift)
affects: [03-02]
key-files:
  created:
    - boringNotch/Orchestrator/OrchestratorPure.swift
    - boringNotch/Orchestrator/OrchestratorCompact.swift
    - boringNotch/Orchestrator/Tests/Phase3Tests.swift
  modified:
    - boringNotch/ContentView.swift
    - boringNotch/Orchestrator/Tests/main.swift
    - boringNotch.xcodeproj/project.pbxproj
requirements-completed: [CMP-01, CMP-02]
duration: 10min
completed: 2026-10-14
---

# Phase 3 Plan 1: Closed-notch indicators Summary

Orange attention dot (shown even while music plays) and a 2pt usage hairline (max of 5h/7d, orange at >=80%) as a hit-test-free overlay on the closed notch; hidden when offline, open, hidden-on-closed, zero-height or during hello animation.

## Commits
- 069cbf2: usageFraction + Phase3Tests (harness prints OK)
- 81e8cf5: OrchestratorCompact view, ContentView hook, pbxproj

## Decisions
- D-02: hairline fits as a bottom overlay with no layout change, so it shows alongside music. Fallback if UAT dislikes it with music: gate on `!MusicManager.shared.isPlaying`.
- Dot is never gated on music (no MusicManager reference in the file).

## Merge with Phase 2
- ContentView.swift: +1 line, `.overlay { OrchestratorClosedIndicators() }` after the top Rectangle overlay, before `.shadow(`.
- Tests/main.swift: +1 line, `runPhase3Tests()` before `print("OK")`.
- project.pbxproj: new IDs in range `0A1C000000000000000003xx` (0301/0302 file refs, 0311/0312 build files); added to the Orchestrator group and app Sources phase.
- Harness compile line now includes OrchestratorPure.swift and Tests/Phase3Tests.swift.
- Dot latency: up to 10s while closed (existing poll rate, unchanged).

## Deviations
None. Pending human UAT: closed notch with music playing shows dot beside visualizer when a run waits; hairline visible; artwork/visualizer unchanged. App not launched; no requests made to 127.0.0.1:4777.

## Self-Check: PASSED
Build succeeded (/tmp/notch-dd-p3), ContentView diff is +1/-0, harness OK, commits present, no music files touched.
