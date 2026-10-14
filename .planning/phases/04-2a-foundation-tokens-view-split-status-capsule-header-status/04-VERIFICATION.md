---
phase: 04-2a-foundation-tokens-view-split-status-capsule-header-status
verified: 2026-10-14T00:00:00Z
status: human_needed
score: 5/5 roadmap criteria verified at code level (visual and music parts pending human)
human_verification:
  - test: "Header fit, segment, capsule variants, status menu, states (04-HUMAN-UAT tests 1-5)"
    expected: "As written in 04-HUMAN-UAT.md"
    why_human: "Visual layout, animation, live serve states"
  - test: "Regression of keyboard focus, prompt buttons, transcript tap, attention dot, usage hairline (test 6)"
    expected: "Unchanged from Phase 2/3"
    why_human: "Needs running app"
  - test: "Music unchanged (test 7, BLD-02 / roadmap criterion 5)"
    expected: "Now-playing, controls, artwork, closed-notch music activity as before"
    why_human: "Needs running app; code-level diff to music is only header/TabButton edits"
---

# Phase 4 Verification

**Goal:** 2a shell (tokens, split files, Chat | Runs segment, one status capsule + menu, stopped/offline/connecting screens), current features intact, seams for Phases 5-7.
**Status:** human_needed. No gaps found at code level.

## Roadmap success criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | One tokens file; thin shell; Chat/PromptCard/RunsBoard/StatusCapsule in own files | VERIFIED | `OrchestratorTokens.swift` (OT.C/F/R/S, includes handoff palette, radii 24/26/22/12 etc.); `OrchestratorView.swift` 68 lines, state switch only; `OrchestratorChat/PromptCard/RunsBoard/StatusCapsule/States.swift` exist |
| 2 | Segment + one capsule in six variants; old header buttons gone | VERIFIED | `OrchestratorHeaderSegment` (hidden when offline or not on Orchestrator tab, count orange when waiting else gray) and capsule states connecting/idle/running/needsYou/stopped/offline via `capsuleState`; grep finds no `OrchestratorUsageBadge`, `OrchestratorChatButton`, `OrchestratorRunsButton` anywhere; `BoringHeader.swift` hosts `OrchestratorHeaderSegment()` and `OrchestratorHeaderTrailing()` |
| 3 | Status menu in notch: usage/resets/bars, Open terminal, Interrupt 1s debounce, End 4s confirm, Start chat when stopped, 35% dim | VERIFIED | Overlay inside `OrchestratorView` (not a window), `.opacity(statusMenuOpen ? 0.35 : 1)`; usage rows with "resets"; `pressEscape()` guards `> 1`s; `Task.sleep(.seconds(4))` confirm revert; "Start chat" row when not running; closes on notch close, tab change (`onDisappear`), outside tap |
| 4 | Stopped/offline/connecting copy+layout; existing features kept | VERIFIED (copy/layout visual: human) | `OrchestratorStates.swift` has "N runs still active · see Runs" (sets `showRunsBoard`), "Retrying every 10s"; chat, prompt buttons, esc lock, transcript-tap expand (`transcriptTapped`) preserved; `pollInterval` keeps 2s/10s |
| 5 | Music unchanged | UNCERTAIN, human | Diff to existing files is `BoringHeader.swift` (5 lines), `TabButton.swift` (padding, 2 lines) in components; no music files touched. Needs on-screen check |

## Requirements coverage (PLAN frontmatter vs REQUIREMENTS.md)

Plans declare: 04-01 FND-01, FND-07; 04-02 FND-02, FND-06, FND-07; 04-03 FND-01..05. Union = FND-01..07, all present in REQUIREMENTS.md and all mapped to Phase 4. No orphans.

| ID | Status | Evidence |
|---|---|---|
| FND-01 | SATISFIED | Tokens file |
| FND-02 | SATISFIED | Split files, thin shell |
| FND-03 | SATISFIED | Header segment, old runs button removed |
| FND-04 | SATISFIED | Capsule + 12px ring (orange at >= 80%), old badge/chat button removed |
| FND-05 | SATISFIED | Status menu as above |
| FND-06 | SATISFIED (visual match: human) | `OrchestratorStates.swift` |
| FND-07 | SATISFIED | `PromptCard`, `manager.prompt` (set via `detectPromptCard` when running), `manager.liveStatus` via `parseLiveStatus`, `ExpandLevel` + `level(for:)`/`setLevel`/`transcriptTapped` on `OrchestratorExpand` |

## MERGE-MAP stubs and hooks

- All 12 Orchestrator files listed exist and are each registered in `project.pbxproj` (4 references each). Stubs are tiny as expected (Transcript 2 lines, Wings 2, RunsPure 7, Expanded 6 with `OrchestratorExpandedView`).
- `Tests/Phase4..7Tests.swift` and `main.swift` exist. They are intentionally not in pbxproj (harness only, not app sources).
- Hooks: `allowedKeys` contains `C-u`; `pollInterval(notchOpen:chatRunning:offline:)` used in the poll loop; `refresh()` sets `prompt` and `liveStatus`, clears both when not running; shell renders `OrchestratorExpandedView` when level != .open and the prompt card instead of chat while `manager.prompt != nil`.
- Transcript hook: present — `OrchestratorManager.swift:151` calls `await OrchestratorTranscriptStore.shared.refresh(base:session:screen:chatRunning:)` into the Phase 5-owned stub in `OrchestratorChat.swift` (orchestrator correction; the verifier's first grep looked for `transcript.refresh`). `OrchestratorChatView(showComposer:)` exists.
- Review fixes WR-01/WR-02 applied after verification (04-REVIEW-FIX.md); harness OK and build SUCCEEDED re-run by the orchestrator.

## Checks run

- swiftc harness from MERGE-MAP.md: compiled and ran, exit 0, prints OK.
- Xcode build: not re-run (reported already passed; a built app exists at /tmp/notch-dd/Build/Products/Debug/Boring Notch.app).
- Debt markers (TBD/FIXME/XXX) in `boringNotch/Orchestrator/*.swift`: none.
- Not run: any POST to serve, /term, launching the app.

## Gaps

None blocking. Human UAT items 1-7 in `04-HUMAN-UAT.md` are all still pending.
