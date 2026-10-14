---
phase: 02-sending-prompt-answers
verified: 2026-10-14T00:00:00Z
status: human_needed
score: 5/5 roadmap truths verified at code level (runtime parts need human)
human_verification:
  - test: "UAT 1-8 in 02-HUMAN-UAT.md (typing focus, send, keep-open, prompt buttons, esc, End, Start, music)"
    expected: "See 02-HUMAN-UAT.md; all 8 currently pending"
    why_human: "Keyboard focus, notch staying open, panel key-window behaviour and real button POSTs cannot be checked without running the app"
---

# Phase 2: Sending & Prompt Answers Verification Report

**Goal:** User can steer the orchestrator from the notch: send messages, answer numbered prompts, cancel, start or end the chat.
**Status:** human_needed (no code-level gaps)

## Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Gated canBecomeKey (no app activation); detectPrompt fixtures from real captures | VERIFIED (code) | BoringNotchSkyLightWindow.swift:112 `canBecomeKey { OrchestratorManager.shared.keyboardWindow === self }`, keyboardWindow set only in beginTyping and nil'd in endTyping; no `NSApp.activate` anywhere. Real fixtures `Tests/fixtures/question.txt`, `permission.txt`; harness passes (5 and 4 options, idle/unmarked/lone/scrolled cases return []). Runtime key behaviour: human. |
| 2 | Type, Enter, appears in chat tail; notch stays open while typing, released on submit/Esc/outside click/close | VERIFIED (code), runtime human | submit() -> sendText -> post(.text) -> refresh on 200, draft cleared on success. beginTyping calls SharingStateManager.beginInteraction (preventNotchClose is honoured in ContentView/BoringViewModel); endTyping idempotent/balanced; stopTyping on submit, onExitCommand, focus loss, didResignKey, onDisappear, chat stop, offline, prompt shown. INT-06 fix dcfa824 removed pointer-leave ending. |
| 3 | Prompt options as buttons; one tap sends only that digit once; Esc control | VERIFIED (code) | promptOptions from detectPrompt (only when chat running); pressOption guards `optionsLocked`, locks, 3s timer with generation, unlock on prompt change; key allowlist 1-9; esc button debounced 1s and sends Escape. "Type something." button intentionally hidden (IN-06). |
| 4 | Start when not running; End asks inline confirm then stops | VERIFIED (code) | `!chatRunning` shows Start -> POST api/chat/start; End -> "End chat? Yes/No", 4s revert, Yes -> POST api/chat/stop. 409 handled as refresh. |
| 5 | Music unchanged | VERIFIED (code) | `git diff --name-only d7edeef -- boringNotch`: only 4 files under Orchestrator/ plus BoringNotchSkyLightWindow.swift (one-line canBecomeKey change). No music/media files touched. Runtime: human. |

## Behavioral checks

| Check | Result |
|-------|--------|
| Harness (OrchestratorModels + Tests/main.swift) | OK |
| xcodebuild Debug (ad-hoc) | BUILD SUCCEEDED |
| POSTs sent to 4777 by verifier | none |

## Requirements Coverage

| ID | Source plan | Status | Evidence |
|----|-------------|--------|----------|
| INT-01 | 02-01, 02-02 | SATISFIED (code) | OrchestratorPost.text, TextField onSubmit -> sendText |
| INT-02 | 02-01, 02-02 | SATISFIED (code) | detectPrompt + option buttons -> pressOption -> .key(digit) |
| INT-03 | 02-01, 02-02 | SATISFIED (code) | esc button -> pressEscape -> .key("Escape") |
| INT-04 | 02-01, 02-02 | SATISFIED (code) | Start button -> .start |
| INT-05 | 02-01, 02-02 | SATISFIED (code) | End confirm -> .stop |
| INT-06 | 02-02 | SATISFIED (code), runtime human | beginInteraction held while typing; pointer-leave no longer ends typing |

No orphaned requirements: REQUIREMENTS.md maps exactly INT-01..06 to Phase 2 and all appear in plan frontmatter. (REQUIREMENTS.md checkboxes still show Pending; update after UAT.)

## Anti-patterns

No TBD/FIXME/XXX in boringNotch/Orchestrator. Reviewed 02-REVIEW findings; 8 of 9 in-scope fixed, IN-02/03/04 deliberately left (info-level).

## Warnings

- Typing start is rolled back if the panel refuses key (by design); real behaviour unverified until UAT 1.
- Esc-in-box and keyboard handback to the previous app (`front.activate()`) are unverified at runtime (WR-02).

## Human Verification Required

All 8 items in `.planning/phases/02-sending-prompt-answers/02-HUMAN-UAT.md` (status pending): typing focus, send, keep-open, prompt buttons, esc, End, Start, music regression.

---
_Verified: 2026-10-14_
_Verifier: Claude (gsd-verifier)_
