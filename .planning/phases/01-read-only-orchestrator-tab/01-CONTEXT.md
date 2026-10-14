# Phase 1: Read-only Orchestrator Tab - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator dispatch brief (user decisions relayed from the orchestrator chat)

<domain>
## Phase Boundary

Fork builds from the CLI; a new "Orchestrator" tab in the opened notch shows the chat tail, a runs strip, 5h/7d usage bars and an offline state, fed by one polling manager. Includes the pure `detectPrompt(screen)` function with one assert-style test. Read-only: GET requests only. No sending, no closed-notch indicators, no expand-down (Phases 2 and 3).

</domain>

<decisions>
## Implementation Decisions

### API & networking
- D-01: Only `GET /api/state` and `GET /api/chat` against `http://127.0.0.1:4777` in this phase. No POST of any kind.
- D-02: Run status field is `state` (running|waiting|done|failed|stopped|stuck), not `status`. Usage `resets_at` is epoch seconds. Decode leniently (optional fields) so server additions never break decoding.
- D-03: Own `URLSession(configuration: .ephemeral)` with ~3s request timeout; connection errors/timeouts → offline state showing the `127.0.0.1:4777` / `node orch.js serve` hint; recovers automatically.

### Polling
- D-04: One `@MainActor` `ObservableObject` singleton (`OrchestratorManager.shared`), `Task` + `Task.sleep` loop: ~2s while the notch is open, slower (e.g. ~10s) while closed. Polling continues while closed (Phase 3 needs fresh data for closed-notch indicators).

### Prompt detection
- D-05: `detectPrompt(screen:)` is a pure function returning the numbered options (or nil/empty) for Claude Code question/permission prompts (e.g. `❯ 1. Yes`). One runnable assert-based test covering the idle input box (no prompt) and a numbered-options prompt. Fixtures refined from real captures in Phase 2.

### Attention state (forward-compat for Phase 3)
- D-06: User decision 2026-10-14: while music is playing on the closed notch, the "orchestrator needs you" attention dot STILL shows (small dot at the notch edge alongside the music activity) — a waiting question must never be hidden. Built in Phase 3. Phase 1 must not design anything that rules it out: the manager exposes a derived `needsAttention` (any run `waiting` OR `detectPrompt` finds a prompt) that is independent of music/now-playing state and not gated on the tab being selected or the notch being open.

### Integration / diff hygiene
- D-07: All new code under `boringNotch/Orchestrator/`; upstream hooks limited to: `NotchViews` enum case, tab entry in `TabSelectionView`, switch case in `ContentView`, pbxproj group/file refs. No new packages. Music/now-playing code untouched.
- D-08: Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/<dir> build`. Never touch `/Applications/boringNotch.app`, never launch apps.

### Claude's Discretion
- Exact layout/styling of chat tail, runs strip and usage bars (follow existing notch view styling, SF Symbols, `Capsule`/`ProgressView` bars).
- How tabs show when Shelf is disabled (`BoringHeader.swift:19`): either document it or add one minimal hook — keep the diff small.
- How the prompt-detection test is run (an XCTest target if one exists, otherwise a standalone `swiftc`-compiled assert script over the pure function file).
- Closed-notch poll interval exact value.

</decisions>

<canonical_refs>
## Canonical References

- `.planning/PROJECT.md` — API shapes, build command, constraints
- `.planning/REQUIREMENTS.md` — BLD-01..03, TAB-01..06
- `.planning/research/SUMMARY.md`, `ARCHITECTURE.md`, `PITFALLS.md`, `STACK.md`, `FEATURES.md`
- `boringNotch/enums/generic.swift` (`NotchViews`), `boringNotch/components/Tabs/TabSelectionView.swift`, `boringNotch/ContentView.swift`, `boringNotch/components/Notch/BoringHeader.swift`
- `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicNetworking.swift` — URLSession/Codable template

</canonical_refs>

<specifics>
## Specific Ideas

- Live serve is running at 127.0.0.1:4777; capture real `/api/state` and `/api/chat` JSON with `curl` (GET only) to build Codable models.

</specifics>

<deferred>
## Deferred Ideas

- Sending, option buttons, Esc, Start/End, key-window spike — Phase 2
- Closed-notch usage indicator + attention dot (shown alongside music) and expand-down — Phase 3

</deferred>

---

*Phase: 01-read-only-orchestrator-tab*
*Context gathered: 2026-10-14 from dispatch brief*
