# Phase 5: 2a Structured chat - Research

**Researched:** 2026-10-14
**Domain:** SwiftUI/AppKit (macOS 14 target) chat transcript + composer in a non-activating NSPanel; JSON client for serve's `/api/chat/blocks`
**Confidence:** MEDIUM-HIGH (endpoint shape HIGH, verified live; SwiftUI key-interception behaviour MEDIUM, needs on-device check)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: Rows come from serve's `GET /api/chat/blocks?since=<id>`, not screen parsing. Decode every field optionally; unknown kinds are skipped.
- D-02: Incremental fetch with last block `id`; first load / chat restart = no `since`, replace. Accept bare array or `{blocks:[…]}`. Cap kept blocks (~200).
- D-03: Fallback to `chatTail` lines restyled (prose font) on 404 / decode failure. A failed blocks fetch is non-fatal (never flips the tab offline).
- D-04: Blocks fetch is a GET run from the Phase 4 refresh hook. Test decode/merge with fixture JSON in the swiftc harness, never the live server.
- D-05: Row styles per README 01 (user ❯ 12pt #8E8E93; tool chip mono 10pt medium #C4C4C6 on #1C1C1E r5 pad 2/6 + target mono 11pt #D1D1D6 + result 11pt #636366; +N #30D158 / −N #FF6961 mono 10pt + static "▸ diff"; prose 13pt white line-height 1.35). Content padding 0 6 8, gap 5, bottom aligned.
- D-06: Status row "✻ Working · 0:41" (11pt #D97757) + "esc to interrupt" (#636366) from `manager.liveStatus`. Shimmer while live; elapsed ticks locally.
- D-07: New rows keyed by block id insert with `.move(edge: .bottom).combined(with: .opacity)`, spring 0.3/0.85. Clicking transcript opens terminal.
- D-08: Composer per README 02; focus/typing via existing `OrchestratorKeyGate`, `beginTyping`, `endTyping` **unchanged**.
- D-09: `inputLine` parsed from the screen `❯` line; suggestion when field empty and not focused-with-draft; on focus with box text, pull in as terminal draft with "from terminal · " UI prefix. Record heuristic with a ponytail comment.
- D-10: Ghost text #636366 + "[Tab] accept" keycap; Tab or → accepts (fill + POST `{key:"Tab"}`); other char replaces; ⌃U clears cursor→line start locally AND POSTs `{key:"C-u"}`; "line cleared" tag ~1.2s.
- D-11: Owned files: `OrchestratorChat.swift`, `OrchestratorTranscript.swift`, `Tests/Phase5Tests.swift`. Shared edit only a `// Phase 5` block in `OrchestratorManager.swift` if state cannot live on a Phase 5 object. No edits to Models, Expand, header, ContentView, pbxproj. Every plan lists `<merge_points>`.
- S-01..S-07: never POST to 127.0.0.1:4777; no app launch; build with `-derivedDataPath /tmp/notch-dd-p5`; new files under `boringNotch/Orchestrator/`; no deps; Swift 5 mode, ObservableObject singletons; music must not regress; never push, no branches; pure logic gets swiftc-harness asserts; follow README exactly.

### Claude's Discretion
- Transcript state on a separate `ObservableObject` (preferred) vs the manager.
- How the composer intercepts Tab/→/⌃U in a SwiftUI TextField.

### Deferred Ideas (OUT OF SCOPE)
Streaming caret, ▸ diff expansion, `suggested` flag, ctx % (Phase 8). Expanded conversation column (Phase 7 embeds this phase's view). Prompt cards (6), runs board / expand levels / wings (7).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CHAT-01 | Rows from `/api/chat/blocks?since=`, incremental, fallback while endpoint missing | Endpoint is **already live** (below). Lossy decoder, merge/reset rules, chatTail fallback |
| CHAT-02 | Live "✻ Working · elapsed · esc to interrupt" row | TimelineView ticking + gradient shimmer, anchored locally |
| CHAT-03 | Composer matches frame 02 using existing key-gate | Preserve list for existing typing logic; pill/ring/hint layout |
| CHAT-04 | Message box mirrors Claude's input box: ghost, Tab/→, ⌃U, tag, terminal draft | `parseInputLine`, NSEvent local monitor, send-sync pitfall (C-u before text) |
| CHAT-05 | Rows animate in from bottom; click transcript opens terminal | id-keyed transitions, animate only appends |
</phase_requirements>

## Summary

`GET /api/chat/blocks` **exists and is live now** (merged to orchestrator `main`, serve restarted; commit `09da209` "GET /api/chat/blocks"; code in `/Users/mitch/Documents/Claude/orchestrator/orch.js` `chatBlocks()` / `chatBlocksLive()`, route ~line 636). I curled it (GET only) and captured the real shape: wrapper is `{"running":bool,"blocks":[…]}` (not a bare array), ids are **strings** (Claude transcript `uuid` for user/prose, `toolu_…` for tool). So D-02's "accept both" is cheap insurance only. Server caps responses at the last 80 blocks and re-parses the transcript tail (last 4 MB) on every call. `running:false, blocks:[]` is returned when serve cannot locate the chat's transcript (no tmux session, or pane pid has no `~/.claude/sessions/<pid>.json`).

The SwiftUI side is plain: lossy Codable, an id-keyed merge in the pure file, a transcript store object owned by Phase 5, a bottom-aligned VStack (no ScrollView) in the 190 px notch. The risky part is the composer: macOS 14 `onKeyPress` on a focused TextField is unproven for Tab (and Tab/Shift-Tab are intercepted by AppKit for focus navigation), and TextField exposes no caret. Recommendation: an `NSEvent.addLocalMonitorForEvents(.keyDown)` installed only while the composer is focused (Tab keyCode 48, → 124, ⌃U keyCode 32) that reaches the field editor `NSTextView` for the caret. Same technique already used in `OrchestratorExpand` (mouse monitors), no new files or deps.

Two spec problems the planner must resolve (details in Open Questions): (1) sending text via `POST {text}` **types into** Claude's real input box without clearing it, so after Tab-accept or a pulled-in terminal draft a naive send would duplicate text; send `C-u` first. (2) D-09 ("on focus, pull box text in as draft") contradicts README 02b frame (a), where the focused composer shows the box text as ghost + Tab hint.

**Primary recommendation:** Pure decode/merge/`parseInputLine` in `OrchestratorTranscript.swift` with fixture asserts; a `@MainActor ObservableObject` store + views in `OrchestratorChat.swift`; NSEvent local monitor for Tab/→/⌃U; always `C-u` before `sendText` when the real box is non-empty.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Transcript → blocks parsing (JSONL, tool pairing, diffs) | Serve (orch.js, other repo) | — | Already done server-side; client only decodes |
| Decode / merge / cap blocks, `parseInputLine` | Pure Swift (`OrchestratorTranscript.swift`) | — | Harness-testable, Foundation only |
| Fetch + state (`blocks`, `inputLine`, `blocksMode`) | `@MainActor` store in `OrchestratorChat.swift` | Manager hook (Phase 4) | Zero manager diff |
| Rendering rows, status row, composer | SwiftUI (`OrchestratorChat.swift`) | AppKit (key monitor, field editor) | Spec UI |
| Real input-box state (draft/suggestion) | Claude Code in tmux (via POST keys) | — | Notch mirrors it; must keep in sync (C-u) |

## Standard Stack

All system; no packages (project constraint). No Package Legitimacy Audit needed: **no external packages installed**.

| Item | Use | Provenance |
|------|-----|-----------|
| `URLSession` async + `JSONDecoder` | blocks GET | in-repo pattern (`OrchestratorManager.get`) [VERIFIED: codebase] |
| `TimelineView(.periodic)` / `.animation` | elapsed tick, shimmer | SwiftUI, macOS 12+ [ASSUMED: training] |
| `NSEvent.addLocalMonitorForEvents` | Tab/→/⌃U | already used in `OrchestratorExpand.swift:78` [VERIFIED: codebase] |
| `Regex` literals | `parseInputLine`, result cleanup | already used in `detectPrompt` [VERIFIED: codebase] |

Harness (fixed by MERGE-MAP): `mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t`. Existing `Tests/main.swift` uses `precondition`. Phase 5 fills `func runPhase5Tests()`. (Nyquist validation disabled in config, so no separate Validation Architecture section.)

## Endpoint contract (verified live 2026-10-14)

`GET /api/chat/blocks[?since=<id>]` → `{"running":true,"blocks":[Block…]}`

```json
{"running":true,"blocks":[
 {"id":"3257d34b-01db-4371-b214-d5094c5bd102","kind":"user","text":"have we built the drop down expansion?"},
 {"id":"52c4f248-c8d9-44d5-9c11-df826315f555","kind":"prose","text":"Not yet, ...\n- Phase 1, done: ...\n\nmarkdown **bold** allowed"},
 {"id":"toolu_01GsEgsf94zK7n2coKF57YWe","kind":"tool","name":"Bash","target":"grep '\"type\":\"result\"' runs/x.jsonl | tail -1 | node -e '…B…","result":"All three tweaks are in… (+14 lines)"}
]}
```
Edit/MultiEdit/Write tool blocks additionally (only once the tool_result arrives) carry `"added":12,"removed":4,"diff":[{"oldStart":10,"newStart":10,"lines":[" ctx","-old","+new"]}]` (diff: max 4 hunks × 40 lines). A pending tool has `"result":null` and no `added/removed/diff`. [VERIFIED: orch.js source + live curl; no live Edit sample was in the current 80 blocks, so the added/removed/diff shape is VERIFIED from source only.]

Mapping rules (from `chatBlocks`, orch.js ~498):
- user: `type:"user"` JSONL line, string/text content, not tool_result, not sidechain/meta/compact summary, not `origin` non-human; text starting with `<` skipped unless it has `origin`. Whole text kept (can be multi-line, long).
- prose: all `text` parts of one assistant line joined by blank line. No thinking blocks.
- tool: each `tool_use`; `id` = tool_use id; `target` = first of file_path/notebook_path/command/pattern/path/url/query/skill/description/first question, via `one()`: first non-empty line, max 200 chars + "…" , plus " (+N lines)" if multi-line. `result` = `one(tool_result body)` (first non-empty line ≤160 chars + " (+N lines)"), prefixed `error: ` when `is_error`; `(no output)` when empty. Pairing is by `tool_use_id`, so results fill in **later** than the tool block appears.
- added/removed: counted from `toolUseResult.structuredPatch` lines starting `+`/`-` (Write-create: every line `+`), only for names Edit/MultiEdit/Write.
- `since`: returns blocks after `since`, **plus the contiguous run of tool blocks ending at `since`** (so their late results refresh). Unknown `since` is treated as no `since` → last 80 blocks (indistinguishable from a normal response). Limit 80, so `count == 80` can mean truncation.
- Read results are the file's first line + "(+N lines)" (not "287 lines"): UI must derive "N lines" itself.

## Architecture Patterns

### Data flow
```
Phase 4 refresh() ──await──> store.refresh(base,session,chatRunning)
   GET /api/chat/blocks[?since=lastId]  ── 404/err/decode fail ──> mode = .fallback (chatTail lines), non-fatal
        │ ok
        v
   decodeBlocks (lossy: bare array | {running,blocks}; unknown kind dropped)
        │
        v
   merge(existing, incoming, reset?) ── cap 200 ──> store.blocks (animate only appends)
screen (from manager) ──> parseInputLine ──> store.inputLine
        v
OrchestratorChatView: transcript VStack (bottom-aligned) + status row + composer + hint
   composer: TextField + NSEvent monitor (Tab, →, ⌃U) ──> manager.post(.key/.text)
```

### Recommended structure
- `OrchestratorTranscript.swift` (pure, Foundation only): `ChatBlock`, `ChatBlock.Kind`, `DiffHunk`, `decodeBlocks(_ data: Data) -> (running: Bool?, blocks: [ChatBlock])?`, `mergeBlocks(...)`, `parseInputLine(screen:) -> String?`, display helpers (`toolTargetDisplay`, `toolResultDisplay`, `formatElapsed`). **No SwiftUI/Combine** (harness compiles it standalone).
- `OrchestratorChat.swift`: `@MainActor final class OrchestratorTranscriptStore: ObservableObject` (static `shared`), `OrchestratorChatView`, row views, status row, composer. Keep the Phase 4 view name `OrchestratorChatView` and its init signature (Phase 7 embeds it by type name, MERGE-MAP #4). Add only defaulted parameters.
- **Dependency on Phase 4 output (not built yet):** the exact signature of the `transcript.refresh(...)` hook and what the stub is called must be read from Phase 4's plans/summary before planning Phase 5 tasks. If the hook does not pass `URLSession`/baseURL/screen, the store can own a tiny ephemeral session (3 s timeout) and read `OrchestratorManager.shared.screen`; that is zero manager diff. Phase 5 must not widen the hook signature (shared line with Phase 6).

### Pattern: lossy decode
```swift
struct Lossy<T: Decodable>: Decodable { let value: T?; init(from d: Decoder) throws { value = try? T(from: d) } }
struct ChatBlock: Decodable, Equatable, Identifiable {
    enum Kind: Equatable { case user, tool, prose, other(String) }
    let id: String; let kind: Kind
    let text, name, target, result: String?
    let added, removed: Int?; let diff: [DiffHunk]?
    // init(from:): id via String, else Int, else throw (block dropped by Lossy); kind via String → switch;
    // every other field `try? container.decodeIfPresent`
}
// Wrapper: try {running, blocks:[Lossy<ChatBlock>]} first, then [Lossy<ChatBlock>] bare array.
// Drop .other kinds and blocks whose decode threw. Dedup by id while merging.
```
`running == false` (or nil with empty) means "no transcript": clear blocks and use fallback if the screen shows chat.

### Merge semantics (pure, tested)
`mergeBlocks(existing, incoming, reset, cap=200)`: `reset` → `incoming`; else for each incoming block: id already present → **replace in place** (tool result/diff arrived); else append. Then `suffix(cap)`. Request `since = reset ? nil : existing.last?.id`.
Reset triggers (no server signal exists for restart, so detect client-side):
1. first load, or `chatRunning` false → true (chat restarted), or response `running == false` (clear);
2. `since` was sent, `incoming.count >= 80` and no incoming id is in `existing` (server truncated/lost continuity) → replace;
3. safety resync: every ~15th successful poll (about 30 s open) do a full fetch without `since` and replace (covers `/clear` or `--continue` switching transcript file, where `since` is unknown and the server returns the whole new transcript, indistinguishable from an append). `// ponytail:` comment naming this ceiling.
Fetch concurrency: one in flight (guard like `refreshing`); do not run while `chatRunning` is false.

### Pattern: parseInputLine (pure)
Fixture `Tests/fixtures/inputbox.txt` (verified): opening rule `───… <session title> ─`, line `❯\u{a0}merge 199` + ~150 trailing spaces, closing rule, then 2 status lines. Algorithm (mirror `chatTail`'s box detection; do **not** edit Models, duplicate the 8 lines with a ponytail comment): trim lines (spaces, NBSP, tab, CR), find last index `i` where line `i` hasPrefix `───`, line `i+1` hasPrefix `❯`, and a later rule exists. Box text = line `i+1` minus `❯` and leading NBSP/space, plus any continuation lines up to the closing rule joined by a space (serve flattens newlines anyway). Return `nil` when no box (live prompt, empty screen, offline), `""` for empty box (`❯` alone). A live prompt `❯ 1. Yes` has no closing rule below, so returns nil (same guard as chatTail). Asserts: fixture → "make it my real app" (the file content differs from the chatTail test string; assert against the actual file), `❯` only → "", prompt screens `permission.txt`/`question.txt` → nil, empty → nil.

### Pattern: rows in 190 px
Budget: 190 − header 34 − bottom padding 12 = 144. Composer 30 + hint row ~12 + gaps ≈ 50, status row ~14 → about 80-90 px for transcript: ~4 single-line rows (tool rows ≈ 18 + 5 gap) or about 4 lines of 13pt/1.35 prose (17.5 each). Therefore:
- `VStack(alignment:.leading, spacing:5)` of `ForEach(blocks.suffix(12))` in `.frame(maxHeight:.infinity, alignment:.bottomLeading).clipped()`; **no ScrollView** (scroll would fight the click-to-expand tap, and top-clipped rows are fine). Optional top fade via `.mask(LinearGradient)`.
- Prose `lineLimit(4)` tail-truncated in this compact view (parameter `proseLineLimit: Int? = 4`, Phase 7 expanded passes nil). User rows `lineLimit(1)` of the first line. Tool target: `lineLimit(1)`; `.middle` truncation for paths, `.tail` for commands.
- Display transforms (pure, tested): target for Read/Edit/Write/MultiEdit/NotebookEdit and absolute-path targets → `lastPathComponent` (README shows file names); result → strip trailing ` (+N lines)`; for `Read` show "\(N+1) lines" parsed from that suffix; hide result for Edit/Write when `added != nil` and show +N/−N and "▸ diff"; `error:` prefix → #FF6961.
- Prose may contain markdown (`**bold**`, lists): render with `Text(.init(markdownString))`-style inline `AttributedString(markdown:, options: .inlineOnlyPreservingWhitespace)` falling back to plain on failure. [ASSUMED: API availability, macOS 12+]

### Pattern: insert animation (CHAT-05)
`ForEach(blocks)` identified by `id` with `.transition(.move(edge:.bottom).combined(with:.opacity))`. Transitions only play when the mutation happens inside `withAnimation(.spring(response:0.3,dampingFraction:0.85))`. In the store: animate only when the merge **appended** ids; assign without animation on reset/first load (otherwise the whole list animates in on open) and for in-place tool-result updates. README says "keyed by content hash"; CONTEXT D-07 says block id, which is right since server ids are stable (content hash would re-key rows when a tool result lands).

### Pattern: status row + shimmer (CHAT-02)
Phase 4 provides `manager.liveStatus` (text + elapsed seconds; exact type not yet built). Store a local anchor `(elapsed, Date)` in view `@State`, reset in `.onChange(of: liveStatus?.elapsed)`; render `TimelineView(.periodic(from: .now, by: 1))` computing `base + context.date - anchor`, formatted `m:ss` (README "0:41"; 1h+ → `h:mm:ss`). Shimmer without deps: `Text` filled with `LinearGradient` whose stops slide with `TimelineView(.animation(minimumInterval: 1/30))` phase, or a `mask` of a moving gradient; only instantiate while `liveStatus != nil`, so closed/idle costs nothing. Honour `accessibilityReduceMotion` (static). Row hidden when `liveStatus == nil`. Idle "✻ Brewed for 2m 4s" in README 02b is **not** in CONTEXT; skip unless cheap (open question).

### Pattern: composer (CHAT-03/04)
- Pill: 30 px, `RoundedRectangle(cornerRadius:15)` fill #1C1C1E, padding `0 6 0 14`, 12pt, send circle 20 px (#3A3A3C bg, #8E8E93 ↑; focused/non-empty: #D97757 bg, black ↑), ring `.overlay(Capsule().stroke(#D97757, lineWidth:1.5))` when `fieldFocused`. Hint row 10pt #636366 right-aligned: "⏎ send · ⌃U clear line · esc release". Use Phase 4 tokens (`OT`), not literals.
- **Preserve unchanged from today's `OrchestratorView.swift` (Phase 4 moves it into `OrchestratorChat.swift` verbatim; do not alter):** `WindowAnchor`/`anchor`, `@State keyWindow`, `@FocusState fieldFocused`; `startTyping()` (`manager.beginTyping(in:)`, `OrchestratorKeyGate.activate()`, `w.makeKey()`, async second `makeKey()` + `fieldFocused = true`, 600 ms give-up Task); `stopTyping(handBack:)`; `submit()` (stopTyping then `sendText`); `expandChat()`; the `.onReceive(didResignKey)`, `.onDisappear`, `.onChange(of: fieldFocused / chatRunning / offline / promptOptions)` teardown; `.allowsHitTesting(manager.wantsKeyboard)` + the tap-catcher `Color.clear` that calls `startTyping()` when not yet keyboard-capable; `.onExitCommand { stopTyping() }`; `.onSubmit`. The composer restyles the container around the same `TextField`; the field is hit-test-disabled until `wantsKeyboard`, so the pill-wide tap catcher must remain.
- Ghost text: because the ghost only shows when the field is empty, the caret is at position 0 and the ghost simply starts at the leading edge, so alignment is trivial: `ZStack(alignment:.leading) { if draft.isEmpty, let s = suggestion { Text(s).foregroundStyle(#636366).allowsHitTesting(false) }; TextField("", text:$draft) }` with identical font/padding. Placeholder "Message orchestrator" shows when no suggestion. "[Tab] accept" keycap (mono 10pt medium, pad 1/5, r4, #AEAEB2 on #3A3A3C) right of the text, before the send circle, only while ghost is shown.
- Key interception: **recommended = `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`** installed when `fieldFocused` becomes true, removed when false/`onDisappear`. Handlers (return `nil` to swallow, else the event): keyCode 48 (Tab, no modifiers) when ghost showing → accept; keyCode 124 (→, no modifiers) when ghost showing → accept (when draft non-empty, pass through so the caret moves normally); keyCode 32 with `.control` → ⌃U. Reasons: AppKit consumes Tab for focus navigation before SwiftUI `onKeyPress` sees it on macOS (DTS reply in Apple forum thread 825509 recommends exactly this monitor for Tab/Shift-Tab; not tested on a focused single-line TextField, so MEDIUM) [CITED: developer.apple.com/forums/thread/825509]; `onKeyPress` needs a focusable view and its behaviour inside a non-activating panel is unverified [ASSUMED]. The monitor does not care about SwiftUI focus semantics and is the only no-new-file way to read the caret. Cost ≈ 25 lines. Fallback if the planner prefers fewer moving parts: `.onKeyPress(.tab)`/`.rightArrow` on the TextField plus ⌃U as "clear whole field" (see below) and put an on-device check in the verification checklist.
- ⌃U caret: macOS 14 TextField has no selection API [ASSUMED: macOS 15 added `TextSelection`, not available at target 14]. Via the monitor: `(w.fieldEditor(false, for: nil) as? NSTextView)` or `w.firstResponder as? NSTextView` → `selectedRange().location` = caret; delete `[0, caret)` with `tv.insertText("", replacementRange: NSRange(0, caret))` (fires the change notification so the SwiftUI binding updates and caret stays at 0). If no NSTextView is reachable, fall back to clearing the whole field (matches the spec exactly when the caret is at end, the common case). Always also POST `{key:"C-u"}` and show the "line cleared" tag ~1.2 s (Task with generation counter to avoid early dismissal on a second ⌃U). After clear, if the field is empty the suggestion returns (ghost reappears) per frame d. Note: ⌃U in the real box clears the whole line to start regardless of the notch caret, so mid-line ⌃U can desync; with the C-u-before-send rule below this is harmless.
- Accept: `draft = suggestion; fromTerminal = false; POST {key:"Tab"}` (fire and forget, allowed key).
- Terminal draft (frame e): UI-only prefix "from terminal · " rendered as a leading `Text` (#8E8E93) outside the TextField, not part of `draft`; cleared when the user empties the field or sends.

### Send sync (critical, not in spec)
`POST /api/chat {text}` runs `tmux send-keys -l <text>` then Enter: it **types into the real box without clearing it** [VERIFIED: orch.js ~654]. After Tab-accept (real box now holds the suggestion) or a pulled-in terminal draft, the real box already contains text, so a plain `sendText` yields duplicated/concatenated text. Rule: in `submit()`, if the latest `inputLine` (re-read after `await refresh`) is non-empty, `await post(.key("C-u"))` first, then `sendText`. `post` is serialised by the `sending` guard, so await each call sequentially. `C-u` and `Tab`/`Enter` are all in `allowedKeys` after Phase 4. This touches `submit()` which D-08 says stays unchanged: treat it as "the typing/key-gate logic (begin/end/anchor/key window)" stays unchanged and call out the one added pre-send step in `<merge_points>`/SUMMARY; if the user wants `submit()` byte-identical, do the C-u inside the composer's own wrapper before calling the unchanged `submit()`.

### Anti-patterns
- Replacing the list on every poll (kills insert animations and tool-result in-place updates).
- Failing the poll when blocks fails (D-03: never set offline from blocks).
- ScrollView in the compact transcript (steals taps; unneeded in 190 px).
- Putting the store/view in `OrchestratorTranscript.swift` (harness compiles it with Foundation only).
- Editing `OrchestratorModels.swift` (Phase 6 moves `detectPrompt` out of it; Phase 7 edits `OrchestratorRun`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| JSONL transcript parsing / tool pairing / diff counts | Any client-side transcript parser | Serve's `/api/chat/blocks` |
| Caret / selection in field | Custom text engine | AppKit field editor via `firstResponder as? NSTextView` |
| Elapsed ticking | Own Timer | `TimelineView(.periodic)` |
| Markdown in prose | Custom parser | `AttributedString(markdown:)` |

## Common Pitfalls

1. **Duplicate text on send** (above). Warning sign: sent message appears twice in transcript after Tab-accept.
2. **Tool rows never get results**: merging append-only drops late `result`/`added`/`diff`. Merge must replace by id; server `since` deliberately re-sends the trailing tool run.
3. **Restart/`/clear` leaves stale rows**: see reset triggers; the bogus-`since` response is the same shape as a normal one.
4. **Whole list re-animates on open**: assign without `withAnimation` on reset.
5. **`running:false` with `chatRunning` true** (transcript not locatable): fall back to chatTail rows rather than an empty transcript.
6. **Ghost vs draft ambiguity** (Phase A): a typed draft in the terminal and a dim suggestion look identical on screen. See open question; never POST Tab unless the user pressed Tab/→ while ghost is showing.
7. **Monitor leaks**: remove the NSEvent monitor on focus loss, `onDisappear`, and when `stopTyping()` runs; one monitor per composer (expanded Phase 7 may host a second composer; make install idempotent).
8. **Poll refresh clobbering the field**: never write `draft` from `inputLine` while focused except the single pull-in at focus time.
9. **Closed-notch cost**: blocks fetch re-parses up to 4 MB server-side; skip the fetch while the notch is closed (or only when `blocks` would be visible); fetch on open. [ASSUMED: acceptable; confirm with Phase 7's 3 s closed poll]
10. **Unbounded ForEach layout**: render `suffix(12)`, not all 200.

## Code Examples

Merge (pure):
```swift
func mergeBlocks(_ existing: [ChatBlock], _ incoming: [ChatBlock], reset: Bool, cap: Int = 200) -> (blocks: [ChatBlock], appended: Bool) {
    if reset { return (Array(incoming.suffix(cap)), false) }   // caller does not animate resets
    var out = existing; var appended = false
    for b in incoming {
        if let i = out.firstIndex(where: { $0.id == b.id }) { out[i] = b } else { out.append(b); appended = true }
    }
    return (Array(out.suffix(cap)), appended)
}
```
Fixtures for `Phase5Tests.swift` (inline strings, harness style): bare array; `{running,blocks}`; unknown kind `"thinking"` dropped; missing `text`; int id `{"id":7,...}`; one malformed block among valid ones (others survive); tool with `added/removed/diff`; tool `"result":null`; merge replace-in-place of a tool result; reset; cap; `running:false` empty; `parseInputLine` cases; display helpers (`Read` "(+286 lines)" → "287 lines", path basename, `error:` prefix, `formatElapsed(41)=="0:41"`, `3725=="1:02:05"`).

## State of the Art
| Old | Current | Impact |
|-----|---------|--------|
| Screen parsing for rows | Server-built blocks from Claude's JSONL | Real diffs/results; client is dumb |
| Phase B SSE | Not now | Poll `?since=` every 2 s open |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `onKeyPress` on a focused TextField does not reliably deliver Tab; NSEvent monitor works in the key-gated non-activating panel | Composer | Tab/→ accept fails; needs on-device test, monitor fallback is the plan |
| A2 | `NSTextView.insertText("", replacementRange:)` on the field editor updates the SwiftUI binding and keeps caret | Composer | ⌃U falls back to clearing whole line |
| A3 | Claude Code's Tab accepts its ghost suggestion in the real box (README claim) | Composer | POSTing Tab does nothing; local fill still works but `C-u` pre-send keeps it safe |
| A4 | `C-u` clears the whole Claude input line | Send sync | If it only clears to cursor, residue possible (cursor is at end after typing, so fine) |
| A5 | Heuristic "text that changes between polls = draft, static = suggestion" is good enough for Phase A | Open Q1 | Misclassified draft shown as ghost (harmless) or suggestion pulled as draft |
| A6 | TimelineView/gradient shimmer cost is negligible | Status | Battery in closed state; mitigated by instantiating only while live and open |
| A7 | macOS 14 TextField has no selection API | Composer | If wrong, simpler caret code |

## Open Questions

1. **D-09 vs README 02b(a):** D-09 says on focus the box text is pulled in as a "from terminal" draft; frame (a) shows a focused composer with ghost + Tab hint. Phase A cannot tell them apart. If D-09 is applied literally, a suggestion becomes a white draft the moment the user clicks the composer and the Tab-accept flow (a, b, d) never appears. Recommendation: ghost by default; classify as a terminal draft only if the box text has been seen changing between polls (A5); record with the ponytail comment; ask the user to confirm. **Needs user decision.**
2. **`submit()` unchanged vs C-u-before-send:** see Send sync. Recommendation: add the pre-send C-u in a wrapper around the unchanged `submit()`.
3. **Idle summary row** ("✻ Brewed for 2m 4s", README 02b) and the user row's ❯ glyph (README text says ❯, screenshot 01 shows none): not in CONTEXT. Recommendation: follow CONTEXT/README text (❯ prefix, no idle row); minor.
4. **Phase 4 hook signature** unknown until Phase 4 is planned/built: Phase 5's planner must read `04-*-PLAN.md`/SUMMARY for `transcript.refresh(...)`, `liveStatus` type, `OrchestratorChatView` name/init, token names.
5. **Closed-notch fetching:** skip blocks fetch while closed? (Phase 7 may need the finished-turn signal from the screen, not blocks.) Recommendation: only fetch when `notchOpen`.

## Environment Availability

| Dependency | Required By | Available | Notes |
|------------|------------|-----------|-------|
| serve on 127.0.0.1:4777 with `/api/chat/blocks` | manual shape check only | yes (live now) | tests use fixtures, never the server |
| Xcode / swiftc | build + harness | assumed per CLAUDE.md | build per S-02 with `/tmp/notch-dd-p5` |

## Security Domain

Local loopback client; no auth surface added. Applicable ASVS: V5 Input Validation only: treat block text as untrusted (render with `verbatim`/inline markdown, no link opening, no HTML), cap block count/length, never interpolate into shell (no process spawning). POSTs go only through the existing `OrchestratorPost` allowlist (`C-u`, `Tab`, `Enter` present after Phase 4). Threat: a malicious transcript string with `AttributedString` markdown links; disable link activation (don't make `Text` links clickable, or strip via plain rendering). [ASSUMED]

## Merge risks (Phases 6 and 7, per MERGE-MAP)

- `OrchestratorManager.swift`: prefer **zero** edits (store lives in `OrchestratorChat.swift`). If any, one `// Phase 5` block of stored properties only.
- Hook line in `refresh()` is shared with Phase 6 (prompt parse) and Phase 4: Phase 5 only fills the body of the Phase 5-owned object; do not touch the call site.
- Phase 7 embeds `OrchestratorChatView` by type name (expanded column): keep init defaulted, expose `proseLineLimit`/compact params, avoid hard-coded 190 px heights (use `maxHeight: .infinity`).
- Phase 6's prompt card replaces the composer area when a prompt shows: do not assume the composer is always visible; the chat view should still render transcript while `manager.prompt != nil` (today `bottomBar` swaps on `promptOptions`; Phase 4 moves that swap to the shell/PromptCard, check where).
- Key monitor + Phase 6 hover key handling (1–9, esc): both are NSEvent-level; Phase 5's monitor must only act while the composer is focused, and never swallow digits/esc.
- Tests: only `Tests/Phase5Tests.swift` + fixtures; add new fixture files under `Tests/fixtures/` with `phase5-` prefix to avoid name collisions; `Tests/main.swift` already calls the runner (Phase 4).
- No `project.pbxproj` edit: Phase 4 pre-registers the stubs; do not add new Swift files (put extra types in the owned files).

## Project Constraints (from CLAUDE.md)
Fork stays upstream-mergeable (new files, minimal hooks); music must not regress; no new third-party packages; HTTP API only, never spawn processes; build with `DEVELOPER_DIR=… xcodebuild`; never push, stay on current branch; GSD workflow for edits; Swift 5 mode, `ObservableObject` singletons, `@MainActor` managers; Defaults for settings.

## Sources
### Primary (HIGH)
- `/Users/mitch/Documents/Claude/orchestrator/orch.js` (`chatBlocks`, `chatBlocksLive`, `/api/chat*` routes) and live `GET /api/chat/blocks`, `GET /api/chat` (GET only)
- Repo: `boringNotch/Orchestrator/*.swift`, `Tests/main.swift`, `Tests/fixtures/inputbox.txt`, design README + screenshots 01, 02b, MERGE-MAP
### Secondary (MEDIUM)
- https://developer.apple.com/forums/thread/825509 (Tab intercepted by macOS; DTS suggests NSEvent local monitor)
- https://developer.apple.com/forums/thread/765733 (multiline TextField Tab behaviour)
### Tertiary (LOW)
- Training knowledge for TimelineView, onKeyPress availability, field editor APIs

## Metadata
**Confidence:** endpoint/contract HIGH; merge/decoder design HIGH; SwiftUI key interception MEDIUM (needs on-device check in verification, cannot be unit tested); shimmer/layout sizes MEDIUM.
**Research date:** 2026-10-14. **Valid until:** ~2026-10-28 (serve endpoint is brand new and may change; re-curl before executing).
