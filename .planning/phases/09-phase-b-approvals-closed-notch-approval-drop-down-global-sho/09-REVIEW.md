---
phase: 09-phase-b-approvals-closed-notch-approval-drop-down-global-sho
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 14
files_reviewed_list:
  - boringNotch/ContentView.swift
  - boringNotch/Orchestrator/OrchestratorApproval.swift
  - boringNotch/Orchestrator/OrchestratorCompact.swift
  - boringNotch/Orchestrator/OrchestratorExpand.swift
  - boringNotch/Orchestrator/OrchestratorManager.swift
  - boringNotch/Orchestrator/OrchestratorModels.swift
  - boringNotch/Orchestrator/OrchestratorPure.swift
  - boringNotch/Orchestrator/OrchestratorStream.swift
  - boringNotch/Orchestrator/OrchestratorTokens.swift
  - boringNotch/Orchestrator/Snapshots/SnapClosed.swift
  - boringNotch/Orchestrator/Tests/Phase9Tests.swift
  - boringNotch/Orchestrator/Tests/main.swift
  - boringNotch/Orchestrator/Tests/approval-mock.py
  - boringNotch.xcodeproj/project.pbxproj
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 9: Code Review Report

**Depth:** standard. Static read only; nothing built or run.

## Summary

The core lifecycle holds up. Offline, stop and not-running all clear the approval. The answer gate re-reads the screen and compares ids. Its check-then-hide section has no `await` in it, so a double keypress cannot send twice. The hover guard, the branch order and the wings shift are fine: `OrchestratorWingsView.onDisappear` resets `shiftX` to 0 when the approval branch replaces it. The single `syncWindow` setFrame path is consistent. A pending shrink is cancelled on each call, and the delayed shrink re-reads `target()`. The notch is top- and centre-pinned. Music sizing is unchanged: closed `notchSize` maps to the base window size.

Three robustness gaps and three minor items remain.

## Warnings

### WR-01: Allow on a non-plain option 1 does nothing when the card cannot show

**Status: FIXED**

**File:** `boringNotch/Orchestrator/OrchestratorApproval.swift:156`, `boringNotch/ContentView.swift:295`
**Issue:** `.openCard` is delivered by bumping `cardRequest`, and only `OrchestratorApprovalPanel.onChange` observes it. That view exists only on the closed-notch approval branch. If the notch is open, `hideOnClosed` is set, or an earlier branch (HUD, sneak peek) wins, ⌥⏎ does nothing and gives no feedback. The hotkeys stay registered the whole time (see WR-02).
**Fix:** Handle `cardRequest` where the notch always exists, for example `.onChange(of: approvals.cardRequest)` in ContentView next to the other hooks. It should run the same open-orchestrator-tab code as `onMore`, and only if the notch is closed. Remove the `onChange` from the panel so it does not fire once per screen.

### WR-02: Global hotkeys answer an approval the user cannot see

**Status: FIXED**

**File:** `boringNotch/Orchestrator/OrchestratorApproval.swift:148`
**Issue:** Enable and disable depend only on `approval != nil`, not on whether the card is visible. While `hideOnClosed` is set (fullscreen, for example) or the notch is open on another tab, ⌥⏎ sends a blind "1". The `promptOptions` gate only proves that some prompt is on screen. It does not prove the user has seen the command. ⌥⏎ and ⌥⎋ are also swallowed from other apps for the whole time. Swallowing is intended while pending, but here the user may not know why.
**Fix:** Either accept this as a deliberate design choice and document it, or gate `answer` on visibility. For example, skip when `vm.hideOnClosed`, or require the closed panel or the Orchestrator tab to be showing.

### WR-03: Approval applied before the stale-response check, so a late poll can resurrect a cleared approval

**Status: FIXED**

**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:296`
**Issue:** `applyChat` applies `r.approval` before any `applySeq` comparison, and `.approval` SSE events carry no sequence. A poll that started before an SSE `approval: null` (or before an answer) but finishes after it re-applies the old approval. The poll-from-before-the-answer case is covered for 3 seconds by the ignore window. The SSE-null case is not, and neither is a stale response arriving after the window. The panel and the hotkeys then flash back until the next poll. A hotkey press in that gap goes through the re-read, which is safe. The effect is flicker plus a 3s-window hotkey grab.
**Fix:** Take `mine = applySeq` before the `get` in `load()` and skip the approval apply when a newer SSE approval event has arrived since. For example, stamp `lastApprovalSeq` on SSE events and ignore poll results that started earlier.

## Info

### IN-01: Malformed approval is handled differently on the two paths

**File:** `boringNotch/Orchestrator/OrchestratorModels.swift:78` and `boringNotch/Orchestrator/OrchestratorStream.swift:56`
**Issue:** A poll body whose `approval` object is malformed (for example, no `id`) gives `hasApproval == true` with `approval == nil`, which clears the pending approval. A malformed SSE event keeps the current one. Failing closed on the poll path is arguably right, but the inconsistency is undocumented.
**Fix:** Pick one behavior and make the comments match.

### IN-02: Corner radius changes even when the panel is not drawn

**File:** `boringNotch/ContentView.swift:59`
**Issue:** The radius check uses only `approvals.approval != nil && closed`. It does not check `hideOnClosed` or the HUD branches that take precedence over the panel, so the notch gets the 22pt radius with no panel.
**Fix:** Reuse one `showsApprovalPanel` computed property for both places.

### IN-03: Shortcut re-set on every launch

**File:** `boringNotch/Orchestrator/OrchestratorApproval.swift:136`
**Issue:** `setShortcut` runs on every `init`, so user customisation is overwritten. The comment says this is intentional so the labels always match. Deny sends Escape, and in Claude Code Esc on a permission prompt may also interrupt the turn. This is worth confirming against the contract.
**Fix:** None required if intended.

---

_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
