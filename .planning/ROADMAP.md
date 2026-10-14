# Roadmap: Boring Notch — Orchestrator Fork

## Overview

Three phases along the dependency chain build → manager → input → indicators/expand. Phase 1 proves the build and ships a read-only Orchestrator tab fed by one polling manager (including the pure `detectPrompt(screen)` the later phases rely on). Phase 2 adds sending: it starts with the gated key-window spike and real prompt-screen captures, then the message box, option buttons, Esc and Start/End. Phase 3 adds the closed-notch indicators and the expand-down mode with a larger chat and the live `/term` terminal. Music must keep working at the end of every phase.

## Phases

- [x] **Phase 1: Read-only Orchestrator Tab** - Fork builds from CLI; tab shows chat tail, runs, usage, offline state, with polling (completed 2026-10-14)
- [ ] **Phase 2: Sending & Prompt Answers** - Type messages, answer numbered prompts, Esc, start/end the chat from the notch
- [ ] **Phase 3: Compact Indicators & Expand-Down** - Closed-notch usage + attention dot; notch grows down for larger chat and live terminal

## Phase Details

### Phase 1: Read-only Orchestrator Tab

**Goal**: User can glance at the orchestrator (chat tail, runs, usage) from a new notch tab in a fork that builds from the command line, with music untouched
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: BLD-01, BLD-02, BLD-03, TAB-01, TAB-02, TAB-03, TAB-04, TAB-05, TAB-06
**Success Criteria** (what must be TRUE):

  1. `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... CODE_SIGN_IDENTITY=- ...` builds the fork ad-hoc with entitlements intact, and the diff to upstream is new files under `boringNotch/Orchestrator/` plus small hooks (enum case, tab entry, switch case, pbxproj group) with no new packages
  2. Opening the notch shows an "Orchestrator" tab beside the existing tabs; selecting it shows the trimmed chat tail, a compact runs strip (project, state, short prompt) and 5h/7d usage bars with reset times
  3. With `orch.js serve` stopped, the tab shows "orchestrator offline" with the 127.0.0.1:4777 hint within a few seconds, and recovers on its own when serve returns
  4. Data visibly refreshes about every 2s while the notch is open and polls more slowly while closed
  5. `detectPrompt(screen)` is a pure function with an assert-based check covering the idle input box (no prompt) and a numbered-options prompt; music playback controls, artwork and closed-notch music activity still work as before

**Plans:** 2/2 plans complete
Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Walking skeleton: tab hooks + polling manager (GET /api/chat) + chat tail, offline state, 2s/10s cadence, CLI build

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — Runs strip + 5h/7d usage bars (GET /api/state), detectPrompt + needsAttention, diff/music checks

**UI hint**: yes

### Phase 2: Sending & Prompt Answers

**Goal**: User can steer the orchestrator from the notch — send messages, answer its numbered prompts, cancel, and start or end the chat
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: INT-01, INT-02, INT-03, INT-04, INT-05, INT-06
**Success Criteria** (what must be TRUE):

  1. (Spike first) The notch panel takes keyboard focus only while the message box wants it (gated `canBecomeKey`, no app activation), and `detectPrompt` fixtures come from real captured question/permission screens
  2. User types a one-line message, presses Enter and sees it appear in the chat tail; the notch stays open while typing and releases on submit, Esc, outside click or close
  3. When a numbered prompt is on screen, user sees its options as buttons; tapping one sends only that digit once (no double-send), and an Esc control cancels the prompt
  4. When the chat is not running, a Start button starts it; an End button asks for inline confirmation and then stops it
  5. Music playback controls, artwork and closed-notch music activity still work as before

**Plans**: TBD
**UI hint**: yes

### Phase 3: Compact Indicators & Expand-Down

**Goal**: User notices when the orchestrator needs them with the notch closed, and can grow the notch downward for a larger chat or the full live terminal
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: CMP-01, CMP-02, EXP-01, EXP-02, EXP-03
**Success Criteria** (what must be TRUE):

  1. With the notch closed, user sees a small Claude usage indicator, and a dot appears when any run is `waiting` or the chat shows a prompt — and the dot still shows while music is playing on the closed notch (small dot at the notch edge alongside the music activity; a waiting question is never hidden — user decision 2026-10-14)
  2. An expand control grows the same notch window further down to show a larger chat view
  3. In the expanded notch, user can see and type into the live `/term` terminal (WKWebView created only while expanded; "terminal in use" shown if ttyd's single client is taken)
  4. Clicking anywhere outside the expanded notch collapses it back to normal size
  5. Music playback controls, artwork and closed-notch music activity still work as before

**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Read-only Orchestrator Tab | 2/2 | Complete   | 2026-10-14 |
| 2. Sending & Prompt Answers | 0/TBD | Not started | - |
| 3. Compact Indicators & Expand-Down | 0/TBD | Not started | - |
