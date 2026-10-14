---
phase: 04-2a-foundation-tokens-view-split-status-capsule-header-status
fixed_at: 2026-10-14T00:00:00Z
review_path: .planning/phases/04-2a-foundation-tokens-view-split-status-capsule-header-status/04-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 4: Code Review Fix Report

**Fixed at:** 2026-10-14
**Source review:** .planning/phases/04-2a-foundation-tokens-view-split-status-capsule-header-status/04-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 2 (WR-01, WR-02). Info items left as requested.
- Fixed: 2
- Skipped: 0

Verification: the swiftc harness prints OK and the xcodebuild Debug ad-hoc build succeeded after both fixes. The app was not launched, /term was not loaded, and no requests were made to 127.0.0.1:4777.

## Fixed Issues

### WR-01: Opening the status menu while typing leaves the app activated
**Files modified:** `boringNotch/Orchestrator/OrchestratorChat.swift`
**Commit:** 9848dfd
**Applied fix:** The `statusMenuOpen` handler now calls `stopTyping()` with the default `handBack: true`, so `OrchestratorKeyGate.restore` returns focus to the previous app.

### WR-02: `showRunsBoard` is sticky and hides a live prompt
**Files modified:** `boringNotch/Orchestrator/OrchestratorView.swift`
**Commit:** 9a6f647
**Status:** fixed: requires human verification
**Applied fix:** `OrchestratorTabContent` has two `.onChange` handlers that set `manager.showRunsBoard = false` when a prompt appears and when `offline` becomes true. Branch order and `OrchestratorManager` are unchanged.

---

_Fixed: 2026-10-14_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
