# Phase 5: 2a Structured Chat - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator dispatch brief (user decisions 2026-10-14) + design handoff

<domain>
## Phase Boundary

Replace the raw terminal tail with typed transcript rows (frame 01), a live working status row, the composer (02) and the message box behaviours (02b), with row-insert motion. Runs **in parallel with Phases 6 and 7** on a separate branch after Phase 4 — stay inside the files MERGE-MAP.md assigns to Phase 5.

Not in this phase: prompt cards (6), runs board/expand levels/expanded view/wings (7), streaming caret, ▸ diff expansion, suggested flag from capture-pane -e, context % (8).
</domain>

<decisions>
## Implementation Decisions

### Transcript source (CHAT-01) — user decision 2026-10-14
- D-01: Rows come from serve's **new** `GET /api/chat/blocks?since=<id>` built from Claude Code's transcript — **not** from screen parsing. Shape to design against: an array of blocks `{id, kind: "user"|"tool"|"prose", text}`; tool blocks carry `{name, target, result, added, removed, diff}` (added/removed ints, diff optional). The endpoint is being built in parallel in the orchestrator repo; it is not live yet. Decode every field optionally; unknown kinds are skipped.
- D-02: Incremental fetch: keep the last block `id`, request `?since=<id>`, append; on first load or after chat restart request without `since` (or since empty) and replace. If the response wrapper turns out to be `{blocks:[…]}` rather than a bare array, accept both. Cap kept blocks (e.g. last 200).
- D-03: Fallback: if the endpoint returns 404 / fails to decode, show the existing `chatTail` lines restyled (prose font) so the tab keeps working before serve ships the endpoint. Treat a failed blocks fetch as non-fatal (do NOT flip the tab offline).
- D-04: Blocks fetch is a GET; it runs from the Phase 4 refresh hook (MERGE-MAP). Test decoding/merge with fixture JSON in the swiftc harness — never hit the live server in tests.

### Rows and status (CHAT-02, CHAT-05)
- D-05: Row styles exactly per README 01: user ❯ (12pt `#8E8E93`, one line); tool chip (mono 10pt medium `#C4C4C6` on `#1C1C1E`, radius 5, padding 2/6) + target (mono 11pt `#D1D1D6`) + result (11pt `#636366`) + for edits `+N` `#30D158` / `−N` `#FF6961` mono 10pt and a static "▸ diff" label (expansion is Phase 8); prose SF Pro 13pt white, line spacing for 1.35. Rows bottom-aligned, content padding 0 6 8, gap 5.
- D-06: Status row "✻ Working · 0:41" (11pt `#D97757`) + "esc to interrupt" (`#636366`) from Phase 4's `manager.liveStatus` (screen). Shimmer while live; elapsed ticks locally between polls.
- D-07: New rows keyed by block id insert with `.move(edge: .bottom).combined(with: .opacity)`, spring 0.3/0.85. Clicking the transcript still opens the terminal (existing expand call / Phase 4 expand-level API).

### Composer and message box (CHAT-03, CHAT-04)
- D-08: Composer per README 02 (30px pill radius 15 `#1C1C1E`, padding 0 6 0 14, 12pt, placeholder "Message orchestrator", 20px send circle; focused ring 1.5px `#D97757`, send turns accent with black ↑); hint row "⏎ send · ⌃U clear line · esc release" 10pt `#636366` right-aligned. Focus/typing uses the existing `OrchestratorKeyGate`, `beginTyping`, `endTyping` logic **unchanged**.
- D-09: `inputLine`: parse Claude Code's input box `❯` line from the screen (the box chatTail strips; fixture `Tests/fixtures/inputbox.txt`). Phase A cannot tell a dim suggestion from a typed draft: treat box text as a **suggestion** when the field is empty and not focused-with-draft; on focus, if the box has text, pull it in as a terminal draft with the "from terminal · " prefix (`#8E8E93`, UI only, not part of the sent text). Record the heuristic with a ponytail comment (Phase 8 replaces it with serve's `suggested` flag).
- D-10: Suggestion: ghost text `#636366` after the caret + "[Tab] accept" keycap. Tab or → accepts: fill the field and POST `{key:"Tab"}`. Any other character replaces it. ⌃U clears from cursor to line start locally AND POSTs `{key:"C-u"}` (`C-u` is already in `allowedKeys` from Phase 4 and in serve's allowlist); show "line cleared" tag (10pt `#8E8E93` on `#2C2C2E`, radius 8) ~1.2s. Keycap style per README.

### Parallel-merge rules
- D-11: Files owned: `OrchestratorChat.swift`, `OrchestratorTranscript.swift`, `Tests/Phase5Tests.swift`. Shared-file edits allowed only per MERGE-MAP "Phase 5" (a marked `// Phase 5` block in `OrchestratorManager.swift` if state can't live on a Phase 5 object). No edits to Models, Expand, header, ContentView, pbxproj. Every plan lists its merge points in a `<merge_points>` section.

### Safety and constraints (all phases)
- S-01: NEVER POST to 127.0.0.1:4777 during build or verification (it types into or ends the user's real chat). GETs are fine, but do not load `/term` (it would attach a ttyd client).
- S-02: Do not launch apps. Build only: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-pN build` with N = this phase number (separate derived data per parallel phase).
- S-03: Keep upstream mergeable: new files under `boringNotch/Orchestrator/`, minimal hooks into upstream files. No new dependencies. HTTP-only to the orchestrator; never spawn processes. Swift 5 mode, `ObservableObject` + `@Published` singletons, `@MainActor` managers.
- S-04: Music must not regress (now-playing, controls, artwork, closed-notch music live activity).
- S-05: Never push; stay on the current branch; do not create or switch GSD phase/milestone branches.
- S-06: Pure logic gets assert checks in the swiftc harness (`boringNotch/Orchestrator/Tests/`), command in `.planning/design/orchestrator-2a/MERGE-MAP.md`.
- S-07: Follow the design handoff exactly for sizes, colours, copy and SF Symbols: `.planning/design/orchestrator-2a/README.md` + `screenshots/`. Rebuild in SwiftUI; do not port the HTML.

### Claude's Discretion
- Whether transcript state lives on a separate `ObservableObject` (preferred, zero manager diff) or the manager.
- How the composer intercepts Tab/→/⌃U in a SwiftUI TextField (`onKeyPress` is macOS 14+, fine).
</decisions>

<canonical_refs>
## Canonical References

- `.planning/design/orchestrator-2a/README.md` — the design spec (option 2a, high fidelity). Screenshots in `screenshots/` (2×). `Orchestrator Notch Options.dc.html` is reference only.
- `.planning/design/orchestrator-2a/MERGE-MAP.md` — file ownership and merge points for Phases 5–7 (binding).
- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `CLAUDE.md`
- Prior phases: `.planning/phases/01-*/`, `02-*/`, `03-*/` (CONTEXT, SUMMARY, REVIEW-FIX)
- Code: `boringNotch/Orchestrator/*.swift`, `boringNotch/components/Notch/BoringHeader.swift`, `boringNotch/ContentView.swift`, `boringNotch/models/BoringViewModel.swift`, `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`, `boringNotch/sizing/matters.swift`
- Serve (read-only, other repo): `/Users/mitch/Documents/Claude/orchestrator/orch.js` — `/api/state` runs carry `id, project, ws, agent, prompt, state, startedAt, lastOutput, result, denials, latest, activity{step, agents}`; `/api/chat` returns `{running, screen}` (capture-pane -J -S -200); POST keys allowlist already includes `C-u`.
- Frames for this phase: 01, 02, 02b; Interactions and motion; State management.
- Phase 4 plans/summary: `.planning/phases/04-*/` (the seams you build on).
</canonical_refs>

<deferred>
## Deferred Ideas
- Streaming caret, ▸ diff expansion, `suggested` flag, ctx % — Phase 8. Expanded conversation column (bubbles, diff card) — Phase 7 embeds this phase's view.
</deferred>
