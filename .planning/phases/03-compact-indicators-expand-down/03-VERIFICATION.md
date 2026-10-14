---
phase: 03-compact-indicators-expand-down
verified: 2026-10-14T00:00:00Z
status: human_needed
score: 5/5 must-haves verified in code (on-screen behaviour pending UAT)
gaps: []
human_verification:
  - test: "Closed notch, orchestrator online: usage hairline along the bottom edge; orange dot at top-right when a run is waiting or chat shows a numbered prompt"
    expected: "Hairline length tracks the larger of 5h/7d usage (orange at >=80%); dot appears/disappears with waiting state"
    why_human: "Visual overlay"
  - test: "Play music, close the notch, trigger a waiting run/prompt"
    expected: "Dot still shows beside the music activity; music artwork/visualizer/controls unchanged"
    why_human: "Visual, music coexistence"
  - test: "Open notch, Orchestrator tab, click the expand arrow (bottom-right)"
    expected: "Same notch grows downward (top edge pinned) showing a larger chat tail; arrow flips to collapse"
    why_human: "Window resize/animation"
  - test: "In expanded notch, wait for the terminal; type into it"
    expected: "Live ttyd terminal appears and keystrokes reach it (key-window gate works in the non-activating panel); with another ttyd client attached shows 'terminal in use' + Retry"
    why_human: "Keyboard focus and WKWebView need the running app (/term not loaded during verification)"
  - test: "While expanded, click outside the notch (desktop, another app, another screen's notch); also collapse via button, leave tab, close notch"
    expected: "Notch collapses to normal size and closes; focus returns to previous app; reopening starts normal size; terminal slot freed (reload works)"
    why_human: "Event monitors/focus"
  - test: "Regression: music controls, artwork, hover/open/close on a normal notch"
    expected: "Unchanged"
    why_human: "Runtime"
---

# Phase 3 Verification

**Goal:** User notices when the orchestrator needs them with the notch closed, and can grow the notch downward for a larger chat or the full live terminal.

## Automated checks (run by verifier)

| Check | Result |
|---|---|
| swiftc harness (Models, Pure, Phase3Tests, main) | prints `OK` |
| xcodebuild Debug ad-hoc, derivedData /tmp/notch-dd-p3 | `** BUILD SUCCEEDED **` |
| Music files changed vs ac68084 | none (changed Swift: ContentView, BoringViewModel, SkyLightWindow, pbxproj, Orchestrator/*) |
| POST / httpMethod in boringNotch/Orchestrator | none |
| TODO/FIXME/TBD/XXX in Orchestrator | none |

## Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | Closed notch: usage indicator + attention dot, dot not hidden by music | VERIFIED (code) | `OrchestratorClosedIndicators` overlaid in ContentView on the notch shape (overlay, no layout effect, no music condition); `needsAttention` = waiting run or non-empty promptOptions; hairline from `usageFraction`. Hidden only when offline/hello animation/hideOnClosed |
| 2 | Expand control grows same window downward | VERIFIED (code) | `OrchestratorExpand.expand` sets `pinnedFrame` with taller window, `openSize(for:)` hooked in `BoringViewModel.open()`, ContentView max height relaxed; chat tail of 28 lines in overlay |
| 3 | Live /term in WKWebView only while expanded, "terminal in use" | VERIFIED (code); typing is UAT | WKWebView created inside `isExp` branch, torn down in `dismantleNSView`; `terminalState` detects ttyd overlay text -> `.inUse`; `canBecomeKey` gated by `OrchestratorKeyGate`, `makeKey` + first responder on load |
| 4 | Click outside collapses | VERIFIED (code) | global+local mouse monitors -> `collapseIfOutside` -> collapse then `vm.close()`; `reset()` on notch close / view disappear; per-notch keyed state (review fixes WR-02/03/05, IN-03 applied) |
| 5 | Music unchanged | VERIFIED (static) | No music/MediaController files touched; only small hooks in ContentView/BoringViewModel/window |

Requirements CMP-01, CMP-02, EXP-01, EXP-02, EXP-03: all implemented in code; no orphaned requirements. Phase 2 dependency (typing into chat, `wantsKeyboard`) is on a parallel branch by design, not a gap; key gate here is terminal-only and ORs later.

## Notes (non-blocking)

- Window `canBecomeKey` now returns true while the terminal is shown; keyboard focus handoff and refocus of the previous app are unproven until run.
- ttyd single-client slot is freed only when WebKit deallocates the page (best-effort about:blank); check Retry after collapse/expand in UAT.

## Human Verification Required

See frontmatter list: closed-notch visuals (with and without music), expand/collapse visuals, typing in terminal and "terminal in use", click-outside collapse and focus return, music regression.
