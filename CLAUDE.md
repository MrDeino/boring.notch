<!-- GSD:project-start source:PROJECT.md -->
## Project

**Boring Notch — Orchestrator Fork**

A personal fork of TheBoredTeam/boring.notch (Swift/SwiftUI macOS notch app, GPL-3.0) that adds an **Orchestrator** tab: from the notch the user can read and chat with their local Claude Code orchestrator, answer its question/permission prompts, start or end it, and watch its dispatched runs and Claude usage — while Boring Notch's music player keeps working as before.

**Core Value:** Answer and steer the Claude Code orchestrator from the notch without switching to a terminal — and never break the music player doing it.

### Constraints

- **Upstream mergeability**: keep the diff to upstream small and isolated — new files where possible, minimal hooks into existing files.
- **Music**: must not regress now-playing/music controls.
- **Dependencies**: no new third-party packages unless unavoidable.
- **Sandbox**: talk to the orchestrator only over the HTTP API; never spawn processes.
- **Build**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild`, local unsigned/ad-hoc, macOS 26.
- **Git**: never push; stay on the current branch, no GSD phase/milestone branches.
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## What the repo already has (verified)
| Item | Value | Where |
|------|-------|-------|
| Swift language mode | `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = targeted` | project.pbxproj |
| Deployment target | macOS 14.0 | project.pbxproj |
| Sandbox | on, with `network.client` **and** `network.server` | boringNotch/boringNotch.entitlements |
| Hardened runtime | YES | project.pbxproj |
| ATS | `NSAllowsArbitraryLoads = true` already | boringNotch/Info.plist |
| State pattern | `ObservableObject` + `@Published` singletons (`static let shared`), not `@Observable` | managers/*.swift, BoringViewCoordinator |
| Async delays | `Task.sleep(for:)` throughout | BoringViewCoordinator, ContentView, controllers |
| URLSession + JSONDecoder async/await | yes, as a template | MediaControllers/YouTube Music Controller/YouTubeMusicNetworking.swift |
| Settings | `Defaults` 9.0.6, keys in `extension Defaults.Keys` | models/Constants.swift |
| WebKit | not used anywhere yet | — |
| Window size | fixed: `windowSize` = `openNotchSize` (640x190) + shadow; panel created at that rect | sizing/matters.swift, boringNotchApp.swift:235, ContentView.swift:206 |
## Recommended Stack
### Core Technologies (all system, no new deps)
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| URLSession async/await (`data(for:)`) | macOS 12+ | GET /api/state, /api/chat; POST /api/chat, /start, /stop | Already used in the repo (YouTubeMusicNetworking); trivially cancellable inside a Task. Use a dedicated `URLSession(configuration: .ephemeral)` with `timeoutIntervalForRequest ≈ 3s` so an offline serve flips to "offline" fast instead of hanging 60s. |
| Codable + JSONDecoder | stdlib | Decode `/api/state`, `/api/chat`; encode `{text}` / `{key}` | Native. Make all fields the UI does not strictly need optional so server additions/omissions never break decoding. `resets_at` is epoch seconds → `Date(timeIntervalSince1970:)` (decode as `Double`, or `.secondsSince1970` strategy). |
| Swift Concurrency polling loop (`Task` + `Task.sleep(for:)`) | macOS 13+ | ~2s open / slower closed polling | Matches existing repo idiom; one `@MainActor` Task, cancelled on stop; interval read each loop from notch open state. Simpler and safer than Timer + callbacks. |
| ObservableObject + @Published (`OrchestratorManager.shared`) | Combine/SwiftUI | Shared state for tab view and closed-notch indicator | Matches every other manager in the repo; `@Observable` would be a second pattern for upstream readers. Mark the class `@MainActor`. |
| WebKit `WKWebView` via `NSViewRepresentable` | macOS 10.10+ (SwiftUI wrap) | Live ttyd terminal at `http://127.0.0.1:4777/term` | ttyd's websocket Origin check is satisfied because the page's own origin is `http://127.0.0.1:4777`. Wrapper is ~15 lines. |
| `Defaults` (in-repo) | 9.0.6 | Optional settings: base URL, enable tab | Already the settings mechanism; one or two `Key`s in a new file's `extension Defaults.Keys`. |
### Supporting (in-repo reuse)
| Item | Purpose | When to Use |
|------|---------|-------------|
| `NotchViews` enum + `TabSelectionView` | Add `.orchestrator` case and tab entry | Tab hook (minimal edit to existing files) |
| `BoringViewCoordinator.shared` / `BoringViewModel` | Read notch open/closed state to choose poll interval; current tab | Polling cadence and attention dot |
| `openNotchSize` / `windowSize` / panel frame in `boringNotchApp.swift` | Expand-down needs a taller window | Expand phase — see note below |
| SF Symbols / existing view styling | Buttons, dots, bars | All UI; `ProgressView(value:)` or a plain `Capsule` for usage bars |
### Development Tools
| Tool | Purpose | Notes |
|------|---------|-------|
| `xcodebuild` (Xcode at `/Applications/Xcode.app`) | CLI build | `CODE_SIGNING_ALLOWED=NO` or ad-hoc `CODE_SIGN_IDENTITY=-`; sandbox entitlements still apply with ad-hoc signing |
| `curl` against 127.0.0.1:4777 | Capture real JSON fixtures | Build the Codable models from real responses, not the doc |
## Installation
## Key implementation notes
- **POST headers:** every POST needs `x-orch: 1` and `Content-Type: application/json`. Treat 409 on POST /api/chat as "chat not running" (show Start), not an error.
- **WKWebView:** create once and keep it (don't recreate on every SwiftUI update — `updateNSView` should be a no-op unless the URL changed). Use default `WKWebViewConfiguration`; set `webView.setValue(false, forKey: "drawsBackground")` only if a transparent background is wanted (private-ish KVC, optional). Load `URLRequest(url: …/term)`. Keyboard input needs the notch panel to become key — the panel is likely a non-activating `NSPanel`; verify `canBecomeKey` when the terminal is shown (flag for the expand phase).
- **Expand-down:** the window is created at a fixed `windowSize` and ContentView clamps to `maxHeight: windowSize.height`. Growing downward means resizing the panel frame (keep top edge pinned: adjust `origin.y` by the delta) and relaxing that clamp. This is AppKit `NSWindow.setFrame(_:display:animate:)`, no new tech, but it touches existing files — keep the hook small.
- **Prompt detection:** parse `screen` text with `String`/`Regex` (Swift 5.7+ `Regex` literal or `firstMatch(of:)`) for Claude Code numbered option lines (e.g. `❯ 1. Yes`). Pure function → easy single test.
- **Offline:** `URLError.cannotConnectToHost` / `.timedOut` → offline state; keep polling at the slow interval.
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `Task` + `Task.sleep` loop | `Timer.publish` / `Timer.scheduledTimer` | Never here — overlapping requests and run-loop mode issues when menus are open |
| `ObservableObject` | `@Observable` (Observation, macOS 14) | Would be fine technically (target is 14.0), but breaks repo consistency |
| WKWebView on /term | SwiftTerm + own websocket client | Only if WKWebView keyboard focus in the panel proves unworkable — and it's a new dep |
| Polling | `URLSessionWebSocketTask` / SSE | Only if serve adds a push endpoint; it doesn't today |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Any third-party HTTP/JSON lib (Alamofire, etc.) | Project constraint; URLSession covers it | URLSession + Codable |
| `Process` / `NSTask` / tmux / shell calls | Sandbox forbids; out of scope | HTTP API only |
| `WebView` (SwiftUI-native, macOS 26 only) | Deployment target is 14.0 | `NSViewRepresentable` over `WKWebView` |
| New entitlements or `NSAllowsLocalNetworking` | Already covered by `network.client` + `NSAllowsArbitraryLoads`; extra upstream diff | Nothing |
| `URLSession.shared` with default timeouts | 60s hang when serve is down | Own session, ~3s request timeout |
| A new window/popover for the terminal | Agreed design is expand-down | Resize existing panel |
| Swift 6 language mode / strict concurrency change | Project-wide churn | Stay on Swift 5 mode; mark new manager `@MainActor` |
## Version Compatibility
| Item | Compatible With | Notes |
|------|-----------------|-------|
| `Task.sleep(for: .seconds())` | macOS 13+ | Target 14.0, fine |
| Swift `Regex` | macOS 13+ | Fine |
| `WKWebView` in NSViewRepresentable | macOS 14 target | Fine; avoid macOS 26-only SwiftUI `WebView` |
| Defaults 9.x | macOS 14 | Already resolved at 9.0.6 |
## Sources
- Repo inspection (HIGH): boringNotch/boringNotch.entitlements, boringNotch/Info.plist, boringNotch.xcodeproj/project.pbxproj, Package.resolved, sizing/matters.swift, boringNotchApp.swift, managers/*, YouTubeMusicNetworking.swift
- Apple docs (training knowledge, stable APIs — MEDIUM-HIGH): URLSession async API, WKWebView, ATS `NSAllowsArbitraryLoads`/`NSAllowsLocalNetworking`, App Sandbox `com.apple.security.network.client`, Local Network privacy (applies to LAN, not loopback — MEDIUM, verify on first run)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
