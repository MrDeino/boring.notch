---
phase: quick-261014-qei
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - boringNotch/Orchestrator/OrchestratorTranscript.swift
  - boringNotch/Orchestrator/Tests/QuickQeiTests.swift
  - boringNotch/Orchestrator/Tests/main.swift
  - boringNotch/Orchestrator/OrchestratorChat.swift
  - boringNotch/Orchestrator/Snapshots/Snap.swift
autonomous: true
requirements: [QUICK-261014-qei]

must_haves:
  truths:
    - "Pressing Enter clears the composer at once; the field keeps focus and accepts the next message while the first is still sending"
    - "The sent message appears immediately as a dimmed user row (compact ❯ row in the open notch, dimmed bubble in the expanded column)"
    - "Messages typed while a send is in flight are queued and sent in order through the existing sending lock; none are dropped"
    - "When the matching user block arrives from /api/chat/blocks, the pending row is replaced by it (whitespace-normalised text match, newest unclaimed block first)"
    - "A failed send shows the row as 'Not sent' with Retry (re-queues) and Edit (puts the text back in the composer)"
  artifacts:
    - path: "boringNotch/Orchestrator/OrchestratorTranscript.swift"
      provides: "PendingMessage, normalizeChatText, reconcilePending (pure, in the swiftc harness)"
      contains: "func reconcilePending"
    - path: "boringNotch/Orchestrator/Tests/QuickQeiTests.swift"
      provides: "runQuickQeiTests()"
    - path: "boringNotch/Orchestrator/OrchestratorChat.swift"
      provides: "store pending queue (enqueue/drain/retry/restore), optimistic composer submit, pending row UI"
      contains: "func enqueue"
  key_links:
    - from: "OrchestratorChatView.submit()"
      to: "OrchestratorTranscriptStore.enqueue"
      via: "draft cleared before enqueue, no stopTyping"
      pattern: "enqueue\\("
    - from: "OrchestratorTranscriptStore.refresh"
      to: "reconcilePending"
      via: "called after blocks merge"
      pattern: "reconcilePending\\("
    - from: "OrchestratorTranscriptStore.drain"
      to: "OrchestratorManager.sendText"
      via: "clearFirst: clearRealLine, one message at a time"
      pattern: "sendText\\("
---

<objective>
Optimistic chat sending from the notch composer: Enter clears the field and keeps it usable, the message shows at once as a dimmed pending user row, sends run in order in the background through the existing one-at-a-time `sending` lock, the real user block from /api/chat/blocks replaces the pending row, and a failed send becomes a "Not sent" row with Retry / Edit.

Purpose: typing a follow-up shouldn't wait on the POST round trip or lose text.
Output: pure matching logic + test, store queue, composer change, pending row UI, 3 snapshot scenes looked at.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@./CLAUDE.md
@.planning/quick/261014-pug-question-prompts-optimistic-polish/261014-pug-SUMMARY.md
@boringNotch/Orchestrator/OrchestratorChat.swift
@boringNotch/Orchestrator/OrchestratorTranscript.swift

## Hard rules (executor)

- Stay on the current branch; don't create or switch GSD phase/milestone branches. Never push.
- NEVER POST to 127.0.0.1:4777 (no curl -X POST, no running the app). Don't launch apps. Leave ORCH_MOCK_LOG unset.
- No new Swift files in the app target (explicit pbxproj refs). New files only under `boringNotch/Orchestrator/Tests/`. No new deps. Don't touch ContentView.swift or other upstream files.
- Test: `mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t | tail -1` -> `OK`
- Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20`
- Snapshots (after a build): `DD=/tmp/notch-dd boringNotch/Orchestrator/Snapshots/run.sh > /tmp/notch-snap.log 2>&1` -> /tmp/notch-snapshots/*.png; open the new PNGs with Read and look at them.

<interfaces>
Current send path (OrchestratorChat.swift / OrchestratorManager.swift):
- `OrchestratorManager.sendText(_ s: String, clearFirst: (() async -> Bool)? = nil) async -> Bool` — returns false immediately if `sending` is already true (lock busy) as well as on failure; on 200 it calls `refresh()`, which calls `OrchestratorTranscriptStore.shared.refresh(...)`. `manager.sending` is `@Published private(set)`. `manager.promptOptions` non-empty = a prompt card is up. Both are @MainActor, so checking `!manager.sending` and then calling `sendText` with no await between is race-free.
- `OrchestratorTranscriptStore.submit(_ text:) async -> Bool` = `sendText(text) { await self.clearRealLine() }` (C-u then text; Enter is part of the text POST server-side).
- `OrchestratorChatView.submit()` today: trims draft, returns if `manager.sending`, terminal-draft pull-in (`!fromTerminal, store.boxIsDraft` -> prepend inputLine and return), then `stopTyping()` and only clears `draft` after the POST succeeds; failure flashes "Couldn't send" and keeps the draft. `sendButton` is `.disabled(blank || manager.sending)`.
- Rows: `rows` renders `ForEach(store.blocks.suffix(maxRows)) { ChatBlockRow(block:proseLineLimit:expanded:) }` then the live/idle status row. `pinKey` drives scroll-to-bottom. ChatBlockRow: expanded + `.user` = right-aligned bubble (80% width, `OT.C.raised`), compact `.user` = `❯` marker + first line in `OT.C.text5`.
- `ChatBlock` (OrchestratorTranscript.swift) has only `init(from: Decoder)` — no memberwise init.
- Store refresh merges with `mergeChatBlocks` then assigns `blocks` (animated when appended).
- Snapshot: `OrchestratorTranscriptStore.snapshotSet(blocks:)` under `#if ORCH_SNAPSHOT` (also called at Snap.swift ~235 and ~292 with blocks only); `Scene` already has a `pending: [Int: Bool]` field (prompt toggles) — use a different name for sends. `markerBlocks`, `editBlocks`, `shortBlocks` exist in Snap.swift.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Pure pending-message matching + test</name>
  <files>boringNotch/Orchestrator/OrchestratorTranscript.swift, boringNotch/Orchestrator/Tests/QuickQeiTests.swift, boringNotch/Orchestrator/Tests/main.swift</files>
  <behavior>
    - normalizeChatText("  a\n  b\u{a0} c  ") == "a b c" (every run of whitespace/newlines/nbsp -> one space, trimmed)
    - a `.sent` pending "fix the  build" + a user block "fix the\nbuild" whose id is not in `known` -> pending removed, returned known contains that id
    - an old user block with the same text whose id IS in `known` -> not matched, pending stays
    - a `.queued` pending is never matched, even if a matching unknown block exists
    - two pending "ok","ok" with one new "ok" block -> only the oldest pending removed; with two new blocks -> both removed
    - newest first: unknown user blocks u3 "x" and u5 "x", one pending "x" -> claims u5 (known gains u5, not u3)
    - a `.failed` row whose text arrives as a block is removed (it landed after all)
    - stale: `.sent` with sentAt = now-31s and no match -> dropped; `.sending` (sentAt nil) and `.failed` rows are kept without a match
    - prose/tool blocks with matching text are ignored (user kind only)
  </behavior>
  <action>
In OrchestratorTranscript.swift (Foundation-only, already in the harness) add:
- `struct PendingMessage: Equatable, Identifiable` with `enum State { case queued, sending, sent, failed }`, `let id: Int`, `let text: String`, `var state: State`, `var sentAt: Date?` (memberwise init is fine).
- `func normalizeChatText(_ s: String) -> String`: split on whitespace/newlines (incl. U+00A0) and join with single spaces.
- `func reconcilePending(_ pending: [PendingMessage], blocks: [ChatBlock], known: Set<String>, now: Date, staleAfter: TimeInterval = 30) -> (pending: [PendingMessage], known: Set<String>)`: walk pending oldest first; skip `.queued`; for the others search `blocks` from newest to oldest for `kind == .user`, id not in known, `normalizeChatText(text ?? "") == normalizeChatText(p.text)`; on a hit drop the row and insert the id into known. Unmatched `.sent` rows with `sentAt` older than `staleAfter` are dropped too, with a `ponytail:` comment (ceiling: a sent message whose block text differs, e.g. a slash command, would otherwise stay dimmed forever; upgrade = serve echoing a client id).
- `extension ChatBlock { init(pendingID: String, text: String) }` setting kind `.user`, the text, every other field nil — so pending rows reuse ChatBlockRow and snapshots can build blocks. (A plain init in an extension keeps the decoder init.)

Create Tests/QuickQeiTests.swift with `func runQuickQeiTests()` covering every behavior bullet (build blocks with `decodeChatBlocks(Data(json.utf8))!.blocks` or the new init; use a fixed `now`). Add `runQuickQeiTests()` to Tests/main.swift before `print("OK")`. Write the test first, see it fail to compile/assert, then implement.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t | tail -1 | grep -x OK && grep -n "runQuickQeiTests()" boringNotch/Orchestrator/Tests/main.swift</automated>
  </verify>
  <done>Harness prints OK with runQuickQeiTests covering normalisation, known-id exclusion, queued skip, duplicates, newest-first, failed-landed, stale drop, user-kind only.</done>
</task>

<task type="auto">
  <name>Task 2: Store queue, optimistic composer, pending rows, snapshot scenes</name>
  <files>boringNotch/Orchestrator/OrchestratorChat.swift, boringNotch/Orchestrator/Snapshots/Snap.swift</files>
  <action>
OrchestratorTranscriptStore (OrchestratorChat.swift):
- Add `@Published private(set) var pending: [PendingMessage] = []`, `private var knownUserIDs: Set<String> = []`, `private var nextPendingID = 0`, `private var draining = false`.
- `func enqueue(_ text: String)`: add every current `.user` block id to knownUserIDs (so an older identical message can't claim the new row), append `.queued`, call `drain()`.
- `private func drain()`: if draining return; set draining; `Task { @MainActor in ... }` loop while there is a first `.queued` row: wait (50 ms `Task.sleep` steps) while `OrchestratorManager.shared.sending` or `!manager.promptOptions.isEmpty` (never type queued text into a permission/question prompt); mark the row `.sending`; `let ok = await OrchestratorManager.shared.sendText(text) { await self.clearRealLine() }`; then look the row up by id (it may already be gone — refresh inside sendText can reconcile it) and set `.sent` + `sentAt = Date()` or `.failed`. After the loop clear draining. Decision (Claude's discretion): a failure marks only that row and the queue continues with the next one, so nothing gets stuck behind a dead row; note it in a `ponytail:` comment. Remove the old `submit(_:)` (its only caller is the view) or keep it as a thin wrapper only if something else uses it (grep).
- `func retry(_ id: Int)`: set that row `.queued`, `sentAt = nil`, `drain()`. `func restore(_ id: Int) -> String?`: remove the row and return its text.
- In `refresh`, after the `blocks` assignment block (and after the reset path), run `reconcilePending(pending, blocks: blocks, known: knownUserIDs, now: Date())` and assign `pending`/`knownUserIDs` only when changed; wrap in the same spring animation when a row is removed so the swap reads as a replace.
- Snapshot extension: `snapshotSet(blocks: [ChatBlock], pending: [PendingMessage] = [])` sets both (no drain), so existing callers compile unchanged.

OrchestratorChatView:
- `submit()`: keep the blank check and the terminal-draft pull-in branch as is; drop the `guard !manager.sending` line and the `stopTyping()` call. Otherwise: `store.enqueue(t)`, `draft = ""`, `fromTerminal = false` — immediately, field stays focused and typing continues. Remove the "Couldn't send" tag path (failure now lives on the row). `sendButton` disabled only when blank.
- `rows`: after the `if store.fallback { … } else { … }` block (so pending rows show in both the blocks and the chatTail fallback mode and a send never vanishes) and before the status row, `ForEach(store.pending) { p in pendingRow(p) }` with the same move+opacity transition. `pendingRow`: `ChatBlockRow(block: ChatBlock(pendingID: "pending-\(p.id)", text: p.text), proseLineLimit: proseLineLimit, expanded: expanded).opacity(0.5)` (compact ❯ row and expanded bubble both dim); for `.failed` add under it a trailing-aligned (expanded) / marker-indented (compact, 16pt leading) HStack: "Not sent" in `OT.F.meta` / `OT.C.redText`, then plain Buttons "Retry" (`store.retry(p.id)`) and "Edit" (`if let t = store.restore(p.id) { draft = draft.isEmpty ? t : t + " " + draft; fromTerminal = false; if showComposer { startTyping() } }`) in `OT.F.meta` / `OT.C.text5`. Buttons win over the chat area's `onTapGesture(expandChat)`.
- `pinKey`: append `|\(store.pending.count)` so new pending rows scroll into view.

Snap.swift: add `var sends: [PendingMessage] = []` to `Scene`, pass it as `snapshotSet(blocks: s.blocks, pending: s.sends)`, and add scenes `25-chat-pending` (compact, markerBlocks + `.sent` "Thanks — now fix the build error" + `.queued` "and then run the tests"), `26-chat-not-sent` (compact, markerBlocks + `.failed` message long enough to truncate), `27-expanded-pending` (expanded, editBlocks + `.sending` short message + `.failed` long message that wraps in the bubble). Build, run snapshots, Read 25, 26, 27 (and 15, 23 to confirm normal rows unchanged). Fix anything clipped, undimmed, or misaligned and re-shoot.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t | tail -1 | grep -x OK && grep -n "reconcilePending(" boringNotch/Orchestrator/OrchestratorChat.swift && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20 && DD=/tmp/notch-dd boringNotch/Orchestrator/Snapshots/run.sh > /tmp/notch-snap.log 2>&1; ! grep FAILED /tmp/notch-snap.log && ls /tmp/notch-snapshots/25-chat-pending.png /tmp/notch-snapshots/26-chat-not-sent.png /tmp/notch-snapshots/27-expanded-pending.png</automated>
    <human-check>Read /tmp/notch-snapshots/25, 26, 27 PNGs: pending rows visibly dimmed (compact ❯ row and expanded bubble), "Not sent" + Retry + Edit readable and not clipped, newest pending row visible above the composer; 15 and 23 unchanged.</human-check>
  </verify>
  <done>BUILD SUCCEEDED; snapshot run has no FAILED; scenes 25-27 written and looked at; Enter clears and keeps focus; sends queue in order through sendText; refresh reconciles pending rows; failed rows offer Retry/Edit.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| notch -> local serve (127.0.0.1:4777) | user-typed text POSTed as chat input; blocks JSON read back |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-qei-01 | Tampering | drain() typing into a live prompt | mitigate | drain waits while `promptOptions` is non-empty, and every send still goes through sendText's C-u + one-lock window |
| T-qei-02 | Denial of service | queue stuck behind a failed send | mitigate | failure marks only that row; queue continues; Retry/Edit per row |
| T-qei-03 | Information disclosure | pending text in memory | accept | loopback only, same data the composer already holds |
</threat_model>

<verification>
- swiftc harness prints OK (runQuickQeiTests included).
- xcodebuild into /tmp/notch-dd: BUILD SUCCEEDED.
- Snapshot scenes 25-27 written, no FAILED, PNGs looked at.
- No POSTs to 127.0.0.1:4777, no app launched, no new app-target files, branch unchanged.
</verification>

<success_criteria>
Enter clears and keeps the composer usable; the message shows instantly as a dimmed pending row in both compact and expanded views; queued sends go out in order without drops; the real block replaces the pending row; failed sends show "Not sent" with Retry and Edit.
</success_criteria>

<output>
Create `.planning/quick/261014-qei-optimistic-message-sending/261014-qei-SUMMARY.md` when done
</output>
