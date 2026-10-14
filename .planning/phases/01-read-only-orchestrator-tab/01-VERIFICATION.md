---
phase: 01-read-only-orchestrator-tab
verified: 2026-10-14T00:45:00Z
status: human_needed
score: 5/5 must-haves verified (code level); runtime visuals need human
overrides_applied: 0
human_verification:
  - test: "Launch the built app (/tmp/notch-dd/Build/Products/Debug/Boring Notch.app), open the notch, select the Orchestrator tab"
    expected: "Tab sits beside Home (and Shelf if enabled); shows chat tail (8 lines), 5h/7d bars with reset times, up to 3 runs with state dot, project, short prompt; layout fits 640x190"
    why_human: "Visual layout cannot be checked without running the app"
  - test: "Stop `node orch.js serve`, watch the tab; restart serve"
    expected: "'orchestrator offline' + '127.0.0.1:4777' hint within a few seconds; recovers by itself"
    why_human: "Needs running app and toggling serve"
  - test: "Play music, check controls, artwork and closed-notch music activity; also toggle Shelf off in settings and confirm the Orchestrator tab still shows"
    expected: "Music unchanged; Orchestrator tab visible with Shelf disabled"
    why_human: "Runtime music behaviour"
  - test: "Watch network (or serve log) with notch open vs closed"
    expected: "About 2s polling open, 10s closed"
    why_human: "Timing observed at runtime"
---

# Phase 1: Read-only Orchestrator Tab Verification Report

**Phase Goal:** User can glance at the orchestrator (chat tail, runs, usage) from a new notch tab in a fork that builds from the command line, with music untouched.
**Verified:** 2026-10-14
**Status:** human_needed
**Re-verification:** No, initial verification

## Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | CLI ad-hoc xcodebuild builds; diff = new files under `boringNotch/Orchestrator/` plus small hooks; no new packages | VERIFIED | Ran the exact build: `** BUILD SUCCEEDED **`. Diff vs main (excluding .planning/CLAUDE.md): 4 new Orchestrator files, pbxproj +20 (group/file refs), ContentView +2, boringNotchApp +1, generic.swift +1 enum case, BoringViewModel +2, TabSelectionView and BoringHeader small edits. Entitlements and Package.resolved untouched. |
| 2 | Orchestrator tab beside existing tabs; shows chat tail, runs strip, 5h/7d bars with reset times | VERIFIED (code) | `.orchestrator` case, tab entry `Orchestrator`/`terminal.fill`, `case .orchestrator: OrchestratorView()` in ContentView. View renders `chatTail`, `stripRuns(limit:3)`, usage rows with reset times. Model keys (`five_hour`, `used_percentage`, `resets_at`, run `state`/`project`/`prompt`) match the live `/api/state` GET. Visual fit: human. |
| 3 | Serve stopped shows "orchestrator offline" + 127.0.0.1:4777 hint, auto-recovers | VERIFIED (code) | Any thrown error in `refresh()` sets `offline`; view shows text and hint; next poll clears `offline`. 3s request timeout on ephemeral session. Runtime: human. |
| 4 | Refresh ~2s open, slower closed | VERIFIED (code) | Poll loop sleeps 2s if `notchOpen` else 10s; `notchOpen` set in BoringViewModel open/close hooks; started from boringNotchApp at launch. |
| 5 | `detectPrompt` pure with assert check (idle box vs numbered options); music untouched | VERIFIED | swiftc test compiled and ran, output `OK`, exit 0. No music/MediaController files in diff. The only existing-behaviour change is Shelf gating (see note). |

**Score:** 5/5

### D-06: needsAttention independence

VERIFIED. `needsAttention` is a computed property of `runs` (any `state == "waiting"`) and `promptOptions` (from `detectPrompt` when chat running). Both are populated by the polling loop started at app launch. It reads no music, tab-selection, or notch-open state.

### Requirements Coverage

| Requirement | Source Plan | Status | Evidence |
|---|---|---|---|
| BLD-01 | 01-01, 01-02 | SATISFIED | Build succeeded with given command |
| BLD-02 | 01-02 | SATISFIED (code); runtime human | No music files touched |
| BLD-03 | 01-01, 01-02 | SATISFIED | New folder, small hooks, no packages |
| TAB-01 | 01-01 | SATISFIED | Tab + enum + switch case |
| TAB-02 | 01-01 | SATISFIED | `chatTail` fed from `/api/chat` |
| TAB-03 | 01-02 | SATISFIED | `stripRuns` + runsStrip |
| TAB-04 | 01-02 | SATISFIED | usage bars with reset times |
| TAB-05 | 01-01 | SATISFIED | offline view |
| TAB-06 | 01-01 | SATISFIED | 2s/10s loop |

All 9 IDs appear in PLAN frontmatter (01-01: BLD-01, BLD-03, TAB-01, TAB-02, TAB-05, TAB-06; 01-02: TAB-03, TAB-04, BLD-01, BLD-02, BLD-03) and in REQUIREMENTS.md. No orphans.

### Anti-Patterns

No TBD/FIXME/XXX in `boringNotch/Orchestrator`. One `ponytail:` note that the prompt format is assumed (refined in Phase 2); not a blocker. No stubs found; data flows from real GETs (live `/api/state` and `/api/chat` returned data).

### Notes (non-blocking)

- Existing-file edits go slightly beyond a pure hook: `BoringHeader.swift` no longer requires `boringShelf` for showing the tab bar, and `TabSelectionView` filters Shelf by the setting instead. This is needed so the Orchestrator tab shows with Shelf disabled; it changes upstream lines (2 modified), but Shelf behaviour is preserved. Worth a glance in the human music/Shelf check.
- `refresh()` fetches `/api/chat` and `/api/state` together, so one failing endpoint marks the whole tab offline. Acceptable for Phase 1.

## Gaps Summary

No gaps. Automated checks pass; runtime and visual behaviour are listed under human verification.

---
_Verified: 2026-10-14_
_Verifier: Claude (gsd-verifier)_
