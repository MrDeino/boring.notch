# Phase 6: 2a Prompt Cards - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator dispatch brief (user decisions 2026-10-14) + design handoff

<domain>
## Phase Boundary

Claude Code's permission prompts show as the decision card (frame 03) and AskUserQuestion prompts as the vertical question list (frame 04), driven by an enriched `detectPrompt` (title/purpose/body/kind/header/progress). Keys 1–9 and esc answer while the pointer is over the notch; "Something else…" and "Chat about this" work. Runs **in parallel with Phases 5 and 7** after Phase 4 — stay inside the files MERGE-MAP.md assigns to Phase 6.

Not in this phase: transcript rows/composer (5), runs/expand levels/wings (7), closed-notch approval drop-down and global ⌥⏎/⌥⎋ (9), exact options from serve (8/9).
</domain>

<decisions>
## Implementation Decisions

### Parser (PRM-01)
- D-01: Enrich `detectPromptCard(screen:) -> PromptCard?` in `OrchestratorPromptParse.swift` (moved there by Phase 4). Keep `detectPrompt` behaviour for options (existing tests must still pass).
- D-02: Permission (fixture `Tests/fixtures/permission.txt`): title = first line after the `───` rule ("Bash command"); skip "Tip:" lines; purpose = next line ("Write current date to stamp file"); body/command = lines between the `╌╌╌` dashed rules ("date > /tmp/…"); ends at "Do you want to proceed?". Kind = permission.
- D-03: Question (fixture `question.txt`): header tag from the "☐ Fruit" line (also handle ☒/✔ progress chips for multi-question prompts: progress "1 of 2" when several chips exist); question = next line; options keep their description lines (indented line under each option); kind = question. "Type something." and "Chat about this" are recognised as special options with their actual numbers (they are n+1 and n+2, e.g. 4 and 5 in the fixture — don't hard-code 4/5).
- D-04: Highlighted (❯) option index captured for the default highlight.

### Permission card (PRM-02)
- D-05: Exactly per README 03: title 14pt semibold + purpose 12pt `#8E8E93`; command block mono 12pt `#E5E5EA` on `#1C1C1E` radius 8 padding 8/10, one line, ellipsis, `$ ` prefix `#636366`; pills 30px radius 15 gap 6 bottom-aligned; option 1 white/black weight 500 light keycap; others `#1C1C1E` white dark keycap; deny (last "No") pushed right `#FF6961` with keycap "esc"; shortened labels ("Yes, and always allow access to X…" → "Always in X…", "…switch to auto mode…" → "Auto mode") via a pure function with tests, full label as `.help` tooltip. After a press the chosen pill fills, others dim to 40% for the existing 3s `optionsLocked` window.
- D-06: The deny pill sends the deny option's number (not Escape) — esc keycap is the keyboard shortcut; pressing esc sends Escape via the debounced `pressEscape()`.

### Question list (PRM-03, PRM-05)
- D-07: Exactly per README 04: header tag + "1 of 2"; question 14pt semibold wraps; option rows radius 10 padding 8/10 gap 5, label 12pt semibold, description 11pt `#8E8E93`, keycap right; highlighted row white bg/black label/`#48484A` desc/light keycap; ↑/↓ move the local highlight, ⏎ selects. Footer 28px pills: "Something else…" free-text field (keycap = its real number) — send the option number, then the text via `sendText`; "Chat about this" (keycap = its number); esc.
- D-08: The notch grows to fit (mock 640×400) using Phase 4's `OrchestratorExpand.setLevel(.expanded, …)` API; list scrolls if it still overflows; return to `.open` when the prompt goes away (only if this card raised it).

### Keys while hovered (PRM-04)
- D-09: 1–9 and esc answer while the pointer is over the notch. The notch panel is non-activating and only becomes key while typing/terminal (`OrchestratorKeyGate`, gated `canBecomeKey`). Research must pick a sandbox-safe way: preferred is a gated key-take on hover while a prompt is shown (reuse `OrchestratorKeyGate` with its restore/refocus logic, release on pointer exit/answer), versus a local monitor (only fires when our app is active). No Accessibility/Input Monitoring permission prompts. Keep this inside the Orchestrator folder; if `BoringNotchSkyLightWindow.canBecomeKey` must change, it is one line and a declared merge point.
- D-10: Free-text "Something else…" typing uses the same `beginTyping`/`endTyping` path as the composer.

### Parallel-merge rules
- D-11: Files owned: `OrchestratorPromptCard.swift`, `OrchestratorPromptParse.swift`, `Tests/Phase6Tests.swift`. No edits to Manager (use `manager.prompt`, `pressOption`, `pressEscape`, `sendText` as they are), Models, Expand internals, header, ContentView, pbxproj — any unavoidable edit is a declared merge point in the plan's `<merge_points>`.

### Safety and constraints (all phases)
- S-01: NEVER POST to 127.0.0.1:4777 during build or verification (it types into or ends the user's real chat). GETs are fine, but do not load `/term` (it would attach a ttyd client).
- S-02: Do not launch apps. Build only: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-pN build` with N = this phase number (separate derived data per parallel phase).
- S-03: Keep upstream mergeable: new files under `boringNotch/Orchestrator/`, minimal hooks into upstream files. No new dependencies. HTTP-only to the orchestrator; never spawn processes. Swift 5 mode, `ObservableObject` + `@Published` singletons, `@MainActor` managers.
- S-04: Music must not regress (now-playing, controls, artwork, closed-notch music live activity).
- S-05: Never push; stay on the current branch; do not create or switch GSD phase/milestone branches.
- S-06: Pure logic gets assert checks in the swiftc harness (`boringNotch/Orchestrator/Tests/`), command in `.planning/design/orchestrator-2a/MERGE-MAP.md`.
- S-07: Follow the design handoff exactly for sizes, colours, copy and SF Symbols: `.planning/design/orchestrator-2a/README.md` + `screenshots/`. Rebuild in SwiftUI; do not port the HTML.

### Claude's Discretion
- Label-shortening rules beyond the two examples (keep a small table + fallback truncation).
- `matchedGeometryEffect` rise-from-composer motion (README) — do it if it stays inside owned files; otherwise a simple transition.
</decisions>

<canonical_refs>
## Canonical References

- `.planning/design/orchestrator-2a/README.md` — the design spec (option 2a, high fidelity). Screenshots in `screenshots/` (2×). `Orchestrator Notch Options.dc.html` is reference only.
- `.planning/design/orchestrator-2a/MERGE-MAP.md` — file ownership and merge points for Phases 5–7 (binding).
- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `CLAUDE.md`
- Prior phases: `.planning/phases/01-*/`, `02-*/`, `03-*/` (CONTEXT, SUMMARY, REVIEW-FIX)
- Code: `boringNotch/Orchestrator/*.swift`, `boringNotch/components/Notch/BoringHeader.swift`, `boringNotch/ContentView.swift`, `boringNotch/models/BoringViewModel.swift`, `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift`, `boringNotch/sizing/matters.swift`
- Serve (read-only, other repo): `/Users/mitch/Documents/Claude/orchestrator/orch.js` — `/api/state` runs carry `id, project, ws, agent, prompt, state, startedAt, lastOutput, result, denials, latest, activity{step, agents}`; `/api/chat` returns `{running, screen}` (capture-pane -J -S -200); POST keys allowlist already includes `C-u`.
- Frames for this phase: 03, 04; Interactions and motion (prompt card).
- Fixtures: `boringNotch/Orchestrator/Tests/fixtures/permission.txt`, `question.txt`, `inputbox.txt`.
- Phase 4 plans/summary: `.planning/phases/04-*/`.
</canonical_refs>

<deferred>
## Deferred Ideas
- Closed-notch approval drop-down, global ⌥⏎/⌥⎋, hook-fed exact options — Phase 9. Allow/Deny on run cards — dropped (user 2026-10-14).
</deferred>
