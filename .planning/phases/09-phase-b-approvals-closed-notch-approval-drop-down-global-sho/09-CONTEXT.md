# Phase 9: Phase B Approvals - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator dispatch brief (user, 2026-10-14) + design handoff `.planning/design/orchestrator-2a/README.md` (frame 00 approval drop-down, Phase B 1e)

<domain>
## Phase Boundary

The orchestrator chat's pending tool approvals reach the notch from a Claude Code hook (via serve), not screen parsing. With the notch closed, a pending approval drops down the 460px approval panel (Allow ⌥⏎ / Deny ⌥⎋ / More…). ⌥⏎ / ⌥⎋ answer it globally. The panel frame follows its content instead of the fixed `windowSize` plus a separate expand step.

**Serve and hook work is NOT notch work.** The hook script, its registration in the orchestrator's Claude Code settings, and serve's hook endpoint + `approval` event are built in the orchestrator repo by a separate dispatch. This phase's docs carry the contract below.

Depends on Phase 8 (the SSE stream carries `approval`). Approvals concern **only the orchestrator chat** (tmux session `orchestrator`), never dispatched runs — waiting run cards keep sending context into the chat (user decision; no per-run Allow/Deny endpoints).

Not in this phase: multi-select questions, optimistic prompt UI, prompt-card polish (parallel quick task on another branch); frame 03 card itself (Phase 6 — "More…" only opens the notch onto it).
</domain>

<decisions>
## Implementation Decisions

### Approval source (APR-01)
- D-01: The notch learns of an approval from the stream's `approval` event (and `approval` in `GET /api/chat` when polling). It never infers approvals from screen text. The existing Phase 6 screen-parsed prompt card stays as is for the open notch.
- D-02: Answering uses the **existing** `POST /api/chat {key}`: Allow = the first option's digit (`"1"`), Deny = `"Escape"`. No new answer endpoint. Before answering, the notch re-checks freshness (`refresh(fresh:)` pattern) and only sends if the approval id is still the current one and the screen still shows a prompt (no stale keypress into the input box).

### Drop-down (APR-02)
- D-03: Frame 00 approval drop-down, notch closed: panel 460px wide, bottom radius 22, padding 30/16/14, gap 10. Title row: 7px orange dot, "Orchestrator wants to run" 13pt semibold, tool name right 11pt `#636366`. Command block mono 12pt `#E5E5EA` on `#1C1C1E`, radius 8, padding 7/10. Buttons 30px pills: **Allow ⌥⏎** white bg black text flex 1; **Deny ⌥⎋** `#1C1C1E` bg `#FF6961` text flex 1; **More…** opens the notch onto the frame 03 card.
- D-04: Music wins on the closed notch as in Phase 7 except here: a pending approval **does** drop down over music (an approval is never hidden — consistent with the 2026-10-14 "a waiting question is never hidden" decision). Music state, controls and live activity resume unchanged after the panel closes. (Flagged for user confirmation.)
- D-05: Panel closes when the approval resolves (event clears, or answered from terminal/notch), or on Deny/Allow. Outside click does not dismiss it (it's the only signal); it collapses back to the closed notch if the user opens the notch normally.

### Global shortcuts (APR-03)
- D-06: Use the **already-installed** `KeyboardShortcuts` package (sindresorhus; Carbon `RegisterEventHotKey` underneath — no Accessibility/Input Monitoring permission, works sandboxed). Register the two hotkeys only while an approval is pending, unregister when it clears, so ⌥⏎/⌥⎋ stay free for other apps otherwise. Names declared in a new Orchestrator file's `extension KeyboardShortcuts.Name`, with defaults; no Settings UI unless research says it's needed.
- D-07: Research must confirm whether macOS 15+ still rejects Option-only (and Option+Shift) hotkeys via `RegisterEventHotKey`. If so, pick a fallback combo and record it as a decision for the user (default proposal: ⌃⌥⏎ / ⌃⌥⎋, labels updated to match), and never add Accessibility permission.

### Content-sized panel (APR-04)
- D-08: The notch panel frame follows its content (open, expanded, terminal, drop-down) instead of fixed `windowSize` + `expandedExtra`. Keep the top edge pinned (adjust origin.y by the delta, as `cdaa3ed` does), one continuous spring, and the existing outside-click/monitor/key-release logic. Minimum hook into `boringNotchApp.swift` / `ContentView.swift`; music sizing unchanged.

### Safety and constraints (all phases)
- S-01: NEVER POST to 127.0.0.1:4777 during build or verification. GETs fine; never load `/term`.
- S-02: Don't launch apps. Build only: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-p9 build`.
- S-03: Upstream mergeable, no new dependencies, HTTP only, never spawn processes, Swift 5 mode, `ObservableObject`, `@MainActor`.
- S-04: Music must not regress.
- S-05: Never push; stay on the current branch; don't create or switch GSD phase/milestone branches.
- S-06: Pure logic (approval decode, answer-gate, frame-size computation) gets assert checks in the swiftc harness.
- S-07: Follow the design handoff exactly for sizes, colours, copy.

### Claude's Discretion
- How the drop-down is hosted (state on the closed-notch path vs. a new notch state), within D-08's minimum-hook rule.
</decisions>

<serve_contract>
## Serve + hook API contract (orchestrator repo — dispatched separately)

### Hook (orchestrator repo `.claude/settings.json`, project-level, so only the orchestrator chat loads it)
- Events: `PermissionRequest` if the installed Claude Code supports it (fires exactly when a permission dialog shows), else `Notification` with matcher `permission_prompt` **plus** `PreToolUse` for the tool details. `PostToolUse` and `Stop` to clear.
- Command: a small node script in the orchestrator repo that reads the hook JSON on stdin and POSTs it unchanged to `http://127.0.0.1:4777/api/hook` with `x-orch: 1`, 1s timeout, always exits 0 with no output (never blocks or alters Claude's decision).

### `POST /api/hook` (header `x-orch: 1`, body = Claude Code hook JSON)
- Serve accepts only payloads whose `session_id` matches the tmux `orchestrator` chat's session (from `chatTranscript()`); others → 204 ignored.
- `PermissionRequest` / permission `Notification` (+ last `PreToolUse` for that session) → sets the pending approval. `PostToolUse` for that `tool_use_id`, `Stop`, or the chat stopping → clears it. Serve also clears it if the screen no longer shows a prompt for >2s.
- Responds 204.

### `approval` (SSE event on `/api/events`, and field `approval` on `GET /api/chat`)
- `{ "id": string, "tool": string, "command": string, "description": string|null, "at": iso8601 }` or `null`.
  - `id`: `tool_use_id` (or a hash of session+tool+input if unavailable).
  - `command`: one line — Bash `command`, else `file_path`/`pattern`/`url`, else compact JSON of the input, ≤300 chars.
- Sent on change only.

### Answering
- No new endpoint: `POST /api/chat {key:"1"}` (Allow) / `{key:"Escape"}` (Deny), already allowed.
</serve_contract>

<canonical_refs>
## Canonical References

- `.planning/design/orchestrator-2a/README.md` — frame 00 approval drop-down, Phase B (1e)
- `.planning/design/orchestrator-2a/screenshots/00-closed.png`, `03-permission.png`
- `.planning/phases/08-*/08-CONTEXT.md` — SSE stream contract
- `.planning/phases/07-*/07-CONTEXT.md` — wings, music-wins rule, expand levels
- `boringNotch/boringNotchApp.swift`, `boringNotch/ContentView.swift`, `boringNotch/sizing/matters.swift` — panel frame, `windowSize`
- `boringNotch/Shortcuts/ShortcutConstants.swift` — existing `KeyboardShortcuts.Name` pattern
- `/Users/mitch/Documents/Claude/orchestrator/orch.js` (read-only) — serve
</canonical_refs>

<deferred>
## Deferred Ideas
- Per-run Allow/Deny — dropped (user decision).
- Settings UI for rebinding the approval shortcuts.
</deferred>

---
*Phase: 09-phase-b-approvals*
*Context gathered: 2026-10-14 from the dispatch brief*

<post_research_decisions>
## Post-research decisions (orchestrator, 2026-10-14) — override earlier items where they differ

- R-01 Hotkeys: keep ⌥⏎ / ⌥⎋ via `KeyboardShortcuts` (Carbon `RegisterEventHotKey`; no Accessibility/Input Monitoring permission; sandbox-safe). Its Option-only rejection applies only to sandboxed apps on macOS 15.0–15.1; a small pure function picks ⌃⌥⏎ / ⌃⌥⎋ (labels to match) on those versions. Register `onKeyDown` once; `KeyboardShortcuts.enable`/`disable` both names as an approval appears/clears. A failed registration only logs; buttons still work. Verify on first sandboxed run (UAT item).
- R-02 Hook: Claude Code 2.1.299 supports `PermissionRequest` — use it alone (no Notification/PreToolUse). Hook entry `"async": true`; script prints nothing and exits 0 (any decision output would answer for the user).
- R-03 Contract corrections: approval `id` = hash of `session_id` + `tool_name` + canonical JSON of `tool_input` (PermissionRequest has no `tool_use_id`). Clear on any `PostToolUse` / `PostToolUseFailure` / `Stop` for the chat session, on chat stop, and when the screen shows no prompt for >2s (no hook fires on a user denial). The notch clears locally after its own answer and ignores that id for ~3s.
- R-04 Notch decodes `approval` as optional on `GET /api/chat` and on the Phase 8 stream; works by polling today (serve has neither yet).
- R-05 Answer gate: Allow sends `"1"` only if the screen-parsed prompt's option 1 is a plain "Yes"; otherwise Allow opens the notch onto the frame 03 card ("More…" behaviour).
- R-06 Hosting: one closed-state branch at the top of ContentView's `NotchLayout` chain, before `MusicLiveActivity` (no new `NotchState`); bottom radius 22 via `currentNotchShape`; `approval == nil` added to the `handleHover` guard; "More…" sets `currentView = .orchestrator` and opens. Wings/closed indicators hidden while it shows. The 460×~150 drop-down fits the existing 640×210 window — no resize for it.
- R-07 APR-04: pure `panelHeight(notchHeight:) = max(windowSize.height, notchHeight + shadowPadding)` (equals today's height for every current case → music unchanged) and one `OrchestratorExpand.fit(vm:window:)` (grow now, shrink after 650ms, top edge pinned) driven by a single `.onChange(of: vm.notchSize.height)`; replaces the `extra` dictionary and separate grow/collapse calls. No `sizingOptions` auto-resize, no second window.
</post_research_decisions>
