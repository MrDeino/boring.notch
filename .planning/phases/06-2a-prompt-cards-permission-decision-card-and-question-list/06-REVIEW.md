---
phase: 06-2a-prompt-cards-permission-decision-card-and-question-list
reviewed: 2026-10-14T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - boringNotch/Orchestrator/OrchestratorPromptCard.swift
  - boringNotch/Orchestrator/OrchestratorPromptParse.swift
  - boringNotch/Orchestrator/Tests/Phase6Tests.swift
findings:
  critical: 2
  warning: 9
  info: 7
  total: 18
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-10-14
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Narrative Findings (AI reviewer)

## Summary

I reviewed the prompt card controller (hover key-take, stale-screen guard, free-text send), the parser and the Phase 6 tests. I also read the parts of `OrchestratorManager`, `OrchestratorKeyGate`, `OrchestratorExpand` and the `orch.js` `/api/chat` handler that these files depend on.

Most of the parser works for the captured fixtures. The interaction layer has two blockers:
- The free-text send types text and presses Enter without checking that the option-number press actually landed. If the press was dropped, the text goes into the live select list.
- The key-take can stay active after the pointer has left the notch. Stray digits then answer the prompt.

The stale-screen guard is weaker than it looks. Its `refresh()` can return without fetching, and `submitFreeText` uses a different, silent guard.

## Critical Issues

### CR-01: Free-text submit sends text + Enter even when the option-number press was dropped, so it answers the wrong option

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:184-202` (with `OrchestratorManager.swift:64-66, 86-95`)
**Issue:** `submitFreeText` calls `m.pressOption(ft.number)`, which returns nothing and can silently do nothing:
- it returns early if `optionsLocked` is set;
- inside, `post()` returns `false` straight away if `sending` is already true, for example when an Escape or text POST is in flight;
- the POST can fail or time out.

The code then sleeps 350 ms and calls `m.sendText(t)` anyway. In `orch.js` (lines 656-658) that is `tmux send-keys -l <text>` followed by `Enter` 150 ms later. If the number press did not land, the TUI is still in the select list:
- each digit in the text (for example "use 3 columns") picks that option;
- the trailing Enter submits whichever option is highlighted (option 1 by default).

So one dropped request turns "Something else: …" into a silent answer the user never chose. After the press, nothing checks that the screen is now in text-entry mode.
**Fix:** Make the press awaitable and check the result before typing:
```swift
// manager
func pressOptionAwait(_ n: Int) async -> Bool {
    guard !optionsLocked, (1...9).contains(n) else { return false }
    optionsLocked = true; lockGen += 1; let gen = lockGen
    let ok = await post(.key(String(n)))
    Task { try? await Task.sleep(for: .seconds(3)); if lockGen == gen { optionsLocked = false } }
    return ok
}
// controller
guard await m.pressOptionAwait(ft.number) else { flashStale(); return }
await m.refresh()
// The select list must be gone (or show the free-text input) before typing.
guard m.prompt.map(promptIdentity) != promptIdentity(displayed) else { flashStale(); return }
_ = await m.sendText(t)
```

### CR-02: Key-take stays active after free-text editing ends with the pointer outside, so stray keystrokes answer the prompt

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:106-112, 415, 430`
**Issue:** When the pointer leaves, the exit dwell skips `release()` if `fieldEditing` is true, and no other release is scheduled. Suppose the user then leaves the field with the pointer outside: Esc via `onExitCommand { fieldFocused = false }`, or any focus loss. `fieldEditing` becomes false, but the app is still active and the panel is still key, so the local monitor keeps capturing every key. `editingText` is now false, so the next `1`-`9`, Return or Esc the user types, believing focus went back to their previous app, is sent as a prompt answer. PRM-04 limits key capture to "while the pointer is over the notch". The same leak happens when all four `sendText` retries fail and the field later loses focus.
**Fix:** Re-check hover when editing ends:
```swift
.onChange(of: fieldFocused) { _, f in
    ctl.fieldEditing = f
    if !f { ctl.hover(ctl.isHovering, window: anchor.window) } // schedules release if pointer is outside
}
```
or make `fieldEditing` a `didSet` in the controller: `if !fieldEditing && !hovering { release() }`.

## Warnings

### WR-01: Stale-screen guard can compare against a screen up to about 2 s old

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:63-75` (with `OrchestratorManager.swift:129-131`)
**Issue:** `refresh()` returns at once when a poll is in flight (`guard !refreshing`). `stillCurrent` then compares against `m.prompt` from the previous poll, and the in-flight poll may be about to replace it. This is the only R-04 protection before a number key reaches a live permission prompt. The ponytail comment notes the limit, but the guard is weakest exactly while a poll is running.
**Fix:** Keep the in-flight refresh as a `Task` in the manager and await it, then run a fresh one: `if let t = refreshTask { await t.value }; await refresh()`. This is a small manager change.

### WR-02: `submitFreeText` uses a different, silent guard from `choose`/`escape`

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:191-192`
**Issue:** The free-text path checks `m.prompt == displayed` (full equality, including `highlighted`) and not `promptIdentity` plus `!optionsLocked`, as `stillCurrent` does.
- If the TUI cursor moves, it rejects a prompt that is still valid.
- It does not refuse when `optionsLocked` is set, which leads into the dropped-press path in CR-01.
- On failure it returns silently: no flash, no feedback, text still in the field.
**Fix:** Use `guard await stillCurrent(displayed) else { return }` here as well.

### WR-03: Retrying `sendText` can type the text twice; 409 is retried pointlessly

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:197-200`
**Issue:** `sendText` returns `false` in three cases: transport timeout (the request timeout is 3 s, and the server may already have run `send-keys`), 409 (chat not running), or `sending` busy. The loop retries all of them up to four times. A timeout after the server accepted the text means the text plus Enter is typed again into whatever comes next. If all retries fail, nothing tells the user.
**Fix:** Retry only while `m.sending` is busy (wait for it to go false, then send once). Never re-POST after a completed request that did not return 200. Flash on final failure.

### WR-04: App-wide local key monitor ignores the terminal key gate

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:119, 125-127, 155`
**Issue:** `NSEvent.addLocalMonitorForEvents` sees keyDown events for every window and responder in the app. `takeKey` checks `!m.wantsKeyboard` but not `OrchestratorKeyGate.terminalWantsKey`. The `editingText` check only exempts `NSText`, and `WKWebView` (the ttyd terminal) is not `NSText`. At `.terminal` level the prompt card is still mounted under the overlay. If the card gets hover there, digits, arrows, Return and Esc typed into the terminal are swallowed as prompt answers. `release()` then calls `makeFirstResponder(nil)`, which pulls focus off the terminal.
**Fix:** Add `!OrchestratorKeyGate.terminalWantsKey` to the `takeKey` guard. In `handle`, pass the event through unless `e.window === keyWindow`.

### WR-05: Arrow keys can highlight items that have no highlight styling; Return then sends "Chat about this"

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:157-164, 355, 395-405`
**Issue:** `nums` contains every item number, including the `.freeText` and `.chat` items. Only `.normal` items are drawn as rows with highlight styling. Pressing Down past the last row moves `highlighted` to the free-text and then the chat number, and nothing on screen shows it. Return (`.select`) then calls `choose(chatNumber)` and leaves the question for chat, which the user cannot predict.
**Fix:** Navigate only rows that are drawn: `let nums = card.items.filter { $0.role == .normal }.map(\.number)`. Alternatively, add highlight styling to the footer pills.

### WR-06: One shared controller holds per-display state (`window`, `vm`, `raisedByCard`)

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:15-18, 40-59`
**Issue:** There is one notch panel per display, but `PromptCardController.shared` stores a single `vm`/`window`, overwritten by whichever card synced last.
- `sync` expands every display that is at `.open`, but `raisedByCard` only remembers the last one. On the next permission prompt, `promptChanged` collapses only that `vm`, and the other display stays expanded.
- `promptChanged` re-hovers using `self.window`, which can take key on the wrong display's panel.
**Fix:** Key `raisedByCard` by `ObjectIdentifier(vm)` (a `Set`, like `OrchestratorExpand`). Remember the window passed to `hover(_:window:)` and use it in `promptChanged`.

### WR-07: Hover dwell takes keyboard focus from the frontmost app; a stray digit can approve a Bash permission

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:97-135`
**Issue:** 300 ms of hover calls `NSApp.activate(ignoringOtherApps:)` and makes the panel key, with no click. If the user is typing in another app while the pointer rests at the top of the screen, a `1` approves the permission card ("Allow", or "Always…" for `2`). This follows from PRM-04, and a ponytail comment acknowledges it. It is still the riskiest path in the phase, and nothing marks a permission card as "keys live".
**Fix:** Pending Phase 9, at least: ignore key events for about 300 ms after activation; draw a visible "keys active" state on the card; or require a click (not hover) before keys can answer `.permission` cards.

### WR-08: `detectPromptCard` is gated on a 25-line window but parses a 40-line window, so long questions produce no card

**File:** `boringNotch/Orchestrator/OrchestratorPromptParse.swift:9-11, 83`
**Issue:** `detectPromptCard` returns nil unless `detectPrompt` (`window: 25`) finds a run. That run must start at `1.`, and lines 34-35 reset it when option 1 falls outside the window. A question with wrapped multi-line option details in a narrow terminal goes past 25 non-blank lines, so:
- `detectPrompt` returns `[]`;
- `promptOptions` is empty, so `needsAttention` is false;
- no card is shown, even though the 40-line scan would parse it.
**Fix:** Gate on the same scan: `guard let sc = scanPrompt(screen, window: 40) else { return nil }`. Either raise `detectPrompt`'s window to match, or derive `promptOptions` from `prompt?.options` so the two can never disagree. Add a fixture with long details.

### WR-09: Fallback "deny" role shows an approve or select option in red with an "esc" keycap

**File:** `boringNotch/Orchestrator/OrchestratorPromptParse.swift:94, 128-129`; `OrchestratorPromptCard.swift:308-313`
**Issue:** When no option starts with "no", the last `.normal` option is marked `.deny`. Two cases hit this:
- Multi-select questions are forced to `.permission` ("toggle", line 94; the test at line 70 asserts this). Their last answer (for example "cherry") is drawn red, right-aligned, with an `esc` keycap.
- Permission prompts with no "No…" label do the same to an approve option.

Clicking that pill sends its number (toggle or approve), not Escape. The keycap and colour say the opposite of what happens.
**Fix:** Apply the fallback only when the label means cancel (`Cancel`, `No…`, `Reject`). Otherwise leave the option `.normal`. Keep a deny pill's keycap as its number unless Esc and the number really do the same thing.

## Info

### IN-01: `for _ in 0..<40 where m.sending` does not stop when sending ends

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:196`
**Issue:** `where` filters iterations, so the loop keeps running and only skips the sleep. It works by accident and reads like a bounded wait.
**Fix:** `var i = 0; while m.sending && i < 40 { try? await Task.sleep(for: .milliseconds(50)); i += 1 }`.

### IN-02: Same regex matched twice per line

**File:** `boringNotch/Orchestrator/OrchestratorPromptParse.swift:30-31`
**Fix:** Match once (`let m = try? line.wholeMatch(in: s)`), then branch on `n <= 9`.

### IN-03: `freeText` is never cleared when the prompt changes

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:28, 38-46`
**Issue:** Text typed for one question stays in the field for the next, unrelated question.
**Fix:** Clear `freeText` in `sync` when `promptIdentity` changes.

### IN-04: `promptIdentity` ignores `header` and `progress`

**File:** `boringNotch/Orchestrator/OrchestratorPromptParse.swift:75-77`
**Issue:** Two multi-question pages with the same question text and labels count as the same prompt for the stale guard.
**Fix:** Add `c.header` and `c.progress` to `text`.

### IN-05: `shortLabel` maps any label starting "No" to "Deny"

**File:** `boringNotch/Orchestrator/OrchestratorPromptParse.swift:157`
**Issue:** "Not now", "None", "Normal mode" and similar all become "Deny".
**Fix:** `s == "No" || s.hasPrefix("No,")`.

### IN-06: Transient poll failure removes the card mid-typing

**File:** `boringNotch/Orchestrator/OrchestratorPromptCard.swift:38-46` (with `OrchestratorManager.swift:155-160`)
**Issue:** Any failed GET sets `prompt = nil`. `promptChanged(nil)` then calls `release()` and collapses the raised view, which kicks the user out of the free-text field after a single 3 s timeout.
**Fix:** Before releasing, wait for two nil results in a row, or for `offline` to stay set.

### IN-07: Tests miss the risky paths; one assertion is redundant

**File:** `boringNotch/Orchestrator/Tests/Phase6Tests.swift:51`
**Issue:**
- Line 51 is implied by line 50.
- No test covers a question longer than 25 non-blank lines (WR-08), the deny fallback on non-cancel labels (WR-09), or `moveHighlight` over the row subset (WR-05).

**Fix:** Add one fixture-based test for each of those three.

---

_Reviewed: 2026-10-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
