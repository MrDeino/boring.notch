---
quick_id: 261014-pug
phase: quick
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - boringNotch/Orchestrator/Tests/fixtures/multiselect-1.txt
  - boringNotch/Orchestrator/Tests/fixtures/multiselect-toggled.txt
  - boringNotch/Orchestrator/Tests/fixtures/multiq-tab2.txt
  - boringNotch/Orchestrator/Tests/fixtures/review-submit.txt
  - boringNotch/Orchestrator/Tests/QuickPugTests.swift
  - boringNotch/Orchestrator/Tests/Phase6Tests.swift
  - boringNotch/Orchestrator/Tests/main.swift
  - boringNotch/Orchestrator/OrchestratorPromptParse.swift
  - boringNotch/Orchestrator/OrchestratorManager.swift
  - boringNotch/Orchestrator/OrchestratorPromptCard.swift
  - boringNotch/Orchestrator/OrchestratorTranscript.swift
  - boringNotch/Orchestrator/OrchestratorChat.swift
  - boringNotch/Orchestrator/OrchestratorExpanded.swift
  - boringNotch/Orchestrator/Snapshots/Snap.swift
  - boringNotch/ContentView.swift
autonomous: true
requirements: [QUICK-261014-pug]
must_haves:
  truths:
    - "A multiSelect AskUserQuestion shows checkbox rows; tapping a row flips its checkbox at once and sends the toggle key; a Submit button sends the keys that submit the selection"
    - "A multi-question prompt shows its question tabs as chips and the user can move between questions from the notch"
    - "Tapping any prompt answer (permission pill, question row, Submit, Something else) highlights it at once and springs the card away without waiting for a poll"
    - "If ~2s after the tap a fresh screen still shows the same prompt, the card returns with the choice cleared and a small 'Didn't go through' note"
    - "In the expanded view user messages are right-aligned bubbles and Edit rows fold out into a diff card; the open notch keeps its compact rows"
    - "Swipe/scroll-up does not close the notch while the Orchestrator tab is showing; Home/Shelf keep the close gesture"
    - "The ⏺ marker dot is ~7px visible"
  artifacts:
    - path: "boringNotch/Orchestrator/Tests/fixtures/multiselect-1.txt"
      provides: "Real capture of a multiSelect AskUserQuestion (tmux capture-pane -p -J)"
    - path: "boringNotch/Orchestrator/Tests/QuickPugTests.swift"
      provides: "runQuickPugTests(): multi-select/tabs/review parse, diffRows, mergeChecked"
    - path: "boringNotch/Orchestrator/OrchestratorPromptParse.swift"
      provides: "PromptCardOption.checked, PromptCard.multiSelect/tabs, mergeChecked"
  key_links:
    - from: "PromptCardController.choose/submit"
      to: "OrchestratorManager.pressKeys"
      via: "one sending window for a key sequence"
      pattern: "pressKeys\\("
    - from: "ChatBlockRow (expanded)"
      to: "diffRows(_:)"
      via: "Edit card renders hunk lines"
      pattern: "diffRows\\("
    - from: "ContentView.handleUpGesture"
      to: "coordinator.currentView"
      via: "guard != .orchestrator"
      pattern: "currentView != .orchestrator"
---

<objective>
Make Claude Code question prompts fully answerable from the notch (multi-select toggles, Submit, moving between questions), make every prompt answer feel instant (optimistic select + spring away, restore with a note if it didn't land), and three polish items (expanded-view user bubbles + fold-out Edit diff card, no swipe-close on the Orchestrator tab, heavier ⏺ dot).

Output: real fixtures, parser + manager changes with tests, prompt card UI, chat polish, snapshot PNGs checked.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
</execution_context>

<context>
@./CLAUDE.md
@.planning/STATE.md
@.planning/quick/261014-gkq-orch-chat-chrome-keyboard-layout/261014-gkq-SUMMARY.md
@.planning/design/orchestrator-2a/README.md (section "12 · Expanded view") and screenshots/12-expanded.png

Hard rules (executor):
- Stay on the current branch; don't create or switch GSD phase/milestone branches. Never push.
- NEVER POST to 127.0.0.1:4777 (no curl -X POST, no running the app). Don't launch apps. The Tests harness's mock POSTs only run with ORCH_MOCK_LOG set against port 4799 — leave that unset.
- tmux: only the session `notch-fixture`. Never send keys to, capture, or kill a session named `orchestrator`.
- No new Swift files in the app target (the Xcode project uses explicit file refs; new files would need pbxproj edits). New files only under `Orchestrator/Tests/` (swiftc harness, not in the target). Keep ContentView.swift diff to one line. No new deps.
- Test: `mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t | tail -1`  → `OK`
- Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20`
- Snapshots (after a build): `DD=/tmp/notch-dd boringNotch/Orchestrator/Snapshots/run.sh` → /tmp/notch-snapshots/*.png; open the new PNGs with Read and look at them.

<interfaces>
Server facts (orch.js, read-only): `screen` = `tmux capture-pane -p -J -t orchestrator -S -200` (plain text, no -e styling). Allowed keys (server CHAT_KEYS, mirrored in `OrchestratorPost.allowedKeys`): Enter, Escape, Up, Down, Tab, C-u, 1-9. No Space, no Left/Right, no Shift-Tab — do NOT add keys to allowedKeys, the server rejects them.

OrchestratorPromptParse.swift (Foundation-only, compiled into the test harness):
- `struct PromptOption { number; label }`, `detectPrompt(screen:) -> [PromptOption]`, private `scanPrompt` (bottom-window heuristic, needs "Esc to cancel" footer).
- `struct PromptCardOption { number; label; detail?; role: .normal/.deny/.freeText/.chat }`
- `struct PromptCard { title, purpose, body, options, kind: .permission/.question, header, progress, question, items, highlighted }`
- `promptIdentity(_:)` → kind + [title, question, body] + labels (ignores highlighted). Must keep ignoring checkbox state.
- `detectPromptCard(screen:)`: chip line = first line starting with one of `←☐☒✔` between the rule above and the first option; a footer containing "toggle" currently forces `.permission` (Phase 6 multi-select fallback — this task replaces it). Chips parsed into (done, label), "Submit" chip dropped; header = first not-done chip, progress "k of n".
- `promptKey(...)`, `moveHighlight(...)`, `shortLabel(...)`.

OrchestratorManager.swift: `@Published sending`, `@Published optionsLocked` + `lockGen` + `pressOption(_ n:)` (posts the digit, then a 3s lock); `post(_:)` (guards `sending`), `postNow(_:)` (200 → refresh), `sendText(_:clearFirst:)` (pattern for one `sending` window), `refresh(fresh:)`, `apply` resets `optionsLocked` when promptOptions change. `optionsLocked`/`pressOption` are used only in OrchestratorManager.swift and OrchestratorPromptCard.swift.

OrchestratorPromptCard.swift: `PromptCardController.shared` (pressed, highlighted, flash, freeText, submitting, `stillCurrent(_:)` = fresh refresh + identity check, `choose(_:displayed:)`, `escape`, `submitFreeText`, hover key-take, `sync`, `promptChanged`); `OrchestratorPromptCard` renders `manager.prompt` as `PermissionCard` / `QuestionCard`; `pressState(...)` helper drives pressed/dim from `optionsLocked`.

OrchestratorTranscript.swift: `struct ChatDiffHunk { oldStart: Int?; newStart: Int?; lines: [String]? }`, `ChatBlock { id, kind: .user/.tool/.prose, text, name, target, result, added, removed, diff: [ChatDiffHunk]? }`. Fixture phase5-blocks.json has an Edit with `diff: [{oldStart:10,newStart:10,lines:[" ctx","-old","+new"]}]`.

OrchestratorChat.swift: `OrchestratorChatView(showComposer:proseLineLimit:maxRows:)`; rows `ChatBlockRow(block:proseLineLimit:)` at line ~194; `ChatBlockRow.marker` / `dot(_:)` (⏺ U+23FA U+FE0E at `.system(size: 10)`), `content`, `toolRow` (Edit shows +N −M "▸ diff"). Expanded column creates `OrchestratorChatView(showComposer: true, proseLineLimit: nil, maxRows: 60)` in OrchestratorExpanded.swift:173. Tapping chat lines calls `expandChat()` (open → terminal).

OrchestratorTokens.swift: `OT.C.raised` #1C1C1E, `OT.C.diffCard` #141416, `OT.C.text2` #D1D1D6, `OT.C.text6` #636366, `OT.C.green`, `OT.C.redText`, `OT.F.monoChip` etc.

ContentView.swift:592 `handleUpGesture(translation:phase:)` — first line `guard vm.notchState == .open && !vm.isHoveringCalendar else { return }`; `coordinator` = `BoringViewCoordinator.shared`, `coordinator.currentView` is `.home/.shelf/.orchestrator`.

Snap.swift: `Scene(name:loaded:chat:blocks:runsBoard:expanded:railCollapsed:)` list in `Snap.main()`; `fixture(_:)` loads Tests/fixtures; `OrchestratorManager.snapshotApply`, `OrchestratorTranscriptStore.shared.snapshotSet(blocks:)`; 700ms settle before capture.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Capture real multi-select screens; parse checkboxes, tabs and review; key-sequence sends</name>
  <files>boringNotch/Orchestrator/Tests/fixtures/multiselect-1.txt, boringNotch/Orchestrator/Tests/fixtures/multiselect-toggled.txt, boringNotch/Orchestrator/Tests/fixtures/multiq-tab2.txt, boringNotch/Orchestrator/Tests/fixtures/review-submit.txt, boringNotch/Orchestrator/Tests/QuickPugTests.swift, boringNotch/Orchestrator/Tests/Phase6Tests.swift, boringNotch/Orchestrator/Tests/main.swift, boringNotch/Orchestrator/OrchestratorPromptParse.swift, boringNotch/Orchestrator/OrchestratorManager.swift</files>
  <behavior>
    - multiselect-1: kind == .question, multiSelect == true, every normal item has checked == false, labels have no checkbox glyphs, header == the question's header chip.
    - multiselect-toggled: the toggled items have checked == true, others false; promptIdentity equal to multiselect-1's (checkbox state is not identity).
    - multiq-tab2: tabs lists every question chip (+ done flags) in order; header/progress point at the shown question.
    - review-submit: parses as whatever the capture shows (the Submit/review step) with a Submit item the UI can press; no crash, items non-empty.
    - question.txt / permission.txt / phase6-edit / phase6-fetch assertions unchanged; single-select cards have multiSelect == false and checked == nil.
    - mergeChecked(screen: [1:false,2:true], pending: [1:true]) == [1:true,2:true]; a pending entry the screen already agrees with is dropped from pending.
  </behavior>
  <action>
1. Capture (scratch dir, session name `notch-fixture` only): `D=$(mktemp -d)`; `tmux new-session -d -s notch-fixture -x 200 -y 50 -c "$D" claude`; accept the folder-trust dialog if shown. Ask via `tmux send-keys -t notch-fixture -l '...'` then `tmux send-keys -t notch-fixture Enter`: "Use the AskUserQuestion tool once with two questions and do nothing else: question 1 header 'Fruit', multiSelect true, options apple, banana, cherry; question 2 header 'Color', single select, options red, blue." Poll `tmux capture-pane -p -J -t notch-fixture -S -200` (same flags as the server, no -e) until the prompt shows. Save: `multiselect-1.txt` (fresh multiSelect question), then toggle two options using ONLY server-allowed keys (digits, Up/Down, Enter, Tab — try which toggles a checkbox and which advances; Space is not available to the notch) and save `multiselect-toggled.txt`; advance to question 2 and save `multiq-tab2.txt` (tabs visible); answer it and save `review-submit.txt` (the Submit/review step). Write down the exact key map you observed (toggle key, how to submit a multi-select question, whether Tab moves forward and wraps, how to reach the review step, what Submit answers is) as a comment block at the top of QuickPugTests.swift — fixtures stay raw captures. Then Escape out, `tmux kill-session -t notch-fixture`, `rm -rf "$D"`, and confirm `tmux ls` shows no notch-fixture (and you never touched `orchestrator`). If a needed action is impossible with the allowed keys, record it as a blocker in the SUMMARY and leave that control out — never add keys to allowedKeys.
2. Parser (OrchestratorPromptParse.swift): add `var checked: Bool? = nil` to PromptCardOption, `var multiSelect = false` and `var tabs: [PromptTab] = []` (`struct PromptTab: Equatable { label: String; done: Bool }`, Submit chip kept as the last tab if the capture shows one) to PromptCard. Strip the checkbox glyph form that the capture uses from option labels and set `checked`; a card with any checkbox item is `.question` + `multiSelect = true` (replace the "toggle footer → .permission" fallback). Reuse the existing chip parsing for `tabs`; header/progress keep working. Add `func mergeChecked(screen: [Int: Bool], pending: [Int: Bool]) -> (shown: [Int: Bool], pending: [Int: Bool])` (pending wins until the screen agrees, then the entry drops) for the optimistic toggle in Task 2. Add a pure `func promptKeys(...)`-style helper only if the observed key map needs computation (e.g. Tab count to reach tab k); otherwise put the keys inline in Task 2.
3. Manager: replace `pressOption(_:)` + `optionsLocked` + `lockGen` with `func pressKeys(_ keys: [String]) async -> Bool` — one `sending` window (same pattern as `sendText`), posts each key via `sendOrchestratorPost`, stops at the first non-200, then `refresh()`; returns true only if all were 200. Remove `optionsLocked = false` from `apply`. Leave PromptCard.swift compiling (minimal call-site swap to `Task { await m.pressKeys([String(n)]) }`; Task 2 reworks it).
4. Tests: new `Tests/QuickPugTests.swift` with `runQuickPugTests()` covering the behavior list; call it from main.swift before `print("OK")`. Update Phase6Tests' `msc` (toggle footer → permission) assertion to the new multi-select behavior; if the real captures contradict the synthetic phase6-multiq-1/2 layout, delete those fixtures and move their assertions to the real ones.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t | tail -1 | grep -x OK && ! tmux has-session -t notch-fixture 2>/dev/null && ls boringNotch/Orchestrator/Tests/fixtures/multiselect-1.txt boringNotch/Orchestrator/Tests/fixtures/review-submit.txt</automated>
  </verify>
  <done>Four real fixtures committed, notch-fixture session gone, key map documented, parser exposes checked/multiSelect/tabs, manager has pressKeys and no optionsLocked, harness prints OK.</done>
</task>

<task type="auto">
  <name>Task 2: Prompt card — checkboxes, Submit, question tabs, optimistic answer with retry note</name>
  <files>boringNotch/Orchestrator/OrchestratorPromptCard.swift, boringNotch/Orchestrator/Snapshots/Snap.swift</files>
  <action>
Controller (PromptCardController):
- Optimistic answer for permission pills, question rows (single-select), multi-select Submit, review-step Submit and Something-else submit. On tap: `pressed = n` immediately (row/pill draws its light pressed state), then ~120ms later `withAnimation(.spring(response: 0.3, dampingFraction: 0.85))` set `dismissed = promptIdentity(displayed)`; the view hides a card whose identity == `dismissed` (transition: move down + opacity). In a Task: `stillCurrent(displayed)` (keep it — if stale, un-dismiss at once, flash, stop), then `await manager.pressKeys(keys)`. If pressKeys returns false → restore now. Otherwise wait until ~2s after the tap, `await refresh(fresh: true)`; if `!offline` and the prompt identity still equals the displayed one → restore. Restore = `dismissed = nil`, `pressed = nil`, `note = "Didn't go through"` (clears after ~3s or when the prompt identity changes). Any new prompt identity in `promptChanged` clears `dismissed`, `pressed`, `note`, pending toggles. No 3s lock and no greyed-out siblings: drop `pressState`'s optionsLocked logic; controls are disabled only while `manager.sending`. Esc keeps its current behavior.
- Free text: `submitFreeText` keeps its land-then-type logic but dismisses the card instantly and restores with the note when it fails.
- Multi-select: `toggle(n, displayed:)` flips `pendingChecked[n]` instantly (no dismiss) and sends the observed toggle key(s) via pressKeys; rows show `mergeChecked(screen:pending:)` so the next screen reconciles. Submit sends the key sequence Task 1 documented. Tab chips: tapping a chip sends the documented navigation keys (e.g. Tab × distance if Tab wraps; if only forward is reachable, only forward chips are tappable). Keyboard: Enter on a multi-select row toggles it (route through `toggle`).
View:
- QuestionCard: when `card.multiSelect`, rows draw a leading checkbox (SF Symbol `checkmark.square.fill` / `square`, 13pt) and tapping toggles instead of answering; footer gains a light "Submit" pill (white capsule, black text, same metrics as the permission primary pill) that calls the submit path. When `card.tabs.count > 1`, replace the header chip + "k of n" with a row of tab chips (done = check glyph, current = OT.C.selected2 background) wired to the chip tap.
- `note`: small `OT.F.meta` `OT.C.redText` text above the options of whichever card is showing.
Snapshots (Snap.swift): add an `#if ORCH_SNAPSHOT` `snapshotSet(pressed:dismissed:note:pending:)` + reset on PromptCardController (in the PromptCard file) and scenes: `17-question-multiselect` (multiselect-1.txt), `18-question-multiselect-toggled` (multiselect-1 + pending toggles), `19-question-multiq-tabs` (multiq-tab2.txt), `20-question-review-submit` (review-submit.txt), `21-permission-pressed` (phase6-edit + pressed=1, not dismissed), `22-permission-retry-note` (phase6-edit + note). Reset controller state between scenes.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && ! grep -n "optionsLocked" boringNotch/Orchestrator/*.swift && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20 && DD=/tmp/notch-dd boringNotch/Orchestrator/Snapshots/run.sh > /tmp/notch-snap.log 2>&1; grep -c "^wrote" /tmp/notch-snap.log; ! grep FAILED /tmp/notch-snap.log</automated>
    <human-check>Read /tmp/notch-snapshots/17..22 PNGs: checkboxes visible and toggled ones checked, Submit pill present, tab chips readable, pressed pill highlighted, note visible and not clipped.</human-check>
  </verify>
  <done>BUILD SUCCEEDED; scenes 17-22 written and inspected; no optionsLocked anywhere; answer taps hide the card immediately and restore with the note on a stale screen.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: Expanded bubbles + Edit diff card, no swipe-close on the Orchestrator tab, heavier ⏺</name>
  <files>boringNotch/Orchestrator/OrchestratorTranscript.swift, boringNotch/Orchestrator/OrchestratorChat.swift, boringNotch/Orchestrator/OrchestratorExpanded.swift, boringNotch/ContentView.swift, boringNotch/Orchestrator/Tests/QuickPugTests.swift, boringNotch/Orchestrator/Snapshots/Snap.swift</files>
  <behavior>
    - diffRows([ChatDiffHunk(oldStart:10,newStart:10,lines:[" ctx","-old","+new"])]) == [(.context,10,"ctx"), (.removed,11,"old"), (.added,11,"new")]
    - context advances old and new; removed shows and advances old; added shows and advances new; a line without a ' '/'-'/'+' prefix (e.g. "\ No newline") is context with no number; nil oldStart/newStart → no numbers; multiple hunks concatenate.
  </behavior>
  <action>
1. OrchestratorTranscript.swift: add `struct DiffRow: Equatable { enum Kind { case context, removed, added }; let kind: Kind; let number: Int?; let text: String }` and `func diffRows(_ hunks: [ChatDiffHunk]) -> [DiffRow]` per the behavior; tests in QuickPugTests (Task 1's file) using the phase5-blocks.json hunk.
2. OrchestratorChat.swift: add `expanded: Bool = false` to `OrchestratorChatView.init` and pass it to `ChatBlockRow`; OrchestratorExpanded.swift:173 passes `expanded: true`. Only when expanded: user blocks render as a right-aligned bubble (no ❯ marker column; full text, `OT.C.text2` 12pt, padding 6×10, `OT.C.raised`, `UnevenRoundedRectangle(topLeading: 12, bottomLeading: 12, bottomTrailing: 4, topTrailing: 12)`, max 80% of the column width — leading Spacer + `containerRelativeFrame` or a GeometryReader-free `frame(maxWidth:)` from the row width); Edit/Write tool blocks with a non-empty `diff` render the fold-out card: `OT.C.diffCard` background, radius 9, header row "▾"/"▸" + "Edit" + file name (`toolTargetDisplay`) + `+N` green / `−M` redText right-aligned, tappable as a Button that toggles fold (per-row @State, default open; must not trigger the chat's tap-to-terminal), then `diffRows` lines in mono 10pt (`OT.F.monoChip`), line spacing ≈ 1.5, padding horizontal 10, number before the text ("- 59", "+ 59", "58"); removed = background `Color(red:1,green:105/255,blue:97/255).opacity(0.12)`, text #FF9D97; added = `Color(red:48/255,green:209/255,blue:88/255).opacity(0.12)`, text #7EE69A; context = `OT.C.text6`. Open notch (expanded == false) keeps today's compact rows exactly.
3. Marker: make the ⏺ dot ~7px visible (e.g. `dot(_:)` at ~13-14pt, or a 7pt Circle aligned with `.alignmentGuide(.firstTextBaseline)`), keeping the 10pt marker column alignment with the first text line; measure in the 15-chat-markers PNG.
4. ContentView.swift `handleUpGesture`: extend the first guard with `&& coordinator.currentView != .orchestrator` (single-line change; Home/Shelf and music keep the close gesture, the down/open gesture is untouched).
5. Snap.swift: add `23-expanded-bubbles-edit` (expanded, blocks = a user message long enough to wrap + Read + an Edit with a 2-hunk diff incl. removed/added/context + prose) and `24-chat-edit-compact` (same blocks, open notch, to prove compact rows are unchanged). Rebuild, rerun snapshots, Read 15, 16, 23, 24 PNGs.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t | tail -1 | grep -x OK && grep -n "currentView != .orchestrator" boringNotch/ContentView.swift && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20 && DD=/tmp/notch-dd boringNotch/Orchestrator/Snapshots/run.sh > /tmp/notch-snap.log 2>&1; ! grep FAILED /tmp/notch-snap.log && ls /tmp/notch-snapshots/23-expanded-bubbles-edit.png /tmp/notch-snapshots/24-chat-edit-compact.png</automated>
    <human-check>Read 15, 16, 23, 24 PNGs: bubble right-aligned and ≤80% width; Edit card colors/numbers match frame 12; compact rows in 24 unchanged; dot visibly heavier.</human-check>
  </verify>
  <done>Tests OK, BUILD SUCCEEDED, `git diff --stat boringNotch/ContentView.swift` shows 1 line changed, PNGs 15/16/23/24 inspected and match the spec.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| serve screen/blocks → app | Screen text and transcript diffs are untrusted text rendered in the notch |
| app → serve POST | Key sequences sent to the live Claude session |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-pug-01 | Tampering | pressKeys | mitigate | Keys go through `OrchestratorPost.request`, which rejects anything outside allowedKeys; stillCurrent() identity check before every answer so a stale card never answers a different prompt |
| T-pug-02 | Tampering | optimistic retry | mitigate | Restore never re-sends automatically; the user taps again |
| T-pug-03 | Spoofing | diff/bubble rendering | accept | Rendered as verbatim Text (no markdown/links), same as existing tool rows |
| T-pug-04 | Elevation | fixture capture | mitigate | Only tmux session `notch-fixture` in a mktemp dir, killed afterwards; never the `orchestrator` session; no POST to :4777 |
</threat_model>

<verification>
- Test harness prints OK (incl. runQuickPugTests and updated Phase6Tests).
- xcodebuild into /tmp/notch-dd: BUILD SUCCEEDED.
- Snapshot scenes 15-24 written and looked at.
- `tmux ls` has no notch-fixture; the orchestrator session untouched; no POST to 127.0.0.1:4777 made.
- Music untouched: no edits under MediaControllers/ or managers/; ContentView diff is the one guard.
</verification>

<success_criteria>
Multi-select and multi-question prompts are fully answerable from the notch with the real key map; every answer tap feels instant and self-heals with a note; expanded view shows bubbles and fold-out Edit diffs; swipe-close is off only on the Orchestrator tab; ⏺ is heavier.
</success_criteria>

<output>
Create `.planning/quick/261014-pug-question-prompts-optimistic-polish/261014-pug-SUMMARY.md` (include the observed key map and any blocker).
</output>
