---
phase: 06-2a-prompt-cards-permission-decision-card-and-question-list
fixed_at: 2026-10-14T05:15:01Z
review_path: .planning/phases/06-2a-prompt-cards-permission-decision-card-and-question-list/06-REVIEW.md
iteration: 1
findings_in_scope: 11
fixed: 10
skipped: 1
status: partial
---

# Phase 6: Code Review Fix Report

**Fixed at:** 2026-10-14T05:15:01Z
**Source review:** .planning/phases/06-2a-prompt-cards-permission-decision-card-and-question-list/06-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 11 (2 critical, 9 warning)
- Fixed: 10
- Skipped: 1 (WR-01: the fix needs a change to the shared manager)

Checks after all fixes: the swiftc harness prints `OK` and xcodebuild (derived data `/tmp/notch-dd-p6`) reports `BUILD SUCCEEDED`. Only `OrchestratorPromptCard.swift`, `OrchestratorPromptParse.swift` and `Tests/Phase6Tests.swift` were edited. No shared files were touched.

## Fixed Issues

### CR-01: Free-text submit sends text + Enter even when the option-number press was dropped

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift`
**Commit:** 46a8040
**Status:** fixed: requires human verification (UAT A1)
**Applied fix:** `submitFreeText` now does the following, with no manager change:
1. Runs the `stillCurrent` guard (identity plus `!optionsLocked`, with a flash).
2. Presses the option number.
3. Waits for `sending` to clear, refreshes, and checks whether the select-list prompt has gone or changed (`promptIdentity` differs or `prompt == nil`, and not `offline`, because a failed GET also sets the prompt to nil). It tries this up to 6 times, because `refresh()` can return early while a poll is in flight.
4. Calls `sendText` only if the prompt changed. Otherwise it flashes and keeps the typed text.

**Needs checking on a real screen:** after pressing "Type something.", Claude Code's screen must actually stop parsing as the same prompt. If the select list stays on screen unchanged while text entry is active, every submit will now abort with a flash.

### CR-02: Key-take stays active after free-text editing ends with the pointer outside

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift`
**Commit:** cc06602
**Applied fix:** Added a `didSet` on `fieldEditing`. When editing goes from true to false and the pointer is not over the notch, it re-runs the exit dwell (`hover(false, …)`), so `release()` runs 150 ms later. This covers every way editing can end: Esc, focus loss, and failed submits.

### WR-02: `submitFreeText` uses a different, silent guard

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift`
**Commit:** 46a8040 (same function as CR-01)
**Applied fix:** `submitFreeText` now uses `stillCurrent(displayed)` instead of `m.prompt == displayed`.

### WR-03: Retrying `sendText` can type the text twice; 409 is retried pointlessly

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift`
**Commit:** 46a8040 (same function as CR-01)
**Applied fix:** Removed the 4x retry loop. The text is sent with exactly one POST, and only after `sending` is clear. A timeout, a 409 or any other non-200 result flashes and keeps the text; nothing is re-sent. The bounded wait is now a real `while` loop, which also resolves IN-01.

### WR-04: App-wide local key monitor ignores the terminal key gate

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift`
**Commit:** 1b57091
**Applied fix:**
- `takeKey` refuses while `OrchestratorKeyGate.terminalWantsKey` is set.
- `handle` passes an event through unless `e.window === keyWindow` and the terminal does not want keys.
- `release()` no longer calls `makeFirstResponder(nil)` or `restore()` (which would re-activate the previous app) while the terminal holds the panel.

### WR-05: Arrow keys can highlight items that have no highlight styling

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift`
**Commit:** 6263b38
**Status:** fixed: requires human verification
**Applied fix:** Up/Down now move only over `.normal` rows. Return selects only when the highlight is on one of those rows, so a TUI cursor resting on "Chat about this" can no longer be sent by pressing Return.

### WR-06: One shared controller holds per-display state

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift`
**Commit:** 062dd1c
**Applied fix:**
- Replaced `raisedByCard`/`vm`/`window` with a list of weak `(vm, window)` pairs. When a non-question prompt arrives, every panel the question card expanded is collapsed back to `.open`.
- `promptChanged` re-hovers using the window last passed to `hover(true, …)` instead of the window from the last `sync`.

### WR-07: Hover dwell takes keyboard focus; a stray digit can approve a permission

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift`
**Commit:** 5f2f499
**Applied fix:** This is the smallest of the review's suggested mitigations. Answer, arrow, Return and Esc keys are swallowed, not acted on, for 300 ms after the hover key-take. Keystrokes already in flight for the app that lost focus therefore cannot answer. A `ponytail:` comment records the limit: anyone still typing after 300 ms can still answer. A click-to-arm for permission cards, or a visible "keys active" state, is left for Phase 9.

### WR-08: `detectPromptCard` gated on a 25-line window but parses a 40-line window

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptParse.swift`, `boringNotch/Orchestrator/Tests/Phase6Tests.swift`
**Commit:** 8de0207
**Applied fix:**
- `detectPrompt` now scans the same 40-line window, and `detectPromptCard` gates only on its own 40-line `scanPrompt`, so the two can no longer disagree.
- Added a test with a 34-line question (long option details), which asserts a card and 5 options from both functions.
- Side effect: the manager's `promptOptions`/`needsAttention`, which use `detectPrompt`, now also look back 40 lines. The footer and last-option-within-4-lines checks still apply, and the Phase 3–7 tests pass.

### WR-09: Fallback "deny" role marks an approve or select option red with an esc keycap

**Files modified:** `boringNotch/Orchestrator/OrchestratorPromptParse.swift`, `boringNotch/Orchestrator/Tests/Phase6Tests.swift`
**Commit:** 2cc263b
**Applied fix:**
- Removed the "last normal option" fallback. Only a label starting with No, Cancel or Reject gets `.deny`.
- Added tests: on the multi-select variant no option is deny ("cherry" stays normal), and a Yes/"Yes, always" prompt has no deny.
- Left the deny pill's `esc` keycap as it is. Every remaining deny label is one that Esc also triggers in Claude Code.

## Skipped Issues

### WR-01: Stale-screen guard can compare against a screen up to about 2 s old

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:63-75`
**Reason:** The fix needs an awaitable in-flight refresh (`refreshTask`) inside `OrchestratorManager.refresh()`. `OrchestratorManager.swift` is a shared file outside Phase 6's allowed edits while Phases 5 and 7 run in parallel. The existing `ponytail:` comment in `stillCurrent` records the limit. For the free-text path, CR-01's re-check loop partly makes up for the early return.
**Original issue:** `refresh()` returns at once when a poll is in flight, so `stillCurrent` compares against `m.prompt` from the previous poll.

---

_Fixed: 2026-10-14T05:15:01Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
