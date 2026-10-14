# Phase 8: Phase B Live Data - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator dispatch brief (user, 2026-10-14) + design handoff `.planning/design/orchestrator-2a/README.md` (Phase B notes, frames 01, 02b, 12, capsule)

<domain>
## Phase Boundary

The notch updates from a serve push stream instead of polling, shows a streaming caret on assistant prose, expands ▸ diff on Edit/Write/MultiEdit rows into the frame 12 diff card, uses serve's exact `suggested` flag for the input box ghost text, and shows "ctx N%" in the Running capsule.

**Serve work is NOT notch work.** The SSE endpoint, the `suggested` flag (`tmux capture-pane -e`) and context % are built in the orchestrator repo (`orch.js serve`) by a separate dispatch. This phase's docs carry the **serve API contract** below; notch plans consume it and must degrade cleanly when serve doesn't have it yet (old serve = today's polling + heuristics, no ctx, no caret).

Not in this phase: approvals drop-down, hook endpoint, global shortcuts, content-sized panel (Phase 9); per-run Allow/Deny (dropped — waiting run cards send context to the chat); multi-select questions, optimistic prompt UI and prompt-card polish (a parallel quick task on another branch owns those — do not touch `OrchestratorPromptCard.swift` / `OrchestratorPromptParse.swift` beyond what this phase strictly needs, and nothing there is needed).
</domain>

<decisions>
## Implementation Decisions

### Live stream (LIVE-01)
- D-01: The manager consumes `GET /api/events` (SSE, contract below) with `URLSession.bytes(for:)` + `.lines`, inside the existing `@MainActor` manager pattern (one Task, cancelled on stop). Each event replaces the matching slice of state through the **same apply path polling uses** (no second state model).
- D-02: Fallback: if `/api/events` returns 404, the connection fails, or no event/heartbeat arrives for 20s, drop back to today's polling loop (`pollInterval`) and retry the stream every 30s. Offline detection unchanged (fast 3s ephemeral session for GETs; the stream uses its own session with a long `timeoutIntervalForRequest`).
- D-03: Polling stays the only path while the notch app talks to an old serve — every current feature must keep working with no stream.
- D-04: Blocks: the stream's `blocks` event carries the same `{id, kind, text}` / tool `{name, target, result, added, removed, diff}` shape as `GET /api/chat/blocks`, merged with the existing transcript store's merge-by-id. No second decoder.

### Streaming caret (LIVE-02)
- D-05: Claude Code writes the transcript per finished content block, not per token, so "streaming" = the turn is live. The 7×13 `#D97757` caret (radius 1) sits at the end of the **last prose row** while serve reports `chat.live == true` (or, without a stream, while `liveStatus` shows working) and that prose row is the newest row. Blinks (opacity 1↔0.2, ~1s). No caret when idle.

### ▸ diff (LIVE-03)
- D-06: Serve **already** returns `diff: [{oldStart, newStart, lines}]` (≤4 hunks × 40 lines) on Edit/MultiEdit/Write tool blocks — no serve change. Notch decodes `diff` (optional) and "▸ diff" toggles the frame 12 Edit card inline: `#141416`, radius 9; header ▾ "Edit" file name +N/−N; lines mono 10pt line-height 1.5, padding 0 10; `-` lines `rgba(255,105,97,.12)` bg / `#FF9D97`; `+` lines `rgba(48,209,88,.12)` / `#7EE69A`; context `#636366`. Expansion state per block id, local to the view. Works in both the open chat and the expanded column; tapping ▸ diff must not trigger the transcript's open-terminal tap.

### Suggested flag (LIVE-04)
- D-07: When serve sends `input: {text, suggested}`, the composer ghost text uses it directly (suggested=true → ghost; false → terminal draft) and the Phase 5 heuristic is bypassed. Without it, keep the Phase 5 heuristic unchanged.
- D-08: User decision 2026-10-14 stands: Tab/→ accept and ⌃U are **local only** — no `Tab`/`C-u` POSTs; every send clears Claude's box first (`sendText(_:clearFirst:)`).

### Context % (LIVE-05)
- D-09: Running capsule shows divider (1×10 `#3A3A3C`) + "ctx N%" (`#8E8E93`) when serve sends `context.percent`; hidden when absent. Orange `#FF9F0A` at ≥80% is Claude's discretion (design doesn't specify; default: keep `#8E8E93`).

### Safety and constraints (all phases)
- S-01: NEVER POST to 127.0.0.1:4777 during build or verification. GETs are fine (including opening `/api/events` briefly to check it, if serve has it), but do not load `/term`.
- S-02: Don't launch apps. Build only: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-p8 build`.
- S-03: Upstream mergeable: new files under `boringNotch/Orchestrator/`, minimal hooks. No new dependencies. HTTP only; never spawn processes. Swift 5 mode, `ObservableObject` + `@Published`, `@MainActor` managers.
- S-04: Music must not regress.
- S-05: Never push; stay on the current branch; don't create or switch GSD phase/milestone branches.
- S-06: Pure logic (SSE line parser, event decode/apply, caret condition, diff line classification) gets assert checks in the swiftc harness under `boringNotch/Orchestrator/Tests/` (command in `.planning/design/orchestrator-2a/MERGE-MAP.md`).
- S-07: Follow the design handoff exactly for sizes, colours, copy.

### Claude's Discretion
- SSE line parser shape (pure function over lines), reconnect backoff details within D-02.
- Whether the stream also drives `/api/state` data or state stays polled at the slow interval (prefer: stream carries it, see contract).
</decisions>

<serve_contract>
## Serve API contract (orchestrator repo, `orch.js serve` — dispatched separately)

All additive; every existing endpoint keeps its shape. Host check and `x-orch` POST rule unchanged.

### `GET /api/events` — Server-Sent Events
- Headers: `content-type: text/event-stream`, `cache-control: no-cache`, `connection: keep-alive`. Same Host check as other routes.
- Optional `?since=<blockId>`: first `blocks` event is incremental from that id (same semantics as `/api/chat/blocks?since=`); otherwise the last 80.
- On connect serve sends, in order: `state`, `chat`, `blocks` (full snapshots). After that, each event is sent only when its JSON changed.
- Serve-side cadence: `chat` checked every ~500ms while the tmux session exists (capture-pane), `blocks` on transcript size change (fs.watch or 500ms stat), `state` every ~2s. Heartbeat comment line `: ping` every 15s.
- Events (`event:` name, one-line JSON `data:`):
  - `state` — exactly the `GET /api/state` body.
  - `chat` — `{ "running": bool, "screen": string, "live": bool, "input": { "text": string, "suggested": bool } | null, "context": { "tokens": int, "window": int, "percent": int } | null }`
    - `screen`: same as `GET /api/chat`.
    - `live`: Claude is mid-turn (screen shows the `✻ …(esc to interrupt)` status line).
    - `input`: the `❯` input-box line. `suggested` = the box text is Claude Code's dim suggestion, read from `tmux capture-pane -p -e` SGR attributes (dim `\e[2m` / grey foreground) on that line; `text` without ANSI. `null` when no input box is on screen (e.g. a prompt is showing).
    - `context`: from the latest assistant `message.usage` in the chat transcript: `tokens = input_tokens + cache_read_input_tokens + cache_creation_input_tokens`; `window` = 1,000,000 if the session runs a 1M-context model else 200,000 (serve decides; documented in code); `percent = round(100*tokens/window)`. `null` if unknown.
  - `blocks` — `{ "running": bool, "blocks": [...] }`, same shape as `GET /api/chat/blocks`, incremental after the first event (tool blocks whose result changed are re-sent, as `since` already does).
- Also add `input` and `context` (same shapes) to `GET /api/chat` so polling clients get them too.

### Notch behaviour against an old serve
- `/api/events` 404 → polling (D-02/D-03). `input`/`context`/`live` missing → Phase 5 heuristic, no ctx, caret from `liveStatus`.
</serve_contract>

<canonical_refs>
## Canonical References

- `.planning/design/orchestrator-2a/README.md` — frames 01 (caret, ▸ diff), 02b, 12 (Edit card), header capsule; Phase B notes
- `.planning/design/orchestrator-2a/MERGE-MAP.md` — file ownership, test harness command
- `.planning/design/orchestrator-2a/screenshots/01-chat-streaming.png`, `12-expanded.png`, `02b-message-box.png`
- `.planning/phases/05-*/05-CONTEXT.md`, `05-0*-SUMMARY.md` — transcript store, blocks decode, input-box heuristic
- `.planning/phases/07-*/07-CONTEXT.md` — pollInterval, expanded column
- `/Users/mitch/Documents/Claude/orchestrator/orch.js` (read-only) — `chatBlocks`, `/api/chat`, `/api/chat/blocks`, `cmdServe`
</canonical_refs>

<deferred>
## Deferred Ideas
- Per-run endpoints (1f) — dropped by user decision; waiting cards send context to the chat.
- Approvals/hook/global shortcuts/content-sized panel — Phase 9.
</deferred>

---
*Phase: 08-phase-b-live-data*
*Context gathered: 2026-10-14 from the dispatch brief*

<post_research_decisions>
## Post-research decisions (orchestrator, 2026-10-14) — override earlier items where they differ

- R-01 SSE parsing: `URLSession.bytes(for:).lines` drops blank lines, so dispatch on each `data:` line using the last `event:` name (contract guarantees one-line JSON). `: ping` lines count as liveness for the 20s watchdog. The stream has its own URLSession (request timeout ~45s, long resource timeout).
- R-02 One apply path: split the manager's apply into `applyChat` / `applyState`, the transcript store's refresh into `applyScreen` / `ingestBlocks` (reusing `decodeChatBlocks` + `mergeChatBlocks`); polling `load()` calls the same functions. Polling loop and the notch-open refresh are gated off while `streaming`.
- R-03 `input`: absent key (old serve) → Phase 5 heuristic; present `null` (new serve, no box) → no input line. Set `store.inputLine` / `store.boxIsDraft` from it; no composer view change.
- R-04 ctx % is orange `#FF9F0A` at ≥80% (resolves D-09 discretion).
- R-05 Contract corrections: (a) context window comes from Claude Code's statusline JSON — extend `usage-tap.js` to write `runs/context.json` (`session_id`, `context_window.context_window_size`, `used_percentage`); serve uses it when `session_id` matches the chat; fallback = transcript usage with window 1M if tokens > 200k else 200k. (b) first `blocks` event of a connection, and any transcript/session change, carries `"reset": true` (notch tolerates absence). (c) serve matches `/api/events` on `req.url.split('?')[0]`, uses one shared ticker fanned out to clients, `res.flushHeaders()`, `setNoDelay`, removes clients on `req` close; the `-e` capture is only taken when the plain screen shows an input box (`❯ ` + `\e[2m…\e[0m` = suggestion, verified live).
- R-06 New pure code lives in a new `OrchestratorStream.swift` (+ diff-line classifier); `Tests/Phase8Tests.swift` + `runPhase8Tests()` in `main.swift`; MERGE-MAP swiftc command extended.
</post_research_decisions>
