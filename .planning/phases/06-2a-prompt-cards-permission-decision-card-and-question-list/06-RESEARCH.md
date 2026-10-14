# Phase 6: 2a Prompt cards - Research

**Researched:** 2026-10-14
**Domain:** Swift/SwiftUI/AppKit (parse of Claude Code TUI screens, key handling in a non-activating NSPanel)
**Confidence:** MEDIUM (fixtures and repo code HIGH; Claude Code behaviour for variants not in fixtures is ASSUMED because POSTing to the live chat is forbidden)

<user_constraints>
## User Constraints (from 06-CONTEXT.md)

Locked: D-01..D-11 and S-01..S-07 as written in 06-CONTEXT.md (enrich `detectPromptCard` in `OrchestratorPromptParse.swift`; permission card per README 03; question list per README 04; keys 1-9/esc while hovered via gated key-take, no Accessibility/Input Monitoring; "Something else..." = number then `sendText`; grow via `OrchestratorExpand.setLevel(.expanded...)`; own only `OrchestratorPromptCard.swift`, `OrchestratorPromptParse.swift`, `Tests/Phase6Tests.swift`; never POST to 4777, never load /term, never launch apps; build with derived data `/tmp/notch-dd-p6`).
Discretion: label-shortening table beyond the two examples; matchedGeometryEffect only if inside owned files.
Deferred (ignore): closed-notch approval drop-down, global option-return/option-esc, hook-fed exact options (Phase 9); Allow/Deny on run cards (dropped).
</user_constraints>

<phase_requirements>
| ID | Description | Research Support |
|----|-------------|------------------|
| PRM-01 | `detectPromptCard` returns title/purpose/body/kind/header/progress/options | Parse rules below, verified against the 3 fixtures |
| PRM-02 | Permission card, shortened labels, esc deny, 3s lock | Label table, deny rule, existing `optionsLocked` |
| PRM-03 | Question list, default highlight, up/down/return, grow + scroll | Highlight handling, ExpandLevel notes |
| PRM-04 | 1-9/esc while hovered | Key-take recommendation (a) |
| PRM-05 | Something else / Chat about this | Two-step send + timing notes |
</phase_requirements>

## Summary

Everything needed is already in the repo: `detectPrompt` scans the last 25 non-blank lines for a 1..n numbered run with a `❯` mark and an "Esc to cancel" footer; the manager has `pressOption` (3s lock, `optionsLocked`), `pressEscape` (1s debounce), `sendText`, `beginTyping/endTyping` (idempotent, holds a SharingStateManager interaction), and `OrchestratorKeyGate.activate/restore`. The new work is (1) a richer pure parser built on the same scan, (2) two SwiftUI cards, (3) a hover key-take session that reuses the typing path, (4) calling Phase 4's expand level.

**Primary recommendation:** Refactor the scan inside `OrchestratorPromptParse.swift` so `detectPrompt` and `detectPromptCard` share it (existing `main.swift` preconditions stay green). Hover key-take = option (a): on pointer dwell over the card, `manager.beginTyping(in: window)` + `OrchestratorKeyGate.activate()` + `makeKey()`, plus one local `NSEvent` keyDown monitor that is active only while the session lives; release on pointer exit/answer/disappear. Send the chosen number directly on return (never Up/Down). Use a plain bottom-move transition, not matchedGeometryEffect.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary | Rationale |
|---|---|---|---|
| Prompt parse | Pure Swift (swiftc-tested) | - | No UI types; fixtures drive tests |
| Cards / highlight / label shortening | SwiftUI view | pure `shortLabel` fn | Presentation |
| Key capture | AppKit (NSPanel key + local monitor) | `OrchestratorKeyGate` | Panel is non-activating |
| Answer delivery | `OrchestratorManager` (HTTP -> serve -> tmux) | - | Existing, unchanged |
| Notch growth | `OrchestratorExpand` | - | Phase 4 API, Phase 7 owns behaviour |

## Standard Stack
No new packages (project constraint). System only: SwiftUI, AppKit (`NSEvent.addLocalMonitorForEvents`), Foundation `Regex` (macOS 13+, already used). Package Legitimacy Audit: not applicable (no installs).

## Findings

### 1. Parse rules (against real fixtures) [VERIFIED: fixtures, byte-level via `cat -v`]

Glyphs in fixtures: full rule `─` U+2500 (a line of ~150), dashed rule `╌` U+254C, chip `☐` U+2610 (☒ U+2612 and ✔ U+2714 are ASSUMED from Claude Code, not captured), pointer `❯`, bullet `⏺`, result `⎿`.

Shared scan (extend existing `detectPrompt` internals to also return line indices of the first/last option and the `❯` index; lines array kept with blanks removed). Widen the window for the card scan from `suffix(25)` to ~`suffix(40)` (a 4-option question with descriptions + chips + rules is already ~20 lines; keep `detectPrompt` itself at 25 unchanged if tests require, but sharing a parameter is fine). `capture-pane -J` joins soft-wrapped lines, so long labels stay single lines; Claude's own hard wraps (long question text) do not, so join multiple lines.

**Anchor on the option run, not on text.** Do not hard-code "Do you want to proceed?"; other permission prompts ask "Do you want to make this edit to X?", "Do you want to create X?" etc.

Permission (kind = .permission, footer `Esc to cancel · Tab to amend`):
- `qLine` = nearest non-blank line above option 1 (fixture: "Do you want to proceed?").
- Walk up from `qLine` to the nearest full rule (`─{10,}`). Lines between rule and `qLine` = block.
- title = first block line (fixture "Bash command"). Drop any line starting `Tip:` anywhere in the block. purpose = next remaining line before the first dashed rule (fixture "Write current date to stamp file"). body = lines between the two `╌{10,}` rules (fixture `date > /tmp/notch-fixture.WJuB/stamp.txt`).
- Stale history above the rule (the fixture contains an earlier "User declined to answer questions" and a `⏺ Run this exact shell command...` line) is ignored because the walk stops at the rule. Test this explicitly: both a `⏺`/`⎿` line above the rule must never become title.
- No dashed rules present: body = nil, purpose = remaining block line(s) joined, still render title + pills. No rule found at all: title nil, render only the question text + pills.

Degrade table for variants not in fixtures [ASSUMED: from Claude Code behaviour; no captures, add synthetic fixtures labelled synthetic and ask the user for real ones]:

| Variant | Likely screen | Parser result |
|---|---|---|
| Edit/Write file | title "Edit file"/"Create file", path line, dashed rule, diff lines (`  12 + foo`), dashed rule, "Do you want to make this edit to X?" | title; purpose = path; body is a diff: detect `^\s*\d+\s*[+-]` or `^\s*[+-]` majority and set `body = nil` (card shows no command block) rather than printing a diff in a `$ ` block |
| WebFetch | title "Fetch", URL line(s), prompt text, question "Do you want to allow Claude to fetch this content?" | title + purpose (URL); body nil or first line |
| MCP tool | title "Tool use", "server - tool(args) (MCP)" lines | title + purpose; no body |
| Multi-line Bash | several lines between dashed rules | body = first line only, card ellipsizes; full text as `.help` |
| Submit review (end of multi-question) | "Review your answers", ... "Ready to submit your answers?" `1. Submit answers 2. Cancel` | treated as permission-like (footer says Esc); title from the preceding line, pills "Submit answers"/"Cancel" |

Deny option = last option whose label starts with `No` (case-insensitive); fall back to the last option. Option keycap for deny is "esc" but the pill sends the option number (D-06).

Question (kind = .question; discriminated by a chip line `^[←→ ]*[☐☒✔]` above option 1 OR footer containing "Enter to select"; a permission footer contains "Tab to amend"):
- Chip line (fixture ` ☐ Fruit `): split on glyphs; chips = labels excluding the `✔ Submit` tab. header = label of the current chip. Progress "i of N" only when N > 1: N = chip count excluding Submit, i = (count of ☒) + 1. With the first-unanswered convention this fails only if the user navigated back with the left arrow (plain capture carries no highlight info); accept. Multi-question layout itself is ASSUMED (not captured): `← ☒ Q1  ☐ Q2  ✔ Submit →`.
- question = non-blank lines between the chip line and option 1, joined with a space (fixture "Which fruit do you like?").
- Options: for each numbered line, the following non-matching, non-rule lines up to the next numbered line are its description (fixture: "apple" -> "Apple", etc.; joined with a space). Skip separator rules (a `─` line sits between "Type something." and "Chat about this").
- Specials by label, not number: label hasPrefix "Type something" -> `.freeText`; label == "Chat about this" -> `.chat`. In the fixture they are 4 and 5 but n+1/n+2 is the rule. Real options = the rest. Special options have no descriptions.
- Highlight: index of the option line carrying `❯` (fixture: option 1). D-04.
- Old multi-select ("Space to toggle") questions exist in Claude Code [ASSUMED]; if footer contains "toggle", fall back to kind = .permission-like plain pills (do not offer return-selects).

Suggested types (Equatable so the manager's change checks and card identity work): `PromptCard { kind, title?, purpose?, body?, header?, progress: (index:Int,total:Int)?, question?, options: [PromptOption] (with optional description, role: .normal/.freeText/.chat/.deny), highlighted: Int? }`. Note Phase 4's D-09 fixes `PromptCard` fields `title, purpose, body, options, kind, header, progress`; Phase 6 adds `question`, per-option `description`/`role`, `highlighted`. Keep `PromptOption` initialiser source-compatible (`PromptOption(number:label:)` is used in `main.swift` as `po([...])`; new fields need defaults) and `==` must still equal on number+label only for the existing preconditions, OR give `PromptCard` its own option type (`PromptCardOption`) and leave `PromptOption` untouched. Recommend the latter: zero risk to existing tests.

### 2. "Type something." flow [ASSUMED for the TUI side; serve code VERIFIED]
- Serve (`orch.js` lines 645-658): a `key` POST is one `tmux send-keys <key>` and returns 200 immediately; a `text` POST does `send-keys -l <text with newlines collapsed to spaces>`, waits 150 ms, then sends `Enter`, and responds after that.
- In Claude Code's AskUserQuestion, "Type something." is an inline text-entry option. Pressing its number focuses/selects the entry row; typed characters then land in it and Enter submits. Sending the number then `{text}` is the right shape. This cannot be confirmed without POSTing (forbidden), so mark for human UAT.
- Timing risk: `pressOption` is fire-and-forget (`Task { await post(key) ... }`), and `post` bails with `false` while `sending` is true. So `pressOption(n)` immediately followed by `sendText` will drop the text. Without editing the manager (D-11): `manager.pressOption(n)`; then loop `try? await Task.sleep(.milliseconds(350))`; `refresh` is polled anyway; then retry `sendText` up to 3 times (each `false` = still sending or not running) with 250 ms gaps. Better: before sending text, `await manager.refresh()` and check the card's `highlighted == freeText.number` or that the `Type something` row now shows `❯` (assumption: the TUI moves the pointer there). If the check never succeeds within ~1.5 s, send anyway only if the prompt is still present (the number key at least selected something visible); otherwise abort and leave the field text in place so the user can retry.
- `pressOption` sets `optionsLocked` for 3 s, which disables the rest of the card during the free-text step: acceptable (the text field is its own control). The lock clears automatically when the options change after submit.
- Newlines are collapsed by serve, so the field is single-line (`TextField`, submit on return); empty text is rejected by `OrchestratorPost.request` (returns false, nothing sent).
- "Chat about this": send its number once; Claude Code ends the question and returns to the input box with the question contextually available [ASSUMED]. No follow-up needed.
- Safety: if the user presses the number for free text and then closes the notch before sending text, the TUI is left in text-entry; Esc via the card is the recovery.

### 3. Keys while hovered (PRM-04)

Facts [VERIFIED in repo]: `BoringNotchSkyLightWindow.canBecomeKey = OrchestratorManager.shared.keyboardWindow === self || OrchestratorKeyGate.terminalWantsKey`. `beginTyping(in:)` sets `keyboardWindow` (so canBecomeKey flips true), takes one `SharingStateManager` interaction (notch will not auto-close) and is idempotent; `OrchestratorView.startTyping()` then does `OrchestratorKeyGate.activate()` (records frontmost app, `NSApp.activate(ignoringOtherApps:)`), `w.makeKey()`, and a deferred second `makeKey()` plus a 600 ms give-up check. Release = `w.makeFirstResponder(nil)`, `manager.endTyping()`, `OrchestratorKeyGate.restore(refocus: wasKey)`. Phase 2 UAT items are still all pending (headless), so real focus behaviour is not yet user-verified, though quick task 261014-gkq ("activate app for notch typing") is merged.

| Option | Works? | Side effects | Verdict |
|---|---|---|---|
| (a) Gated key-take on hover + activate + restore previous app, plus local keyDown monitor | Yes: once the panel is key and the app active, local monitor sees keyDown | Steals focus from the user's app while hovering: keystrokes meant for e.g. an editor go to the notch. Mitigations below | **Recommended** |
| (b) Local monitor only | Only fires if our app is already active; the app is never active while the user is in another app | none | Insufficient alone (it is the receiving half of (a)) |
| (c) Global monitor (`addGlobalMonitorForEvents(.keyDown)`) | Needs Input Monitoring / Accessibility on modern macOS and cannot consume the key | permission prompt | Rejected (D-09) |

Design for (a), all in `OrchestratorPromptCard.swift` (new file-private `PromptWindowAnchor` NSViewRepresentable, because `WindowAnchor` in `OrchestratorView.swift` is `private`):
1. Trigger: card root `.onHover`. On enter: start a ~300 ms dwell `Task`; only if still hovering, `manager.prompt != nil`, `!manager.wantsKeyboard` (composer not already typing), not `optionsLocked`, then take the key (steps of `startTyping()` above). Dwell prevents a mouse pass-through from hijacking the user's typing elsewhere; this is the main focus-steal side effect and cannot be fully removed. Do not take key when the previous frontmost app is a text-input-heavy context? Not detectable; accept dwell.
2. Monitor: `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` installed at take, removed at release (store token; remove in `onDisappear` too). Handler: ignore events with command/control/option modifiers; if `NSApp.keyWindow?.firstResponder is NSText` (free-text field editing) return the event untouched, except Esc which ends editing; digits `1...9` that match a real option number -> consume (return nil) and answer; Esc -> consume, `pressEscape()`; up/down arrows -> move local highlight (question kind); return -> answer highlighted (question kind). Any other key: return the event unchanged.
3. Release (all idempotent): pointer exit (grace 150 ms; skip if the free-text field is focused, matching INT-06 "pointer leaving keeps typing"), after answering, prompt gone (`manager.prompt == nil`), `onDisappear`, `NSWindow.didResignKeyNotification` for the window, 600 ms give-up if the panel never became key. Release = remove monitor, `w.makeFirstResponder(nil)`, `manager.endTyping()`, `OrchestratorKeyGate.restore(refocus: wasKey)`. Skipping release keeps the notch open forever (interaction held), so release on exit matters more than for the composer: `ContentView.handleHover` only closes when `preventNotchClose` is false.
4. Shared state conflict: `typing` in the manager is a single flag. The "Something else..." field (D-10) must reuse the already-held session (do not call `beginTyping` twice with different windows; same window is idempotent). The existing `OrchestratorView.onChange(of: manager.promptOptions) { stopTyping() }` only acts on its own `keyWindow`, so it will not tear down the card's session (it returns early if its `keyWindow` is nil); Phase 4's shell rewrite must preserve that guard. Flag for the Phase 4 summary check.
5. Stale-screen guard (important): the card shows a screen up to 2 s old. A fast "1" could land on a different, newer prompt (e.g. approve a Bash command the user never saw). Before every keyboard-triggered answer: `await manager.refresh()`, compare `manager.prompt` with the card's displayed prompt (Equatable); send only if equal, else do nothing (the card re-renders). `refresh()` is internal (not private) so no manager edit. Mouse clicks get the same guard cheaply.
6. Unavoidable shared edit: none required. `canBecomeKey` already ORs `keyboardWindow`, which `beginTyping` sets. Declare in `<merge_points>`: "none". `BoringNotchSkyLightWindow.swift` untouched.
- Closed-notch case (prompt arrives while closed) is Phase 9; hover-take only runs when the card is on screen, i.e. notch open.

### 4. Up/down/return
Local highlight (`@State highlighted: Int`, initialised from `card.highlighted ?? 0`, reset whenever the card identity changes: kind+question+option labels). Up/down move through real options plus the specials in on-screen order; return sends that row's number via the guarded `pressOption`. Never send `Up`/`Down`/`Enter` to Claude Code for selection: its pointer is invisible to us, a number is unambiguous, and an extra Enter could submit the wrong thing. Because `pressOption` ignores while `optionsLocked`, double returns are safe. Selecting the free-text row on return focuses the text field instead of sending (user then types, return submits via the two-step flow).

### 5. Label shortening (pure `shortLabel(_:)`, tested) [real strings from permission.txt VERIFIED; the rest ASSUMED]
Pipeline: (1) cut at first ` · ` (fixture option 3 has "· auto mode handles these prompts for you"); (2) strip trailing shortcut hints like ` (shift+tab)`/`(esc)`; (3) table:

| Input pattern | Output |
|---|---|
| `Yes` | `Yes` |
| `No` / `No, ...` | `No` |
| `Yes, and always allow access to <path> from this project` | `Always in <last path component>...` (e.g. `Always in notch-fixture.WJuB...`) |
| `Yes, and switch to auto mode` | `Auto mode` |
| `Yes, and don't ask again for <x>` (assumed) | `Always: <x>` truncated |
| `Yes, allow all edits during this session` (assumed) | `All edits` |
| other `Yes, and X` / `Yes, X` | capitalised X |
| fallback | truncate to ~22 chars with `...` |

Full original label always as `.help` tooltip. Question option labels are never shortened (rows are full width).

### 6. Growing the notch
Current `OrchestratorExpand` (read): `expand(vm:window:)` computes `extra = expandedExtra(screenHeight:openHeight:)` (max 300, so 190+300 = 490 cap; mock 400 is just a lower extra), `setFrame(pinnedFrame(...))` keeping the top edge, inserts into `expanded`, installs global+local mouse-down monitors that call `collapseIfOutside`, calls `SharingStateManager.beginInteraction()` exactly once per expand (balanced in `finish`), animates `vm.notchSize`. `collapse` shrinks the notch first, then the window after 450 ms. `reset()` runs on notch close and `OrchestratorExpandOverlay.onDisappear`. Today `OrchestratorExpandOverlay` draws a black terminal when `isExp`, so Phase 4's `.expanded` must NOT show it; this is a Phase 4 deliverable to confirm in its summary.

Constraints for the card:
- Call `OrchestratorExpand.setLevel(.expanded, vm:, window:)` when a question card appears (kind == question always has >= 2 described rows; rough height = header 28 + question 20/line + rows ~52 (with description) or ~34 + footer 28 + padding > open height 190); keep a pure `questionNeedsExpand(card)` for tests. Track `raisedByCard`; on card disappear or prompt gone call `setLevel(.open, ...)` only if `raisedByCard` and the level is still `.expanded` (never downgrade a user-chosen `.terminal`).
- Interaction count: one `beginInteraction` per expand is internal to Expand; the hover key-take holds a second one via `beginTyping`. Both are independently balanced; release order does not matter.
- Outside-click collapse applies while expanded: a click outside the notch collapses and closes it; the pending prompt remains in the TUI and the card reappears on next open.
- Permission cards fit the 190 open height (title row + command + 30 px pills); do not expand.
- ScrollView with `.scrollBounceBehavior(.basedOnSize)` around the list for overflow.
- Exact `setLevel` signature is from MERGE-MAP/Phase 4 CONTEXT D-09 and not yet in the code (VERIFIED absent: current file has only `expand/collapse/reset`). Plan code against the MERGE-MAP signature and re-check after Phase 4 lands.

### 7. matchedGeometryEffect rise-from-composer
Needs one `@Namespace` shared by the composer (Phase 5 file `OrchestratorChat.swift`) and the card (Phase 6), declared in the shell (`OrchestratorView`, Phase 4) and passed down; both sides must tag the same id inside the same transaction, and the notch window also grows during the question case, which fights the geometry match. No such hook is listed in MERGE-MAP. **Recommendation:** not feasible inside owned files; use `.transition(.move(edge: .bottom).combined(with: .opacity))` with `.spring(response: 0.3, dampingFraction: 0.85)` on the card root, and declare the matchedGeometry request as a possible follow-up (needs a `Namespace.ID?` parameter on the card and composer). Mark deviation in the plan.

### 8. Merge risks with Phases 5 and 7
- Phase 5 (composer, transcript): both phases care about "prompt present replaces transcript/composer"; that switch is in the Phase 4 shell, not in 5 or 6 files. Only shared surface is `manager.prompt` and the `typing` flag (item 3.4). Phase 5's composer must call `stopTyping` for its own window only.
- Phase 7: owns `OrchestratorExpand.swift` behaviour and the `.expanded` visual; Phase 6 depends on `setLevel(.expanded)` showing no terminal and on `.open` restore semantics. If 7 changes the extra height or animation, the card still works (it only requests levels). 7's expanded column embeds `OrchestratorPromptCard` by type name: keep its initialiser parameterless (`OrchestratorPromptCard()` reading `OrchestratorManager.shared`/environment) or with defaults, so 7's call site does not break. Both read `manager.prompt`.
- `PromptCard`/`PromptOption` type shape: Phase 4 creates stubs; Phase 6 edits the same file, no other phase should touch it. Do not rename Phase 4's fields; add fields with defaults.
- Merge map says tests harness compiles `OrchestratorModels.swift` and `OrchestratorPure.swift` but `OrchestratorPromptParse.swift` must import only Foundation. `main.swift` owns the `fixture()` helper; `Phase6Tests.swift` can call it (same module).

## Don't Hand-Roll
| Problem | Use instead |
|---|---|
| Sending keys/text | `manager.pressOption/pressEscape/sendText` (lock, debounce, 409 handling) |
| Focus hand-back | `OrchestratorKeyGate.activate/restore`, `manager.beginTyping/endTyping` |
| Window growth | `OrchestratorExpand` API |
| Process/tmux calls | never (sandbox); HTTP only |

## Common Pitfalls
1. **Anchoring on "Do you want to proceed?"** misses edit/write/fetch prompts. Anchor on option 1's preceding line and the nearest full rule.
2. **Stale history above the rule** (fixture has an old declined AskUserQuestion block) leaking into title/chips: stop at the nearest rule/chip line; test with the real fixture.
3. **`pressOption` then `sendText` race** (item 2): second call returns false while `sending`; retry loop needed.
4. **Stale-screen keypress** answering a different prompt (item 3.5): refresh and compare first.
5. **Holding the key forever** keeps the notch open; always release on exit/answer/disappear.
6. **Diff body in command block** for Edit/Write; hide diffs.
7. **Duplicate `OrchestratorExpand` expand from card and terminal**: guard on current level; never downgrade `.terminal`.
8. **Hard-coded 4/5** for specials; use labels.
9. **Modifier keys**: ignore keyDown with cmd/ctrl/opt so system shortcuts (cmd-1) still work.

## Code Examples

Shared scan sketch (pure, Foundation only):
```swift
// Source: derived from existing detectPrompt in OrchestratorModels.swift
struct ScannedOption { let number: Int; let label: String; let line: Int; let marked: Bool }
func scanOptions(_ lines: [String]) -> [ScannedOption]   // same run/footer/bottom-4 rule as detectPrompt
func detectPrompt(screen: String) -> [PromptOption] { /* map scanOptions, unchanged behaviour */ }
func detectPromptCard(screen: String) -> PromptCard? { /* title/purpose/body/header/progress/descriptions */ }
```
Local key monitor skeleton:
```swift
monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
    guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return e }
    if NSApp.keyWindow?.firstResponder is NSText { return e }          // free-text field editing
    if e.keyCode == 53 { onEsc(); return nil }                        // esc
    if let c = e.charactersIgnoringModifiers, let n = Int(c), validNumbers.contains(n) { onNumber(n); return nil }
    switch e.keyCode { case 125: moveDown(); return nil; case 126: moveUp(); return nil; case 36, 76: onReturn(); return nil; default: return e }
}
```

## Environment Availability
Xcode at `/Applications/Xcode.app` (build + swiftc harness per MERGE-MAP). No other dependencies. Serve is read-only for this phase; GET only, no POST, no `/term`.

## Validation Architecture
| Property | Value |
|---|---|
| Framework | swiftc assert/precondition harness (`Tests/main.swift`, `Tests/Phase6Tests.swift` -> `runPhase6Tests()`) |
| Quick command | the MERGE-MAP `xcrun swiftc ... && /tmp/orch-test/t` line |
| Build | `xcodebuild ... -derivedDataPath /tmp/notch-dd-p6 build` |

| Req | Test |
|---|---|
| PRM-01 | permission fixture: title "Bash command", purpose "Write current date to stamp file", body `date > /tmp/notch-fixture.WJuB/stamp.txt`, kind permission, 4 options, deny = 4. Question fixture: header "Fruit", question "Which fruit do you like?", descriptions Apple/Banana/Cherry, freeText=4, chat=5, highlighted=0, progress nil. Synthetic: two-chip line gives "1 of 2" and "2 of 2"; edit-diff body -> nil; no-dashed-rules permission; multi-line question text; inputbox fixture -> nil; old `detectPrompt` preconditions still pass |
| PRM-02 | `shortLabel` table incl. both README examples, fallback truncation, ` · ` cut |
| PRM-03 | `questionNeedsExpand`, highlight movement pure helper (clamp, includes specials) |
| PRM-04, PRM-05 | Not unit-testable (AppKit focus, tmux). Human UAT list: hover dwell takes key and 1/esc answers; pointer exit releases and restores previous app; Something else sends number then text; Chat about this; no music regression; screenshots vs 03/04 |

Wave 0: none beyond Phase 4's stubs.

## Security Domain
ASVS V5 input validation applies to typed free text only (already enforced server-side: non-empty, newlines collapsed); the stale-screen guard (item 3.5) is the real safety control since a key press can approve a command. No new entitlements, no network beyond 127.0.0.1:4777.

## Assumptions Log
| # | Claim | Risk if wrong |
|---|---|---|
| A1 | Pressing the free-text option's number focuses its input and subsequent text + Enter submits | Text lost or typed into wrong place; needs UAT |
| A2 | Multi-question chip line format (`☒`, `✔ Submit`, arrows) and "Review your answers" screen | progress/header wrong; degrade to no progress |
| A3 | Edit/Write/WebFetch/MCP permission screen layouts | title/purpose may be off; degrade rules cover |
| A4 | Option strings other than the three in the fixture ("don't ask again", "allow all edits") | falls to generic truncation |
| A5 | Claude Code multi-select ("toggle") questions exist | would offer wrong return semantics; guarded by footer check |
| A6 | `NSApp.activate` + `makeKey` on hover works for key events in this panel | PRM-04 fails; Phase 2 UAT also still pending |

## Open Questions / Spec Gaps
1. CONTEXT D-11 forbids manager edits, but a clean two-step free-text send wants an awaitable `pressOption`. Workaround (retry loop) is specified; a tiny `pressOptionAndWait` in the manager would be better and is a declarable merge point.
2. README says "esc" pill/deny; CONTEXT D-06 resolves it (deny sends its number, esc key sends Escape). No conflict.
3. README claims "Type something." is "filtered out today"; actually `detectPrompt` returns it (main.swift line 49). Not a blocker.
4. matchedGeometryEffect deviation (item 7).
5. Real fixtures for edit/write/fetch/multi-question are missing; ask the user for captures when such prompts occur naturally.

## Sources
- Repo (HIGH): `boringNotch/Orchestrator/*.swift`, `Tests/main.swift` and fixtures, `BoringNotchSkyLightWindow.swift`, `ContentView.swift` (handleHover), design README + MERGE-MAP, Phase 4 CONTEXT D-09.
- Serve (HIGH): `/Users/mitch/Documents/Claude/orchestrator/orch.js` lines 590, 645-658 (read-only).
- Claude Code TUI behaviour beyond fixtures: training knowledge (LOW, flagged A1-A5).

**Research date:** 2026-10-14 · **Valid until:** ~14 days (Claude Code TUI changes fast; Phase 4 API unverified until it lands)
