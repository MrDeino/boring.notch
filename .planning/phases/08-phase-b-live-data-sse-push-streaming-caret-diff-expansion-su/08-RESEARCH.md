# Phase 8: Phase B Live Data - Research

**Researched:** 2026-10-14
**Domain:** SwiftUI/URLSession SSE client in an existing polling manager; serve (`orch.js`) contract feasibility
**Confidence:** HIGH (repo + orch.js read in full, SSE line behaviour tested, dim-attribute and context data inspected live)

<user_constraints>
## User Constraints (from CONTEXT.md)

Locked: D-01..D-09 and S-01..S-07 in `08-CONTEXT.md` (SSE via `URLSession.bytes(for:).lines` in the `@MainActor` manager, one Task; fallback to polling on 404/failure/20s silence with 30s retry; same apply path, no second state model; blocks merged by id with the existing decoder; caret 7x13 `#D97757` on newest prose row while live; ▸ diff toggles the frame 12 card inline, state per block id, must not trigger the open-terminal tap; `input.{text,suggested}` bypasses the Phase 5 heuristic, Tab/→/⌃U stay local-only; ctx N% in the Running capsule; S-01 no POSTs to 4777, no apps launched; upstream-mergeable new files; pure logic asserted in the swiftc harness).
Discretion: SSE parser shape, reconnect backoff, whether the stream also carries state (prefer yes).
Deferred/out of scope: per-run Allow/Deny, approvals, hooks, global shortcuts, content-sized panel. Do not touch `OrchestratorPromptCard.swift` / `OrchestratorPromptParse.swift` (parallel quick task).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| LIVE-01 | SSE for blocks + state, polling fallback | SSE client section, apply-path split |
| LIVE-02 | Streaming caret | Caret condition + placement |
| LIVE-03 | ▸ diff expands Edit row | Diff hook-in (decode already exists) |
| LIVE-04 | Ghost text uses `suggested` | Composer hook; dim detection verified live |
| LIVE-05 | Capsule ctx % | Capsule hook; serve context fix |
</phase_requirements>

## Summary

The notch side is small because most of it already exists: `ChatBlock` already decodes `diff` (`ChatDiffHunk`, in `OrchestratorTranscript.swift`), `mergeChatBlocks` merges by id, `apply(_,_)` is a clean replace-slice path, and the "▸ diff" text is already rendered (inert) in `ChatBlockRow.toolRow`. The real work is (1) a pure SSE event parser + a stream Task in the manager, (2) splitting `apply(chat, state)` and `OrchestratorTranscriptStore.refresh` so a stream event can feed the same code, (3) four small view hooks.

**Critical gotcha (tested):** `URLSession.AsyncBytes.lines` **drops empty lines**. The SSE blank-line dispatch delimiter never reaches you. I ran a swiftc script against a local server: input `event: a / data: {..} / blank / : ping / blank / event: b / data: 2 / blank` yields only `event: a`, `data: …`, `: ping`, `event: b`, `data: 2`. The parser must therefore dispatch on each `data:` line using the most recent `event:` name (valid because the contract guarantees one-line JSON data), then clear the name. [VERIFIED: local swiftc test, 2026-10-14]

Serve contract is implementable with three corrections (below). The most important: do **not** detect the 1M window from the transcript model string, it does not contain it.

**Primary recommendation:** Add `OrchestratorStream.swift` (pure parser + decode + apply-ready structs, in the swiftc harness) and drive the existing manager through new `applyChat/applyState/ingestBlocks` entry points; keep `load()` polling untouched as the fallback; hook caret, diff, ghost text and ctx as 4 isolated view edits.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary | Rationale |
|------------|-------------|-----------|-----------|
| SSE endpoint, change detection, suggested flag, context % | serve (orch.js) | — | Only serve can run tmux / read transcript; sandbox forbids it in notch |
| Stream consumption, reconnect, fallback | Notch manager | — | Single owner of connectivity state |
| Event decode / merge / caret condition / diff line class | Pure Swift (harness-tested) | — | S-06 |
| Caret, diff card, ghost text, ctx label | SwiftUI views | — | Presentation only |

## Standard Stack

No new packages. URLSession `bytes(for:)` (macOS 12+), Codable, `Regex`-free line parsing, `Task`. Nothing to install; Package Legitimacy Audit not applicable (no external packages).

## Architecture Patterns

### Flow
```
orch.js /api/events ──SSE lines──> stream Task (manager, @MainActor)
   pure parser: (eventName?, line) -> StreamEvent?
      state  ─> StateResponse ─> applyState()   (runs, usage)
      chat   ─> ChatResponse(+live,input,context) ─> applyChat()  (running, screen, prompt, liveStatus, ctx, input)
      blocks ─> decodeChatBlocks ─> store.ingestBlocks()  (mergeChatBlocks)
stream down / 404 / 20s silent ─> polling loop (existing load()) ; retry stream every 30s
```

### Pattern 1: SSE client
- Dedicated `URLSession(configuration: .ephemeral)`: `timeoutIntervalForRequest = 45` (idle gap; heartbeat is 15s), `timeoutIntervalForResource = .greatestFiniteMagnitude` (default resource timeout is 7 days; ephemeral is fine but set explicitly), `waitsForConnectivity = false`. The existing 3s/5s `session` must NOT be used (resource timeout 5s kills the stream).
- Request: `GET /api/events` (+ `?since=` last block id on reconnect), `Accept: text/event-stream`. Check `(resp as? HTTPURLResponse)?.statusCode == 200` before reading; 404 = old serve.
- Loop: `for try await line in bytes.lines`. Cancellation: `Task.cancel()` ends the `for await` and cancels the connection. Keep `streamTask` as a property; cancel in a `stopStream()`.
- 20s watchdog: record `lastEventAt = Date()` on every line (including `: ping` comments, they arrive as lines). A sibling Task (or a `withTaskGroup` race) checks every 5s; if `now - lastEventAt > 20` cancel the stream task and mark fallback. Do not rely on URLSession timeout (45s) for this.
- Sandbox: `network.client` already present; loopback http with ATS arbitrary loads already works for polling. No change. [VERIFIED: repo CLAUDE.md stack table]
- Mode switch: `@Published private(set) var streaming = false`. The polling loop in `start()` becomes: `if streaming { sleep 2s; continue }` (keep looping so it resumes instantly on stream loss), else `refresh()` as today. `notchOpen` didSet `refresh()` should remain (cheap cross-check) but skip when `streaming`.
- Offline: connection refused / timeout on the stream also means serve is down: call `applyOffline()` once, then rely on the polling loop (10s offline interval) plus the 30s stream retry. `hasLoaded` set after first event.
- Backoff: fixed 30s retry per D-02 is enough (ponytail: no exponential). A 404 can be retried at the same 30s.

### Pattern 2: One apply path
Current `apply(_ r: ChatResponse, _ st: StateResponse)` handles both. Split into `applyChat(_ r: ChatResponse)` and `applyState(_ st: StateResponse)`; `load()` calls both (unchanged behaviour), stream events call one each. `ChatResponse` (in `OrchestratorModels.swift`) gains optional `live: Bool?`, `input: ChatInput?` (`text: String?`, `suggested: Bool?`), `context: ChatContext?` (`tokens/window/percent: Int?`). Missing = nil = old-serve behaviour. The `chat` SSE `data:` is decoded with the same `ChatResponse` type, so GET `/api/chat` and the event share one decoder (contract says serve adds `input`/`context` to `GET /api/chat` too).

`OrchestratorTranscriptStore.refresh` mixes three jobs: input-line/draft heuristic, idle status, and block fetch. Split into `applyScreen(screen:chatRunning:input:)` (first two) and `ingestBlocks(running:blocks:reset:)` (merge + animation + `fallback=false`), with `refresh` calling both. Stream `blocks` events call `ingestBlocks` directly; reconnect passes `?since=store.blocks.last?.id`, and a first event that fails `blocksDiscontinuous` falls back to the existing full `fetchBlocks` (see contract fix 1 for a simpler way).

The store's `guard notchOpen` and `polls % 15` full-resync exist because of polling cost; with a healthy stream drop both (ingest regardless of open state; the cap is 200).

### Pattern 3: Suggested flag (LIVE-04)
Heuristic lives in `OrchestratorTranscriptStore.refresh` (`globalBoxIsDraft(previous:current:wasDraft:editing:)` -> `@Published boxIsDraft`, `inputLine`). In `applyScreen`: if `input` is non-nil, set `inputLine = input.text` (empty -> nil), `boxIsDraft = !(input.suggested ?? true)`, skip `boxIsDraft(...)`. If `input == nil` and the response had the key (new serve, no box): `inputLine = nil`. If the key is absent (old serve) run the heuristic unchanged. Distinguish "absent" from "null" via an explicit `hasInputKey` (decode with `container.contains(.input)`), else a new serve's `null` (prompt showing) would fall to the heuristic and use `parseInputLine` (which also returns nil with a prompt, so low-risk, but be explicit).
All composer reads (`suggestion`, `ghostLayer`, `focusChanged`, `submit`) already read `store.boxIsDraft` / `store.inputLine`, so **no view change is needed**. Keep `clearRealLine` (D-08).

### Pattern 4: Streaming caret (LIVE-02)
Condition (pure fn, tested): `caretVisible(live: Bool?, liveStatusWorking: Bool, block: ChatBlock, newest: ChatBlock?) = (live ?? liveStatusWorking) && block.kind == .prose && block.id == newest?.id`. "Newest row" = `store.blocks.last` (the stream never has a newer row once a tool block follows, so the caret disappears naturally when a tool row appears). Manager exposes `isLive` = `chatLive ?? (liveStatus != nil)` (store `chatLive` from `applyChat`).
Placement: `ChatBlockRow.content .prose` case, `ChatBlockRow` gets a `caret: Bool` param from `ForEach` (`caret: caretVisible(...)`). Two options; recommend (a): (a) append `Text(" ")`+glyph is not 7x13 exact, so use an `HStack(alignment: .lastTextBaseline, spacing: 2) { Text(prose); caretRect }` where caretRect is `RoundedRectangle(cornerRadius: 1).fill(OT.C.claude).frame(width: 7, height: 13)` with `.opacity` driven by `TimelineView(.periodic(from:.now, by: 0.5))` toggling 1 / 0.2 (respect `accessibilityReduceMotion`: static 1). Caveat: with a multi-line wrapped paragraph the caret sits right of the block, not at the last word; (b) inline `Text(image)` concatenation is exact but needs an image render; not worth it. Note the open chat uses `proseLineLimit: 4` (truncated rows hide the real end) - accepted (design shows caret at end of visible prose).
Also add `manager.isLive` to `pinKey` so the view stays pinned; no other change.

### Pattern 5: ▸ diff (LIVE-03)
Hook: `toolRow` already shows `+N −N ▸ diff` whenever `block.added != nil`. Changes, all inside `ChatBlockRow` (OrchestratorChat.swift is Phase-5 owned but phase 5 is merged; put the new diff card view and a pure `classifyDiffLine` in a new `OrchestratorDiff.swift`):
1. `@State private var diffOpen = false` in `ChatBlockRow` (per-row view state; row identity is the block id via `ForEach(store.blocks)`, so state follows the id. The 200-block cap eviction just discards it). Only offer the toggle when `block.diff?.isEmpty == false`; otherwise render the `+N −N` without the "▸ diff".
2. Replace the inert `Text("▸ diff")` with `Button { withAnimation { diffOpen.toggle() } } label: { Text(diffOpen ? "▾ diff" : "▸ diff") }.buttonStyle(.plain)`.
3. Return a `VStack(alignment: .leading)` from `toolRow`: the HStack, then `if diffOpen { OrchestratorDiffCard(...) }`.
Tap isolation: the transcript scroll area has `.contentShape(Rectangle()).onTapGesture { expandChat() }` on the container (Chat.swift ~163). A SwiftUI `Button` child consumes its click before the ancestor tap gesture, so the toggle does not fire `transcriptTapped`. The diff card body itself (non-button) would still bubble a click to the terminal-open tap; add `.onTapGesture {}` (swallow) on the card or make the whole header a button. Verify at runtime in the build smoke (no app launch allowed: add to the manual UAT list). Same view in the expanded column (`OrchestratorChatView(proseLineLimit: nil, maxRows: 60)`) so both surfaces get it for free.
Line classification (pure, tested): first char `+` -> added, `-` -> removed, else context (`" "` prefix or empty). Strip the first char for display. Hunk header: show nothing (design has none) but separate hunks with a thin `OT.C.divider2` 1pt gap. Styling per D-06; tokens: add `OT.C` entries for the `rgba(255,105,97,.12)` / `rgba(48,209,88,.12)` backgrounds and `#FF9D97` / `#7EE69A` text (append only, per Tokens file rule); card bg is existing `OT.C.diffCard`; radius `OT.R.cardS` (9); font `.system(size: 10, design: .monospaced)` with `.lineSpacing(~5)` for 1.5; header "▾ Edit  file  +N −N". Lines `lineLimit(1)`/truncate or horizontal scroll: use `lineLimit(1).truncationMode(.tail)` (ponytail: no h-scroll).
Note Write diffs come from serve as all-`+` lines (`oldStart:0`), so "Write" renders as an all-green card; fine.

### Pattern 6: Capsule ctx % (LIVE-05)
`OrchestratorStatusCapsule.body`, `HStack(spacing: 7)` in the label: after the `Text(label)` (and before/after the ring, per frame: divider then ctx): add
`if s == .running, let p = manager.contextPercent { Rectangle().fill(OT.C.selected2).frame(width: 1, height: 10); Text("ctx \(p)%").foregroundColor(p >= 80 ? OT.C.orange : OT.C.text5) }`.
`#3A3A3C` is `OT.C.selected2`. Spec says Running capsule; `.running` only (design shows it there). Orange at >= 80: Claude's discretion; recommend yes, reuse `usageIsHigh(Double(p))`; it costs one ternary and the codebase already does this for usage. `manager.contextPercent: Int?` set in `applyChat` from `r.context?.percent`, cleared when not running / offline. Capsule width grows ~45pt; check the header still fits the closed-notch wings (`OrchestratorWings.swift` line 50 only reads `working`; wings don't show ctx, none needed).

## Don't Hand-Roll

| Problem | Use Instead |
|---------|-------------|
| SSE framing across chunks | `bytes.lines` (already line-split; ignore its blank-line drop, see above) |
| Block merge / dedupe | existing `mergeChatBlocks`, `decodeChatBlocks`, `blocksDiscontinuous` |
| Dim detection in notch | serve provides `suggested`; notch never parses ANSI |
| Timers | `Task.sleep`, no `Timer` (project rule) |

## Common Pitfalls

1. **Blank lines dropped by `.lines`** (tested). Dispatch on `data:` with remembered `event:`; ignore `:` comments but count them as liveness; data lines without prior event name default to `message` (ignore).
2. **Wrong URLSession.** Reusing the 3s/5s session kills the stream. Use a separate long-lived session.
3. **Double state:** running both polling and stream writes duplicate state and double-animates blocks. Gate polling on `streaming`; `refresh()` from `notchOpen` didSet must also check it.
4. **`since` ambiguity on reconnect.** Use contract fix 1.
5. **Null vs absent `input`** (above).
6. **Caret + `lineLimit(4)`** hides end of long prose; only cosmetic.
7. **`Button` in a row inside `ScrollView`** with a parent tap gesture: the diff card body must swallow taps (above).
8. **Hidden coupling:** `OrchestratorModels.swift` and `OrchestratorTranscript.swift` are compiled by the harness, so new pure code goes in a new `OrchestratorStream.swift` and is **added to the swiftc command** in MERGE-MAP (it currently lists Models, Pure, Transcript, PromptParse, RunsPure). Phase 8 tests go in `Tests/Phase8Tests.swift` + `runPhase8Tests()` call in `main.swift`. Avoid editing PromptParse/PromptCard.

## Contract check against `orch.js` (read-only analysis)

Verified facts about `orch.js`: plain `http.createServer`, all tmux calls are blocking `execFileSync`; `GET /api/chat` uses `capture-pane -p -J -S -200`; `chatBlocksLive` re-parses up to 4 MB on size change (cached by size); `state()` calls `liveSessions()` (reads `~/.claude/sessions`, `alive()`, transcripts) and `listRuns()` + `gsdActivity` per run.

**Implementable, with these fixes:**

1. **Add `reset: true` to the first `blocks` event of a connection** (and whenever the transcript file/session changes, i.e. `chatTranscript()` returns a different file or size shrinks). Today the notch must infer "full vs incremental" via `blocksDiscontinuous` + extra GET. With `reset`, the notch replaces (`mergeChatBlocks(reset: true)`) and never needs the extra fetch. Cheap to add serve-side. Notch must tolerate `reset` absent.
2. **Context: do not infer the window from the transcript.** Evidence: the live orchestrator transcript's assistant `message.model` is `claude-opus-5-5` for 812 of 813 entries (one `claude-opus-5-5[1m]`), `usage` for the last turn was 311k tokens, and the terminal footer says "Opus 5.5 (1M context)". The 1M marker is not reliably in `message.model`. Instead use Claude Code's statusline JSON, which already flows through `usage-tap.js` (settings `statusLine.command` = `usage-tap.js` wrapper): it receives `context_window.context_window_size` (200000 default, 1000000 for extended context), `context_window.used_percentage`, `context_window.current_usage`, `session_id` [CITED: code.claude.com/docs/en/statusline]. Fix: extend `usage-tap.js` to also write `runs/context.json` = `{at, session_id, size, percent, tokens}` (keep the existing `usage.json` shape unchanged; the tap currently only writes when `rate_limits` exists, so write context independently). Serve's `chat.context` = that file if `session_id` equals the chat transcript's session id (basename of `chatTranscript()` minus `.jsonl`; dispatched interactive sessions share the same tap file otherwise) and `at` is recent; **fallback** when absent: tokens from the last assistant `message.usage` (same sum as in the contract) with `window = tokens > 200000 ? 1000000 : 200000` (a session over 200k must be 1M; under 200k the percent may be 5x overstated for a 1M session; documented limitation) or env/setting hint if desired. Note `used_percentage` from Claude Code is authoritative; prefer it over recomputing. `context` after `/compact` is null until next API call: serve sends `null` (notch hides the label).
3. **Cost of per-connection timers.** Each connection running `state()` every 2s (`liveSessions` spawns nothing but reads files; `listRuns` etc.) and `capture-pane` via `execFileSync` every 500ms blocks the Node event loop for each client. Use **one shared ticker** that computes `state`/`chat`/`blocks` once and fans out to all open connections (skip the work entirely when zero clients), diff against last-sent JSON per event name. Required SSE mechanics: `res.writeHead(200, {...})` then `res.flushHeaders()`, `req.socket.setNoDelay(true)`, `req.on('close')` removes the client, write `retry: 3000\n\n` once, `: ping\n\n` every 15s. The `/api/events` route must be matched with `req.url.split('?')[0]` (existing routes compare the whole `req.url`, so `?since=` would 404) and sit before the final `send(404)`. Note the Host check already applies (top of handler).

Confirmed implementable as written: **`capture-pane -p -e` dim detection.** I read the live `orchestrator` tmux pane with `tmux capture-pane -p -e -J -t orchestrator` (read-only): the input line renders as `❯ ` then `\e[2m<text>\e[0m` for a Claude Code suggestion ("make it my real app after this lands"), while the surrounding text uses `\e[38;5;246m` greys. So `suggested` = on the `❯` line, the text segment after the prompt is wrapped in `\e[2m` (SGR 2). Rules for serve: take the input-box line using the same box rule as the notch (rule, `❯` line, rule), strip ANSI (`/\x1b\[[0-9;:]*m/g`) for `text`, set `suggested` when an SGR `2` (not `22`) is active at the first non-space character after `❯`. Use `-J` consistently with the existing `/api/chat` so wrapped lines match. Caveat: a real typed draft is not dim, but the cursor cell may add `\e[7m`; ignore it. Use `execFileSync('tmux', ['capture-pane','-p','-e','-J',...])` as a second call only when the plain screen shows an input box (avoids doubling the cost every tick). The multi-line input box (long drafts) should join lines as `parseInputLine` does.

Minor: `live` = the same `esc to interrupt` working-line condition as `parseLiveStatus`; serve can use `/\(.*esc to interrupt.*\)/` over the last 30 lines. Note that with a custom statusLine Claude Code stops showing `esc to interrupt` in the footer, but the spinner line still contains it (existing live detection already relies on it, A1 in Phase 4 research).

## Runtime / environment

| Check | Result |
|-------|--------|
| `GET http://127.0.0.1:4777/api/events` | HTTP 404 today (old serve): fallback path is the live case until serve is dispatched |
| Xcode, swiftc harness | Present (used in this research) |
| New dependencies | None |

## Validation Architecture

Framework: swiftc harness (`precondition`), command in MERGE-MAP with `OrchestratorStream.swift` (and `OrchestratorDiff.swift` if its pure fn lives there) appended. Test file `Tests/Phase8Tests.swift`; add `runPhase8Tests()` to `main.swift`.

| Req | Behaviour | Automated |
|-----|-----------|-----------|
| LIVE-01 | Parser: lines `event:`/`data:`/`: ping` (no blank lines) -> events; unknown event ignored; bad JSON dropped; `blocks` event reuses `decodeChatBlocks`; `reset` flag | harness |
| LIVE-01 | Watchdog/fallback decision as a pure fn `streamHealthy(lastEventAt:now:)` (20s) | harness |
| LIVE-02 | `caretVisible` truth table (live nil/true/false, kind, newest) | harness |
| LIVE-03 | `classifyDiffLine`, decode of `diff` from `phase5-blocks.json` (already has diff? check, else add fixture) | harness |
| LIVE-04 | `resolveInput(response, previous...)`: present/null/absent x suggested | harness |
| LIVE-05 | `ChatResponse` decode with/without `context`; `percent` null -> hidden | harness |
| UI | caret blink, ▸ diff click does not open terminal, capsule width, stream fallback | manual UAT (no app launch allowed during build; user verifies). Build: S-02 xcodebuild command |

Wave 0: create `Phase8Tests.swift`, update MERGE-MAP harness command.

## Security Domain

Loopback only, no new entitlements. Treat SSE payloads as untrusted like the existing blocks (diff lines rendered with `Text(verbatim:)`, never markdown; prose already goes through `proseAttributed`). Cap event size (drop a line > 2 MB; `screen` is bounded by 200 lines). No POSTs added. Host/Origin rules unchanged server-side. ASVS: V5 input validation (lossy decode, size cap) applies; auth/session/crypto n/a.

## Assumptions Log

| # | Claim | Risk if Wrong |
|---|-------|---------------|
| A1 | A view `Button` inside the row consumes the click before the container's `onTapGesture` (standard SwiftUI; not run here, cannot launch app) | Diff toggle opens terminal; fix by `.highPriorityGesture`/swallow tap |
| A2 | `usage-tap.js` statusline input carries `session_id` and `context_window.*` in this Claude Code version (docs cite them; not observed in a live payload here) | Serve falls back to transcript heuristic |
| A3 | `proseLineLimit: 4` truncation is acceptable for caret placement | cosmetic |

## Open Questions (RESOLVED)

1. Should serve (separate dispatch) adopt fixes 1-3? RESOLVED: yes, see 08-CONTEXT R-05; the notch tolerates both.
2. Orange ctx at >= 80: RESOLVED: yes, see 08-CONTEXT R-04.

## Sources

- Repo: OrchestratorManager/Chat/Transcript/Models/Pure/StatusCapsule/Expanded, Tests, MERGE-MAP (HIGH)
- `/Users/mitch/Documents/Claude/orchestrator/orch.js` serve, chatBlocks, usage-tap.js (HIGH)
- https://code.claude.com/docs/en/statusline (context_window fields) (HIGH)
- Local experiments 2026-10-14: swiftc `bytes.lines` blank-line test; read-only `tmux capture-pane -e` of live orchestrator pane; transcript model/usage sampling (HIGH)

## Metadata
**Research date:** 2026-10-14 · **Valid until:** ~2026-11-13
