# Phase 3: Compact Indicators & Expand-Down - Research

**Researched:** 2026-10-14
**Domain:** SwiftUI/AppKit notch panel (closed-notch overlays, NSPanel resize, key-window gating, WKWebView terminal)
**Confidence:** MEDIUM-HIGH (repo facts HIGH; WKWebView/nonactivating-panel keyboard runtime behaviour MEDIUM, user UAT needed)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- D-01: Attention dot on the closed notch whenever `OrchestratorManager.shared.needsAttention` is true, shown EVEN while music plays (small dot at the notch edge alongside the music activity). A waiting question is never hidden.
- D-02: Tiny usage indicator on the closed notch only if it fits without hurting music (music closed-notch activity, artwork, sizing unchanged). If it cannot fit cleanly, show only when no music activity is visible, or skip with a note; record the choice.
- D-03: Expand control in the Orchestrator tab grows the SAME notch window further DOWN (no separate window/popover). Top edge pinned.
- D-04: Expanded view shows live terminal: WKWebView on `http://127.0.0.1:4777/term`, created only while expanded and torn down on collapse (ttyd allows one viewer). If the single client is taken / page fails, show "terminal in use" (or offline) gracefully.
- D-05: Collapse via the same control, or by clicking anywhere outside the notch. Closing the notch also collapses.
- D-06: Terminal WebView needs keyboard input while expanded. Implement narrowly (panel may become key only while expanded/terminal shown), isolate it so it merges cleanly with Phase 2's key-window gating. Note explicitly in summary for the merge.
- D-07: New code in new files under `boringNotch/Orchestrator/`. Edits to `OrchestratorView.swift`, `OrchestratorManager.swift` and window/panel focus code minimal, isolated (ideally one hook each). Build no Phase 2 feature.
- D-08: Keep upstream diff small: minimal hooks into ContentView, sizing, boringNotchApp panel frame, closed-notch view.
- D-09: NEVER POST to 127.0.0.1:4777. GETs fine but NOT /term (loading it connects a ttyd client that can type; never load during build/verification).
- D-10: Don't launch apps. Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-p3 build` (not /tmp/notch-dd).
- D-11: Music must not regress.
- D-12: Never push; stay on current branch; no GSD branches.

### Claude's Discretion
Expanded height, animation, dot placement/colour, expand icon; how "terminal in use" is detected; whether a larger chat view is shown when expanded; pure-function asserts in `boringNotch/Orchestrator/Tests/main.swift`.

### Deferred Ideas (OUT OF SCOPE)
Message box, prompt option buttons, Esc, Start/End, message-box key-window gating (Phase 2, parallel branch).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CMP-01 | Closed-notch usage indicator | Overlay in ContentView closed notch (section "Closed-notch indicators"); thin bottom bar, pure fraction fn |
| CMP-02 | Closed-notch dot when run waiting/prompt, even with music | Same overlay, driven by `needsAttention`; no layout impact |
| EXP-01 | Expand notch downward, larger chat view | `vm.notchSize` + window frame grow; chat tail fallback with more lines |
| EXP-02 | Live terminal /term typeable | WKWebView, gated `canBecomeKey`, keep-open interaction |
| EXP-03 | Click outside collapses | Local+global NSEvent monitors with notch-rect test |
</phase_requirements>

## Summary

The notch is one borderless non-activating `BoringNotchSkyLightWindow` (NSPanel) per display, created at fixed `windowSize` (640 x 210) and pinned to the screen top by `positionWindow`, which computes `y = screen.maxY - window.frame.height` from the CURRENT frame height. So a taller window stays top-pinned across screen-change recomputation with no extra work. The visible notch height is driven by `vm.notchSize.height` (ContentView line ~118 `.frame(height: vm.notchState == .open ? vm.notchSize.height : nil)`), but the root view is clamped by `.frame(maxWidth: windowSize.width, maxHeight: windowSize.height)` (ContentView ~line 191). Expand-down therefore needs exactly three coordinated things: (1) `vm.notchSize.height += extra`, (2) relax that one clamp, (3) `window.setFrame` taller with the top edge fixed.

The notch auto-closes on hover exit via `handleHover` -> `vm.close()`, but `vm.close()` and every hover/gesture close path already early-out on `SharingStateManager.shared.preventNotchClose`. Reuse `SharingStateManager.shared.beginInteraction()/endInteraction()` as the keep-open flag (Phase 2 uses it too for its message box; it is a counter, so the two coexist).

Keyboard: the real class is `BoringNotchSkyLightWindow` (line 112 `override var canBecomeKey: Bool { false }`); `BoringNotchWindow.swift` is dead code (never instantiated). Phase 2 plans to change that same line to `OrchestratorManager.shared.wantsKeyboard`. To merge trivially, Phase 3 should NOT add a property on `OrchestratorManager` with that name; use a separate static gate in a new file and edit the line to OR them.

**Primary recommendation:** one new file `Orchestrator/OrchestratorExpand.swift` (state + pure math + monitors + window resizer), one new file `Orchestrator/OrchestratorTerminal.swift` (WKWebView wrapper + busy detection), one new file `Orchestrator/OrchestratorCompact.swift` (dot + usage bar views). Upstream hooks: ContentView (1 overlay line + 1 clamp line), BoringViewModel.open() (1 line), SkyLight window canBecomeKey (1 line), OrchestratorView (expand button + branch to terminal).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary | Rationale |
|------------|-------------|-----------|-----------|
| Attention dot / usage bar | SwiftUI view (ContentView closed notch) | OrchestratorManager (data) | Pure render of existing published state |
| Expanded size state | New `OrchestratorExpand` @MainActor singleton | BoringViewModel.notchSize | Per-screen state, VM already owns visible size |
| Window growth | AppKit NSPanel frame | SwiftUI representable to find window | Only AppKit can resize the panel |
| Outside-click collapse | AppKit NSEvent monitors | — | SwiftUI has no global click awareness |
| Keep notch open | SharingStateManager counter | — | Existing mechanism, all close paths honour it |
| Terminal | WKWebView (NSViewRepresentable) | ttyd via serve proxy | Same-origin 127.0.0.1:4777 satisfies Origin check |
| Key input | NSPanel.canBecomeKey gate | makeFirstResponder(webView) | Panel is non-activating |

## Standard Stack

All system frameworks, no new packages (WebKit is newly imported but is a system framework; no pbxproj package change; verify the target links it automatically via `import WebKit` — Xcode auto-links system frameworks via modules).

| Item | Purpose | Source |
|------|---------|--------|
| `WKWebView` + `WKNavigationDelegate` | terminal | [CITED: developer.apple.com/documentation/webkit/wkwebview] |
| `NSEvent.addGlobalMonitorForEvents` / `addLocalMonitorForEvents` | outside click | already used: `observers/DragDetector.swift:55`, `extensions/PanGesture.swift:89` [VERIFIED: codebase grep] |
| `SharingStateManager.beginInteraction/endInteraction` | keep-open | `models/SharingStateManager.swift` [VERIFIED: codebase] |

Package Legitimacy Audit: no external packages installed this phase. Not applicable.

## Concrete Code Locations (verified in this repo)

### 1. Closed-notch rendering (CMP-01/02)
- `ContentView.body`: `mainLayout = NotchLayout().frame(alignment:.top).padding(...).background(.black).clipShape(currentNotchShape).overlay(alignment:.top){Rectangle 1pt}.shadow(...).padding(.bottom, ...)` (~lines 90-118). Music closed activity is drawn INSIDE `NotchLayout()` -> `MusicLiveActivity()` (HStack artwork | black spacer with visualizer), width driven by `computedChinWidth` (closedNotchSize.width + 2*(h-12)+20).
- **Hook:** add ONE `.overlay(alignment: .topTrailing) { OrchestratorClosedIndicators() }` modifier on `mainLayout` right after the existing `.overlay(alignment: .top){Rectangle...}` and BEFORE `.shadow`. Overlays do not affect layout, so music sizing/artwork are untouched (D-11). Because it is after `.clipShape`, keep the dot inset (>= ~8pt from the trailing edge, ~4pt from top) so the notch corner radius (closed top 6, bottom 14) does not clip it.
- The view self-gates: `vm.notchState == .closed && !vm.hideOnClosed && vm.effectiveClosedNotchHeight > 0` (on non-notch screens in fullscreen the closed notch is 0-high; show nothing). Take `@EnvironmentObject vm` + `@ObservedObject OrchestratorManager.shared`.
- **Dot:** 6pt `Circle().fill(.orange)` (matches runs-strip "waiting" colour), `.opacity` pulse optional (skip; YAGNI). Placed topTrailing so it sits at the notch edge beside the visualizer on the right side of MusicLiveActivity. Show when `manager.needsAttention && !manager.offline`.
- **Usage (D-02 recommendation):** do not render text (closed height is ~32pt, music artwork+visualizer fill it). Render a 2pt-high `Capsule` bar along the bottom edge inside the clip (`.overlay(alignment:.bottom)`), width = `usageFraction(usage)` of the notch width, orange at >= 80 else white at 0.5 opacity. It is an overlay so music is unaffected; record "fits as bottom hairline overlay, no layout change". Fallback if the user dislikes it on UAT: gate with `!musicManager.isPlaying`. Pure helper `usageFraction(_ u: OrchestratorUsage?) -> Double?` = max of 5h/7d `usedPercentage`/100 clamped 0...1, nil when no usage (testable).
- `needsAttention` is already defined (`runs.contains{state=="waiting"} || !promptOptions.isEmpty`) in `OrchestratorManager.swift:15`. Polling while closed runs every 10s (`notchOpen ? 2 : 10`), fine for a dot (note up-to-10s latency; acceptable, mention in summary; do not change poll rate).
- Battery sneak peek chin (width 640) and hello animation also draw in this region; overlay is harmless there. Optionally hide while `coordinator.helloAnimationRunning`.

### 2. Window/panel sizing
- `sizing/matters.swift`: `openNotchSize = 640x190`, `windowSize = 640 x (190+20 shadowPadding)`.
- `boringNotchApp.swift:234 createBoringNotchWindow`: rect = windowSize; `positionWindow` (268) sets origin `y = screen.maxY - window.frame.height` using current frame height -> top pinned even when taller. `adjustWindowPosition` (478, run on screen-parameter changes at lines ~288-325, 458-472) only calls `positionWindow`/`vm.close()` if closed; it never resets the frame size. So an expanded window survives a screen change and stays pinned. One caveat: it also calls `vm.close()` only when `notchState == .closed`.
- `BoringViewModel.open()` (line 192): `self.notchSize = openNotchSize`. `close()` (201): blocked by `preventNotchClose`; sets closed size.
- **Problem found:** `ContentView` `.onTapGesture { doOpen() }` calls `vm.open()` even when already open, which resets `notchSize` to `openNotchSize` and would visually shrink the notch inside a still-tall window. **Hook (1 line):** in `BoringViewModel.open()` replace `openNotchSize` with `OrchestratorExpand.shared.openSize(for: screenUUID)` (returns `openNotchSize` plus extra when that screen is expanded).
- **Clamp (1 line):** ContentView ~191 `.frame(maxWidth: windowSize.width, maxHeight: windowSize.height + max(0, vm.notchSize.height - openNotchSize.height), alignment: .top)`. Closed `notchSize.height` is < 190 so the extra is 0 when closed; no new observation needed because `vm` is already observed. Pure fn: `windowHeight(notchHeight:) = windowSize.height + max(0, notchHeight - openNotchSize.height)`.
- **Window grow:** an `NSViewRepresentable` "WindowAccessor" (new file) placed as `.background` inside the expand-capable view captures `view.window`. `OrchestratorExpand.expand(vm:window:)`: `var f = window.frame; f.origin.y -= extra; f.size.height += extra; window.setFrame(f, display: true)` (no AppKit animation; SwiftUI spring animates content; window is transparent so instant growth is invisible). Collapse: set `vm.notchSize` first with animation, shrink the window after ~0.45s (`Task.sleep(for:)`) so the spring is not clipped. Use `f.origin.y += extra` for shrink. Better: compute from `screen.frame.maxY - newHeight` (pure fn `pinnedFrame(current:, newHeight:)` keeps `maxY` constant) so rounding cannot drift.
- Multi-display (`showOnAllDisplays`): there is one window+vm per screen (`windows[uuid]`, `viewModels[uuid]`). Key expansion state by `vm.screenUUID` (`Set<String>`/`String?`), not a single global Bool; the representable gives the right window automatically.
- Expanded height: recommend `extra = 300` (notch total 190+300=490, window 510). Clamp so it fits: `extra = min(300, screen.visibleFrame.height - openNotchSize.height - 40)` (pure fn `expandedExtra(screenHeight:)`).

### 3. Click-outside and keep-open
- Hover close: `ContentView.handleHover(false)` -> after 100 ms `vm.close()` guarded by `!isBatteryPopoverActive && !preventNotchClose`. `.sharingDidFinish`, battery popover and drop handlers have the same guards; `vm.close()` itself early-returns on `preventNotchClose`. **So while expanded: `SharingStateManager.shared.beginInteraction()`; on collapse `endInteraction()` (balanced exactly once; guard with the expanded flag).** Collapse then calls `vm.close()` only for the click-outside / close-requested case.
- Click outside: no existing global click-to-close. Add monitors in new code when expanded, remove on collapse:
  - `NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown])` fires for clicks in OTHER apps/windows (no extra permission for mouse events; DragDetector already uses it under this sandbox).
  - `NSEvent.addLocalMonitorForEvents(matching: [...])` for clicks in the app's own windows including the transparent margin of the panel (window 640x210+ is bigger than the visible notch because of shadow/8pt padding). Return the event unchanged.
  - Both test `NSEvent.mouseLocation` (screen coords, same space as `window.frame`) against `notchRect = (frame.midX - openNotchSize.width/2, frame.maxY - vm.notchSize.height, openNotchSize.width, vm.notchSize.height)`. Pure fn `isOutsideNotch(point:windowFrame:notchSize:)` -> testable. Outside -> `collapse()` (and per D-05 "closing also collapses": after collapse also `vm.close()` if the pointer is not hovering; the hover handler will normally do this itself 100 ms after `endInteraction`, but hover state is already false so call `vm.close()` explicitly).
  - Ignore clicks inside the notch rect (the terminal and header buttons). Remember to remove monitors (`NSEvent.removeMonitor`) on collapse, on view disappear, and when `notchOpen` becomes false.
- Closing the notch also collapses: `OrchestratorManager.notchOpen didSet` (already fed by `vm.open()/close()`) is the existing hook; add one line `if !notchOpen { OrchestratorExpand.shared.reset() }`. Because `close()` is blocked while expanded, this fires only after collapse released the interaction; it is a safety net. Also collapse in `OrchestratorView.onDisappear` (tab switch).

### 4. Keyboard focus
- `BoringNotchSkyLightWindow` (components/Notch/BoringNotchSkyLightWindow.swift): `NSPanel`, style `[.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]`, `canBecomeKey { false }`, `canBecomeMain { false }`. `BoringNotchWindow.swift` is unused.
- **Merge-safe design:** new file defines `@MainActor enum OrchestratorKeyGate { static var terminalWantsKey = false }`. Edit the one existing line to `override var canBecomeKey: Bool { OrchestratorKeyGate.terminalWantsKey }`. Phase 2 will edit the same line (`OrchestratorManager.shared.wantsKeyboard`); resolution at merge is the trivial OR: `OrchestratorManager.shared.wantsKeyboard || OrchestratorKeyGate.terminalWantsKey`. State this in the summary. Do NOT add `wantsKeyboard` on OrchestratorManager in Phase 3 (would conflict with P2's addition).
- Flow: on terminal shown -> `terminalWantsKey = true`; `window.makeKey()` then `window.makeFirstResponder(webView)`; never `NSApp.activate`. On collapse: `terminalWantsKey = false; window.resignKey()`. Clicking in the WKWebView also makes the panel key because `canBecomeKey` now returns true. [ASSUMED: a non-activating NSPanel that returns true from canBecomeKey receives key events without app activation; standard behaviour, needs user UAT.]
- Swift 5 mode: `canBecomeKey` is nonisolated-in-practice but NSWindow is `@MainActor` in the macOS 14+ SDK so reading a `@MainActor` static compiles; if the compiler complains use `nonisolated(unsafe) static var`.

### 5. WKWebView / ttyd / serve proxy
- Entitlements: sandbox with `network.client` + `network.server`, `NSAllowsArbitraryLoads` already true [VERIFIED: project CLAUDE.md/stack table]. WKWebView out-of-process networking in a sandbox needs `com.apple.security.network.client` only; present. No change.
- Serve proxy (read-only `/Users/mitch/Documents/Claude/orchestrator/orch.js`): ttyd listens on a unix socket with args `-b /term -W -O -m 1` (writable, `-O` check-origin, `-m 1` max-clients=1). `/term` and `/term/*` proxy to ttyd; Host must be `127.0.0.1:4777`/`localhost:4777`; websocket upgrade requires Origin `http://127.0.0.1:4777` and path under `/term/`, else the socket is destroyed. `HEAD /term` returned `302 Location: /term/` from `ttyd/1.7.7` [VERIFIED: curl -sI]. If ttyd not installed, `/term` returns 503 text; if ttyd not ready, 502 text.
- **Load `http://127.0.0.1:4777/term/`** (trailing slash avoids the redirect; either works). Origin of the page is then exactly the allowed origin. Never use `localhost`.
- **Busy detection:** ttyd `--max-clients 1` refuses the second websocket in `LWS_CALLBACK_FILTER_PROTOCOL_CONNECTION` (`return 1`) [CITED: github.com/tsl0922/ttyd src/protocol.c]. The HTML page itself still loads (HTTP 200), so `WKNavigationDelegate.didFinish` succeeds and cannot detect it. The ttyd web client on socket close shows an xterm overlay "Connection Closed", then "Press ⏎ to Reconnect" (error sets `doReconnect=false`) [CITED: github.com/tsl0922/ttyd html/src/components/terminal/xterm/index.ts]. **Recommended detection:** after `didFinish`, poll `evaluateJavaScript("document.body.innerText")` every 1s for up to ~5s and treat text containing `Reconnect` or `Connection Closed` as "terminal in use". Pure fn `terminalState(pageText: String?) -> .connected|.inUse` is testable. Also `didFail`/`didFailProvisionalNavigation` -> offline/error; HTTP 502/503 body text is plain, so detect via `decidePolicyFor navigationResponse` status code `!= 200` -> show "terminal unavailable". Overlay class names are not confirmed, so rely on text, not selectors. [ASSUMED: text search of body works on the xterm overlay DOM; overlay may be rendered inside xterm container div, innerText should include it. Verify at UAT; fallback = if nothing after 5s keep showing the web view.]
- Gracefulness: overlay `Text("terminal in use")` + Retry button (recreates the webview). Behind it optionally the larger chat tail (EXP-01) so expanded is still useful: reuse `chatTail(screen:maxLines:)` with maxLines ~ 24.
- Teardown: on collapse call `webView.stopLoading(); webView.load(URLRequest(url: URL(string:"about:blank")!))` then drop the reference (state `@State`/owner view destroyed). A lingering view keeps the ttyd client slot; a quick re-expand would otherwise show "in use". `dismantleNSView` in the representable is the place for this.
- Navigation restriction: `decidePolicyFor navigationAction` allow only host `127.0.0.1` port 4777; cancel others.
- Never load /term in build/verification (D-09). Verification is compile + swiftc asserts; runtime behaviour is user UAT.
- Appearance: `webView.setValue(false, forKey: "drawsBackground")` (KVC, works on macOS) to avoid white flash; the notch is black.

### 6. Pure logic for the swiftc harness
Compile (as Phase 1): `mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/Tests/main.swift && /tmp/orch-test/t` — so put pure funcs in a NEW Foundation/CoreGraphics-only file `OrchestratorPure.swift` (no SwiftUI/AppKit imports, no dependency on `windowSize`/`openNotchSize` globals: pass sizes as parameters). Tests to add to `Tests/main.swift` (it uses `precondition`):
- `expandedExtra(screenHeight:)` clamps (e.g. 1080 -> 300; small screen -> reduced, never < 0).
- `windowHeight(base:notchHeight:openHeight:)` (closed -> base; expanded -> base+extra).
- `pinnedFrame(current:newHeight:)` keeps `maxY` equal.
- `isOutsideNotch(point:windowFrame:notchWidth:notchHeight:)` inside/edge/outside/above-top.
- `usageFraction(_:)` (nil, 5h only, max of two, >100 clamp).
- `terminalState(pageText:)` ("Press ⏎ to Reconnect" -> inUse, "Connection Closed" -> inUse, nil/"" -> connecting, other -> connected).
- `chatTail` unchanged.
Note `OrchestratorUsage` lives in `OrchestratorModels.swift` (already in the compile line).

## Architecture Patterns

```
 OrchestratorView (tab) --expand button--> OrchestratorExpand.shared (@MainActor, per-screen)
        |                                      |-- vm.notchSize = open + extra (animated)
        |                                      |-- window.setFrame (top pinned) via WindowAccessor
        |                                      |-- SharingStateManager.beginInteraction (keep open)
        |                                      |-- OrchestratorKeyGate.terminalWantsKey = true; makeKey
        |                                      '-- NSEvent global+local monitors -> outside click -> collapse
        v
 OrchestratorTerminalView (WKWebView, only while expanded) -> http://127.0.0.1:4777/term/ -> serve proxy -> ttyd (-m 1)
 ContentView closed notch -> .overlay(OrchestratorClosedIndicators) <- OrchestratorManager.needsAttention / usage
```

Upstream-touching hooks (each 1 line unless stated): ContentView overlay; ContentView clamp; BoringViewModel.open() size; SkyLight `canBecomeKey`; OrchestratorManager `notchOpen` didSet reset; OrchestratorView (expand button in chat area + `if expanded { OrchestratorTerminalView }`, plus `onDisappear`).

Where to put the expand button: inside `OrchestratorView` (overlay topLeading of the chat, parallel to the runs overlay) rather than the header, to avoid colliding with Phase 2 header/row edits. Keep the edit to a single `.overlay(alignment: .bottomTrailing) { OrchestratorExpandButton() }` line.

## Don't Hand-Roll

| Problem | Use Instead |
|---------|-------------|
| Notch keep-open | `SharingStateManager.beginInteraction/endInteraction` |
| Terminal emulation | ttyd page in WKWebView |
| Polling of state | existing `OrchestratorManager` |
| HTTP | none needed (terminal is the web page) |

## Common Pitfalls

1. **`vm.open()` resets size on tap** (above). Hook the size in `open()`.
2. **Unbalanced begin/endInteraction** leaves the notch stuck open. Tie both to a single `expanded` Bool transition; call end exactly in `collapse()`.
3. **Window shrinks before the SwiftUI collapse animation ends** clips the spring. Delay frame shrink ~0.45s; but if user re-expands within the delay, cancel the pending shrink task.
4. **Global monitor does not see clicks inside the app's own windows** (the panel margin). Install the local monitor too.
5. **Terminal "in use" after quick re-expand** because the old websocket has not closed. Load about:blank in `dismantleNSView`; offer Retry.
6. **WKWebView recreated on every SwiftUI update.** Create once in `makeNSView`; `updateNSView` no-op.
7. **Dot clipped by notch corner radius.** Inset it; the overlay is applied after `.clipShape`.
8. **`canBecomeKey` stays true after collapse** and steals typing from other apps. Reset the gate in `collapse()`, `reset()`, and `dismantleNSView`.
9. **Header/hello/battery overlap:** hide indicators during `helloAnimationRunning`.
10. **Esc inside xterm** goes to the terminal, not to the notch: acceptable.
11. Do not touch `DragDetector` region (uses openNotchSize.height); not needed.

## Code Examples

```swift
// OrchestratorPure.swift (Foundation + CoreGraphics only)
func isOutsideNotch(point: CGPoint, windowFrame: CGRect, notchWidth: CGFloat, notchHeight: CGFloat) -> Bool {
    let r = CGRect(x: windowFrame.midX - notchWidth / 2, y: windowFrame.maxY - notchHeight, width: notchWidth, height: notchHeight)
    return !r.contains(point)
}
func pinnedFrame(current: CGRect, newHeight: CGFloat) -> CGRect {
    CGRect(x: current.minX, y: current.maxY - newHeight, width: current.width, height: newHeight)
}
```

```swift
// ContentView hooks (illustrative)
.overlay(alignment: .top) { Rectangle()... }          // existing
.overlay(alignment: .topTrailing) { OrchestratorClosedIndicators() }   // NEW (self-gated)
...
.frame(maxWidth: windowSize.width, maxHeight: windowSize.height + max(0, vm.notchSize.height - openNotchSize.height), alignment: .top)  // CHANGED
```

```swift
struct OrchestratorTerminalView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.setValue(false, forKey: "drawsBackground")
        w.navigationDelegate = context.coordinator
        w.load(URLRequest(url: URL(string: "http://127.0.0.1:4777/term/")!))
        return w
    }
    func updateNSView(_ v: WKWebView, context: Context) {}
    static func dismantleNSView(_ v: WKWebView, coordinator: Coordinator) {
        v.stopLoading(); v.load(URLRequest(url: URL(string: "about:blank")!))
    }
}
```

## Runtime State Inventory
Not a rename/migration phase: none.

## Environment Availability

| Dependency | Required By | Available | Notes |
|------------|------------|-----------|-------|
| Xcode / xcodebuild, swiftc | build + asserts | assumed present (Phase 1 used) | use derived data `/tmp/notch-dd-p3` |
| orchestrator serve + ttyd 1.7.7 | runtime terminal | yes (HEAD /term answered by ttyd) | runtime only; not touched in verification |

## Security Domain

| ASVS | Applies | Control |
|------|---------|---------|
| V5 Input | yes | WKNavigationDelegate restricts to 127.0.0.1:4777; no user-supplied URLs |
| V4 Access | no | local only |
Threats: WebView navigating to arbitrary page in a privileged always-on-top panel (mitigate by allow-list); terminal key capture left on after collapse (reset gate); POSTs to :4777 never made (Phase 3 makes no HTTP requests of its own).

## Assumptions Log

| # | Claim | Risk if Wrong |
|---|-------|---------------|
| A1 | Non-activating NSPanel with `canBecomeKey == true` delivers keys to WKWebView without app activation | Terminal not typeable; fall back to `NSApp.activate` (rejected by Phase 2 D-09) or user decides; UAT item |
| A2 | `document.body.innerText` contains the ttyd overlay text ("Press ⏎ to Reconnect"/"Connection Closed") | Busy not detected; page shows dead terminal; fallback timeout message or Retry always visible |
| A3 | WKWebView in sandbox needs only network.client | Page fails to load; would need entitlement change (unlikely) |
| A4 | `import WebKit` auto-links without pbxproj edits | Link error; add framework in target |
| A5 | Local+global monitors together cover all outside clicks including panel margin | Margin clicks ignored; verify at UAT |
| A6 | `window.setFrame` growth without AppKit animation is visually fine because window is transparent | Flicker; use animate: true |

## Open Questions
1. Per-screen vs single expanded state with `showOnAllDisplays`: recommended per-screen; low impact if only one display.
2. Whether UAT wants usage bar visible with music: record the choice; easy to gate.

## Validation Architecture
`workflow.nyquist_validation` is false in `.planning/config.json`: section skipped. Automated checks are the swiftc assert harness (above) and the xcodebuild compile; runtime (dot, expand, terminal typing, outside click) is human UAT.

## Sources
- Repo: ContentView.swift, BoringViewModel.swift, sizing/matters.swift, boringNotchApp.swift, BoringNotchSkyLightWindow.swift, SharingStateManager.swift, OrchestratorView/Manager/Models, Tests/main.swift (HIGH)
- orch.js (read-only) serve/ttyd proxy lines 496-600 (HIGH); `curl -sI http://127.0.0.1:4777/term` -> 302 (HIGH)
- ttyd src/protocol.c max-clients/origin refusal; html xterm index.ts overlay behaviour (MEDIUM-HIGH, fetched from GitHub main)
- Phase 2 CONTEXT (branch orch/261014005634-9e3f) D-08..D-10 for merge design
- Apple AppKit/WebKit behaviour: training knowledge (MEDIUM), UAT required

**Research date:** 2026-10-14 | **Valid until:** 30 days
