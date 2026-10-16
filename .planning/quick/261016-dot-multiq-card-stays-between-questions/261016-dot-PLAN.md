---
phase: quick-261016-dot
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - boringNotch/Orchestrator/OrchestratorPromptParse.swift
  - boringNotch/Orchestrator/OrchestratorPromptCard.swift
  - boringNotch/Orchestrator/Tests/QuickDotTests.swift
  - boringNotch/Orchestrator/Tests/main.swift
  - boringNotch/Orchestrator/Tests/fixtures/multiq3-1.txt
  - boringNotch/Orchestrator/Tests/fixtures/multiq3-2.txt
  - boringNotch/Orchestrator/Tests/fixtures/multiq3-3.txt
  - boringNotch/Orchestrator/Tests/fixtures/multiq3-review.txt
  - boringNotch/Orchestrator/Tests/fixtures/multiq3-done.txt
autonomous: true
requirements: [QUICK-261016-dot]

must_haves:
  truths:
    - "Answering q1 of a 3-question AskUserQuestion leaves the card mounted; q2 replaces its content once on screen, with progress '2 of 3'"
    - "The review step shows Submit answers / Cancel; choosing either hides the card (existing optimistic hide)"
    - "Single-question cards, permission cards, free text, Esc/Cancel and digit keys behave as before"
    - "A question answered in the terminal still updates the card (promptChanged path unchanged)"
    - "A stale answer Task from q1 never restores or releases focus while q2/q3 is on screen"
  artifacts:
    - path: "boringNotch/Orchestrator/OrchestratorPromptParse.swift"
      provides: "pure hidesOnAnswer(_:keys:)"
      contains: "func hidesOnAnswer"
    - path: "boringNotch/Orchestrator/Tests/QuickDotTests.swift"
      provides: "runQuickDotTests walking the 3-question sequence + single-question + permission"
      contains: "func runQuickDotTests"
  key_links:
    - from: "PromptCardController.answer"
      to: "hidesOnAnswer"
      via: "branch: hide+release path vs keep-mounted path"
      pattern: "hidesOnAnswer\\("
    - from: "Tests/main.swift"
      to: "runQuickDotTests"
      via: "call before print(\"OK\")"
      pattern: "runQuickDotTests\\(\\)"
---

<objective>
Multi-question AskUserQuestion card must not vanish between questions. Root cause (verified in code):
`PromptCardController.answer` (OrchestratorPromptCard.swift:92) sets `dismissed = id` after 120 ms, which makes
`promptVisible` false in OrchestratorExpanded.swift:226 and unmounts `OrchestratorPromptCard`; `disappeared()`
then calls `release()` (focus back to previous app), and after the 2 s check `answer` calls `release()` again.
The card only returns if the async `promptChanged` sees a new identity.

Fix: one pure decision `hidesOnAnswer` in the parser file; `answer` keeps the card mounted (no `dismissed`, no
`release()`) when the answer leads to another step of the same prompt. Everything else keeps the current path.

Output: pure function + controller branch, 5 recorded-shape fixtures, QuickDotTests, both builds, one commit.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@./CLAUDE.md
@boringNotch/Orchestrator/OrchestratorPromptCard.swift (lines 40-150: promptChanged, answer, restore, choose, toggle, next, goTab)
@boringNotch/Orchestrator/OrchestratorPromptParse.swift (PromptCard, promptIdentity, detectPromptCard chip/review parsing)
@boringNotch/Orchestrator/Tests/QuickPugTests.swift (lines 25-45: how multiq-tab2 / review-submit are asserted)
@boringNotch/Orchestrator/Tests/fixtures/multiq-tab2.txt
@boringNotch/Orchestrator/Tests/fixtures/review-submit.txt
@boringNotch/Orchestrator/Tests/fixtures/inputbox.txt

<interfaces>
From OrchestratorPromptParse.swift:
- struct PromptTab { label: String; done: Bool }
- struct PromptCard { kind: .permission|.question; header; progress; question; items: [PromptCardOption];
  multiSelect; tabs: [PromptTab] (Submit chip last when shown); currentTab: Int?; review: Bool }
- func promptIdentity(_ c: PromptCard) -> PromptIdentity   // kind + [title, question, body] + labels
- func detectPromptCard(screen: String) -> PromptCard?
- func tabKeys(from:to:review:) -> [String]?; let promptBackKey = "BTab"
- Parser facts: progress = "\(cur+1) of \(qs.count)" only when >1 non-Submit chips; current chip = first ☐;
  question.txt has a single "☐ Fruit" chip (progress nil); review step sets review=true, header/progress nil,
  currentTab = tabs.count-1.

From OrchestratorPromptCard.swift (PromptCardController, @MainActor):
- private func answer(_ keys: [String], pressed n: Int?, displayed: PromptCard)  // used by choose, next (["Tab"]), goTab
- private func restore(note: String?)  // dismissed=nil, pressed=nil, busy=false, note
- promptChanged(_:) resets pressed/dismissed/note/pending/busy when identity changes; releases when card == nil
- submitFreeText and escape have their own paths: leave them untouched

From Tests/main.swift: func fixture(_ n: String) -> String (reads Tests/fixtures/<n>.txt); test fns called before print("OK").
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: hidesOnAnswer + 3-question fixtures + QuickDotTests</name>
  <files>boringNotch/Orchestrator/OrchestratorPromptParse.swift, boringNotch/Orchestrator/Tests/QuickDotTests.swift, boringNotch/Orchestrator/Tests/main.swift, boringNotch/Orchestrator/Tests/fixtures/multiq3-1.txt, boringNotch/Orchestrator/Tests/fixtures/multiq3-2.txt, boringNotch/Orchestrator/Tests/fixtures/multiq3-3.txt, boringNotch/Orchestrator/Tests/fixtures/multiq3-review.txt, boringNotch/Orchestrator/Tests/fixtures/multiq3-done.txt</files>
  <behavior>
    - multiq3-1/2/3 each parse as .question, non-review, tabs == [A,B,C,Submit] labels, header == that question's chip, progress "1 of 3" / "2 of 3" / "3 of 3", currentTab 0/1/2
    - promptIdentity differs between every consecutive pair (1→2→3→review)
    - multiq3-review parses with review == true, items labels ["Submit answers", "Cancel"], currentTab == 3
    - multiq3-done: detectPromptCard == nil and detectPrompt isEmpty
    - hidesOnAnswer(q, keys: ["1"]) == false for q1, q2, q3; == true on review (both "1" and "2")
    - hidesOnAnswer(question.txt card, keys: ["1"]) == true; hidesOnAnswer(permission.txt card, keys: ["1"]) == true
    - hidesOnAnswer(any card, keys: ["Tab"]) and (keys: ["BTab"]) == false (multiselect-single "next" lands on the Submit step of the same prompt)
    - existing QuickChromeTests / review-chrome.txt still pass unchanged
  </behavior>
  <action>
Fixtures (RED first): create five .txt files in Tests/fixtures, each modeled byte-for-byte on the layout of the real
Claude Code 2.1.299 captures (same banner, same ❯ prompt line, same full-width ─ rules, same blank padding below).
Fixtures are plain screen text so put the "derived from" note in QuickDotTests.swift as a header comment per
fixture (not inside the .txt, the parser would read it). Use three single-select questions with headers Fruit,
Color, Size (options e.g. apple/banana, red/blue, small/large, each with a one-line description like the capture,
then "N. Type something.", rule, "N. Chat about this", footer
"Enter to select · Tab/Arrow keys to navigate · Esc to cancel").
- multiq3-1.txt (from multiq-tab2.txt): chip line `←  ☐ Fruit  ☐ Color  ☐ Size  ✔ Submit  →`, Fruit question.
- multiq3-2.txt (from multiq-tab2.txt): `←  ☒ Fruit  ☐ Color  ☐ Size  ✔ Submit  →`, Color question.
- multiq3-3.txt (from multiq-tab2.txt): `←  ☒ Fruit  ☒ Color  ☐ Size  ✔ Submit  →`, Size question.
- multiq3-review.txt (from review-submit.txt): `←  ☒ Fruit  ☒ Color  ☒ Size  ✔ Submit  →`, "Review your answers",
  three "● question / → answer" pairs (no ⚠ line, all answered), "Ready to submit your answers?",
  "❯ 1. Submit answers", "  2. Cancel" — no Esc footer, exactly like the capture.
- multiq3-done.txt (from inputbox.txt): a "⏺ User answered Claude's questions:" transcript line or two above the
  real idle input box from inputbox.txt; no numbered options.

Pure function in OrchestratorPromptParse.swift, next to tabKeys: `func hidesOnAnswer(_ c: PromptCard, keys: [String]) -> Bool`
with a one-line doc comment. Returns false when keys contain "Tab" or promptBackKey (navigation inside the same
prompt always leads to another step); otherwise false when c.kind == .question && !c.review && more than one
non-"Submit" tab exists (another question or the review step follows); else true. This keeps single-question,
permission and review (Submit/Cancel) on the existing hide path.

QuickDotTests.swift: `func runQuickDotTests()` with preconditions for every behavior bullet (walk the sequence
in an array loop over the five fixture names). Register `runQuickDotTests()` in Tests/main.swift right after
`runQuickChromeTests()`. Run the harness before writing hidesOnAnswer to see it fail to compile/precondition, then
implement. If a fixture fails to parse, fix the fixture to match the real capture layout, never the parser —
the parser is verified against real captures (only touch detectPromptCard if a real-capture-shaped screen breaks,
and say so in the SUMMARY).
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/clive-261015235107-3f9d && mkdir -p build && xcrun swiftc -o build/orch-test boringNotch/Orchestrator/{OrchestratorModels,OrchestratorPure,OrchestratorTranscript,OrchestratorPromptParse,OrchestratorRunsPure,OrchestratorStream,OrchestratorComposerInput}.swift boringNotch/Orchestrator/Tests/*.swift && ./build/orch-test</automated>
  </verify>
  <done>Harness prints OK; QuickDotTests covers the 3-question walk, single-question and permission.</done>
</task>

<task type="auto">
  <name>Task 2: answer() keeps the card mounted between questions</name>
  <files>boringNotch/Orchestrator/OrchestratorPromptCard.swift</files>
  <action>
In `PromptCardController.answer`, compute `let hides = hidesOnAnswer(displayed, keys: keys)` up front.
- hides == true: exactly the current code (120 ms then `dismissed = id`, stillCurrent, pressKeys, 2 s check,
  restore "Didn't go through" or `release()`). Single-question, permission, review Submit/Cancel unchanged.
- hides == false: skip the 120 ms sleep and the `dismissed = id` line (card stays mounted; `pressed` highlight is
  the feedback). stillCurrent failure → restore(note: nil); pressKeys failure → restore(note: "Didn't go through").
  After the 2 s wait + refresh: only if `!m.offline` and the current prompt's identity == id (screen never moved)
  → restore(note: "Didn't go through"). Otherwise do nothing: NO `release()` (q2 is on screen and the card keeps
  key focus/hover; promptChanged already reset busy/pressed when the identity changed, and it releases on nil).
  This also means a stale q1 Task cannot touch q2/q3 state: it only acts when q1's identity is the one on screen.
- Do not touch submitFreeText, escape, toggle, promptChanged, the OrchestratorExpanded.swift `promptVisible`
  logic, the key monitor or digit handling. goTab and next already route through answer, so they inherit it.
Add one `ponytail:` comment on the keep branch: identity-equal first redraw (chip flips before the question
text) just shows q1 a moment longer; a 2 s no-move still says "Didn't go through".
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/clive-261015235107-3f9d && grep -n "hidesOnAnswer(" boringNotch/Orchestrator/OrchestratorPromptCard.swift && xcrun swiftc -o build/orch-test boringNotch/Orchestrator/{OrchestratorModels,OrchestratorPure,OrchestratorTranscript,OrchestratorPromptParse,OrchestratorRunsPure,OrchestratorStream,OrchestratorComposerInput}.swift boringNotch/Orchestrator/Tests/*.swift && ./build/orch-test && ORCH_RETRY_MOCK=1 ORCH_APPROVAL_MOCK=1 ./build/orch-test && DD=./build SNAP_BUILD=./build/snap boringNotch/Orchestrator/Snapshots/run.sh</automated>
  </verify>
  <done>answer() branches on hidesOnAnswer; unit harness (plain and mock env) and snapshot harness pass.</done>
</task>

<task type="auto">
  <name>Task 3: Debug + Release builds, copy, commit</name>
  <files>(build output only; commit of Task 1-2 files)</files>
  <action>
Build only in this worktree; never touch /tmp/notch-current/Clive.app, never launch anything.
Debug: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath ./build CODE_SIGN_IDENTITY=- build > build/dot-debug.log 2>&1`.
Release: same with `-configuration Release ENABLE_HARDENED_RUNTIME=NO 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ORCH_NO_SPARKLE'` into build/dot-rel.log.
Both must end `** BUILD SUCCEEDED **`. Then `rm -rf build/notch-rel/Clive.app && mkdir -p build/notch-rel && ditto build/Build/Products/Release/Clive.app build/notch-rel/Clive.app`; `codesign -dv build/notch-rel/Clive.app` shows ad-hoc (`Signature=adhoc`).
Commit only the source/test/fixture files listed in Task 1-2 (git add those paths explicitly; never graft/, build/
or .planning/): `fix(quick-261016-dot): keep the multi-question card mounted between questions`, ending with the
Co-Authored-By line from the session attribution. Stay on the current branch.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/clive-261015235107-3f9d && tail -1 build/dot-debug.log | grep -q "BUILD SUCCEEDED" && grep -q "BUILD SUCCEEDED" build/dot-rel.log && test -d build/notch-rel/Clive.app && git log -1 --name-only | grep -q QuickDotTests && ! git log -1 --name-only | grep -q '^graft/'</automated>
  </verify>
  <done>Both builds succeed, Release copied ad-hoc to ./build/notch-rel/Clive.app, one commit on the current branch without graft/.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| serve screen text → parser | screen text from 127.0.0.1:4777 drives which keys the card sends |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-dot-01 | Tampering | answer() keep path | mitigate | stillCurrent() identity check before pressKeys kept on both branches, so a key is never sent to a prompt the user did not see |
| T-dot-02 | Elevation | key focus kept between questions | accept | focus is only held while a prompt card is on screen; promptChanged releases on nil and Esc/escape() releases as before |
</threat_model>

<verification>
- Unit harness plain and with ORCH_RETRY_MOCK=1 ORCH_APPROVAL_MOCK=1: OK
- Snapshot harness run.sh passes
- Debug and Release xcodebuild succeed
</verification>

<success_criteria>
- hidesOnAnswer false for q1..q3, true for review / single-question / permission; Tab/BTab never hide
- answer() no longer sets dismissed or calls release() for steps that lead to another step
- Existing tests (QuickChromeTests, review-chrome.txt, single/permission/digit keys) unchanged and passing
- Committed on the current branch, graft/ untouched
</success_criteria>

<output>
Create `.planning/quick/261016-dot-multiq-card-stays-between-questions/261016-dot-SUMMARY.md` when done (not committed by the executor).
</output>
