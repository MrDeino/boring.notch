---
phase: 01-read-only-orchestrator-tab
fixed_at: 2026-10-14T00:00:00Z
review_path: .planning/phases/01-read-only-orchestrator-tab/01-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 1: Code Review Fix Report

**Scope:** WR-01, WR-02, WR-04, WR-06 (WR-03, WR-05 and info items excluded by request).

## Fixed Issues

### WR-06: Shelf gating change alters existing header behaviour
**Files:** `boringNotch/components/Notch/BoringHeader.swift`
**Commit:** 5948ee8
Condition is now `(!tvm.isEmpty && Defaults[.boringShelf]) || coordinator.alwaysShowTabs`.

### WR-04: detectPrompt returns the last run even if worse
**Files:** `boringNotch/Orchestrator/OrchestratorModels.swift`, `boringNotch/Orchestrator/Tests/main.swift`
**Commit:** 4660336
`best` only updates when the run has 2+ options and a `❯` marker. Added regression assert (trailing `1. foo`). Logic fix: requires human verification.

### WR-01: Stale attention state while offline
**Files:** `boringNotch/Orchestrator/OrchestratorManager.swift`
**Commit:** 52bf6f4
Catch clears `runs` and `promptOptions` so `needsAttention` is false offline. Logic fix: requires human verification.

### WR-02: Overlapping refreshes
**Files:** `boringNotch/Orchestrator/OrchestratorManager.swift`
**Commit:** 51e099b
`refresh()` returns immediately if one is already in flight.

## Verification
- swiftc test script: OK
- xcodebuild Debug: BUILD SUCCEEDED

---
_Fixer: Claude (gsd-code-fixer)_
