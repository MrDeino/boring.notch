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

- [ ] **CMP-01**: With the notch closed, user sees a small Claude usage indicator
- [ ] **CMP-02**: With the notch closed, user sees a dot when any run is `waiting` or the chat shows a question/permission prompt — including while music is playing (small dot at the notch edge alongside the music activity; never hidden by music)
- [ ] **EXP-01**: User can expand the notch further downward (same window) to see a larger chat view
- [ ] **EXP-02**: In the expanded notch, user can see and type into the full live terminal (`/term` in a WKWebView)
- [ ] **EXP-03**: Clicking anywhere outside the expanded notch collapses it back

## v2 Requirements

- **V2-01**: Auto-open the notch when a prompt appears (toggle, default off)
- **V2-02**: Colour-coded attention dot (waiting run vs chat prompt)
- **V2-03**: Option buttons for multi-select prompts

## Out of Scope

| Feature | Reason |
|---------|--------|
| Spawning tmux/node/processes | App is sandboxed; HTTP API only |
| Separate terminal window/popover | Agreed design is expand-down inside the notch |
| Run controls (stop/resume/merge) from the notch | Orchestrator chat owns those; keeps the notch small |
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
| CMP-01 | Phase 3 | Pending |
| CMP-02 | Phase 3 | Pending |
| EXP-01 | Phase 3 | Pending |
| EXP-02 | Phase 3 | Pending |
| EXP-03 | Phase 3 | Pending |

**Coverage:** 20/20 v1 requirements mapped, no orphans. BLD-02 and BLD-03 are cross-cutting: mapped to Phase 1, re-checked by a music criterion in every phase.

---
*Requirements defined: 2026-10-14*
*Traceability updated: 2026-10-14 after roadmap creation*
