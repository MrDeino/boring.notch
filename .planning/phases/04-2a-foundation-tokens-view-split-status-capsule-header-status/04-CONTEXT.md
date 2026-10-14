# Phase 4: 2a Foundation - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator dispatch brief (user decisions relayed from the orchestrator chat) + design handoff

<domain>
## Phase Boundary

Rebuild the Orchestrator tab's shell to design option 2a: design tokens; split `OrchestratorView.swift` into Chat / PromptCard / RunsBoard / StatusCapsule files; header with the **Chat | Runs N** segment and one **status capsule** replacing `OrchestratorUsageBadge`, `OrchestratorChatButton` and `OrchestratorRunsButton`; the **status menu** (frame 06); **stopped** (07), **offline** (08) and **connecting** (09) screens. Also lay down every stub file and hook that Phases 5, 6 and 7 need so they can run in parallel (see MERGE-MAP.md).

Not in this phase: transcript rows from `/api/chat/blocks` (5), new composer/message box (5), decision card and question list (6), runs board cards, expand levels, expanded view and wings (7), anything Phase B.
</domain>

<decisions>
## Implementation Decisions

### Tokens and split (FND-01, FND-02)
- D-01: One `OrchestratorTokens.swift` with the handoff's Design tokens: surfaces, text grays, Claude accent `#D97757`, status colours (green/orange/red with text/background variants), SF Pro / SF Mono sizes, radii, spacing, header height 34, notch padding 0 14 12. Use a namespaced enum (e.g. `enum OT`) — Claude's discretion on naming.
- D-02: `OrchestratorView.swift` becomes a thin shell; existing behaviour moves unchanged into `OrchestratorChat.swift` (chat tail + composer, typing/key-gate logic untouched), `OrchestratorPromptCard.swift` (option buttons, esc, 3s lock), `OrchestratorRunsBoard.swift` (runs strip, shown when the segment is on Runs instead of the overlay). Restyle with tokens only where trivial; full redesign of those is Phases 5–7.

### Header (FND-03, FND-04)
- D-03: Segment and capsule exactly per README "Header". Segment shows only on the Orchestrator tab and is hidden while offline. The capsule shows in the open header on all tabs (today's usage badge does too) — record if this turns out wrong.
- D-04: Capsule state rules: Connecting until `hasLoaded`; Offline when `offline`; Stopped when `!chatRunning`; Needs you when `needsAttention`; Running when the screen shows Claude's live working status line (✻ … esc to interrupt); otherwise Idle. Usage ring = 5h `used_percentage` (orange ≥80). "ctx N%" is Phase B — omit (no divider) in this phase.
- D-05: `showRuns` becomes the segment state (`showRunsBoard`); the runs overlay goes away.
- D-06: Header edits in `BoringHeader.swift` are limited to swapping the three controls for `OrchestratorHeaderSegment()` (left, after `TabSelectionView()`) and `OrchestratorHeaderTrailing()` (right). Tab icons stay as they are (spec gap noted: README lists `house`, `tray`, `terminal`; repo uses its own icons + `terminal.fill`).

### Status menu (FND-05)
- D-07: Menu is a SwiftUI overlay drawn **inside the notch** under the capsule (not `.popover`, which opens a separate window outside the notch). 232px wide, rows per README 06. Interrupt keeps `pressEscape()` 1s debounce; End uses the existing 4s confirm behaviour; Start chat replaces End when stopped. Content dims to 35% while open; tap outside the menu closes it. It must fit inside the 190px open notch — tighten row padding if needed and note it.

### States (FND-06)
- D-08: Copy exactly: "Orchestrator chat is stopped" / "▶ Start chat" / "N runs still active · see Runs" (tapping "see Runs" switches the segment; hide the line when 0 live runs); "Can't reach the orchestrator" / mono chip "node orch.js serve · 127.0.0.1:4777" / "Retrying every 10s"; connecting = four skeleton bars (9px, radius 5, `#1C1C1E`, widths 48/30/62/40%) bottom-aligned plus the composer. Offline polling cadence stays as today; the copy says 10s, so make the offline retry interval 10s (spec says so) if it is not already.

### Shared seams for the parallel phases (FND-07)
- D-09: Implement everything in `.planning/design/orchestrator-2a/MERGE-MAP.md` "Phase 4 pre-creates" and "Shared hooks": stub files registered in `project.pbxproj`, `Tests/Phase4..7Tests.swift` runners called from `main.swift`, `detectPrompt`/`PromptOption` moved into `OrchestratorPromptParse.swift` with a `PromptCard` struct (`title, purpose, body, options, kind: permission/question, header, progress`, all optional except options/kind) and `detectPromptCard(screen:)`; `manager.prompt: PromptCard?` alongside `promptOptions`; `parseLiveStatus(screen:) -> LiveStatus?` (text + elapsed seconds) with `manager.liveStatus`; `ExpandLevel` API on `OrchestratorExpand`; `pollInterval(notchOpen:chatRunning:)`; `"C-u"` in `allowedKeys`.
- D-10: Phase 5–7 design notes needed for stubs: Phase 5 will fetch `GET /api/chat/blocks?since=<id>`; Phase 6 will enrich `detectPromptCard`; Phase 7 will own expand levels, runs fields and wings.

### Safety and constraints (all phases)
- S-01: NEVER POST to 127.0.0.1:4777 during build or verification (it types into or ends the user's real chat). GETs are fine, but do not load `/term` (it would attach a ttyd client).
- S-02: Do not launch apps. Build only: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-pN build` with N = this phase number (separate derived data per parallel phase).
- S-03: Keep upstream mergeable: new files under `boringNotch/Orchestrator/`, minimal hooks into upstream files. No new dependencies. HTTP-only to the orchestrator; never spawn processes. Swift 5 mode, `ObservableObject` + `@Published` singletons, `@MainActor` managers.
- S-04: Music must not regress (now-playing, controls, artwork, closed-notch music live activity).
- S-05: Never push; stay on the current branch; do not create or switch GSD phase/milestone branches.
- S-06: Pure logic gets assert checks in the swiftc harness (`boringNotch/Orchestrator/Tests/`), command in `.planning/design/orchestrator-2a/MERGE-MAP.md`.
- S-07: Follow the design handoff exactly for sizes, colours, copy and SF Symbols: `.planning/design/orchestrator-2a/README.md` + `screenshots/`. Rebuild in SwiftUI; do not port the HTML.

### Claude's Discretion
- Token naming, file-internal structure, exact capsule/segment view decomposition.
- Live-status regex (base it on Claude Code's "✻ Working… (41s · ↑ 1.2k tokens · esc to interrupt)" line and similar spinner words; elapsed parsed from the parenthesised duration, e.g. "41s", "1m 52s").
- Cross-fade for capsule label changes (README motion summary).
</decisions>


<canonical_refs>
## Canonical References

- `.planning/design/orchestrator-2a/README.md` — the design spec (option 2a, high fidelity). Screenshots in `screenshots/` (2×). `Orchestrator Notch Options.dc.html` is reference only.
- `.planning/design/orchestrator-2a/MERGE-MAP.md` — file ownership and merge points for Phases 5–7 (binding).
- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `CLAUDE.md`
- Prior phases: `.planning/phases/01-*/`, `02-*/`, `03-*/` (CONTEXT, SUMMARY, REVIEW-FIX)
- Code: `boringNotch/Orchestrator/*.swift`, `boringNotch/components/Notch/BoringHeader.swift`, `boringNotch/ContentView.swift`, `boringNotch/models/BoringViewModel.swift`, `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`, `boringNotch/sizing/matters.swift`
- Serve (read-only, other repo): `/Users/mitch/Documents/Claude/orchestrator/orch.js` — `/api/state` runs carry `id, project, ws, agent, prompt, state, startedAt, lastOutput, result, denials, latest, activity{step, agents}`; `/api/chat` returns `{running, screen}` (capture-pane -J -S -200); POST keys allowlist already includes `C-u`.
- Frames for this phase: Header, 06, 07, 08, 09; Design tokens; Coverage table.
</canonical_refs>

<deferred>
## Deferred Ideas
- Transcript rows, composer 02/02b — Phase 5. Decision card/question list — Phase 6. Runs cards, expand levels, expanded/rail, wings — Phase 7. ctx %, SSE — Phase 8. Approval drop-down, global shortcuts — Phase 9.
</deferred>
