# Pitfalls Research

**Domain:** Adding an HTTP-polling Orchestrator tab (text input, prompt buttons, WKWebView terminal, expand-down) to the Boring Notch fork
**Researched:** 2026-10-14
**Confidence:** HIGH for repo-specific findings (read from source); MEDIUM for AppKit/WebKit behaviour (well-known, not re-verified against current docs); LOW where noted

Phases: **P1** read-only tab · **P2** sending / start / end · **P3** compact indicators + expand-down

## Critical Pitfalls

### Pitfall 1: Text field never receives keystrokes (panel cannot become key)

**What goes wrong:** The message box shows a caret or nothing, and typed keys go to the frontmost app instead.
**Why it happens:** Both notch window classes hard-code `canBecomeKey = false` / `canBecomeMain = false`: `boringNotch/components/Notch/BoringNotchWindow.swift:43-49` and `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift:112-113` (also around :53). The live window is `BoringNotchSkyLightWindow`, created with `[.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]` (`boringNotch/boringNotchApp.swift:236-238`). The app is `LSUIElement = YES` (pbxproj:1241). The repo's only TextFields are in Settings, which is a normal window.
**How to avoid:** Make `canBecomeKey` conditional, not always true. For example, return true only while the Orchestrator tab is visible and the notch is open, via a static/shared flag. `.nonactivatingPanel` lets the panel become key *without* activating the app, which is the Spotlight pattern. Do not call `NSApp.activate`, because that steals focus from the user's app. Call `window.makeKey()` when the field is clicked, and call `resignKey` or reset the flag on close so the user's app gets the keyboard back. Leave it false everywhere else so music, HUDs and the shelf behave as before.
**Warning signs:** You can only type after clicking twice. The beep sound plays. Keys go to the app behind. `window.isKeyWindow` stays false.
**Phase:** P2. Spike it at the very start of P2, before building the UI, because the rest of P2 depends on it.

### Pitfall 2: Notch collapses while typing or reading

**What goes wrong:** The pointer drifts off the notch while the user types, so the notch closes and the draft is lost. Hover-close is also what the "click outside collapses" expand mode is meant to do, and the two fight each other.
**Why it happens:** `handleHover(false)` closes after 100 ms (`boringNotch/ContentView.swift:540-556`). The only escape hatches are `SharingStateManager.shared.preventNotchClose` and `vm.isBatteryPopoverActive`. `vm.close()` also returns early on `preventNotchClose` (`boringNotch/models/BoringViewModel.swift:200-204`).
**How to avoid:** Reuse the existing guard instead of adding new conditions to every close path. Either add a begin/end session in `SharingStateManager` while the field is focused or the terminal is expanded, or add one `@Published` flag that `close()` checks once. Every close path already routes through `vm.close()`, so a single guard there covers hover, swipe-up, drop and sharing. Release the guard on Escape, on submit, on outside click (a global `NSEvent` monitor for `.leftMouseDown` while expanded), and on screen lock. If any one of those is missed, the notch stays open forever.
**Warning signs:** The notch closes mid-word, or the notch never closes after a send.
**Phase:** P2 (typing). P3 extends it to expand-down plus outside-click collapse.

### Pitfall 3: Breaking music when touching the tab enum or `close()`

**What goes wrong:** Music controls disappear or the notch opens on the wrong tab, or the closed music live activity shifts.
**Why it happens:** `NotchViews` (`boringNotch/enums/generic.swift:27-30`) is switched exhaustively at `ContentView.swift:347-351`. `close()` resets `currentView` to `.home` or `.shelf` (`BoringViewModel.swift:214-218`). With "open last tab by default" on, the notch can reopen on Orchestrator instead of music. Drag/drop forces `.shelf` (`ContentView.swift:222`, `boringNotchApp.swift:227,230`).
**How to avoid:** Append the case `.orchestrator` last and add one `case` in the ContentView switch plus one `TabModel` (`TabSelectionView.swift:17-20`). Don't reorder or rename anything. Leave `close()`'s reset logic alone. Never change `openNotchSize` (`sizing/matters.swift:16`), because home/music layout depends on it. Size the orchestrator view inside the existing 640x190 area. Expand-down is a separate, opt-in height (see Pitfall 4).
**Warning signs:** The diff touches `NotchHomeView`, `MusicManager`, `openNotchSize` or `windowSize`. A music regression check is missing from the phase UAT.
**Phase:** P1 (enum/tab). P3 (sizing).

### Pitfall 4: Expand-down clipped by fixed window size, or leaving a dead click zone

**What goes wrong:** The expanded view is cut off at 210 pt, or the window grows and then blocks clicks to the apps below even when collapsed.
**Why it happens:** The window is created once at `windowSize` (640x(190+20)) (`boringNotchApp.swift:235`, `sizing/matters.swift:17`). ContentView clamps to `.frame(maxWidth: windowSize.width, maxHeight: windowSize.height)` (`ContentView.swift:206`). `positionWindow` anchors the window by its current height (`boringNotchApp.swift:268-279`). The drag detector region uses `openNotchSize` (`boringNotchApp.swift:199-205`). `showOnAllDisplays` creates one window per screen (`:415,:497,:532`).
**How to avoid:** Grow the window frame only while expanded. Use `setFrame` keeping the top edge pinned (y = screen.maxY - newHeight), and shrink it back on collapse. Replace the hard `windowSize` clamp in ContentView with a value that is `windowSize` normally and the expanded height when expanded. That is one-line edits in existing files, and the logic goes in a new file. Animate the SwiftUI content, not the NSWindow frame, to avoid jank.
**Warning signs:** Clicks under the notch area stop working. The expanded content gets cut off on displays without a notch. On multiple screens, only one screen expands.
**Phase:** P3. Flag P3 for a focused research/spike.

### Pitfall 5: WKWebView terminal can't take keyboard input, or tears down on every close

**What goes wrong:** The terminal renders but typing does nothing. Or every open/close reloads ttyd, which reconnects the websocket and spawns a new ttyd client.
**Why it happens:** WKWebView needs its window to be key (Pitfall 1) and itself to be first responder. The open view is only built while `vm.notchState == .open` (`ContentView.swift:345`), so an `NSViewRepresentable` WKWebView is destroyed on every collapse.
**How to avoid:** Use the same conditional `canBecomeKey` as Pitfall 1, and call `window.makeFirstResponder(webView)` after load. Create the view only when the user expands. Accept a reload per expand (cheap), but do not keep a hidden live websocket around. Load exactly `http://127.0.0.1:4777/term`, not `localhost`, so the ttyd `Origin` check passes. Set the background to non-opaque and dark to avoid a white flash.
**Warning signs:** A white rectangle flashes before the terminal draws. ttyd logs show reconnect storms. Keys echo into the app behind the notch.
**Phase:** P3.

### Pitfall 6: Polling leaks, duplicates, or runs on the wrong thread

**What goes wrong:** CPU and battery drain, two or more pollers (one per screen or per view re-render), requests pile up when serve hangs, and "Publishing changes from background threads" warnings appear.
**Why it happens:** SwiftUI recreates views, and `.onAppear` timers are never invalidated. `showOnAllDisplays` creates one ContentView per screen. URLSession's default timeout is 60 s.
**How to avoid:** Use one `@MainActor final class OrchestratorClient: ObservableObject` singleton, created once like `SharingStateManager.shared`. Run a single `Task` loop with `try await Task.sleep`, and change its interval when `notchState` changes (about 2 s open, about 15–30 s closed; closed polling is still needed for P3 indicators). Never start a new request while one is in flight. Set `timeoutIntervalForRequest` to about 3 s. Pause while the screen is locked (the app already observes lock, `boringNotchApp.swift:97-107`). Cancel the task on deinit.
**Warning signs:** Activity Monitor shows CPU above ~1% while idle. Serve logs show more than one GET every 2 s. Xcode shows purple runtime warnings.
**Phase:** P1 (client and loop). P3 (closed-state cadence).

### Pitfall 7: Ad-hoc / unsigned builds silently change sandbox and permissions

**What goes wrong:** (a) With `CODE_SIGNING_ALLOWED=NO`, entitlements are not embedded, so the app runs **unsandboxed**. HTTP and WebKit then "work" in dev but would differ from a signed build, and the embedded XPC helper (`XPCHelperClient.swift:8,28`) may fail to launch. (b) Every ad-hoc rebuild changes the cdhash, so TCC grants (Apple Events for Spotify/Music, Accessibility, Calendar, Camera) can reset. Music control then looks "broken" by the change when it is really a permissions issue.
**How to avoid:** Build with `CODE_SIGN_IDENTITY=-` (ad-hoc, which the project already uses on macOS: pbxproj `"CODE_SIGN_IDENTITY[sdk=macosx*]" = "-"`) and `DEVELOPMENT_TEAM=""`, not `CODE_SIGNING_ALLOWED=NO`. Verify with `codesign -d --entitlements - <app>` that `app-sandbox` and `network.client` are present, and check the helper too. When music fails after a rebuild, check System Settings → Privacy (Automation) before blaming code.
**Warning signs:** `codesign -dv` shows "code object is not signed". Music works in one build and fails in the next with no code change. The XPC connection is interrupted.
**Phase:** P1 (build). Confirm in every phase's UAT.

### Pitfall 8: Sparkle replaces the fork with upstream's release

**What goes wrong:** Sparkle starts on launch (`boringNotchApp.swift:24-25`) with `SUFeedURL` pointing to TheBoredTeam's appcast (`Info.plist:14-15`). An "update" installs stock Boring Notch over the fork, and the Orchestrator tab vanishes.
**How to avoid:** Turn off automatic checks in the local install (Settings → "Automatically check for updates", `SoftwareUpdater.swift:51`), or never install the prompted update. Don't edit `Info.plist`/Sparkle code for this, to keep the upstream diff small. Note it in the README/UAT.
**Warning signs:** An update prompt appears. The tab is gone after a restart.
**Phase:** P1 (document it as part of build/run).

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| `canBecomeKey = true` unconditionally | Typing works instantly | Notch steals keyboard focus on every hover, which breaks normal use | Never |
| Adding new files to the classic `boringNotch` group in pbxproj | Normal Xcode workflow | Each new file adds PBXBuildFile/FileRef/group lines, which means conflicts on upstream merges | Avoid. Use one new `PBXFileSystemSynchronizedRootGroup` (objectVersion 70 supports it; see `private`, pbxproj:325) for an `boringNotch/Orchestrator/` folder. That is one pbxproj edit, then zero |
| Adding strings to `Localizable.xcstrings` (23.6k lines, Crowdin-managed via `crowdin.yml`) | Localized UI | Guaranteed merge conflicts | Never. Use `Text(verbatim:)` / non-localized strings for orchestrator UI |
| Parsing the whole `screen` for prompts | Simple | False positives from old prompts in scrollback | Never (see Integration) |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| ATS | Adding an `NSAllowsLocalNetworking` exception | Not needed. `Info.plist:5-9` already sets `NSAllowsArbitraryLoads`. Don't touch Info.plist |
| Sandbox | Expecting to need new entitlements | `network.client` (plus `network.server`) is already in `boringNotch.entitlements`. Nothing to add |
| POST endpoints | Forgetting the `x-orch: 1` header, which makes requests fail silently | One helper sets the header plus `Content-Type: application/json` for every POST |
| `POST /api/chat` 409 | Treating it as an error toast | 409 = chat not running. Flip the UI to show the Start button |
| Prompt detection | Regex for `1.` anywhere in the screen tail | Only look at the last ~15 non-empty lines, and require Claude Code's selector shape: a `❯` cursor on a numbered option plus a footer like "Esc to cancel" (LOW confidence on exact glyphs: capture real `screen` samples of question and permission prompts first and build the matcher from them). Hide buttons immediately after a key is sent until the next poll |
| Option buttons | Sending the digit plus Enter | Send `{key:"1"}` only. Claude Code selects on the digit, and a following Enter could confirm the next prompt |
| Enter-to-send | `onSubmit` plus a button both firing, or a resend on focus loss | Single send path. Clear the field only on 2xx. Disable while in flight |
| `resets_at` | Treating it as ms or as an ISO string | It is epoch **seconds**: `Date(timeIntervalSince1970:)` |
| Offline | Retry spam or blank tab | Connection refused means "orchestrator offline — run `node orch.js serve`". Keep the same poll cadence |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Re-rendering a 200-line `Text` every 2 s | Scroll jumps, CPU spikes, animation stutter in the music view | Only publish when `screen` changed (compare strings). Show the tail (about 20 lines) in the compact tab. Use a monospaced `Text` in a `ScrollView` anchored to the bottom | Immediately on lower-end Macs |
| Polling while closed at the open rate | Battery drain all day | Slow cadence when closed (Pitfall 6) | Always-on app, 24/7 |
| One poller per screen | N× requests | Singleton client | Multi-display plus `showOnAllDisplays` |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Making the base URL configurable or remote | Sending keystrokes to an arbitrary host | Hard-code `http://127.0.0.1:4777` |
| Click-through on End or option buttons | Accidentally stopping the orchestrator or approving a permission prompt | Confirm before End. Option buttons need a deliberate click (no hover actions, no keyboard shortcuts) |
| WKWebView navigating away from `/term` | Arbitrary pages inside a privileged always-on-top panel | `WKNavigationDelegate`: allow only the `127.0.0.1:4777` origin |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Attention dot that never clears | Notification fatigue | Derive the dot purely from the current poll (any `waiting` run or detected prompt). Don't store it |
| Closed-notch indicator shifting the music live activity | Music UI jumps | Place the indicator in a fixed slot. Check against the closed music activity before shipping (P3) |
| Typing focus held after notch closes | Next keystrokes vanish | Resign key on close (Pitfall 1) |

## "Looks Done But Isn't" Checklist

- [ ] **Text input:** works with another app frontmost (not just Xcode). Focus returns to that app after the notch closes.
- [ ] **Music:** play/pause/skip/artwork still work after the tab is added, both open and closed, and across a rebuild.
- [ ] **Offline:** stop serve, and the tab shows the hint within one poll. Restart, and it recovers without relaunching.
- [ ] **Prompt buttons:** don't appear for an already-answered prompt still in scrollback.
- [ ] **Expand:** collapses on outside click and on Escape. The window frame returns to 210 pt, and clicks below the notch work again.
- [ ] **Signing:** `codesign -d --entitlements -` shows the sandbox on the built app.
- [ ] **Multi-display:** one poller, and the indicator shows on each notch window.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Upstream merge conflict in pbxproj/xcstrings | LOW–MEDIUM | Take upstream's version, then re-add the single synchronized-group entry |
| Lost TCC permissions after rebuild | LOW | `tccutil reset AppleEvents <bundle id>` and re-grant |
| Notch stuck open (guard never released) | LOW | Release on `notchState` → closed, on lock, and on tab change, as a backstop |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 3 Tab enum / music regression | P1 | Music UAT in open and closed states |
| 6 Polling lifecycle and main thread | P1 | One GET per ~2 s open, slower closed. No purple warnings |
| 7 Signing / sandbox / TCC | P1 | `codesign` entitlements check |
| 8 Sparkle overwriting fork | P1 | Auto-check off |
| pbxproj / xcstrings conflicts | P1 | `git diff upstream/main --stat` shows new folder plus a few hook lines |
| 1 Key window for text field | P2 (spike first) | Type with Safari frontmost |
| 2 Hover-close while typing | P2 | Move pointer away mid-typing and the notch stays open |
| Prompt false positives / double send | P2 | Replay captured `screen` samples |
| 4 Expand-down window sizing | P3 (needs a spike) | Frame shrinks back, and click-through works |
| 5 WKWebView focus / origin | P3 | Type `ls` in the terminal, and ttyd accepts the websocket |
| Closed indicator vs music activity | P3 | Closed music activity unchanged |

## Sources

- Repo source, read directly (HIGH): `BoringNotchWindow.swift`, `BoringNotchSkyLightWindow.swift`, `boringNotchApp.swift`, `ContentView.swift`, `BoringViewModel.swift`, `SharingStateManager.swift`, `sizing/matters.swift`, `TabSelectionView.swift`, `enums/generic.swift`, `Info.plist`, `boringNotch.entitlements`, `project.pbxproj`
- AppKit NSPanel `.nonactivatingPanel` / `canBecomeKey` and WKWebView first-responder behaviour: training knowledge (MEDIUM), not re-verified this session
- Claude Code prompt rendering (selector glyphs, footer text): LOW. Capture real samples from `GET /api/chat` before writing the matcher
