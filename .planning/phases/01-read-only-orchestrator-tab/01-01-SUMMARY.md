---
phase: 01-read-only-orchestrator-tab
plan: 01
subsystem: orchestrator-tab
tags: [swiftui, urlsession, polling]
requires: []
provides: [Orchestrator tab, OrchestratorManager.shared polling GET /api/chat, chatTail]
affects: [notch tab strip, BoringViewModel open/close]
tech-stack:
  added: []
  patterns: ["@MainActor ObservableObject singleton", "Task.sleep polling loop"]
key-files:
  created:
    - boringNotch/Orchestrator/OrchestratorModels.swift
    - boringNotch/Orchestrator/OrchestratorManager.swift
    - boringNotch/Orchestrator/OrchestratorView.swift
    - boringNotch/Orchestrator/Tests/main.swift
  modified:
    - boringNotch.xcodeproj/project.pbxproj
    - boringNotch/enums/generic.swift
    - boringNotch/components/Tabs/TabSelectionView.swift
    - boringNotch/components/Notch/BoringHeader.swift
    - boringNotch/ContentView.swift
    - boringNotch/models/BoringViewModel.swift
    - boringNotch/boringNotchApp.swift
decisions:
  - "Orchestrator tab shown regardless of Shelf; Shelf tab filtered out when Shelf disabled"
  - "Polling starts at app launch; 2s open / 10s closed; GET only, ephemeral 3s session"
metrics:
  completed: 2026-10-14
  tasks: 3
---

# Phase 1 Plan 01: Walking skeleton Summary

Orchestrator notch tab polling `GET /api/chat` (2s open / 10s closed, from launch) and showing the trimmed chat tail, with offline/connecting/not-running states.

## Commits
- ca30d9e test: failing chat model/chatTail test
- 4c782e1 feat: ChatResponse + chatTail
- 1b1278d feat: manager, view, pbxproj group
- 5ad903d feat: upstream hooks (enum, tabs, header gate, ContentView, open/close, app start)

## Verification
- xcodebuild ad-hoc: BUILD SUCCEEDED
- swiftc test: OK

## Deviations from Plan
- Test fixture assertion corrected (idle box fixture has 4 non-blank lines, not 3); fixed in the GREEN commit alongside the implementation.
- No main-actor isolation fallbacks were needed for the hooks.

## Known Stubs
None. Plan 02 extends `refresh()` with `/api/state`.

## Self-Check: PASSED
