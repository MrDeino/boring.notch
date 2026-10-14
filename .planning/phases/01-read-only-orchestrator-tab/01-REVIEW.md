---
phase: 01-read-only-orchestrator-tab
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - boringNotch/Orchestrator/OrchestratorManager.swift
  - boringNotch/Orchestrator/OrchestratorModels.swift
  - boringNotch/Orchestrator/OrchestratorView.swift
  - boringNotch/Orchestrator/Tests/main.swift
  - boringNotch.xcodeproj/project.pbxproj
  - boringNotch/ContentView.swift
  - boringNotch/boringNotchApp.swift
  - boringNotch/components/Notch/BoringHeader.swift
  - boringNotch/components/Tabs/TabSelectionView.swift
  - boringNotch/enums/generic.swift
  - boringNotch/models/BoringViewModel.swift
findings:
  critical: 0
  warning: 6
  info: 3
  total: 9
status: issues_found
---

# Phase 01: Code Review Report

**Depth:** standard
**Status:** issues_found

## Summary

Read-only tab is GET-only (verified: only `session.data(from:)`, no POST/process spawn) and music code is untouched except two one-line hooks in `open()`/`close()`. No blockers. Main concerns: stale attention state while offline, overlapping refreshes, `detectPrompt` overwriting its best run, strict decoding mapping to "offline", multi-display `notchOpen` flag, and the BoringHeader Shelf-gating edit changing existing behaviour.

## Warnings

### WR-01: Stale state and attention dot persist while offline

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:68-70`
**Issue:** The `catch` only sets `offline = true`; `runs`, `promptOptions`, `screen`, `chatRunning` keep their last values. `needsAttention` therefore stays true forever after the server dies with a waiting run, and recovery relies on a later successful poll.
**Fix:** In the catch, clear derived state: `runs = []; promptOptions = []; chatRunning = false; screen = ""; usage = nil` (guarded by equality like the success path), or make `needsAttention` return false when `offline`.

### WR-02: Overlapping refreshes can apply stale responses out of order

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:23-25, 38-45`
**Issue:** The `notchOpen` `didSet` spawns an untracked `Task { await refresh() }` while the poll loop may be mid-`refresh()` (timeouts up to 3s/5s). Two refreshes interleave at suspension points and the older response can land last, showing old state (or flipping `offline` incorrectly). The loop also sleeps up to 10s after closing, so the "2s while open" cadence only starts after the sleep ends (masked by the immediate refresh).
**Fix:** Keep a single in-flight guard (`private var refreshing = false; guard !refreshing else { return }; refreshing = true; defer { refreshing = false }`) or wake the loop by cancelling/restarting the sleep instead of spawning a second task.

### WR-03: Decoding failure is reported as "orchestrator offline"

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:61-70`, `OrchestratorModels.swift:27-34`
**Issue:** Any thrown error (non-200, `CancellationError`, JSON type mismatch such as `id` being a number, or one malformed run element) sets `offline = true`, and the whole view is replaced by the offline message. The "all fields optional" design protects against missing keys, not wrong types. Also a non-200 from `GET /api/chat` (e.g. if chat not running yields 409/404) would hide runs and usage even though `/api/state` works, because both are fetched with `try await (chat, state)`.
**Fix:** Distinguish transport errors (`URLError`) from decode/HTTP errors; fetch chat and state independently (`try?` each) and set offline only when both fail at the transport level. Ignore `CancellationError`.

### WR-04: `detectPrompt` returns the last run even if it is a worse one

**File:** `boringNotch/Orchestrator/OrchestratorModels.swift:80-86`
**Issue:** `best` is reassigned on every appended option. A real prompt (`❯ 1. Yes / 2. No`) followed within the last 25 lines by any later line like `1. something` (e.g. assistant text, a list in the footer) replaces `best` with `([1], false)` and the function returns `[]`, losing the prompt. A stale answered prompt higher on the screen, with no later run, is still returned. Not covered by the tests.
**Fix:** Only replace `best` when the new run qualifies (`run.count >= 2 && marked`), and prefer the last qualifying run; add a test with a trailing `1. foo` line.

### WR-05: `notchOpen` is a single global flag fed by per-display view models

**File:** `boringNotch/models/BoringViewModel.swift:195, 209`, `OrchestratorManager.swift:23`
**Issue:** With `showOnAllDisplays`, each screen has its own `BoringViewModel`. Closing one while another is open sets `notchOpen = false`, dropping to the 10s poll while a notch is visible. Opening a second one does not retrigger refresh (no false-to-true edge).
**Fix:** Track a count of open notches (`openCount += 1/-= 1`) or compute from the set of view models.

### WR-06: Shelf gating change alters existing header behaviour

**File:** `boringNotch/components/Notch/BoringHeader.swift:19`, `components/Tabs/TabSelectionView.swift:29`
**Issue:** Removing `&& Defaults[.boringShelf]` makes the tab bar appear whenever the shelf is non-empty even if the user disabled the Shelf (previously hidden); the filter in `TabSelectionView` hides only the Shelf button. Drag-enter and `openShelfByDefault` still set `currentView = .shelf` (`boringNotchApp.swift:227,230`, `BoringViewModel.swift:217`) with the shelf disabled, leaving a Shelf view with no selected tab (pre-existing, but now more visible). With `alwaysShowTabs == false` and an empty shelf the Orchestrator tab is unreachable, and `alwaysShowTabs`' `didSet` can only reset to `.home`, which is fine. Upstream-merge conflict surface in `BoringHeader` is small but real.
**Fix:** Keep the original header condition semantic: `(!tvm.isEmpty && Defaults[.boringShelf]) || coordinator.alwaysShowTabs`; guard the `.shelf` assignments with `Defaults[.boringShelf]` if desired.

## Info

### IN-01: `[weak self]` in a singleton poll loop is moot

**File:** `OrchestratorManager.swift:34-41`
**Issue:** `guard let self` re-strongs each iteration; no cancellation API (`stop()`) exists, so the task is never cancelled and `Task.isCancelled` is dead. Harmless for a singleton but misleading.
**Fix:** Drop `[weak self]` or add `stop()` that cancels and nils `pollTask`.

### IN-02: `stableID` can collide

**File:** `OrchestratorModels.swift:35-36`, `OrchestratorView.swift:78`
**Issue:** Runs without `id` and with equal project/prompt share a ForEach id (SwiftUI duplicate-id warnings, wrong diffing).
**Fix:** Use `ForEach(Array(runs.enumerated()), id: \.offset)` or append the index.

### IN-03: Test target is not wired and uses `precondition`

**File:** `boringNotch/Orchestrator/Tests/main.swift`
**Issue:** Not in the Xcode project (correct, since it's a script), but nothing documents how it runs and `precondition` aborts without naming the failing assertion. Missing cases: trailing-option overwrite (WR-04), wrong-type decoding (WR-03).
**Fix:** Document the `swiftc` invocation in a header comment; add the cases above.

---

_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
