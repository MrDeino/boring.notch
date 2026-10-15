# Requirements: Boring Notch — Orchestrator Fork

**Defined:** 2026-10-14
**Core Value:** Answer and steer the Claude Code orchestrator from the notch without switching to a terminal — and never break the music player doing it.

## v1 Requirements

### Build & Integrity

- [x] **BLD-01**: The fork builds from the command line with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild` (ad-hoc signed, entitlements intact)
- [x] **BLD-02**: Music / now-playing (playback controls, artwork, closed-notch music activity) works exactly as before after every phase
- [x] **BLD-03**: Orchestrator code lives in new files under one folder; upstream files get only small, isolated hooks; no new third-party dependencies

### Orchestrator Tab (read-only)

- [x] **TAB-01**: User can open an "Orchestrator" tab beside the existing tabs in the opened notch
- [x] **TAB-02**: User sees the tail of the orchestrator chat screen (from `GET /api/chat`), trimmed to fit
- [x] **TAB-03**: User sees a compact runs strip: project, state, short prompt per run (from `GET /api/state`)
- [x] **TAB-04**: User sees usage bars for the 5-hour and 7-day windows with their reset times
- [x] **TAB-05**: User sees "orchestrator offline" with a hint (serve on 127.0.0.1:4777) when serve is unreachable
- [x] **TAB-06**: Data refreshes about every 2s while the notch is open and more slowly while closed

### Interaction

- [ ] **INT-01**: User can type a one-line message and press Enter to send it to the orchestrator (`POST /api/chat {text}`)
- [ ] **INT-02**: When a Claude Code question/permission prompt with numbered options is on screen, user sees its options as buttons; tapping one sends that digit (`{key}`)
- [ ] **INT-03**: User can cancel a prompt with an Esc control
- [ ] **INT-04**: When the chat is not running, user sees a Start button that starts it (`POST /api/chat/start`)
- [ ] **INT-05**: User can end the chat with an End button after confirming (`POST /api/chat/stop`)
- [ ] **INT-06**: The notch stays open while the user is typing in the message box

### Compact & Expand

- [x] **CMP-01**: With the notch closed, user sees a small Claude usage indicator
- [x] **CMP-02**: With the notch closed, user sees a dot when any run is `waiting` or the chat shows a question/permission prompt — including while music is playing (small dot at the notch edge alongside the music activity; never hidden by music)
- [x] **EXP-01**: User can expand the notch further downward (same window) to see a larger chat view
- [x] **EXP-02**: In the expanded notch, user can see and type into the full live terminal (`/term` in a WKWebView)
- [x] **EXP-03**: Clicking anywhere outside the expanded notch collapses it back

## v1.1 Requirements — 2a redesign (design: `.planning/design/orchestrator-2a/README.md`)

### Foundation (Phase 4)

- [x] **FND-01**: Orchestrator views take colours, type sizes, radii and spacing from one tokens file that matches the handoff's Design tokens
- [x] **FND-02**: `OrchestratorView.swift` is a thin shell; Chat, PromptCard, RunsBoard and StatusCapsule live in their own files, behaviour unchanged
- [x] **FND-03**: The open-notch header shows a Chat | Runs N segment (count orange while a run waits, gray otherwise, hidden offline) that replaces `OrchestratorRunsButton`
- [x] **FND-04**: The header shows one status capsule (Running / Idle / Needs you / Stopped / Offline / Connecting, 12px 5h usage ring) that replaces `OrchestratorUsageBadge` and `OrchestratorChatButton`
- [x] **FND-05**: Clicking the capsule opens the status menu inside the notch: 5h/7d usage with resets and bars, Open terminal, Interrupt (1s debounce), End chat with 4s confirm or Start chat when stopped; the content dims to 35% while open
- [x] **FND-06**: Stopped (07), offline (08) and connecting (09) screens match the handoff copy and layout
- [x] **FND-07**: Shared seams for the parallel phases exist: `PromptCard` model and `manager.prompt`, live-status parse (`manager.liveStatus` with elapsed), and an expand-level API on `OrchestratorExpand`

### Structured chat (Phase 5)

- [x] **CHAT-01**: Transcript rows (user, tool, prose) come from `GET /api/chat/blocks?since=<id>`, fetched incrementally, with a working fallback while serve lacks the endpoint
- [x] **CHAT-02**: A live "✻ Working · elapsed · esc to interrupt" status row, read from the screen, shows while Claude works
- [x] **CHAT-03**: The composer matches frame 02 (pill, focus ring, send button, hint row) using the existing key-gate typing logic
- [x] **CHAT-04**: The message box mirrors Claude Code's input box: suggestion ghost text with Tab/→ accept (POST Tab), ⌃U clear with POST `{key:"C-u"}` and a "line cleared" tag, terminal draft pulled in on focus
- [x] **CHAT-05**: New transcript rows animate in from the bottom; clicking the transcript opens the terminal

### Prompt cards (Phase 6)

- [x] **PRM-01**: `detectPrompt` returns title, purpose/body, kind, header tag and progress as well as options, tested on the captured fixtures
- [x] **PRM-02**: Permission prompts show the frame 03 decision card with shortened option labels, tooltips, esc deny and the 3s press lock
- [x] **PRM-03**: Question prompts show the frame 04 vertical list with the ❯ default highlighted, ↑/↓/⏎, growing via expand-down and scrolling on overflow
- [x] **PRM-04**: 1–9 and esc answer the prompt while the pointer is over the notch
- [x] **PRM-05**: "Something else…" sends its option number then typed text; "Chat about this" sends its number

### Runs, expand levels, wings (Phase 7)

- [x] **RUN-01**: The Runs segment shows frame 05 run cards; a waiting card shows the run's question and a button that sends that context into the orchestrator chat (no direct Allow/Deny/resume)
- [x] **RUN-02**: The notch steps open → expanded → terminal and back with the specified triggers and motion, keeping the existing outside-click/monitor/key-release logic
- [x] **RUN-03**: Expanded (12) shows the conversation column, runs rail with usage bars and a Terminal ⌘T pill; the terminal (10) has the framed toolbar and in use / unavailable + Retry
- [x] **RUN-04**: The runs rail collapses to a 30px strip (12b), persisted in `Defaults` `orchRunsRailCollapsed`, and auto re-opens on a newly waiting run unless collapsed this session
- [x] **RUN-05**: The closed notch shows Working / Needs you / Run finished wings and the usage hairline; music's live activity is unchanged apart from a 7px orange needs-you dot; closed polling is 3s while the chat runs

### Phase B live data (Phase 8)

- [x] **LIVE-01**: The manager consumes serve's SSE stream for blocks and state, falling back to polling
- [x] **LIVE-02**: Streaming assistant text shows the caret
- [x] **LIVE-03**: ▸ diff expands an Edit row into the diff card
- [x] **LIVE-04**: Input-box ghost text uses serve's `suggested` flag (`capture-pane -e`)
- [x] **LIVE-05**: The Running capsule shows context %

### Phase B approvals (Phase 9)

- [x] **APR-01**: A Claude Code PreToolUse/Notification hook posts pending approvals to serve
- [x] **APR-02**: The closed notch drops down the approval panel (Allow ⌥⏎ / Deny ⌥⎋ / More…)
- [x] **APR-03**: ⌥⏎ / ⌥⎋ answer the pending approval globally via a sandbox-safe hotkey API
- [x] **APR-04**: The panel frame is sized to its content instead of the fixed `windowSize` plus an expand step

## v2 Requirements

- **V2-01**: Auto-open the notch when a prompt appears (toggle, default off)
- **V2-02**: Colour-coded attention dot (waiting run vs chat prompt)
- **V2-03**: Option buttons for multi-select prompts

## Out of Scope

| Feature | Reason |
|---------|--------|
| Spawning tmux/node/processes | App is sandboxed; HTTP API only |
| Separate terminal window/popover | Agreed design is expand-down inside the notch |
| Run controls (stop/resume/merge, Allow/Deny on run cards) from the notch | Orchestrator chat owns those; waiting run cards send their context into the chat instead (user, 2026-10-14) |
| Auto-approve prompts | Unsafe |
| ANSI terminal emulation in SwiftUI | `/term` WKWebView covers full fidelity |
| Multi-line composer, notifications | Not requested |
| Improving stock features other than music | Not used |
| Signing/notarization/distribution, upstream PRs | Personal local build |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| BLD-01 | Phase 1 | Complete |
| BLD-02 | Phase 1 | Complete |
| BLD-03 | Phase 1 | Complete |
| TAB-01 | Phase 1 | Complete |
| TAB-02 | Phase 1 | Complete |
| TAB-03 | Phase 1 | Complete |
| TAB-04 | Phase 1 | Complete |
| TAB-05 | Phase 1 | Complete |
| TAB-06 | Phase 1 | Complete |
| INT-01 | Phase 2 | Pending |
| INT-02 | Phase 2 | Pending |
| INT-03 | Phase 2 | Pending |
| INT-04 | Phase 2 | Pending |
| INT-05 | Phase 2 | Pending |
| INT-06 | Phase 2 | Pending |
| CMP-01 | Phase 3 | Complete |
| CMP-02 | Phase 3 | Complete |
| EXP-01 | Phase 3 | Complete |
| EXP-02 | Phase 3 | Complete |
| EXP-03 | Phase 3 | Complete |
| FND-01 | Phase 4 | Complete |
| FND-02 | Phase 4 | Complete |
| FND-03 | Phase 4 | Complete |
| FND-04 | Phase 4 | Complete |
| FND-05 | Phase 4 | Complete |
| FND-06 | Phase 4 | Complete |
| FND-07 | Phase 4 | Complete |
| CHAT-01 | Phase 5 | Complete |
| CHAT-02 | Phase 5 | Complete |
| CHAT-03 | Phase 5 | Complete |
| CHAT-04 | Phase 5 | Complete |
| CHAT-05 | Phase 5 | Complete |
| PRM-01 | Phase 6 | Complete |
| PRM-02 | Phase 6 | Complete |
| PRM-03 | Phase 6 | Complete |
| PRM-04 | Phase 6 | Complete |
| PRM-05 | Phase 6 | Complete |
| RUN-01 | Phase 7 | Complete |
| RUN-02 | Phase 7 | Complete |
| RUN-03 | Phase 7 | Complete |
| RUN-04 | Phase 7 | Complete |
| RUN-05 | Phase 7 | Complete |
| LIVE-01 | Phase 8 | Complete |
| LIVE-02 | Phase 8 | Complete |
| LIVE-03 | Phase 8 | Complete |
| LIVE-04 | Phase 8 | Complete |
| LIVE-05 | Phase 8 | Complete |
| APR-01 | Phase 9 | Complete |
| APR-02 | Phase 9 | Complete |
| APR-03 | Phase 9 | Complete |
| APR-04 | Phase 9 | Complete |

**Coverage:** 20/20 v1 and 31/31 v1.1 requirements mapped, no orphans. BLD-02 and BLD-03 are cross-cutting: mapped to Phase 1, re-checked by a music criterion in every phase.

---
*Requirements defined: 2026-10-14*
*Traceability updated: 2026-10-14 after roadmap creation*
