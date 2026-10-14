# Walking Skeleton — Boring Notch Orchestrator Fork

**Phase:** 1
**Generated:** 2026-10-14

## Capability Proven End-to-End

Opening the notch and selecting the new "Orchestrator" tab shows the live tail of the orchestrator chat, fetched by one polling manager over `GET http://127.0.0.1:4777/api/chat`, in an app built from the command line with `xcodebuild`.

Path: tab hook (`NotchViews.orchestrator` + `TabSelectionView` entry + `ContentView` switch case) → `OrchestratorManager.shared` (started once from `AppDelegate`, polls GET) → `OrchestratorView` renders `chatTail(screen:)`.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Framework | Existing Boring Notch app: SwiftUI views inside the AppKit notch panel, Swift 5 language mode, macOS 14 target | Fork of upstream; no new UI framework |
| Data source | Orchestrator HTTP API on `http://127.0.0.1:4777` (`/api/chat`, `/api/state`), GET only in Phase 1 | Sandbox forbids spawning processes; serve is the single source of truth |
| Networking | Own `URLSession(configuration: .ephemeral)`, 3s request timeout, `Codable` with all-optional fields | Fast offline detection; server additions never break decoding (D-02, D-03) |
| State | One `@MainActor final class OrchestratorManager: ObservableObject`, `static let shared` | Matches repo managers; shared by the tab now and closed-notch indicators in Phase 3 (D-04, D-06) |
| Polling | `Task` + `Task.sleep` loop, 2s notch open / 10s closed; `notchOpen` fed by `BoringViewModel.open()/close()`; `start()` idempotent, called from `applicationDidFinishLaunching` | Runs from launch so Phase 3 closed indicators have fresh data |
| Pure logic | `OrchestratorModels.swift` is Foundation-only (models, `chatTail`, `detectPrompt`, `stripRuns`) | Testable with plain `swiftc`, no test target needed |
| Tests | `boringNotch/Orchestrator/Tests/main.swift` (NOT in the Xcode target), `precondition` asserts, prints `OK` | No XCTest target exists; zero pbxproj churn for tests |
| Regex | `#/…/#` extended-delimiter literals (or `Regex(...)`), never bare `/…/` | Bare slash literals need `-enable-bare-slash-regex`; project is Swift 5 mode (verified with swiftc) |
| Build | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd build` → `/tmp/notch-dd/Build/Products/Debug/Boring Notch.app` | Local ad-hoc build; installed app never touched (D-08) |
| Directory layout | All new code in `boringNotch/Orchestrator/` (classic PBXGroup `Orchestrator`); upstream hooks one-to-two lines each | Upstream mergeability (D-07, BLD-03) |
| Deployment | None. User runs the built bundle themselves after quitting the installed Boring Notch | Personal local build |

## Stack Touched in Phase 1

- [x] Project scaffold — existing Xcode project; new `Orchestrator` group + 3 files in the Sources phase
- [x] Routing — new tab case `NotchViews.orchestrator` reachable from the tab strip (Shelf no longer gates the strip)
- [x] Data — real GET reads of `/api/chat` and `/api/state` (no writes in this phase by design, D-01)
- [x] UI — tab selection interaction renders live data
- [x] Run — documented local run of the built bundle (not launched by the executor)

## Out of Scope (Deferred to Later Slices)

- Sending messages, option buttons, Esc, Start/End, key-window spike (Phase 2)
- Closed-notch usage indicator and attention dot, expand-down, `/term` WKWebView (Phase 3)
- Settings keys for base URL / enabling the tab (not requested)
- Sparkle auto-update changes

## Subsequent Slice Plan

- Phase 2: user sends messages and answers numbered prompts from the tab (POST via the same manager and session; `detectPrompt` fixtures refined from real captures)
- Phase 3: closed-notch usage + `needsAttention` dot (visible alongside music), expand-down with larger chat and live terminal
