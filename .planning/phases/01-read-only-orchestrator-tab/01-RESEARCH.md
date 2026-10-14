# Phase 1: Read-only Orchestrator Tab - Research

**Researched:** 2026-10-14
**Domain:** SwiftUI/AppKit macOS app hooks, URLSession+Codable polling, Xcode project editing
**Confidence:** HIGH (everything below was read from the repo or captured live this session)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: Only `GET /api/state` and `GET /api/chat` against `http://127.0.0.1:4777`. No POST.
- D-02: Run status field is `state` (running|waiting|done|failed|stopped|stuck). `resets_at` is epoch seconds. Decode leniently (optional fields).
- D-03: Own `URLSession(configuration: .ephemeral)`, ~3s request timeout; errors/timeouts -> offline state showing `127.0.0.1:4777` / `node orch.js serve` hint; recovers automatically.
- D-04: One `@MainActor` `ObservableObject` singleton (`OrchestratorManager.shared`), `Task` + `Task.sleep` loop: ~2s notch open, slower (~10s) closed. Polling continues while closed.
- D-05: `detectPrompt(screen:)` pure function returning numbered options (or nil/empty). One runnable assert-based test: idle input box (no prompt) and numbered-options prompt.
- D-06: Manager exposes derived `needsAttention` (any run `waiting` OR `detectPrompt` finds a prompt), independent of music state and not gated on tab selection or notch open.
- D-07: All new code under `boringNotch/Orchestrator/`; upstream hooks limited to `NotchViews` case, `TabSelectionView` entry, `ContentView` switch case, pbxproj refs. No new packages. Music code untouched.
- D-08: Build with the xcodebuild command (ad-hoc, derived data in /tmp). Never touch `/Applications/boringNotch.app`, never launch apps.

### Claude's Discretion
- Layout/styling of chat tail, runs strip, usage bars.
- Shelf-disabled tab visibility (`BoringHeader.swift:19`): document or one minimal hook.
- How the prompt-detection test runs (XCTest if a target exists, else `swiftc` script).
- Closed-notch poll interval.

### Deferred Ideas (OUT OF SCOPE)
- Sending, option buttons, Esc, Start/End, key-window spike (Phase 2)
- Closed-notch usage indicator + attention dot, expand-down (Phase 3)
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BLD-01 | CLI build works | Baseline build verified: SUCCEEDED, ~41s wall (warm SPM cache?), see Build section |
| BLD-02 | Music untouched | Hooks never touch MusicManager/NotchHomeView; only additive switch case |
| BLD-03 | New folder, small hooks, no deps | Hook list + pbxproj plan below |
| TAB-01 | Orchestrator tab | enum case + tabs entry + ContentView case + Shelf gating note |
| TAB-02 | Chat tail | `/api/chat` `screen` string; tail last N non-blank lines |
| TAB-03 | Runs strip | `/api/state` `runs[]` fields captured |
| TAB-04 | Usage bars | `usage.five_hour/seven_day` captured |
| TAB-05 | Offline state | URLError handling, ephemeral session |
| TAB-06 | 2s open / slower closed | `vm.notchState` / coordinator hooks below |
</phase_requirements>

## Summary

The main app target uses **classic PBXGroups** (not folder-synced), so new Swift files require manual pbxproj entries (PBXBuildFile, PBXFileReference, PBXGroup, Sources build phase). Only `private/` and `BoringNotchXPCHelper/` are `PBXFileSystemSynchronizedRootGroup`. There is **no test target** (no XCTest in pbxproj), so the detectPrompt test must be a `swiftc`-compiled script. Baseline build succeeds in ~41s.

The upstream hook surface is tiny: one enum case, one array entry, one switch case, plus (optionally) the Shelf gating. The notch open/closed state is `BoringViewModel.notchState` (`.open`/`.closed`), but `BoringViewModel` is per-screen and injected via `@EnvironmentObject`; the manager singleton cannot reach it directly. Recommended: the manager owns an `isNotchOpen` Bool set by the tab view's `onAppear/onDisappear` is NOT enough (tab only exists while open and selected). Use a small hook instead, see Pitfall 1.

**Primary recommendation:** New folder `boringNotch/Orchestrator/` with `OrchestratorModels.swift`, `PromptDetector.swift` (pure, no imports beyond Foundation), `OrchestratorManager.swift`, `OrchestratorView.swift`; test script `boringNotch/Orchestrator/Tests/PromptDetectorTests.swift` is NOT added to the target (keep outside Sources phase; put under `scripts/` or `.planning` to avoid compiling two `main`s).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary | Rationale |
|---|---|---|---|
| Polling + decode | App singleton manager (@MainActor) | — | Shared by tab and future closed-notch indicators |
| Prompt detection | Pure function (Foundation only) | Manager derives `needsAttention` | Testable with swiftc, no UI |
| Rendering | SwiftUI view | — | Observes manager |
| Cadence selection | Manager reads open/closed flag | Hook that sets flag | Manager must not depend on per-screen vm |

## Standard Stack

All system: URLSession (ephemeral, 3s), Codable, Swift Concurrency, ObservableObject singleton, SwiftUI. No packages. [VERIFIED: repo inspection; STACK.md]

## Package Legitimacy Audit

No external packages installed in this phase. slopcheck not needed.

## Exact Hook Points (verified in repo)

| # | File:line | Current | Change |
|---|---|---|---|
| 1 | `boringNotch/enums/generic.swift:27-30` | `public enum NotchViews { case home; case shelf }` | add `case orchestrator` |
| 2 | `boringNotch/components/Tabs/TabSelectionView.swift:17-20` | global `let tabs = [TabModel(label:"Home",icon:"house.fill",view:.home), TabModel(label:"Shelf",icon:"tray.fill",view:.shelf)]` | add `TabModel(label: "Orchestrator", icon: "terminal.fill" (or "sparkles"), view: .orchestrator)`. `ForEach(tabs)` at :27 renders all. |
| 3 | `boringNotch/ContentView.swift:347-351` | `switch coordinator.currentView { case .home: NotchHomeView(albumArtNamespace:..) case .shelf: ShelfView() }` | add `case .orchestrator: OrchestratorView()`. Switch is exhaustive, so build fails until added (good safety). Only one switch on `currentView` exists in ContentView (grep: :222 sets `.shelf` on drop, :347 switch). |
| 4 | `boringNotch/components/Notch/BoringHeader.swift:19` | `if (!tvm.isEmpty \|\| coordinator.alwaysShowTabs) && Defaults[.boringShelf] { TabSelectionView() }` | Tabs hidden entirely when Shelf disabled (`Defaults[.boringShelf]`, default true, Constants.swift:166). The orchestrator told the user to enable Shelf. Recommended minimal hook (2 lines): drop `&& Defaults[.boringShelf]` at :19, and in TabSelectionView use `ForEach(tabs.filter { $0.view != .shelf \|\| Defaults[.boringShelf] })`. Alternative: document "enable Shelf" (zero diff). Pick one in plan; recommend the 2-line hook since the user reaches the tab otherwise only after toggling a settings switch. |
| 5 | `boringNotch/BoringViewCoordinator.swift:53,64-70` | `@Published var currentView`; `alwaysShowTabs` didSet resets `currentView = .home` when disabled and shelf empty | No change. Note `:298` also resets to `.home` (on close/reset). `alwaysShowTabs` default true. |

### Notch open/closed for polling cadence
- `BoringViewModel.notchState` (`boringNotch/models/BoringViewModel.swift:20`, `@Published private(set)`), set at :194 (`.open`) and :207 (`.closed`) inside `open()`/`close()`. `NotchState` enum at `enums/generic.swift:22`.
- `BoringViewModel` is per-screen (instances created per display, passed via `.environmentObject(vm)`), so there is no singleton to read. Options (pick A):
  - **A (recommended, 2 lines in BoringViewModel):** in `open()` at :194 add `OrchestratorManager.shared.notchOpen = true`, at :207 `= false`. Tiny, explicit, and independent of which tab is selected. Multi-screen: last writer wins; acceptable.
  - B (zero diff in vm): in `ContentView` `.onChange(of: vm.notchState)`. ContentView already has several; adds a hook in a bigger file.
  - C (no hook): manager polls at a fixed 2s always. Violates TAB-06 "slower while closed"; reject.
- Manager loop reads `notchOpen` each iteration: `try? await Task.sleep(for: .seconds(notchOpen ? 2 : 10))`.
- Start the loop from `OrchestratorManager.shared.start()` called once at app launch. Simplest: first access in the same hook (`open()`), but then closed polling never starts until first open; for Phase 3 closed indicators the loop must run from launch. Put `OrchestratorManager.shared.start()` in `boringNotchApp.swift` `applicationDidFinishLaunching` (one more upstream line) or lazily in `BoringViewModel.init`. Decide in plan; recommend `BoringViewModel.init` is NOT good (per-screen, multiple); use app delegate and make `start()` idempotent.

## Adding files to the Xcode project

Verified: `grep PBXFileSystemSynchronizedRootGroup` hits only `private` (112FB72F...) and `BoringNotchXPCHelper`. The main target `boringNotch` (14CEF4112C5CAED300855D72) uses classic `PBXGroup` children lists with a `Sources` phase (14CEF40E2C5CAED300855D72). Example entries for an existing file (YouTubeMusicNetworking):
- PBXBuildFile (line 33): `1132E5142E777B920068732D /* X.swift in Sources */ = {isa = PBXBuildFile; fileRef = 1132E5132E777B920068732D /* X.swift */; };`
- PBXFileReference (line 203): `1132E5132E777B920068732D /* X.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = X.swift; sourceTree = "<group>"; };`
- Group children entry (line 419) and Sources phase entry (line 990).

For a new folder add: a PBXGroup `Orchestrator` (`path = Orchestrator; sourceTree = "<group>";`) listing 4 file refs, add the group id to the `boringNotch` main group's `children` (group 14CEF4142C5CAED300855D72, children begin ~line 563; `components` is listed at :576), and 4 PBXBuildFile + 4 PBXFileReference + 4 entries in the Sources phase. Use unique 24-hex IDs (e.g. prefix `0A1C` + counter) that do not appear in the file (`grep -c` each before use). Planner task should do this by careful text edit and then verify with the build; a Ruby `xcodeproj` gem or Python script is not required. [VERIFIED: pbxproj read]

## Test infrastructure

No test target (`grep XCTest\|TestTarget` in pbxproj: none). Cheapest runnable assert test:
```bash
# PromptDetector.swift: Foundation only, no @MainActor/SwiftUI deps
mkdir -p /tmp/pd && swiftc -o /tmp/pd/t boringNotch/Orchestrator/PromptDetector.swift scripts/test-prompt-detector.swift && /tmp/pd/t
```
Gotcha: with multiple files, swiftc treats a file named `main.swift` as entry point; name the test file `main.swift` (e.g. `Tests/Orchestrator/main.swift`) OR use top-level code only in the test file when it is the sole non-library... Safest: name the test `main.swift` in a dir NOT included in the Xcode target, and keep PromptDetector.swift free of top-level statements. Test uses `precondition`/`assert` (use `precondition`: `assert` is stripped with `-O`) and prints "OK". [ASSUMED: swiftc main.swift rule, standard Swift behavior; planner should run once to confirm.]

## Captured fixtures (GET only, 2026-10-14T00:29Z)

### GET /api/state (top-level keys)
`now, layout, runs, sessions, projects, events, usage`

`now`: ISO-8601 string with ms, `"2026-10-14T00:29:17.977Z"`.

`usage` (this is the only usage shape seen; `at` is ISO string):
```json
{"at":"2026-10-14T00:28:45.650Z",
 "five_hour":{"used_percentage":9,"resets_at":1791954000},
 "seven_day":{"used_percentage":14,"resets_at":1792116000}}
```
`used_percentage` is an integer here (decode as `Double?`); `resets_at` epoch seconds (`Double?`). Either window or the whole `usage` could be missing/null at other times (no sample of that seen; make everything optional) [ASSUMED for null cases].

`runs[]` element (trimmed; values from a live run):
```json
{"id":"261014002758-f45c","project":"notch","ws":null,"agent":null,
 "prompt":"/gsd-plan-phase 1, then ... (long, multi-line)",
 "cwd":"/Users/.../worktrees/notch-261014002758-f45c","branch":"orch/261014002758-f45c",
 "repo":"/Users/.../boring-notch","sessionId":"cf69...","startedAt":"2026-10-14T00:27:58.732Z",
 "pid":30425,"state":"running","lastOutput":"2026-10-14T00:29:10.010Z","result":null,
 "denials":[],"latest":"[Bash] {...}","activity":{"step":null,"agents":[{"type":"gsd-phase-researcher","desc":"Research Phase 1"}]}}
```
Observed `state` values in sample: `running, waiting, done, stopped` (failed/stuck per D-02 not observed). `ws`, `agent`, `result` null. `prompt` can be very long with newlines: the strip must truncate (first line, ~40 chars, `lineLimit(1)`). Only decode `id, project, state, prompt, ws, agent` (all optional except treat `id` as optional w/ fallback); ignore the rest. `sessions`, `projects`, `events`, `layout` are large: do not decode (the whole payload was multiple KB; fine for 2s polling on loopback). Runs are ordered newest first in sample; sort running/waiting first in the UI.

### GET /api/chat
```json
{"running":true,"screen":"<4411-char string, lines padded with spaces to terminal width (~190 cols), \\n separated>"}
```
Only two keys. `running:false` presumably yields empty/absent screen (not observed; make `screen` optional). Screen characteristics:
- Lines are right-padded with spaces to full width; trim trailing whitespace per line.
- Contains Unicode box-draw rules (`─` lines), `⏺` bullets, `✻` spinner lines, `❯\u{a0}` prompt glyph followed by a NON-BREAKING SPACE (U+00A0), not a normal space. Detector regexes must treat `\u{a0}` as whitespace (`\s` in Swift Regex covers U+00A0? use `[ \u{a0}]` explicitly).
- Idle input box tail (real capture, trailing spaces removed):
```
────────────────────────────── Upstairs printer slow to print ─
❯\u{a0}merge 199
──────────────────────────────────────────────────────────────
  Opus 5.5 (1M context) │ orchestrator █░░░░░░░░░ 19%
  ⏵⏵ auto mode on · 1 monitor · ← 1 agent
```
  Note the idle input line also begins with `❯` (followed by typed text or empty). So `❯` alone is NOT a prompt marker; require `❯` + optional spaces + digit + `.`.
- No numbered-options prompt was on screen at capture time. Claude Code's known format (from training, [ASSUMED] - refine with real capture in Phase 2 per D-05):
```
 Do you want to proceed?
 ❯ 1. Yes
   2. Yes, and don't ask again for ... 
   3. No, and tell Claude what to do differently (esc)
```
  Selected option has `❯` (sometimes with NBSP) before `1.`; others are indented. Detection rule: scan the tail (last ~25 lines); collect consecutive lines matching `^\s*(?:❯[ \u{a0}]*)?(\d+)\.\s+(.+?)\s*$`; require run of digits starting at 1 and incrementing, count >= 2, and at least one line carrying `❯` before a digit (guards against numbered lists in normal assistant output). Return `[(number: Int, label: String)]`, empty array = no prompt. Also the screen may contain box borders `│` on the sides in some Claude Code versions: strip leading `│ ` before matching.

## Closest analog code (copy patterns)

**Networking template** - `boringNotch/MediaControllers/YouTube Music Controller/YouTubeMusicNetworking.swift`: `URLSession(configuration:)` with `timeoutIntervalForRequest`, `try await session.data(for: request)`, `JSONDecoder().decode`. For this phase use `.ephemeral`, `config.timeoutIntervalForRequest = 3`, `config.waitsForConnectivity = false`:
```swift
let cfg = URLSessionConfiguration.ephemeral
cfg.timeoutIntervalForRequest = 3
let session = URLSession(configuration: cfg)
let (data, resp) = try await session.data(from: base.appendingPathComponent("api/state"))
guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
```
**Singleton manager** - `BoringViewCoordinator` (`BoringViewCoordinator.swift:48-50`): `@MainActor class X: ObservableObject { static let shared = X(); @Published var ... }`. (Other managers like `NotchSpaceManager` are plain classes; `MusicManager`/`VolumeManager` are `ObservableObject` singletons.) Follow `@MainActor final class OrchestratorManager: ObservableObject { static let shared = ...; private init() {} }`.
**Tab view** - `ShelfView()` / `NotchHomeView(albumArtNamespace:)` are plain SwiftUI views filling the open notch area; `ContentView` wraps the switch in a `VStack` with transition. Open notch content area is limited by `openNotchSize` (640x190) minus the 26pt header: design for roughly 610x140, no ScrollView needed for the chat tail (show last ~6 lines at `.system(size: 10, design: .monospaced)`). Font/colour: white/gray on black, `Capsule` bars (see TabSelectionView `.secondarySystemFill`).
**Polling loop shape:**
```swift
func start() { guard task == nil else { return }
  task = Task { [weak self] in
    while !Task.isCancelled {
      await self?.refresh()
      try? await Task.sleep(for: .seconds(self?.notchOpen == true ? 2 : 10))
    } } }
```
`refresh()` fetches state and chat concurrently (`async let`), sets `offline = true` on any `URLError`/non-200, otherwise assigns published fields only when changed (avoid needless SwiftUI redraw). Keep last good data while offline? Show offline view instead (TAB-05); keep data for Phase 3 not needed.
**needsAttention (D-06):**
```swift
var needsAttention: Bool { runs.contains { $0.state == "waiting" } || !promptOptions.isEmpty }
```
as a computed property on the manager (promptOptions computed from `detectPrompt(screen:)` on each successful chat fetch, stored `@Published`). Do not reference `currentView`, `vm.notchState`, or MusicManager.

## Build baseline (ran once)

Command (exact):
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd build
```
Result: `** BUILD SUCCEEDED **`, 41s wall. Note from build: "Disabling hardened runtime with ad-hoc codesigning." Output app: `/tmp/notch-dd/Build/Products/Debug/Boring Notch.app` (product name has a space; NOT `boringNotch.app`). The build ran `lsregister -f -R -trusted` on that bundle (a build step side effect, registers the app with Launch Services; harmless but mention it to the user). Use a distinct derived-data dir for executor runs (`/tmp/notch-dd-p1`) so it does not collide.
Sparkle: Info.plist has `SUFeedURL`; the user wants auto-updates off in the fork build, which is out of Phase 1 scope (flag only).

## Common Pitfalls

1. **Per-screen `BoringViewModel`**: manager cannot read `notchState` itself. Use the 2-line hook in `open()`/`close()` (A above).
2. **NBSP after `❯`**: regexes written with a plain space silently miss the idle prompt and any option line. Test fixture must contain `\u{a0}`.
3. **False positives on `❯` idle input**: idle box line `❯ merge 199` is not a prompt; require a digit-dot after the glyph and a numbered sequence.
4. **Polling starts only when the tab opens**: if `start()` is first called from the view, closed-notch polling (needed in Phase 3) never runs. Start at launch.
5. **Switch exhaustiveness**: adding `.orchestrator` breaks any other `switch` over `NotchViews`; grep before and after (`grep -rn "NotchViews\|currentView" boringNotch`). Only ContentView:347 switches in the files reviewed.
6. **Default `URLSession` 60s timeouts / caching**: use ephemeral + 3s.
7. **Shelf gating**: with `boringShelf` false the tab strip is invisible (BoringHeader:19), so the Orchestrator tab is unreachable even though the case exists.
8. **State resets**: `BoringViewCoordinator.swift:298` sets `currentView = .home` (close/reset); orchestrator tab does not persist across closes unless `openLastTabByDefault`. Acceptable.
9. **Huge `/api/state`**: decode only needed keys; Codable ignores the rest. Don't store `sessions/projects/events`.
10. **Test file in the Xcode target**: a `main.swift` or top-level asserts inside the app target would break the app build. Keep the test outside the pbxproj.

## Don't Hand-Roll
| Problem | Use |
|---|---|
| HTTP/JSON | URLSession + Codable |
| Polling timer | `Task` + `Task.sleep` |
| Progress bars | `ProgressView(value:)` or `Capsule` overlay |
| Reset time formatting | `Date.formatted(date: .omitted, time: .shortened)` / `RelativeDateTimeFormatter` |

## Environment Availability

| Dependency | Available | Version |
|---|---|---|
| Xcode (`/Applications/Xcode.app`) | yes | builds OK |
| `swiftc` (via DEVELOPER_DIR) | yes (Xcode toolchain) | for detectPrompt test |
| Orchestrator serve 127.0.0.1:4777 | yes | live, GET OK |

## Validation Architecture
Skipped: `workflow.nyquist_validation` is false in `.planning/config.json`. Verification = xcodebuild success + swiftc detectPrompt test + curl-captured fixtures decode (can test `Codable` models by compiling models file + a main.swift reading a saved JSON fixture).

## Security Domain
Loopback-only, GET-only, no secrets, no user input in this phase. Only concern: do not render `screen` as Markdown/attributed links (use plain `Text(verbatim:)`) so screen contents cannot inject links. ATS already allows arbitrary loads; sandbox has `network.client`. [VERIFIED: STACK.md/entitlements]

## Assumptions Log
| # | Claim | Risk |
|---|---|---|
| A1 | Claude Code numbered-prompt format (`❯ 1. Yes` / indented `2.`) from training, not captured | Detector misses prompts; refined in Phase 2 (accepted by D-05) |
| A2 | Null/missing `usage` or `screen` when chat not running | Mitigated by all-optional decoding |
| A3 | swiftc `main.swift` entry-point behavior | Planner runs once to confirm |

## Sources
- Repo files read: generic.swift, TabSelectionView.swift, ContentView.swift, BoringHeader.swift, BoringViewCoordinator.swift, BoringViewModel.swift, Constants.swift, project.pbxproj, YouTubeMusicNetworking.swift, Info.plist (HIGH)
- Live curl GET `/api/state`, `/api/chat` 2026-10-14 (HIGH)
- Baseline xcodebuild run (HIGH)

**Research date:** 2026-10-14 | **Valid until:** ~30 days (upstream drift only)
