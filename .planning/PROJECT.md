# Boring Notch — Orchestrator Fork

## What This Is

A personal fork of TheBoredTeam/boring.notch (Swift/SwiftUI macOS notch app, GPL-3.0) that adds an **Orchestrator** tab: from the notch the user can read and chat with their local Claude Code orchestrator, answer its question/permission prompts, start or end it, and watch its dispatched runs and Claude usage — while Boring Notch's music player keeps working as before.

## Core Value

Answer and steer the Claude Code orchestrator from the notch without switching to a terminal — and never break the music player doing it.

## Requirements

### Validated

- ✓ Notch window with open/closed states, tab bar (home, shelf) — existing
- ✓ Music / now-playing (MediaRemote adapter, Apple Music, Spotify) — existing
- ✓ Other stock features (calendar, battery, HUDs, shelf, webcam) — existing, not priorities

### Active

- [ ] Fork builds from the command line (xcodebuild, ad-hoc/unsigned, macOS 26)
- [ ] Orchestrator tab beside the existing tabs
- [ ] Tab shows tail of the orchestrator chat screen (GET /api/chat)
- [ ] Tab shows compact runs strip: project, status, short prompt (GET /api/state)
- [ ] Tab shows usage bars for 5h and 7d windows with reset times
- [ ] Tab shows "orchestrator offline" with a hint when serve is unreachable
- [ ] One-line message box; Enter sends text (POST /api/chat {text})
- [ ] When a Claude Code question/permission prompt with numbered options is on screen, show options as buttons that send the digit (POST /api/chat {key})
- [ ] Start button when chat not running (POST /api/chat/start); End button with confirm (POST /api/chat/stop)
- [ ] Closed notch: small usage indicator + attention dot when any run is `waiting` or the chat shows a prompt
- [ ] Expand control: notch grows further DOWN (same window, not a new one) to show the live terminal (/term in a WKWebView) or a larger chat view; clicking outside collapses it
- [ ] Polling ~2s while open, slower while closed

### Out of Scope

- Spawning tmux, node, or any process from the app — sandboxed; HTTP API only
- Separate windows / popovers for the terminal — expand-down inside the notch was agreed
- Upstream contribution — personal fork; only keep it mergeable
- Improving stock features beyond music — not used
- Code signing / notarization / distribution — local ad-hoc build only
- New third-party dependencies — not needed (URLSession, WebKit are system)

## Context

- Repo: fork of TheBoredTeam/boring.notch. `origin` = MrDeino/boring.notch, `upstream` = TheBoredTeam. Existing SPM deps: Defaults, KeyboardShortcuts, SkyLightWindow, Sparkle, Lottie, etc.
- Tabs: `NotchViews` enum (`boringNotch/enums/generic.swift`: home, shelf), `components/Tabs/TabSelectionView.swift`, rendered from `ContentView.swift`. Notch sizing in `boringNotch/sizing/`.
- App is sandboxed with `com.apple.security.network.client` already in `boringNotch.entitlements`.
- Orchestrator: Claude Code chat in tmux session `orchestrator`, served by `node orch.js serve` at `http://127.0.0.1:4777` (LaunchAgent, always on).
  - `GET /api/state` → `{runs:[{id, project, state: running|waiting|done|failed|stopped|stuck, prompt}]  (field is `state`, not `status`), sessions, events, usage:{five_hour:{used_percentage, resets_at}, seven_day:{…}}}` (resets_at = epoch seconds)
  - `GET /api/chat` → `{running: bool, screen: string}` (plain text, last ~200 lines)
  - `POST /api/chat` (header `x-orch: 1`) JSON `{text}` (types text + Enter) or `{key}` ∈ Enter, Escape, Up, Down, Tab, 1–9. 409 if not running.
  - `POST /api/chat/start`, `POST /api/chat/stop` (header `x-orch: 1`); dispatched runs unaffected.
  - `/term` — ttyd web terminal; its websocket requires `Origin: http://127.0.0.1:4777`, which a WKWebView loading that URL satisfies.
- ATS/sandbox already allow it: Info.plist has `NSAllowsArbitraryLoads`, entitlements have `network.client`. No changes needed.
- Notch windows hard-code `canBecomeKey = false` (non-activating panel) — typing needs a gated key-window hook.
- Tabs only show when Shelf is enabled (`BoringHeader.swift:19`).
- Build proven 2026-10-14: `xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build` → BUILD SUCCEEDED (ad-hoc; keep entitlements, don't use CODE_SIGNING_ALLOWED=NO).

## Constraints

- **Upstream mergeability**: keep the diff to upstream small and isolated — new files where possible, minimal hooks into existing files.
- **Music**: must not regress now-playing/music controls.
- **Dependencies**: no new third-party packages unless unavoidable.
- **Sandbox**: talk to the orchestrator only over the HTTP API; never spawn processes.
- **Build**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild`, local unsigned/ad-hoc, macOS 26.
- **Git**: never push; stay on the current branch, no GSD phase/milestone branches.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| HTTP API only (URLSession) | App is sandboxed; serve already exposes everything | — Pending |
| Expand grows notch downward, not a new window | Agreed design; keeps it feeling like the notch | — Pending |
| Terminal via WKWebView on /term | ttyd already served; Origin check satisfied by loading that URL | — Pending |
| Poll ~2s open, slower closed | Cheap, no push channel available | — Pending |
| New files for orchestrator code, small hooks into tabs/ContentView | Keep upstream merges easy | — Pending |
| Attention dot still shows over music on the closed notch (small dot at notch edge alongside music) | A waiting question must never be hidden (user, 2026-10-14) | — Pending (built in Phase 3) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-14 after initialization*
