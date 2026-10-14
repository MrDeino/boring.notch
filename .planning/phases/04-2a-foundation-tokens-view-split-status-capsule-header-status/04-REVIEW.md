---
phase: 04-2a-foundation-tokens-view-split-status-capsule-header-status
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 22
files_reviewed_list:
  - boringNotch/Orchestrator/OrchestratorChat.swift
  - boringNotch/Orchestrator/OrchestratorExpand.swift
  - boringNotch/Orchestrator/OrchestratorExpanded.swift
  - boringNotch/Orchestrator/OrchestratorManager.swift
  - boringNotch/Orchestrator/OrchestratorModels.swift
  - boringNotch/Orchestrator/OrchestratorPromptCard.swift
  - boringNotch/Orchestrator/OrchestratorPromptParse.swift
  - boringNotch/Orchestrator/OrchestratorPure.swift
  - boringNotch/Orchestrator/OrchestratorRunsBoard.swift
  - boringNotch/Orchestrator/OrchestratorRunsPure.swift
  - boringNotch/Orchestrator/OrchestratorStates.swift
  - boringNotch/Orchestrator/OrchestratorStatusCapsule.swift
  - boringNotch/Orchestrator/OrchestratorTokens.swift
  - boringNotch/Orchestrator/OrchestratorView.swift
  - boringNotch/Orchestrator/Tests/Phase4Tests.swift
  - boringNotch/Orchestrator/Tests/main.swift
  - boringNotch/components/Notch/BoringHeader.swift
  - boringNotch/components/Tabs/TabButton.swift
  - boringNotch.xcodeproj/project.pbxproj
findings:
  critical: 0
  warning: 2
  info: 4
  total: 6
status: issues_found
---

# Phase 4: Code Review Report

**Depth:** standard. Music code is untouched. PromptParse move is byte-identical to the removed block. Key-gate logic and begin/end balance hold. No blockers.

## Verified OK
- `OrchestratorExpand`: `terminal` is always a subset of `expanded`. `grow` guards on `expanded`, so begin/endInteraction stay one-to-one. `setLevel(.terminal)` with a nil window does nothing. `finish` clears `terminal`. `setLevel(.expanded)` from terminal only releases the key, with no interaction change.
- `beginTyping`/`endTyping` are idempotent and unchanged.
- `capsuleState` precedence matches the stated rules. `pollInterval` is correct, with offline forced to 10s.
- `C-u` key addition matches the test.
- Removed `OrchestratorUsageBadge`, `OrchestratorChatButton` and `OrchestratorRunsButton` have no remaining references.

## Warnings

### WR-01: Opening the status menu while typing leaves the app activated and the previous app never restored
**File:** `boringNotch/Orchestrator/OrchestratorChat.swift:50` (`stopTyping(handBack: false)`)
**Issue:** `startTyping` calls `OrchestratorKeyGate.activate()`, which stores `previousApp` and activates the app. The `statusMenuOpen` handler calls `stopTyping(handBack: false)`. That skips `OrchestratorKeyGate.restore`. The "something else takes focus next" assumption is true for the terminal, whose `releaseKey` restores later. It is false for the status menu, which takes no keyboard.
- Scenario: the user is typing in the composer, clicks the capsule, and the menu opens. Typing has ended, but Boring Notch stays the active app. The previous app (editor or terminal) never regains focus, so the user's keystrokes go nowhere until they click elsewhere.
- `previousApp` is also left stale.

**Fix:** Use the default `handBack: true` here, so `restore` runs. If the menu is later used to open the terminal, `activate()` runs again.
```swift
.onChange(of: manager.statusMenuOpen) { _, open in if open { stopTyping() } }
```

### WR-02: `showRunsBoard` is sticky and outranks the prompt card, so a "Needs you" state can be hidden
**File:** `boringNotch/Orchestrator/OrchestratorView.swift:20-25`, `OrchestratorManager.swift:19`
**Issue:** `showRunsBoard` is checked before `chatRunning` and `prompt`.
- Scenario 1: the user is on the Runs board and Claude raises a permission prompt. The capsule shows "Needs you", but the card is not shown until the user flips the segment back to Chat. There is no auto-switch.
- Scenario 2: the segment is hidden when offline, but `showRunsBoard` is never reset. After a reconnect the user lands on the Runs board with no obvious reason.

**Fix:** Set `showRunsBoard = false` when `prompt` goes nil to non-nil (in `refresh`), and when `offline` becomes true. Alternatively, let the prompt card win over the board.

## Info

### IN-01: `pollInterval` ignores its `chatRunning` parameter
**File:** `boringNotch/Orchestrator/OrchestratorRunsPure.swift:5`
**Issue:** The argument is accepted and tested but never used. Either drop it or implement the intended behaviour.

### IN-02: Prompt is parsed twice per refresh
**File:** `boringNotch/Orchestrator/OrchestratorManager.swift:145-148`
**Issue:** `detectPrompt` runs for `promptOptions`, then again inside `detectPromptCard`.
**Fix:** Derive `promptOptions` from `pc?.options ?? []`. This also removes the chance of the two diverging.

### IN-03: `confirmEnd` can go stale in the status menu
**File:** `boringNotch/Orchestrator/OrchestratorStatusCapsule.swift:117,136,154`
**Issue:** If the chat stops while "End chat?" is showing, the row flips to "Start chat". `confirmEnd` stays true. If the chat is started again within 4s, the confirm prompt reappears immediately.
**Fix:** Reset `confirmEnd` via `.onChange(of: manager.chatRunning)`. Interrupt is debounced inside `pressEscape` (1s) and the menu is `.disabled(manager.sending)`, so that part is fine.

### IN-04: `TabButton` padding changed for every tab
**File:** `boringNotch/components/Tabs/TabButton.swift:19`
**Issue:** Horizontal padding went from 15 to 5 for all tabs, not just the Orchestrator one. This is a shared upstream file and adds merge surface. The hit area of every tab also shrinks. If this is intended to make room for the segment, say so, or scope it with a parameter.
- Related note: with the status menu open at terminal level, the menu overlays the terminal, but the WKWebView keeps first responder and still receives keystrokes while `allowsHitTesting` is false. This is minor.

---
_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
