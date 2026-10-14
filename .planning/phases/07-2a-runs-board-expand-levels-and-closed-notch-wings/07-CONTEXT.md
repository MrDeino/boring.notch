# Phase 7: 2a Runs Board, Expand Levels & Wings - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator dispatch brief (user decisions 2026-10-14) + design handoff

<domain>
## Phase Boundary

Runs board (frame 05) behind the Runs segment; expand levels open → expanded → terminal (frames 10, 11, 12, 12b) with the runs rail and `Defaults` `orchRunsRailCollapsed`; closed-notch live-activity wings (frame 00) keeping the music live activity intact. Runs **in parallel with Phases 5 and 6** after Phase 4 — stay inside the files MERGE-MAP.md assigns to Phase 7.

Not in this phase: transcript rows/composer (5), prompt cards (6), Allow/Deny on run cards (dropped), approval drop-down (9), content-sized panel frame (9), expanded diff card data (8).
</domain>

<decisions>
## Implementation Decisions

### Runs board (RUN-01) — user decision 2026-10-14
- D-01: Cards per README 05: 196px, radius 12, `#1C1C1E`, padding 9/10, gap 5, horizontal scroll beyond three. Line 1: 6px state dot, project (12pt semibold), elapsed right (10pt `#8E8E93`, from `startedAt`). Line 2: short prompt 11pt `#8E8E93`. Line 3: latest action mono 10pt `#D1D1D6` (from `activity.step` / `latest`). Sort live first (`stripRuns`). Colours: running `#30D158`, waiting `#FF9F0A`, failed/stuck `#FF453A`, done `#8E8E93` at 75% with ✓; stopped = done styling.
- D-02: **Waiting card**: inset 1px `#FF9F0A` ring; shows the run's question (from `result`, last lines, and/or `denials` tool names) and **one button that sends that context into the orchestrator chat** (e.g. "Ask in chat" → `sendText` with a one-line message naming the run id, project and question; serve collapses newlines). **No Allow/Deny/resume of runs from the notch.** The button is disabled when the chat isn't running (offer Start instead) — Claude's discretion on copy, keep it short.
- D-03: Extend `OrchestratorRun` with optional `startedAt`, `lastOutput`, `result`, `denials`, `latest`, `activity{step, agents}` (all optional; existing decoding tests still pass).
- D-04: Bottom row on the Runs board: the composer pill collapses to one line "✻ Orchestrator: <status>" (e.g. "waiting on run x7f2") — derive from `manager.liveStatus` / `needsAttention`.

### Expand levels (RUN-02, RUN-03)
- D-05: Own the Phase 4 `ExpandLevel` API: open (640×190) → expanded (640×~440, content height up to ~45% of screen) → terminal (mode inside expanded). Triggers: click transcript or ⌘↓ → expanded; esc or ⌘↑ back one level; Terminal pill / ⌘T → terminal; click outside closes fully. Keep the existing outside-click, monitor and key-release logic in `OrchestratorExpand`. ⌘-shortcuts only work while the panel is key — research how far that holds (typing/terminal key states) and document the limit rather than adding Accessibility permissions.
- D-06: Motion: height is one continuous spring (response 0.4, damping 0.82); content cross-fades in after ~120ms, 0.18s ease-out. Bottom radius 26 when expanded.
- D-07: Expanded body (12): header capsule + 24px "⌃" collapse button (inside `OrchestratorHeaderTrailing` in `OrchestratorStatusCapsule.swift` — the declared header merge point); conversation column embeds `OrchestratorChatView` (Phase 5 fills it; until merge it shows Phase 4's tail) — user bubble/expanded diff card styling belongs to the Phase 5 rows + Phase 8; runs rail 178px with "Runs · N active", compact cards, 5h/7d usage bars pinned bottom; bottom row composer (32px) + "Terminal ⌘T" pill. Waiting rail cards: same "Ask in chat" button as D-02 (no Allow/Deny).
- D-08: Terminal (10): existing ttyd `WKWebView` (`OrchestratorTerminal.swift`) inside a `#0B0B0C` frame radius 12 with inset 1px `#1C1C1E`; toolbar 11pt `#8E8E93`: green dot, "Terminal · keyboard captured", "Collapse ⌃" pill; in use / unavailable replace the body with the message + Retry pill. WebView still created only in terminal mode.
- D-09: Rail collapse (12b): 30px strip with ‹ button, one 22px circle per run with 7px state dot (waiting = inset orange ring), usage ring at bottom; ‹ or ⌘\ re-expands; hover a dot peeks that run's card. Persist in `Defaults` key `orchRunsRailCollapsed` (declared in a Phase 7 file's `extension Defaults.Keys`). Auto re-open when a run newly enters waiting unless the user collapsed it this session. Width animates with spring 0.3/0.85.

### Closed-notch wings (RUN-05)
- D-10: Per README 00: wings grow sideways from the hardware notch like the music live activity, black, 32px tall, radius 12, padding 0 12 0 14. Working (285 wide): ✻ `#D97757` 15pt rotating slowly | elapsed mono 11pt medium `#AEAEB2`. Needs you (305): 8px orange dot with pulsing glow (1.2s) | pill with the prompt's tool name + "?" (from `manager.prompt?.title`, Phase 6 enriches it; fall back to "Needs you" while nil) 11pt medium `#FFB35C` on `#3A2410`, radius 9, padding 2/8. Run finished (285): ✓ `#30D158` 13pt | project name 11pt `#AEAEB2`, fades after 4s (detect a run transitioning to done). Wings spring out 0.35/0.8.
- D-11: **Music wins**: while the music live activity is showing, the wings do not show; music keeps album art and visualizer, and a 7px orange dot appears before the visualizer when needs-you. The current attention dot + usage hairline (2px, inset 14, track white 12%, fill white 50%, orange ≥80%) stay. ContentView edits are the minimum hook needed; music sizing/behaviour unchanged.
- D-12: Closed polling 3s while `chatRunning` (via `pollInterval` in `OrchestratorRunsPure.swift`), 10s otherwise; 2s open.

### Parallel-merge rules
- D-13: Files owned: `OrchestratorRunsBoard.swift`, `OrchestratorRunsPure.swift`, `OrchestratorExpanded.swift`, `OrchestratorWings.swift`, `OrchestratorExpand.swift`, `OrchestratorCompact.swift`, `OrchestratorTerminal.swift`, `Tests/Phase7Tests.swift`; plus `OrchestratorRun` fields in Models, `ContentView.swift` wing hook, the trailing header view. Any other shared edit (e.g. a `// Phase 7` manager block for finished-run tracking) is a declared merge point in the plan's `<merge_points>`.

### Safety and constraints (all phases)
- S-01: NEVER POST to 127.0.0.1:4777 during build or verification (it types into or ends the user's real chat). GETs are fine, but do not load `/term` (it would attach a ttyd client).
- S-02: Do not launch apps. Build only: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-pN build` with N = this phase number (separate derived data per parallel phase).
- S-03: Keep upstream mergeable: new files under `boringNotch/Orchestrator/`, minimal hooks into upstream files. No new dependencies. HTTP-only to the orchestrator; never spawn processes. Swift 5 mode, `ObservableObject` + `@Published` singletons, `@MainActor` managers.
- S-04: Music must not regress (now-playing, controls, artwork, closed-notch music live activity).
- S-05: Never push; stay on the current branch; do not create or switch GSD phase/milestone branches.
- S-06: Pure logic gets assert checks in the swiftc harness (`boringNotch/Orchestrator/Tests/`), command in `.planning/design/orchestrator-2a/MERGE-MAP.md`.
- S-07: Follow the design handoff exactly for sizes, colours, copy and SF Symbols: `.planning/design/orchestrator-2a/README.md` + `screenshots/`. Rebuild in SwiftUI; do not port the HTML.

### Claude's Discretion
- How to measure "45% of screen" and the expanded height cap against `expandedExtra`.
- Hover-peek implementation for rail dots.
</decisions>


<canonical_refs>
## Canonical References

- `.planning/design/orchestrator-2a/README.md` — the design spec (option 2a, high fidelity). Screenshots in `screenshots/` (2×). `Orchestrator Notch Options.dc.html` is reference only.
- `.planning/design/orchestrator-2a/MERGE-MAP.md` — file ownership and merge points for Phases 5–7 (binding).
- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `CLAUDE.md`
- Prior phases: `.planning/phases/01-*/`, `02-*/`, `03-*/` (CONTEXT, SUMMARY, REVIEW-FIX)
- Code: `boringNotch/Orchestrator/*.swift`, `boringNotch/components/Notch/BoringHeader.swift`, `boringNotch/ContentView.swift`, `boringNotch/models/BoringViewModel.swift`, `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`, `boringNotch/sizing/matters.swift`
- Serve (read-only, other repo): `/Users/mitch/Documents/Claude/orchestrator/orch.js` — `/api/state` runs carry `id, project, ws, agent, prompt, state, startedAt, lastOutput, result, denials, latest, activity{step, agents}`; `/api/chat` returns `{running, screen}` (capture-pane -J -S -200); POST keys allowlist already includes `C-u`.
- Frames for this phase: 00, 05, 10, 11, 12, 12b; Interactions and motion; State management (UI state).
- Music live activity code: `boringNotch/ContentView.swift` closed-notch music layout (read before touching).
- Phase 4 plans/summary: `.planning/phases/04-*/`.
</canonical_refs>

<deferred>
## Deferred Ideas
- Allow/Deny on run cards and rail (README Phase B 1f) — dropped by user decision 2026-10-14; the button sends context to chat instead.
- Expanded Edit diff card, streaming caret — Phase 8. Approval drop-down, content-sized frame — Phase 9.
</deferred>
