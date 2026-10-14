# Roadmap: Boring Notch — Orchestrator Fork

## Overview

Three phases along the dependency chain build → manager → input → indicators/expand. Phase 1 proves the build and ships a read-only Orchestrator tab fed by one polling manager (including the pure `detectPrompt(screen)` the later phases rely on). Phase 2 adds sending: it starts with the gated key-window spike and real prompt-screen captures, then the message box, option buttons, Esc and Start/End. Phase 3 adds the closed-notch indicators and the expand-down mode with a larger chat and the live `/term` terminal. Music must keep working at the end of every phase.

Phases 4–9 rebuild the tab to the high-fidelity design handoff (option 2a, `.planning/design/orchestrator-2a/README.md`). Phase 4 lays the foundation (tokens, view split, header capsule, status menu, empty states, shared seams). Phases 5, 6 and 7 then run in parallel on separate branches and merge: each lives in its own new files and touches shared files only at documented merge points. Phases 8 and 9 are Phase B of the handoff and need serve-side work.

## Phases

- [x] **Phase 1: Read-only Orchestrator Tab** - Fork builds from CLI; tab shows chat tail, runs, usage, offline state, with polling (verified; human UAT passed 2026-10-14)
- [ ] **Phase 2: Sending & Prompt Answers** - Type messages, answer numbered prompts, Esc, start/end the chat from the notch (built and verified at code level 2026-10-14; awaiting human UAT)
- [ ] **Phase 3: Compact Indicators & Expand-Down** - Closed-notch usage + attention dot; notch grows down for larger chat and live terminal (built and verified at code level 2026-10-14; awaiting human UAT)
- [x] **Phase 4: 2a Foundation** - Design tokens, OrchestratorView split, Chat | Runs segment + status capsule header, status menu, stopped/offline/connecting screens, shared seams for 5–7 (completed 2026-10-14)
- [x] **Phase 5: 2a Structured Chat** - Transcript rows from serve's GET /api/chat/blocks, live status, composer and message box (suggestion, Tab, ⌃U, terminal draft), row-insert motion (parallel with 6, 7) (completed 2026-10-14)
- [x] **Phase 6: 2a Prompt Cards** - Permission decision card, vertical question list, richer detectPrompt, 1–9/esc while hovered, 'Something else…' and 'Chat about this' (parallel with 5, 7) (completed 2026-10-14)
- [x] **Phase 7: 2a Runs Board, Expand Levels & Wings** - Runs board, open→expanded→terminal levels with runs rail, closed-notch live-activity wings (parallel with 5, 6) (completed 2026-10-14)
- [x] **Phase 8: Phase B Live Data** - SSE push from serve, streaming caret, ▸ diff expansion, suggested flag, context % (completed 2026-10-14)
- [x] **Phase 9: Phase B Approvals** - Closed-notch approval drop-down, global ⌥⏎/⌥⎋, Claude Code hook posting to serve, panel frame sized to content (completed 2026-10-14)

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

**Plans:** 2/2 plans complete
Plans:
**Wave 1**

- [x] 02-01-PLAN.md — detectPrompt tuned to real captured screens + Foundation-only POST client (mock-server tested)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — Message box with gated canBecomeKey + keep-open, option buttons, Esc, Start/End confirm
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

**Plans:** 2/2 plans complete
Plans:
**Wave 1**

- [x] 03-01-PLAN.md — Closed-notch attention dot (shown with music) + usage hairline overlay

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 03-02-PLAN.md — Expand-down: same window grows to larger chat, live /term terminal (gated key), click-outside collapse

**UI hint**: yes

### Phase 4: 2a Foundation — tokens, view split, status capsule header, status menu, stopped/offline/connecting

**Goal**: The Orchestrator tab has the 2a shell — tokens, split view files, a header with the Chat | Runs segment and one status capsule (with its status menu), and the stopped/offline/connecting screens — with every current feature still working and the shared seams Phases 5–7 build on in place
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: FND-01, FND-02, FND-03, FND-04, FND-05, FND-06, FND-07
**Design**: `.planning/design/orchestrator-2a/README.md` — Header, frames 06, 07, 08, 09, Design tokens
**Success Criteria** (what must be TRUE):

  1. Orchestrator colours, type sizes and radii come from one tokens file matching the handoff's Design tokens; `OrchestratorView.swift` is a thin shell and Chat, PromptCard, RunsBoard and StatusCapsule live in their own files
  2. The open-notch header shows the Chat | Runs N segment (count orange while a run waits, hidden offline) and a single status capsule in the six specified variants; `OrchestratorUsageBadge`, `OrchestratorChatButton` and `OrchestratorRunsButton` are gone from the header
  3. Clicking the capsule opens the status menu inside the notch with 5h/7d usage and resets, Open terminal, Interrupt (1s debounce kept), End chat with 4s confirm (Start chat when stopped), and the transcript dims to 35%
  4. Stopped, offline and connecting states show the specified copy and layout; message box, prompt options, Esc, expand/terminal, attention dot and usage hairline still work
  5. Music playback controls, artwork and closed-notch music activity still work as before

**Plans:** 3/3 plans complete

Plans:
- [x] 04-01-PLAN.md — Seams + tokens: pure helpers (PromptCard, parseLiveStatus, capsuleState, pollInterval, ExpandLevel), Phase4-7 test runners, 11 files registered in pbxproj, manager + expand hooks
- [x] 04-02-PLAN.md — View split (Chat, PromptCard, RunsBoard), stopped/offline/connecting screens, thin shell with expand-level hook
- [x] 04-03-PLAN.md — Chat | Runs segment, status capsule + usage ring, in-notch status menu, BoringHeader swap

**UI hint**: yes

### Phase 5: 2a Structured chat — transcript rows from /api/chat/blocks, composer and message box

**Goal**: The chat reads like Claude Code — typed transcript rows from serve's transcript endpoint, a live working status, and a composer that mirrors Claude Code's input box
**Mode:** mvp
**Depends on**: Phase 4 (runs in parallel with Phases 6 and 7)
**Requirements**: CHAT-01, CHAT-02, CHAT-03, CHAT-04, CHAT-05
**Design**: README frames 01, 02, 02b; Interactions and motion
**Success Criteria** (what must be TRUE):

  1. Transcript rows (user ❯, tool chip + target + result + +/−, prose) come from `GET /api/chat/blocks?since=<id>` (`{id, kind, text}` / tool `{name, target, result, added, removed, diff}`), fetched incrementally — not from screen parsing — and the tab still shows a usable chat when serve lacks the endpoint
  2. A "✻ Working · 0:41  esc to interrupt" status row, read from the screen, shows while Claude is working
  3. The composer matches frame 02 (pill, focus ring, send button, hint row) using the existing key-gate typing logic unchanged
  4. The message box shows Claude Code's suggestion as ghost text with Tab/→ accept (also POSTs Tab), ⌃U clears locally and POSTs `{key:"C-u"}` with a "line cleared" tag, and a terminal draft is pulled in on focus with "from terminal · "
  5. New rows animate in from the bottom; clicking the transcript still opens the terminal; music unaffected

**Plans:** 3/3 plans complete

Plans:
- [x] 05-01-PLAN.md — Transcript pure core (TDD): blocks decode (both shapes), merge by id, since-chain reset, input-box parse, ghost-vs-draft, clear-to-caret, tool display strings
- [x] 05-02-PLAN.md — Blocks store (GET /api/chat/blocks?since=, chatTail fallback), frame 01 rows, live/idle status rows, insert motion
- [x] 05-03-PLAN.md — Frame 02/02b composer: pill, ring, hint row, ghost suggestion + Tab/→ accept, ⌃U (C-u), terminal draft, C-u before send, UAT list

**Merge points:** no shared-file edits (state on OrchestratorTranscriptStore); OrchestratorChatView gains only defaulted init params

**UI hint**: yes

### Phase 6: 2a Prompt cards — permission decision card and question list

**Goal**: Claude Code's permission and question prompts appear as designed decision cards the user can answer by click or key
**Mode:** mvp
**Depends on**: Phase 4 (runs in parallel with Phases 5 and 7)
**Requirements**: PRM-01, PRM-02, PRM-03, PRM-04, PRM-05
**Design**: README frames 03, 04
**Success Criteria** (what must be TRUE):

  1. `detectPrompt` also returns title, purpose/body, kind (permission/question), header tag and progress, verified against `Tests/fixtures/permission.txt` and `question.txt`
  2. A permission prompt shows the frame 03 card (title, purpose, `$` command block, option pills with shortened labels and full-label tooltip, deny pushed right with esc); after a press the chosen pill fills and the others dim for the 3s lock
  3. A question prompt shows the frame 04 vertical list (header tag, "1 of 2", wrapping question, option rows with the ❯ default highlighted, ↑/↓/⏎), grows the notch via expand-down and scrolls on overflow
  4. 1–9 and esc answer while the pointer is over the notch; "Something else…" sends its option number then the typed text, and "Chat about this" sends its number
  5. Music playback controls, artwork and closed-notch music activity still work as before

**Plans:** 3/3 plans complete

Plans:
- [x] 06-01-PLAN.md — Parser: detectPromptCard title/purpose/body/kind/header/progress/descriptions/default, shortLabel, promptIdentity, key mapping; real + synthetic fixtures
- [x] 06-02-PLAN.md — Frame 03 permission card and frame 04 question list, stale-prompt guard, 3s lock dim, setLevel(.expanded) for questions, Chat about this, esc
- [x] 06-03-PLAN.md — 1–9/esc/↑↓/⏎ while hovered (gated key-take + local monitor), 'Something else…' free text, phase checks, UAT list

**Merge points:** no shared-file edits

**UI hint**: yes

### Phase 7: 2a Runs board, expand levels and closed-notch wings

**Goal**: User sees runs as cards, can step the notch open → expanded → terminal with a runs rail, and gets live-activity wings on the closed notch — without disturbing the music live activity
**Mode:** mvp
**Depends on**: Phase 4 (runs in parallel with Phases 5 and 6)
**Requirements**: RUN-01, RUN-02, RUN-03, RUN-04, RUN-05
**Design**: README frames 00, 05, 10, 11, 12, 12b
**Success Criteria** (what must be TRUE):

  1. The Runs segment shows frame 05 cards (dot, project, elapsed, prompt, latest action; live first; state colours); a waiting card shows the run's question and a button that sends that context into the orchestrator chat — no Allow/Deny/resume of runs from the notch
  2. The notch steps open → expanded (640×~440) → terminal and back (click transcript / ⌘↓, esc / ⌘↑, click outside closes) with one continuous spring and a delayed content cross-fade; outside-click, monitor and key-release logic kept
  3. Expanded shows the conversation column, a runs rail with usage bars and a Terminal ⌘T pill; the terminal sits in the frame 10 frame with in use / unavailable + Retry
  4. The rail collapses to the 30px strip (‹ or ⌘\), persists in `Defaults` `orchRunsRailCollapsed`, and re-opens when a run starts waiting unless collapsed this session
  5. The closed notch shows Working / Needs you / Run finished wings and the usage hairline; with music playing the music live activity is unchanged apart from a 7px orange dot; closed polling drops to 3s while the chat runs

**Plans:** 5/5 plans complete

Plans:
**Wave 1**
- [x] 07-01-PLAN.md — OrchestratorRun fields + pure helpers (TDD): elapsed, latest action, waiting question, Ask-in-chat message, sort, pollInterval 3s, nextLevel, expandedHeight, wing kind/width

**Wave 2** *(blocked on 07-01; disjoint files — run ONE AT A TIME, user 2026-10-14: commit-range checks assume serial commits)*
- [x] 07-02-PLAN.md — Runs board (frame 05), waiting card with question + Ask in chat (no Allow/Deny), bottom status line
- [x] 07-03-PLAN.md — Closed-notch wings (frame 00), music dot overlay, corner-dot hide, radius 26 (ContentView: one else-if after music)
- [x] 07-04-PLAN.md — Expand level machine, ⌘ shortcut monitor, transcriptTapped → .expanded, framed terminal (frame 10), ⌃ collapse button

**Wave 3** *(blocked on Wave 2)*
- [x] 07-05-PLAN.md — Expanded body (frame 12), runs rail + 30px strip (12b), orchRunsRailCollapsed, auto re-open, cross-fade, UAT list

**Merge points:** OrchestratorRun fields (Models), ContentView wing hook, OrchestratorHeaderTrailing — all Phase 7-only

**UI hint**: yes

### Phase 8: Phase B live data — SSE push, streaming caret, diff expansion, suggested flag, context percent

**Goal**: The notch updates live from serve pushes instead of polling, with streaming text, inline diffs, an exact suggestion flag and context usage
**Mode:** mvp
**Depends on**: Phases 5, 6, 7 (merged); needs serve changes in the orchestrator repo
**Requirements**: LIVE-01, LIVE-02, LIVE-03, LIVE-04, LIVE-05
**Design**: README Phase B notes; frames 01 (caret, ▸ diff), 02b (suggested), 12 (Edit card), capsule ctx %
**Success Criteria** (what must be TRUE):

  1. The manager consumes a serve SSE stream (`URLSession.bytes`) for chat blocks and state, falling back to polling when the stream is unavailable
  2. Streaming assistant text shows the 7×13 `#D97757` caret
  3. ▸ diff expands an Edit row into the frame 12 diff card (removed/added/context line colours)
  4. The input box ghost text uses serve's `{text, suggested}` (from `tmux capture-pane -e`) instead of guessing
  5. The Running capsule shows "ctx N%"; music unaffected

**Plans:** 3/3 plans complete

Plans:
- [x] 08-01-PLAN.md — serve `input`/`context` in the chat payload: exact ghost text (LIVE-04), ctx N% capsule (LIVE-05), split apply path
- [x] 08-02-PLAN.md — SSE `/api/events` consumer with polling fallback and 30 s retry (LIVE-01)
- [x] 08-03-PLAN.md — streaming caret (LIVE-02) and ▸ diff frame 12 card (LIVE-03)

**UI hint**: yes

### Phase 9: Phase B approvals — closed-notch approval drop-down, global shortcuts, hook to serve, panel frame sized to content

**Goal**: User can approve or deny the orchestrator's tool calls from a closed-notch drop-down or global shortcut, and the panel sizes itself to its content
**Mode:** mvp
**Depends on**: Phase 8; needs a Claude Code hook and serve changes in the orchestrator repo
**Requirements**: APR-01, APR-02, APR-03, APR-04
**Design**: README frame 00 approval drop-down, Phase B notes (1e)
**Success Criteria** (what must be TRUE):

  1. A Claude Code PreToolUse/Notification hook posts pending approvals to serve, and the notch learns of them without screen parsing
  2. With the notch closed, a pending approval drops down the 460px panel ("Orchestrator wants to run", command block, Allow ⌥⏎ / Deny ⌥⎋ / More…)
  3. ⌥⏎ and ⌥⎋ answer the pending approval globally, without the notch being focused, using a sandbox-safe hotkey API
  4. The panel frame follows content size instead of the fixed `windowSize` plus a separate expand step; music unaffected

**Plans:** 3/3 plans complete

Plans:
**Wave 1**
- [x] 09-01-PLAN.md — Approval from serve (`approval` on GET /api/chat + stream) -> frame 00 closed-notch drop-down, Allow/Deny/More… via POST /api/chat {key} behind the freshness gate (APR-01, APR-02)

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 09-02-PLAN.md — Global ⌥⏎/⌥⎋ via KeyboardShortcuts, registered only while pending; 15.0/15.1 ⌃⌥ fallback (APR-03)

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 09-03-PLAN.md — One sizer: panel window height from vm.notchSize.height (`panelHeight` + `OrchestratorExpand.fit`), top edge pinned, music unchanged (APR-04)

**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Read-only Orchestrator Tab | 2/2 | Complete   | 2026-10-14 |
| 2. Sending & Prompt Answers | 2/2 | Awaiting UAT | - |
| 3. Compact Indicators & Expand-Down | 2/2 | Awaiting UAT | - |
| 4. 2a Foundation | 3/3 | Awaiting UAT | - |
| 5. 2a Structured Chat | 3/3 | Complete   | 2026-10-14 |
| 6. 2a Prompt Cards | 3/3 | Complete   | 2026-10-14 |
| 7. 2a Runs Board, Expand Levels & Wings | 5/5 | Complete   | 2026-10-14 |
| 8. Phase B Live Data | 3/3 | Complete    | 2026-10-14 |
| 9. Phase B Approvals | 3/3 | Complete   | 2026-10-14 |
