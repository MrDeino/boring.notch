# Architecture Research

**Domain:** SwiftUI macOS notch app (Boring Notch fork) + local HTTP client for the Claude Code orchestrator
**Researched:** 2026-10-14
**Confidence:** HIGH for hook points (read from source in this repo); MEDIUM for key-window/text input and window resize behaviour (AppKit behaviour reasoned, not yet tested here)

## Standard Architecture

### System Overview

```
 orch.js serve (127.0.0.1:4777)
        │  GET /api/state, GET /api/chat, POST /api/chat[/start|/stop], /term
        ▼
┌────────────────────────────────────────────────────────────────┐
│ OrchestratorClient (struct, URLSession async, x-orch: 1)        │  new
├────────────────────────────────────────────────────────────────┤
│ OrchestratorManager.shared  (@MainActor ObservableObject)       │  new
│  poll loop (2s visible / ~10s hidden) → @Published state         │
│  isOnline, runs, usage, chatRunning, screen, promptOptions,      │
│  needsAttention, isExpanded                                      │
├──────────────┬──────────────────────────┬──────────────────────┤
│ OrchestratorTabView (open notch)        │ OrchestratorClosed-   │  new
│  runs strip, usage bars, chat tail,     │ Indicator (closed     │
│  input, option buttons, start/end,      │ notch wing)           │
│  expand → OrchestratorTerminalView      │                       │
│  (WKWebView on /term)                   │                       │
└──────────────┴──────────────────────────┴──────────────────────┘
        ▲ 5 small hooks into upstream files (enum case, tab entry, view switch,
          closed-notch branch, height clamp) + 1 window hook (canBecomeKey)
```

This mirrors how upstream already works: `MusicManager.shared` / `BatteryStatusViewModel.shared` are singleton `ObservableObject`s with `@Published` state, and views pick them up with `@ObservedObject var x = X.shared` (ContentView.swift:19-25). Follow the same pattern; no new abstractions.

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|----------------|----------------|
| `OrchestratorClient` | 5 HTTP calls, Codable decode, timeouts (~2s) | `struct` with `static func`s over `URLSession.shared`; no protocol, no DI |
| `OrchestratorManager` | Owns poll loop, published state, prompt-option parsing, attention flag, expand state | `@MainActor final class: ObservableObject`, `static let shared` (same shape as `MusicManager`, managers/MusicManager.swift:17-19) |
| `OrchestratorTabView` | Open-notch tab content | SwiftUI view, `@ObservedObject var orch = OrchestratorManager.shared`, `@EnvironmentObject var vm: BoringViewModel` |
| `OrchestratorClosedIndicator` | Closed-notch wings: usage ring left, attention dot right | SwiftUI view copying `BoringFaceAnimation` wing layout (ContentView.swift:367-386) |
| `OrchestratorTerminalView` | `/term` in WKWebView | `NSViewRepresentable` wrapping `WKWebView`, loads `http://127.0.0.1:4777/term` |
| `NotchWindowResizer` | Grows/shrinks the hosting NSWindow, top-anchored | tiny `NSViewRepresentable` that reads `nsView.window` (per window, so works with `showOnAllDisplays`) |

## Recommended Project Structure

```
boringNotch/Orchestrator/            # one new folder = whole feature
├── OrchestratorClient.swift         # HTTP + Codable models (State, Run, Usage, Chat)
├── OrchestratorManager.swift        # singleton, polling, parsing, expand state
├── OrchestratorTabView.swift        # open tab (runs strip, usage, chat tail, input, buttons)
├── OrchestratorClosedIndicator.swift
└── OrchestratorTerminalView.swift   # WKWebView + NotchWindowResizer + click-outside monitor
```

### Structure Rationale

- **One folder, registered as a synchronized folder.** The Xcode project (objectVersion 70) lists most files individually (4 pbxproj sections per file), but already uses `PBXFileSystemSynchronizedRootGroup` for `boringNotch/private` (project.pbxproj:325, group child at :585, target `fileSystemSynchronizedGroups` at :801). Add one `Orchestrator` synchronized group the same way: 3 pbxproj lines total, and every later file is picked up with no pbxproj churn. This is the single biggest win for upstream mergeability.
- No Info.plist change: `NSAppTransportSecurity/NSAllowsArbitraryLoads = true` already (Info.plist:5-8). No entitlement change: `network.client` present. `import WebKit` autolinks; no package added.

## Exact Hook Points (upstream files)

| # | File:line | Change | Why |
|---|-----------|--------|-----|
| H1 | `boringNotch/enums/generic.swift:27-30` | add `case orchestrator` to `NotchViews` | tab identity |
| H2 | `boringNotch/components/Tabs/TabSelectionView.swift:17-20` | append `TabModel(label: "Orchestrator", icon: "terminal.fill", view: .orchestrator)` | tab button |
| H3 | `boringNotch/ContentView.swift:347-352` | `case .orchestrator: OrchestratorTabView()` in the `switch coordinator.currentView` | tab content (exhaustive switch, compiler forces this) |
| H4 | `boringNotch/ContentView.swift:293` | new `else if vm.notchState == .closed && !vm.hideOnClosed && orch.showClosedIndicator { OrchestratorClosedIndicator() }` placed **after** the MusicLiveActivity branch (290) and before the face branch | closed indicator; music always wins precedence, so music cannot regress |
| H5 | `boringNotch/ContentView.swift:206` | `maxHeight: windowSize.height` → `maxHeight: max(windowSize.height, vm.notchSize.height + shadowPadding)` | lets content grow past the fixed 190pt open height |
| H6 | `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift:112` | `canBecomeKey { false }` → `{ OrchestratorManager.shared.wantsKeyboard }` | text field and terminal cannot receive keystrokes otherwise (see below) |
| H7 | `boringNotch.xcodeproj/project.pbxproj` ~:325/:585/:801 | synchronized `Orchestrator` group | build membership |

Optional H8: if the attention dot must show *while music plays*, add `.overlay(alignment: .topTrailing) { OrchestratorAttentionDot() }` on `mainLayout` near ContentView.swift:105. Skip in v1 unless asked; H4 alone hides the indicator whenever music is playing.

Not hooked (deliberately): `BoringViewModel`, `BoringViewCoordinator`, `boringNotchApp.swift`, `sizing/matters.swift`, `handleHover`.

Note: tabs only render when `Defaults[.boringShelf]` is on and (`alwaysShowTabs` or shelf non-empty) (components/Notch/BoringHeader.swift:19). With shelf disabled the Orchestrator tab is unreachable. Document as a requirement of the fork rather than hooking it.

## Data Flow

### Poll → model → views

```
Task loop in OrchestratorManager (started once, from first view onAppear)
  every tick:
    async let s = Client.state()      // runs, usage
    async let c = Client.chat()       // running, screen
    success → isOnline = true, assign published fields (only if changed)
              promptOptions = parseOptions(screen)        // pure func, testable
              needsAttention = runs.contains{.waiting} || !promptOptions.isEmpty
    failure (URLError / timeout) → isOnline = false (keep last data, show hint)
  sleep(isTabVisible ? 2s : 10s)

OrchestratorTabView.onAppear  → orch.isTabVisible = true; orch.pollNow()
OrchestratorTabView.onDisappear → isTabVisible = false; collapse()
```

- **Writes** (`send(text:)`, `send(key:)`, `start()`, `stop()`) go through the manager, then call `pollNow()` so the screen updates immediately instead of waiting a tick. 409 from `POST /api/chat` → set `chatRunning = false`.
- Prompt parsing: scan the last ~15 lines of `screen` for `^\s*[❯>]?\s*([1-9])\.\s+(.+)$`; only treat as a prompt when the block is at the bottom of the screen. Keep it a free function with one assert-based check — the screen format is Claude Code's, not ours, so it is the most likely thing to break.
- Publish only on change (compare before assigning) so a 2s poll doesn't re-render the whole notch and disturb the music view's animations.

### Expand-down sizing (how it actually works today)

Facts from source:
- Window is created once at a fixed `windowSize` = 640 × (190 + 20 shadow) (sizing/matters.swift:16-17, boringNotchApp.swift:235) and positioned top-anchored: `y = screen.maxY - window.frame.height` (boringNotchApp.swift:268-279). It never resizes; open/close only animates SwiftUI content inside it.
- `vm.open()` sets `vm.notchSize = openNotchSize` (BoringViewModel.swift:192-194); ContentView frames the black notch at `vm.notchSize.height` (ContentView.swift:121) and clamps the whole tree at `windowSize` (ContentView.swift:206).
- `vm.notchSize` is a plain `@Published var`, reset on every `close()` (BoringViewModel.swift:205).

So expanding down = three coordinated steps, all from new code except H5:
1. `vm.notchSize = CGSize(width: openNotchSize.width, height: openNotchSize.height + extra)` (vm is the per-window `@EnvironmentObject`). The notch shape, `isMouseHovering` (BoringViewModel.swift:179-190) and the open animation all follow automatically.
2. `NotchWindowResizer` sets the window frame to the new height keeping `maxY` fixed: `NSRect(x: f.minX, y: f.maxY - h, width: f.width, height: h)`. `positionWindow` uses `window.frame.height`, so a screen change while expanded still anchors correctly.
3. H5 lifts the SwiftUI clamp.
Collapse reverses: restore `openNotchSize` and `windowSize.height`. `vm.close()` already restores `notchSize`; the resizer must also restore the window height on `onDisappear` (tab view leaves the tree on close, ContentView.swift:345).

Pick `extra` from the screen: `min(420, screen.visibleFrame.height - openNotchSize.height - 40)`.

### Click outside / staying open

Upstream has **no click-outside close**: the notch closes on hover-exit after 100ms (ContentView.swift:543-555), on swipe-up, or on drag end. Everything respects one ref-counted guard: `SharingStateManager.shared.beginInteraction()/endInteraction()`, which `vm.close()` itself checks (BoringViewModel.swift:202) and which posts `.sharingDidFinish` on release, where ContentView closes the notch if the pointer is not over it (ContentView.swift:149-162).

Reuse it, no hook needed:
- On expand: `SharingStateManager.shared.beginInteraction()` → notch stays open when the pointer leaves.
- Install `NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown)` (same API DragDetector already uses, observers/DragDetector.swift:55; global mouse monitors need no Accessibility permission). Global monitors only fire for clicks in *other* apps, i.e. outside our window, which is exactly "click outside". On fire: collapse → `endInteraction()` → upstream closes the notch. Remove the monitor on collapse.
- Same guard while the message field is focused, so the notch doesn't close mid-typing when the pointer drifts.
- Must pair begin/end exactly (use a `Bool` in the manager); a leaked begin leaves the notch stuck open, including for music.

### Keyboard input (the hidden blocker)

`BoringNotchSkyLightWindow` returns `canBecomeKey = false` (BoringNotchSkyLightWindow.swift:112); it is a `.nonactivatingPanel`. A non-key window cannot deliver keystrokes, so the message `TextField` and the ttyd terminal will not accept typing without H6. Making it unconditionally `true` risks the notch stealing keyboard focus from the user's app whenever they click a music button. Hence the gated version: `wantsKeyboard` is true only while the Orchestrator tab is visible (or expanded), and the view calls `window.makeKey()` when the field is focused / terminal shown. Non-activating panel = the frontmost app stays active. MEDIUM confidence: needs a 30-minute spike in phase 1 to confirm focus and return-of-focus behaviour on macOS 26.

## Architectural Patterns

### Pattern 1: Singleton manager + `@ObservedObject var x = X.shared`
**What:** exactly what MusicManager, BatteryStatusViewModel, BoringViewCoordinator do.
**When:** all orchestrator state. One manager, not one per screen; views per screen read the same state.
**Trade-offs:** global state, but matches the codebase; nothing to wire through `boringNotchApp.swift`.

### Pattern 2: Per-window side effects inside the view tree
**What:** window resize and key status done from an `NSViewRepresentable` that reads `nsView.window`, not from the app delegate.
**When:** anything that touches the NSWindow. With `showOnAllDisplays` there is one window + one `BoringViewModel` per screen (boringNotchApp.swift:477-512); the view knows which one it lives in, the delegate doesn't without new plumbing.

### Pattern 3: Reuse upstream guards instead of adding conditions
**What:** `SharingStateManager.beginInteraction` for "don't close"; music-first ordering in the closed `if/else` chain.
**Why:** each reuse removes a hook into `ContentView.handleHover`, the most upstream-churned part of the file.

## Anti-Patterns

### Anti-Pattern 1: New NSWindow / popover for the terminal
**Why bad:** explicitly out of scope; duplicates SkyLight/space/level handling (`NotchSpaceManager`, `enableSkyLight`).
**Instead:** grow the existing window (above).

### Anti-Pattern 2: Making the window permanently taller
**Why bad:** one-line change to `windowSize`, but the closed-state `dragDetector` (ContentView.swift:489-503) fills the whole frame, so the shelf drop zone grows; the SwiftUI hover/contentShape area and screen-recording footprint grow too.
**Instead:** resize only while expanded.

### Anti-Pattern 3: Polling from views (`.task` per view / `Timer` in each window)
**Why bad:** N screens = N pollers; restarts on every open/close.
**Instead:** one loop in the manager; views only flip `isTabVisible`.

### Anti-Pattern 4: Adding the indicator by editing `MusicLiveActivity` or `computedChinWidth`
**Why bad:** touches the music path the project must not regress.
**Instead:** separate branch after music (H4); `computedChinWidth` only sizes the invisible hover chin when `hideTitleBar` is on — leave it.

## Build Order

1. **Build + skeleton** — CLI build green unchanged; then H7 (synced folder), H1-H3 with a placeholder tab. Proves membership and tab wiring. Also the keyboard spike (H6) with a dummy TextField.
2. **Client + manager + read-only tab** — models, polling, offline state, runs strip, usage bars, chat tail. No hooks beyond step 1.
3. **Input** — message field (H6 + interaction guard), prompt option buttons, Start / End with confirm.
4. **Closed indicator** — H4 (+ optional H8). Verify music live activity unchanged with music playing / paused / idle.
5. **Expand-down** — H5, resizer, WKWebView `/term`, larger chat view, click-outside monitor. Riskiest UI step, last, isolated.

Dependencies: 3 needs 2 (manager) and the step-1 key spike; 4 needs 2; 5 needs 3's keyboard work for the terminal.

## Scalability Considerations

Single local user; the only "scale" is cost per tick.

| Concern | Approach |
|---------|----------|
| Re-render cost on 2s polls | publish only on change; chat tail shows last ~30 lines, not 200 |
| Multiple displays | one manager, per-window views/resizer |
| serve down | short timeout, `isOnline=false`, keep polling at slow rate |

## Sources

- Repo source (HIGH): ContentView.swift, BoringViewCoordinator.swift, models/BoringViewModel.swift, sizing/matters.swift, components/Tabs/TabSelectionView.swift, components/Notch/{BoringHeader,BoringNotchSkyLightWindow}.swift, models/SharingStateManager.swift, observers/DragDetector.swift, boringNotchApp.swift, Info.plist, boringNotch.entitlements, boringNotch.xcodeproj/project.pbxproj
- AppKit behaviour of `.nonactivatingPanel` + `canBecomeKey`, global mouse monitors (MEDIUM, training knowledge; verify in step-1 spike)
