---
phase: 07-2a-runs-board-expand-levels-and-closed-notch-wings
verified: 2026-10-14T00:00:00Z
status: human_needed
score: 5/5 must-haves verified (code level)
overrides_applied: 0
human_verification:
  - test: "Runs segment: open the notch on the Runs tab with live, waiting, stuck and finished runs"
    expected: "196px cards (dot, project, elapsed, prompt, mono latest action); waiting first, then running/stuck, then finished; waiting card has orange inset ring; scroll beyond three; bottom row reads 'Orchestrator: <status>'"
    why_human: "Visual layout and colours"
  - test: "Tap 'Ask in chat' on a waiting card; stop the chat and look at the button"
    expected: "One-line message naming run id, project, question appears in chat only on tap; button reads 'Start chat' when chat stopped and starts it; no Allow/Deny/resume anywhere"
    why_human: "Live interaction with serve (verifier may not POST)"
  - test: "Click transcript, then press cmd-Down, cmd-T, cmd-Up, Esc, cmd-backslash with the panel key; click outside"
    expected: "open -> expanded (640x~440) -> terminal and back; one continuous spring, content cross-fades after ~120ms; pressing a shortcut that changes no level passes through; outside click closes; no stuck monitors or sharing state (CR-01, WR-04)"
    why_human: "Keyboard events and animation feel need the running app"
  - test: "Expanded view: conversation column, 178px rail with usage bars, Terminal cmd-T pill; terminal frame with toolbar; terminal in use / unavailable + Retry"
    expected: "Matches frames 10 and 12; question card stays visible in the conversation column while a prompt is up"
    why_human: "Visual and WebView behaviour"
  - test: "Collapse the rail with the chevron buttons and cmd-backslash; relaunch; then let a run start waiting; hover a strip dot"
    expected: "30px strip with 22px circles, usage ring at bottom; collapsed state persists across relaunch; rail re-opens on a newly waiting run unless collapsed this session; no auto-open at launch or on reconnect (WR-01/02); hover card sits 10pt left of its dot (WR-06)"
    why_human: "Visual, persistence across launch, timing"
  - test: "Closed notch with music off: chat working, a prompt/waiting run, a run finishing"
    expected: "Working wing (spinning star + m:ss), Needs you wing (pulsing orange dot + pill), Run finished wing (check + project) for 4s; spinner and glow restart on each re-appearance (WR-03); usage hairline stays; old corner dot hides during needs-you"
    why_human: "Animation and closed-notch visuals"
  - test: "Closed notch with music playing"
    expected: "Music live activity unchanged in layout and width; no wings; 7px orange dot just before the visualizer only when needs-you"
    why_human: "Visual regression of the music live activity"
---

# Phase 7: 2a Runs Board, Expand Levels & Closed-Notch Wings Verification Report

**Phase Goal:** User sees runs as cards, can step the notch open -> expanded -> terminal with a runs rail, and gets live-activity wings on the closed notch, without disturbing the music live activity
**Status:** human_needed (all code-level checks pass; on-screen checks remain)
**Re-verification:** No

## Observable Truths

| # | Truth (ROADMAP SC) | Status | Evidence |
|---|---|---|---|
| 1 | Runs cards; waiting card sends context to chat, no Allow/Deny/resume (RUN-01) | VERIFIED (code) | `OrchestratorRunsBoard.swift` (137 lines changed) renders cards; `askInChatMessage(run)` -> `manager.sendText` on tap only (line ~123); button reads "Start chat" when stopped; helpers asserted in harness |
| 2 | open -> expanded -> terminal, shortcuts, spring, outside-click logic kept (RUN-02) | VERIFIED (code) | `OrchestratorExpand.swift` has level machine, key monitor using `isCommandOnly` (CR-01), no-op pass-through (WR-04); `nextLevel`/`shortcut`/`expandedHeight` asserted in harness; ContentView radius hook for expanded |
| 3 | Expanded: conversation column, rail with usage bars, Terminal pill; framed terminal with in use/unavailable + Retry (RUN-03) | VERIFIED (code) | `OrchestratorExpanded.swift` (+191), `OrchestratorTerminal.swift` (+39); shell renders `OrchestratorExpandedView()` at `OrchestratorView.swift:49`; look needs human check |
| 4 | Rail 30px strip, `orchRunsRailCollapsed` Defaults, auto re-open on newly waiting (RUN-04) | VERIFIED (code) | Defaults key at `OrchestratorExpanded.swift:6`; `newlyWaiting` + `RunsBaseline` guard; eager `OrchestratorRailState.shared` in wings init (WR-02) |
| 5 | Wings Working/Needs you/Finished, hairline, music unchanged except 7px dot; closed poll 3s while chat runs (RUN-05) | VERIFIED (code) | `OrchestratorWings.swift`; ContentView else-if placed after the music branch (music branch line untouched); `OrchestratorMusicNeedsDot` overlay; `pollInterval` used at `OrchestratorManager.swift:115`, harness asserts 2/3/10/10 |

**Score:** 5/5 verified at code level; visual behaviour pending human.

## Behavioral Spot-Checks / Tests

| Check | Command | Result | Status |
|---|---|---|---|
| swiftc pure harness (phases 3-7 asserts) | the fixed MERGE-MAP swiftc command into /tmp/orch-test-p7 | prints `OK` | PASS |
| Debug build | xcodebuild ... -derivedDataPath /tmp/notch-dd-p7 | `** BUILD SUCCEEDED **` | PASS |
| Probes | none declared | n/a | SKIPPED |

## Requirements Coverage

| Requirement | Source Plans | Status | Evidence |
|---|---|---|---|
| RUN-01 | 07-01, 07-02 | SATISFIED (code) | Truth 1 |
| RUN-02 | 07-03, 07-04, 07-05 | SATISFIED (code) | Truth 2 |
| RUN-03 | 07-04, 07-05 | SATISFIED (code) | Truth 3 |
| RUN-04 | 07-01, 07-05 | SATISFIED (code) | Truth 4 |
| RUN-05 | 07-01, 07-03 | SATISFIED (code) | Truth 5 |

REQUIREMENTS.md maps exactly RUN-01..05 to Phase 7; all are claimed by at least one plan. No orphans.

## Review fixes (07-REVIEW-FIX.md) present in code

| Finding | Evidence | Status |
|---|---|---|
| CR-01 | `isCommandOnly` in RunsPure:142, used at Expand:66 | present |
| WR-01 | `RunsBaseline` (RunsPure:170) used in Expanded:18 and Wings:11 | present |
| WR-02 | `_ = OrchestratorRailState.shared` Wings:17 | present |
| WR-03 | private `WingSpinner`, `WingGlowDot` subviews Wings:110/119 | present |
| WR-04 | pass-through when target == current level (commit b857fb2 in log; Expand.swift) | present |
| WR-05 | lenient `init(from:)` in `OrchestratorRun` (Models) | present |
| WR-06 | offset `-(22 + 10)` commit 1a40edc | present |

## Merge-map compliance

`git diff --name-only 5a22cc9 HEAD` source files: ContentView.swift; Orchestrator/{Compact, Expand, Expanded, Models, RunsBoard, RunsPure, StatusCapsule, Terminal, Wings}.swift; Tests/Phase7Tests.swift; Tests/fixtures/phase7-state.txt. All are Phase 7-owned or listed merge points per MERGE-MAP. No edits to project.pbxproj, OrchestratorManager.swift, Tests/main.swift, Chat, PromptCard, Transcript, PromptParse. Planning files (STATE/ROADMAP/REQUIREMENTS) are the expected always-conflict set.

## Shared-file edits (merge)

| File | Edit | Listed merge point? |
|---|---|---|
| `boringNotch/ContentView.swift` | (1) `@ObservedObject private var wings = OrchestratorWingsModel.shared`; (2) one `else if` branch `OrchestratorWingsView()` after the unchanged music branch; (3) bottom-radius expression uses `OT.R.notchExpanded` when taller than `openNotchSize`; (4) `.overlay(alignment: .leading) { OrchestratorMusicNeedsDot().offset(x: -8) }` on the visualizer container | Yes: "ContentView.swift (wings)", 4 small hooks as planned |
| `boringNotch/Orchestrator/OrchestratorModels.swift` | `OrchestratorRun` optional fields (startedAt, lastOutput, result, denials, latest, activity), private CodingKeys + lenient `init(from:)`, new `RunActivity`/`RunAgent` structs | Yes: "OrchestratorRun optional fields only" (the lenient decoder and two small structs go slightly beyond fields, confined to the run type; WR-05) |
| `boringNotch/Orchestrator/OrchestratorStatusCapsule.swift` | trailing header view: ⌃ collapse button inside `OrchestratorHeaderTrailing` | Yes: listed |
| `boringNotch/Orchestrator/OrchestratorCompact.swift`, `OrchestratorExpand.swift`, `OrchestratorTerminal.swift` | Phase 7-owned behaviour | Yes: owned |

Note: `OrchestratorManager.swift` unchanged (poll interval flows through the Phase 4 `pollInterval` hook); the MERGE-MAP-expected Phase 7 block was not needed.

## Anti-Patterns

No TBD/FIXME/XXX/TODO in Phase 7 files. No stubs found; stub files from Phase 4 are filled.

## Gaps Summary

None at code level. Remaining risk is visual/interactive (keyboard shortcuts, animations, music regression), listed under human_verification. The review fixer also noted CR-01, WR-04, WR-03, WR-06 were never run in the live app.

---
_Verified: 2026-10-14_
_Verifier: Claude (gsd-verifier)_
