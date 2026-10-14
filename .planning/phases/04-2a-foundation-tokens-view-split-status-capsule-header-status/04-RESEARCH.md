# Phase 4: 2a Foundation - Research

**Researched:** 2026-10-14
**Domain:** SwiftUI/AppKit refactor of an existing in-repo feature (Swift 5 mode, macOS 14 target); no new packages
**Confidence:** HIGH on codebase facts (all `[VERIFIED: codebase]`), MEDIUM on Claude Code spinner format, LOW-MEDIUM on header fit (not rendered; app may not be launched)

<user_constraints>
## User Constraints (from 04-CONTEXT.md)

### Locked Decisions
D-01 One `OrchestratorTokens.swift` (namespaced enum, e.g. `OT`): surfaces, text grays, Claude accent `#D97757`, status colours (+text/background variants), SF Pro/Mono sizes, radii, spacing, header 34, notch padding 0 14 12.
D-02 `OrchestratorView.swift` becomes a thin shell; existing behaviour moves unchanged into `OrchestratorChat.swift` (chat tail + composer, typing/key-gate untouched), `OrchestratorPromptCard.swift` (option buttons, esc, 3s lock), `OrchestratorRunsBoard.swift` (runs strip shown when segment = Runs instead of overlay). Restyle with tokens only where trivial.
D-03 Segment and capsule per README "Header". Segment only on Orchestrator tab, hidden offline. Capsule shows in the open header on all tabs.
D-04 Capsule: Connecting until `hasLoaded`; Offline when `offline`; Stopped when `!chatRunning`; Needs you when `needsAttention`; Running when screen shows live working line (esc to interrupt); else Idle. Ring = 5h used_percentage (orange >=80). No "ctx N%" and no divider this phase.
D-05 `showRuns` becomes `showRunsBoard`; runs overlay goes away.
D-06 `BoringHeader.swift` edits limited to swapping the three controls for `OrchestratorHeaderSegment()` (left, after `TabSelectionView()`) and `OrchestratorHeaderTrailing()` (right). Tab icons stay.
D-07 Status menu is a SwiftUI overlay inside the notch (not `.popover`), 232px wide, README 06 rows. Interrupt = `pressEscape()` (1s debounce); End = 4s confirm; Start chat when stopped. Content dims to 35%; tap outside closes. Must fit 190px; tighten padding and note it.
D-08 Copy exactly: "Orchestrator chat is stopped" / "▶ Start chat" / "N runs still active · see Runs" (tap switches segment; hidden at 0 live runs); "Can't reach the orchestrator" / mono chip "node orch.js serve · 127.0.0.1:4777" / "Retrying every 10s"; connecting = 4 skeleton bars (9px, r5, #1C1C1E, 48/30/62/40%) bottom-aligned + composer. Offline retry interval must be 10s.
D-09 Implement MERGE-MAP "Phase 4 pre-creates" and "Shared hooks" (stubs registered in pbxproj, Tests/Phase4..7Tests.swift + main.swift calls, detectPrompt/PromptOption moved to `OrchestratorPromptParse.swift` with `PromptCard` + `detectPromptCard(screen:)`, `manager.prompt`, `parseLiveStatus` + `manager.liveStatus`, `ExpandLevel` API, `pollInterval(notchOpen:chatRunning:)`, `"C-u"` in allowedKeys).
D-10 Phase 5 fetches `GET /api/chat/blocks?since=<id>`; Phase 6 enriches `detectPromptCard`; Phase 7 owns expand levels, runs fields, wings.
S-01 NEVER POST to 127.0.0.1:4777; do not load /term. S-02 build only with separate derived data (`/tmp/notch-dd-p4`). S-03 upstream-mergeable, no deps, HTTP only, Swift 5, `@MainActor` ObservableObject singletons. S-04 music must not regress. S-05 never push / no branches. S-06 pure logic gets assert checks in swiftc harness. S-07 follow handoff exactly.

### Claude's Discretion
Token naming, file-internal structure, capsule/segment decomposition, live-status regex, cross-fade for capsule label.

### Deferred Ideas (OUT OF SCOPE)
Transcript rows/composer 02/02b (5); decision card/question list (6); runs cards, expand levels behaviour, expanded/rail, wings (7); ctx %, SSE (8); approval drop-down, global shortcuts (9).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FND-01 | Tokens file | Tokens section below; no existing `Color(hex:)` in repo (grep) so tokens file adds its own private `init(hex:)` |
| FND-02 | View split, behaviour unchanged | Split map (what moves where) |
| FND-03 | Chat \| Runs N segment | Header layout (fit problem + TabButton fix), `liveRunCount` |
| FND-04 | Status capsule + ring | `capsuleState` pure fn, ring recipe |
| FND-05 | Status menu in notch | Overlay recipe, vertical budget, dismissal |
| FND-06 | Stopped/offline/connecting | Shell order, copy, 10s retry |
| FND-07 | Seams for 5-7 | pbxproj scheme, hooks, ExpandLevel, harness |
</phase_requirements>

## Summary

The existing Orchestrator code is 1036 lines in 7 files. All of the "typing/key-gate" logic lives in `OrchestratorView` and must travel together into `OrchestratorChatView` as one verbatim block (state: `draft`, `keyWindow`, `anchor`, `fieldFocused`; funcs `startTyping/stopTyping/submit/expandChat`; modifiers `.onReceive(didResignKey)`, `.onDisappear`, 4 `.onChange`; helper `WindowAnchor`). The shell keeps only the state switch, the `.overlay { OrchestratorExpandOverlay() }` and the status-menu overlay.

Three things in the spec do not survive contact with the code and need a planner decision (details below): (1) the header does not have room for 3 current tab buttons plus the segment in the 640px notch (one-line `TabButton` padding edit is needed, contradicting "tab icons stay"); (2) MERGE-MAP's shell order (stopped before runs board) makes "see Runs" unreachable when stopped; (3) the capsule shows on all tabs but the menu overlay lives in `OrchestratorView`, which only exists on the Orchestrator tab.

**Primary recommendation:** Do the split as a pure move first (compiles, zero behaviour change), then tokens, then header/capsule/menu, then stubs+pbxproj+harness; run the swiftc harness and the xcodebuild after each wave.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary | Rationale |
|---|---|---|---|
| Capsule state derivation, live-status parse, elapsed format, ring colour, live-run count | Pure Swift (harness-testable, `OrchestratorPure.swift`/`OrchestratorPromptParse.swift`) | — | No SwiftUI imports so swiftc harness can assert |
| Polling, `liveStatus`, `prompt`, `showRunsBoard`, `statusMenuOpen` | `OrchestratorManager` (@MainActor ObservableObject) | — | Repo pattern |
| Status menu / segment / capsule drawing | SwiftUI views in `OrchestratorStatusCapsule.swift` | `BoringHeader` (2 hook lines) | Header hosts capsule; menu hosted by `OrchestratorView` overlay |
| Window growth / expand levels | `OrchestratorExpand` (AppKit NSWindow.setFrame) | — | Existing |

## Standard Stack

All system: SwiftUI, AppKit, Foundation, Swift `Regex` literals (macOS 13+, target 14), `Defaults` 9.0.6 (not needed this phase). No packages -> no Package Legitimacy Audit rows. **Packages removed/flagged: none.** [VERIFIED: codebase, CLAUDE.md "no new third-party packages"]

Toolchain: Xcode swiftc 6.2.4 (`DEVELOPER_DIR=/Applications/Xcode.app/...`), default language mode 5; existing harness compiled and passed on this machine (printed `OK`). [VERIFIED: ran in /tmp copy]

## 1. Current structure and hooks (exact)

`boringNotch/Orchestrator/`: `OrchestratorModels.swift` (139: ChatResponse, chatTail, StateResponse, OrchestratorRun, OrchestratorUsage/UsageWindow, stripRuns, PromptOption, detectPrompt, OrchestratorPost incl. `allowedKeys`, sendOrchestratorPost), `OrchestratorPure.swift` (45: usageFraction, expandedExtra, windowHeight, pinnedFrame, TerminalState/terminalState, isOutsideNotch), `OrchestratorManager.swift` (147), `OrchestratorView.swift` (286), `OrchestratorExpand.swift` (163: `OrchestratorExpand` + `OrchestratorExpandOverlay`), `OrchestratorTerminal.swift` (107: `OrchestratorKeyGate`, `OrchestratorTerminalView`), `OrchestratorCompact.swift` (29: `OrchestratorClosedIndicators`). `Tests/main.swift`, `Tests/Phase3Tests.swift`, `Tests/fixtures/{inputbox,permission,question}.txt`.

Upstream hooks (all grep-verified):
| File:line | Hook | Phase 4 action |
|---|---|---|
| `BoringHeader.swift` 45 / 62 / 63 | `OrchestratorUsageBadge()`, `OrchestratorChatButton()`, `OrchestratorRunsButton()` | delete the 3; add `OrchestratorHeaderTrailing()` where the badge was (first in the right `HStack(spacing:4)`, inside the non-HUD `else`), and `OrchestratorHeaderSegment()` in the left HStack |
| `ContentView.swift` 111, 353-354 | `OrchestratorClosedIndicators()` overlay; `case .orchestrator: OrchestratorView()` | unchanged |
| `BoringViewModel.swift` 193, 195, 209 | `OrchestratorExpand.shared.openSize(for:)`, `manager.notchOpen = true/false` | unchanged; reset `statusMenuOpen` inside manager's existing `notchOpen` didSet |
| `BoringNotchSkyLightWindow.swift` 112 | `canBecomeKey` = keyboardWindow===self OR terminalWantsKey | unchanged (byte-for-byte) |
| `TabSelectionView.swift` 21 | `TabModel(... "terminal.fill" ...)` | unchanged |
| `TabButton.swift` 19 | `.padding(.horizontal, 15)` | **one-line edit needed, see section 3** |
| `boringNotchApp.swift` 283 | `OrchestratorManager.shared.start()` | unchanged |

### Split map (verbatim moves)
- **OrchestratorChat.swift `OrchestratorChatView`**: everything typing-related: `@State draft, keyWindow, anchor`, `@FocusState fieldFocused`, `@EnvironmentObject vm`, `bottomBar` (composer branch), `startTyping/stopTyping(handBack:)/submit/expandChat`, `WindowAnchor` (make it internal, not `private`, Phase 7 may reuse), the modifiers `.background(WindowAnchor)`, `.onReceive(didResignKey)`, `.onDisappear{stopTyping()}`, `.onChange(fieldFocused/chatRunning/offline/promptOptions)`. Transcript VStack (`chatTail(maxLines: 7)` + `onTapGesture { expandChat() }`). Do not reformat these; Phase 5 rewrites the file.
- **OrchestratorPromptCard.swift `OrchestratorPromptCard`**: the `else` branch of `bottomBar` (HStack of option buttons filtered on `"Type something."`, `pressOption`, `esc` button, `.disabled(manager.optionsLocked || manager.sending)`). ChatView's bottomBar becomes `manager.promptOptions.isEmpty ? composer : OrchestratorPromptCard()`. Behaviour unchanged (transcript stays visible while a prompt shows). MERGE-MAP's shell order lists "prompt card" as a shell-level state; in Phase 4 it must stay *inside* ChatView to keep behaviour; Phase 6 may hoist it.
- **OrchestratorRunsBoard.swift `OrchestratorRunsBoard`**: `runsStrip` + `color(_:)`; shown full-content when `showRunsBoard` (was a 200px overlay). Keep `stripRuns(limit: 6)`; wrap in `ScrollView`. Replace colour literals with tokens (running green, waiting orange, failed/stuck red, else gray; same mapping).
- **Shell `OrchestratorView`**: `Group { connecting | offline | showRunsBoard ? board : (!chatRunning ? stopped : chat) }`, `.frame(maxWidth/maxHeight: .infinity)`, status-menu overlay, `.overlay { OrchestratorExpandOverlay() }` last. The shell must NOT keep typing state.
- **Deleted from the file**: `OrchestratorRunsButton`, `OrchestratorChatButton`, `OrchestratorUsageBadge` (logic migrates: End 4s confirm, usage rows, reset-time formatters).

Behaviour changes the split introduces (accept and note in SUMMARY): switching to Runs removes ChatView so `onDisappear -> stopTyping()` fires (good) and the unsent `draft` is lost; previously `.padding(.horizontal, 8)` and the runs overlay were siblings. If losing `draft` is unacceptable, hoist `@State draft` into the shell and pass a `Binding`; recommended: accept.

## 2. project.pbxproj registration

Existing scheme `[VERIFIED: grep]`: IDs are `0A1C` + 17 zeros + 3 digits (24 hex). File refs: Models 001, Manager 002, View 003 (build files 004-006); Phase 3: refs 301-304 (Pure, Compact, Expand, Terminal), build files 311-314. Group `0A1C00000000000000000007 /* Orchestrator */` (line 374), Sources phase of target `boringNotch` `14CEF40E2C5CAED300855D72` (line ~931). Tests are NOT in the project (swiftc-only). The only synchronized group on the app target is `private/`; the `BoringNotchXPCHelper` target has its own empty Sources phase (`11F7484B…`), do not touch it.

**Four edits per new file** (all in `boringNotch.xcodeproj/project.pbxproj`):
1. `PBXBuildFile` section: `0A1C…45N /* X.swift in Sources */ = {isa = PBXBuildFile; fileRef = 0A1C…40N /* X.swift */; };`
2. `PBXFileReference` section: `0A1C…40N /* X.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = X.swift; sourceTree = "<group>"; };`
3. Group `0A1C…007` `children`: `0A1C…40N /* X.swift */,`
4. Sources phase `14CEF40E…` `files`: `0A1C…45N /* X.swift in Sources */,`

**Proposed IDs** (ref / build file), 11 new files; `OrchestratorView.swift` already registered:
| N | File | ref | build |
|---|---|---|---|
| 01 | OrchestratorTokens.swift | 0A1C00000000000000000401 | 0A1C00000000000000000451 |
| 02 | OrchestratorStatusCapsule.swift | …402 | …452 |
| 03 | OrchestratorStates.swift | …403 | …453 |
| 04 | OrchestratorChat.swift | …404 | …454 |
| 05 | OrchestratorTranscript.swift | …405 | …455 |
| 06 | OrchestratorPromptCard.swift | …406 | …456 |
| 07 | OrchestratorPromptParse.swift | …407 | …457 |
| 08 | OrchestratorRunsBoard.swift | …408 | …458 |
| 09 | OrchestratorRunsPure.swift | …409 | …459 |
| 10 | OrchestratorExpanded.swift | …410 | …460 |
| 11 | OrchestratorWings.swift | …411 | …461 |

(prefix `0A1C00000000000000000` + 3 digits, i.e. `0A1C00000000000000000401`.) Do all pbxproj edits in ONE task (single editor, one commit) so parallel phases never touch it. Verify with `plutil -lint boringNotch.xcodeproj/project.pbxproj` then a build.

Stub bodies that compile today: `OrchestratorExpanded`: `struct OrchestratorExpandedView: View { var body: some View { EmptyView() } }`; `OrchestratorWings`: `struct OrchestratorWingsView: View { var body: some View { EmptyView() } }`; `OrchestratorTranscript` / `OrchestratorRunsPure`: `import Foundation` + one stub type/func each (e.g. `func pollInterval(notchOpen:chatRunning:offline:) -> Double` lives in RunsPure per MERGE-MAP and is real, not a stub).

## 3. Header layout

Open header width: ContentView pads NotchLayout by `cornerRadiusInsets.opened.top`=19 (cornerRadiusScaling default true) + 12 each side, so 640-62 = 578; the centre `Rectangle` is `vm.closedNotchSize.width` (~185 on notch Macs); left/right `HStack`s are `maxWidth: .infinity` so each side gets about (578-185)/2 = **~196px**. [VERIFIED: ContentView 95-102, BoringHeader, matters.swift; arithmetic ASSUMED for the ~185 hardware width]

Left content today: `TabButton` = SF symbol (~17px at `.headline`) + `.padding(.horizontal, 15)` = ~47px x 3 tabs (Home, Shelf when `Defaults[.boringShelf]` (default true), Orchestrator) = **~141px**. Segment (11pt "Chat" + "Runs N", paddings 9, track 2) is ~100-105px, plus 6 margin. 141+6+104 = ~251 > 196. It overflows into the notch cut-out (hidden behind the hardware notch, zIndex 2 left side draws over the spacer but physical notch hides it). README mock uses 24px circles (3x24 + gaps ~ 80). **Required fix:** change `TabButton.swift` line 19 `.padding(.horizontal, 15)` to about `6` (tab ~29px wide; 3 tabs ~87; total ~197 still marginal; use `5`, or drop to 4 if the build-screenshot check shows clipping) and give the segment `.fixedSize()` + `.lineLimit(1)`. This is a 1-line upstream edit that also affects Home/Shelf tab buttons (only ever used here). Flag to the user as an exception to D-06 "Tab icons stay"; alternative with zero upstream edits is none (the Orchestrator code cannot shrink an upstream view's internal padding). Since the app may not be launched, add a human-verify checkpoint for the header fit (UAT), and keep the segment compact (11pt, paddings per README).

Gating: `BoringHeader` shows `TabSelectionView` only if `(!tvm.isEmpty && Defaults[.boringShelf]) || coordinator.alwaysShowTabs` (alwaysShowTabs is `@AppStorage`, default true, BoringViewCoordinator.swift:64). Put `OrchestratorHeaderSegment()` as a **sibling after that `if/else` inside the same left `HStack`** (not inside the `if`), with `.padding(.leading, 6)` (HStack default spacing would add 8) and self-gating: `coordinator.currentView == .orchestrator && manager.hasLoaded && !manager.offline`. The left HStack keeps its existing `.opacity/.blur` for closed state.

Right side: capsule ~100px + battery(~35) + optional mirror < 196, OK. The right HStack applies `.font(.system(.headline, design: .rounded))` and root `.foregroundColor(.gray)`: capsule/segment must set explicit fonts (`.system(size: 11)`) and colours.

## 4. Status menu in the notch

Use a SwiftUI overlay, not `.popover` (popover is a separate NSWindow, escapes the notch, and the notch panel is non-activating / not key). [VERIFIED: D-07, BoringNotchSkyLightWindow]

Recommended wiring:
- `manager.statusMenuOpen: Bool` (`@Published`, `// Phase 4` block). Capsule tap: if `currentView != .orchestrator` then set it and `statusMenuOpen = true` (mirrors the old `OrchestratorRunsButton` jump), else toggle. This resolves the "capsule on all tabs but menu hosted in `OrchestratorView`" conflict without touching `ContentView`. Reset `statusMenuOpen = false` when notch closes (`notchOpen` didSet), when `currentView` changes (`.onChange` in shell), on offline/hasLoaded false.
- Shell: `.overlay(alignment: .topTrailing) { if manager.statusMenuOpen { StatusMenu().frame(width: 232).transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing))) } }` placed **before** `.padding(.horizontal, 8)`, so the trailing edge aligns with the header capsule; content area starts under the 34px header so the menu's top lands directly below the capsule. Order of layers: content (dimmed `opacity(0.35)`, `allowsHitTesting(false)` while open) < scrim `Color.clear.contentShape(Rectangle()).onTapGesture { close }` < menu < `OrchestratorExpandOverlay`. Header is a different subtree with zIndex(2) in ContentView, so the capsule stays clickable (re-click toggles = dismissal).
- Dismissal: scrim tap, capsule toggle, Interrupt/Start/Open terminal/End actions, tab change, notch close. Do not rely on Esc (`onExitCommand`/`onKeyPress` need focus; the panel is non-key unless typing).
- Vertical budget: open height 190 - 12 bottom padding - header (~32-34) = **~144-146px** for the content area, and the mock's menu is ~136px tall at 1x (screenshot 06: 168 to 440 px at 2x). Rows: usage x2 = 2 x ~30 (title row 21 + 3px bar + 4 gap), divider ~7, Open terminal 21, Interrupt 21, End row ~28, padding 10 = ~146. It fits only if row padding is exactly 3px vertical and the End row is <=28px; keep `fixedSize(vertical:true)`; if it exceeds, drop usage row gap by 2px rather than scroll. The mock deliberately overlaps the composer (it covers the send button) - expected.
- **End confirm 4s:** old code used an uncancelled `Task { sleep 4; confirmEnd=false }` (a second tap can be reset by the first timer). Use `.task(id: confirmEnd) { guard confirmEnd else {return}; try? await Task.sleep(for: .seconds(4)); confirmEnd = false }` (auto-cancels). Confirm End calls `manager.stopChat()` and closes the menu. When `!chatRunning`, show "Start chat" (calls `startChat()`). Disable while `manager.sending`.
- **Open terminal** needs an `NSWindow`: shell keeps its own `WindowAnchor` background (separate `NSView`) and calls `OrchestratorExpand.shared.setLevel(.terminal, vm:, window: anchor.window)` (alias of `expand`). If the user was typing, `OrchestratorChatView` should end typing when `statusMenuOpen` flips true (`.onChange(of: manager.statusMenuOpen) { _, o in if o { stopTyping(handBack: false) } }`) so the invisible, dimmed `TextField` cannot keep the keyboard. This is the one new line inside the "untouched" typing code; mark it `// Phase 4`. (`handBack:false` avoids reactivating the previous app mid-click; the terminal/next click takes focus itself. Behaviour not testable without launching: put in UAT.)
- **Interrupt:** `Task { await manager.pressEscape() }` then close menu; debounce already inside `pressEscape` (1s). Disabled if `!chatRunning`.
- Usage rows: reuse the old formatters (5h reset `formatted(date: .omitted, time: .shortened)`, 7d `.dateTime.weekday(.abbreviated).hour().minute()`), copy "9% · resets 3:00 pm"; orange when `>= 80`; bars: `Capsule` track `#3A3A3C`, fill white (orange >=80), 3px high, width via GeometryReader or `ProgressView`-free `Capsule().frame(width:)` scaling. `—` when nil.

## 5. Live-status parse (pure, `OrchestratorPromptParse.swift` or `OrchestratorPure.swift`)

Observed screens: finished turns show `✻ Sautéed for 22s · done 12:48 pm · 1 monitor still running` (live capture of this orchestrator, and `permission.txt` line 15) - **no "esc to interrupt", past tense**. This must NOT be Running. Working line (Claude Code, from training/design brief, not captured because the chat is idle) `[ASSUMED]`: `✻ Working… (41s · ↑ 1.2k tokens · esc to interrupt)`; glyph cycles `· ✢ ✳ ✶ ✻ ✽`, verb varies ("Pondering…", "Cogitating…"), parenthesised segments separated by `·`, elapsed forms `41s`, `1m 52s`, `1h 2m`, sometimes `thought for 3s`, sometimes only `(esc to interrupt)`.

Rule: Running iff a line in the last 30 lines matches `^ *[GLYPH] +(verb…) *\((…)\) *$` **and** the paren part contains `esc to interrupt`. Elapsed = the first `·`-separated segment that consists only of `\d+\s*[hms]` tokens (so `thought for 3s` and `↑ 1.2k tokens` are ignored); sum tokens; nil when absent. Verified working draft (ran in /tmp with swiftc; outputs 41, 112, 3720, nil, nil, nil (non-glyph quote line), 12):

```swift
struct LiveStatus: Equatable { let text: String; let elapsed: TimeInterval? }
func parseLiveStatus(screen: String) -> LiveStatus? {
    let line = #/^[ \u{a0}]*[✻✢✳✶✽✺✹·*][ \u{a0}]+(.+?)[ \u{a0}]*\((.*)\)[ \u{a0}]*$/#
    let dur = #/(\d+)\s*([hms])/#
    for l in screen.split(separator: "\n", omittingEmptySubsequences: false).suffix(30).reversed() {
        guard let m = try? line.wholeMatch(in: String(l)), m.2.contains("esc to interrupt") else { continue }
        let seg = m.2.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { s in !s.isEmpty && s.replacing(dur, with: "").trimmingCharacters(in: .whitespaces).isEmpty }
        let secs = seg.map { $0.matches(of: dur).reduce(0.0) { $0 + Double($1.1)! * ["h": 3600, "m": 60, "s": 1][String($1.2)]! } }
        return LiveStatus(text: String(m.1), elapsed: secs)
    }
    return nil
}
```
Add a `formatElapsed(_ s: TimeInterval) -> String` ("0:41", "1:52", "1:02:00") in Pure for Phase 5/7 (the design shows `0:41`). Test fixtures: add `fixtures/working.txt` (a synthetic screen: working line + input box) to `Tests/fixtures`, and assert the five cases above plus the finished-line negative. Tag: format is `[ASSUMED]`; if the user can capture a real working screen (read-only GET `/api/chat` while Claude is mid-turn), replace the fixture. Risk: if a Claude Code version drops "esc to interrupt" from the line the capsule never shows Running (degrades to Idle, harmless).

`manager.liveStatus` set in `refresh()`: `liveStatus = running ? parseLiveStatus(screen: s) : nil` (only assign when changed, as the code does for others; elapsed changes each poll anyway).

**Capsule state** as a pure function for the harness: `capsuleState(hasLoaded:offline:chatRunning:needsAttention:live:) -> CapsuleState` in D-04 order: connecting, offline, stopped, needsYou, running, idle. Note D-04 puts Stopped before Needs you, so a waiting *run* while chat is stopped shows Stopped (spec order; flag if the user prefers attention first).

## 6. Usage ring (12px)

No deps. Recipe: `ZStack { Circle().fill(OT.track) /*#3A3A3C*/; Circle().inset(by: 3).trim(from: 0, to: f).stroke(fill, lineWidth: 6).rotationEffect(.degrees(-90)) }.frame(width: 12, height: 12)` - a stroke whose width equals the radius of the inset circle renders a filled pie (matches the screenshot's wedge). Fill white; `OT.orange` when `used >= 80`. Use `usageFraction`-style clamping on `fiveHour?.usedPercentage` only (note `usageFraction` in Pure returns the MAX of 5h/7d; the ring needs 5h only - add `fiveHourFraction(_:)` in Pure). `AngularGradient` is unnecessary (hard stops, no benefit). Hidden when usage nil. Menu bars/ring colour threshold shared via one pure `usageIsHigh(_ pct) -> Bool` (>= 80).

## 7. Test harness

How it works today `[VERIFIED: ran]`: `Tests/main.swift` is the swiftc entry (top-level code; `#filePath` locates `fixtures/`), `Tests/Phase3Tests.swift` defines `runPhase3Tests()`, called at the end of main.swift. Current effective command compiles `OrchestratorModels.swift OrchestratorPure.swift Tests/*.swift` (the MERGE-MAP command adds Transcript, PromptParse, RunsPure). I reproduced the restructure in `/tmp/p4r`: moving `PromptOption` + `detectPrompt` (lines from `struct PromptOption` to just before `enum OrchestratorPost`) into `OrchestratorPromptParse.swift` (`import Foundation` only) and running the MERGE-MAP command shape printed `OK`; existing assertions compile unchanged because all files are one module. Constraints: PromptParse/Transcript/RunsPure/Pure must import only Foundation (CoreGraphics ok in Pure); `main.swift` must call `runPhase4Tests()...runPhase7Tests()` and each `PhaseNTests.swift` must define its function (stubs `func runPhaseNTests() {}`; Phase 4's has real asserts). Do not put `PromptCard` in Models (Models must stay compile-independent of PromptParse order - order does not matter in swiftc, fine either way).

Test/command: `mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t` (expected output `OK`). Wave 0 order: create the 3 pure stubs + Tests stubs + main.swift calls first (harness green), then build.

Phase4Tests asserts: `parseLiveStatus` cases (section 5), `formatElapsed`, `capsuleState` truth table incl. D-04 ordering, `liveRunCount` (running/waiting/stuck), `fiveHourFraction`/`usageIsHigh` (79.9 vs 80), `pollInterval` (open 2, closed 10, offline 10, `chatRunning` today's 2/10), `"C-u"` request builds (`OrchestratorPost.key("C-u").request(base:)` non-nil; `"C-x"` nil), `detectPromptCard` wraps `detectPrompt` (options equal, title/purpose nil, kind `.permission` or `.question` by label content "Type something."), and `detectPromptCard(screen: inputbox) == nil`.

`PromptCard` (all optional except options/kind): `struct PromptCard: Equatable { enum Kind { case permission, question }; var title: String?, purpose: String?, body: [String]?, options: [PromptOption], kind: Kind, header: String?, progress: String? }`. Equatable so `manager.prompt != new` guard works. Phase 4 kind heuristic: question if any label == "Type something." else permission.

## 8. ExpandLevel seam

Add to `OrchestratorExpand.swift` (Phase 7 owns behaviour afterwards):
```swift
enum ExpandLevel: Equatable { case open, expanded, terminal }
// state: keep `expanded` = "window grown" (drives extra height, monitors, one beginInteraction); add `terminal: Set<ObjectIdentifier>`
func level(for vm: BoringViewModel) -> ExpandLevel { terminal.contains(key(vm)) ? .terminal : expanded.contains(key(vm)) ? .expanded : .open }
func setLevel(_ l: ExpandLevel, vm: BoringViewModel, window: NSWindow?) {
    switch l {
    case .open: collapse(vm: vm)
    case .expanded: grow(vm, window); terminal.remove(key(vm))      // releaseKey if it was terminal
    case .terminal: grow(vm, window); terminal.insert(key(vm))
    }
}
func expand(vm:window:) { setLevel(.terminal, vm: vm, window: window) }   // existing call site unchanged
```
`grow` = the existing body of `expand` (guard `!expanded.contains(k)`, `extra`, setFrame, `expanded.insert`, monitors, one `beginInteraction`). `finish(k)` must also `terminal.remove(k)`. `OrchestratorExpandOverlay` changes one line: `let isExp = expand.level(for: vm) == .terminal` (and `expand.isExpanded` can remain for window-grown). `.expanded` without terminal = same window growth (`openSize` unchanged since it reads `extra`), no overlay. Pitfalls: leaving `.terminal` to `.expanded` must call `releaseKey` (`terminalWantsKey=false`) because `dismantleNSView` calls it only when the web view is torn down - it is, since overlay content disappears (OK) - but test the `.expanded -> .terminal -> .expanded` path in the harness only via the pure `expandedExtra`; the rest is UAT. `reset()` must clear `terminal`. Keep "exactly one endInteraction per grow".

## 9. Offline cadence

Today `start()` loop: `refresh()` then sleep `notchOpen ? 2 : 10`, offline or not. A failed refresh already waits up to 3s (session timeout 3s), so offline-open actually retries every ~5s and offline-closed every ~13s; the copy says "Retrying every 10s". Implement `pollInterval(notchOpen: Bool, chatRunning: Bool, offline: Bool = false) -> Double` in `OrchestratorRunsPure.swift`: `offline ? 10 : (notchOpen ? 2 : 10)` (chatRunning unused now; Phase 7 returns 3 when closed and running). Loop: `Task.sleep(for: .seconds(pollInterval(...)))`. Notch open still triggers an immediate `refresh()` (notchOpen didSet), so reconnect feels instant. Keep the `offline` default argument so the MERGE-MAP two-argument signature stays callable.

## 10. Manager hooks (exact)

In `refresh()` after decoding (keep existing `promptOptions` behaviour byte-for-byte, incl. `optionsLocked = false` on change):
`let pc = running ? detectPromptCard(screen: s) : nil; if prompt != pc { prompt = pc }`, `let ls = running ? parseLiveStatus(screen: s) : nil; if liveStatus != ls { liveStatus = ls }`, and one `await transcript.refresh(screen: s, running: running)` into a Phase 5-owned stub object (e.g. `final class OrchestratorTranscriptStore { func refresh(...) async {} }` in `OrchestratorTranscript.swift`; owned by manager as `let transcript = OrchestratorTranscriptStore()`). In the `catch`: clear `prompt`, `liveStatus`. New `@Published` props: `showRunsBoard` (replaces `showRuns`; renamed in 3 places: manager, RunsButton (deleted), shell), `statusMenuOpen`, `prompt`, `liveStatus`. Mark with `// Phase 4` comments.
`needsAttention` stays `runs.contains{waiting} || !promptOptions.isEmpty` (D-04 uses it). `"C-u"` added to `OrchestratorPost.allowedKeys`; existing test `.key("x")`/`"0"`/`"10"` still nil.

## Architecture Patterns

```
GET /api/chat + /api/state (2s open / 10s closed / 10s offline)
        │  OrchestratorManager.refresh()
        ├─► screen ─► detectPrompt ─► promptOptions   (existing)
        │          ├► detectPromptCard ─► prompt       (new seam)
        │          └► parseLiveStatus ─► liveStatus    (new seam)
        ├─► usage, runs
        ▼
 BoringHeader ── OrchestratorHeaderSegment (Chat|Runs N) -> manager.showRunsBoard
              └─ OrchestratorHeaderTrailing (capsule: capsuleState + ring) -> statusMenuOpen
 OrchestratorView (shell): connecting|offline|RunsBoard|Stopped|ChatView(PromptCard in bottom bar)
              ├ overlay: scrim + StatusMenu (statusMenuOpen)
              └ overlay: OrchestratorExpandOverlay (terminal, level == .terminal)
```

### Tokens (D-01)
`enum OT { enum C { static let notch=Color(hex:0x000000), s1=0x1C1C1E, s2=0x141416, s3=0x0B0B0C, sel=0x2C2C2E, sel2=0x3A3A3C, t0=white, t1=E5E5EA, t2=D1D1D6, t3=C4C4C6, t4=AEAEB2, t5=8E8E93, t6=636366, claude=D97757, green=30D158, orange=FF9F0A, orangeText=FFB35C, orangeBg=3A2410, red=FF453A, redText=FF6961, redBg=2A1A19 }; enum F {sizes 14/13/12/11/10/9, mono 12/11/10}; enum R {notchOpen 24, expanded 26, dropdown 22, closed 12, card 12/10/9, pill 15/14, key 4}; enum S {header 34, padTop 0, padH 14, padBottom 12} }`. No existing `Color(hex:)`: add `fileprivate init(hex: UInt32)` inside the tokens file (grep found none; avoids collisions upstream). Later phases append only.

### Pattern: capsule label cross-fade
`Text(label).id(state)` with `.transition(.opacity)` inside `.animation(.easeInOut(duration: 0.18), value: state)`.

## Don't Hand-Roll
| Problem | Use | Why |
|---|---|---|
| Usage pie | `Circle().inset(by:).trim.stroke` | 4 lines vs custom Shape |
| 4s confirm timer | `.task(id:)` | auto-cancel; avoids the old stale-timer bug |
| Elapsed parse | the `\d+[hms]` token regex | handles `1h 2m` |
| Popover window | in-notch overlay | `.popover` escapes the notch |

## Common Pitfalls
1. **Finished line treated as Running** (`✻ Sautéed for 22s · done …`): require `esc to interrupt`.
2. **Header overflow** into the hardware notch (section 3); needs the TabButton padding edit; verify visually (UAT).
3. **Stopped screen hides Runs**: shell order must test `showRunsBoard` before `!chatRunning` (conflict with MERGE-MAP order; fix and note it in the plan).
4. **Typing state split across views**: moving `anchor/keyWindow/fieldFocused` to different views breaks `canBecomeKey`/`beginTyping(in:)` (key window must be the one the manager recorded). Move as one block.
5. **Menu key/typing**: dimmed `TextField` still focused (section 4 `onChange`).
6. **`.onChange` two-parameter closure** is macOS 14+ (already used in repo; target 14, fine). `onKeyPress` is macOS 14+ too but is not needed in Phase 4 (and needs focus the panel lacks).
7. **Capsule font inherits `.headline` rounded + gray** from BoringHeader: set explicit font/colour.
8. **pbxproj**: ID collisions or a missing Sources entry compiles fine until the type is referenced; build after edit; `plutil -lint`.
9. **Music**: Phase 4 touches no music file; BoringHeader edit must not alter the `isHUDType`/`showMirror`/battery branches or the `.opacity/.blur/.zIndex(2)` modifiers. Check `git diff` on BoringHeader is limited to 3 deletions + 2 insertions (+ TabButton 1 line).
10. `usageFraction` returns max(5h,7d) (used by closed hairline, untouched): do not reuse it for the ring.
11. Offline copy: the mono chip text is `node orch.js serve · 127.0.0.1:4777`; the old text was lowercase "start `node orch.js serve`"; replace entirely.

## Code Examples
Status capsule skeleton (tokens, no ctx):
```swift
HStack(spacing: 7) {
  Circle().fill(dotColor).frame(width: 6, height: 6)
  Text(label).font(.system(size: 11)).foregroundStyle(labelColor)
  if showRing { UsageRing(fraction: f, high: f >= 0.8) }
}
.padding(.leading, 8).padding(.trailing, 10).frame(height: 24)
.background(bg, in: Capsule())   // 12px radius at 24px height = Capsule
```
Stopped content: `VStack(spacing: 10) { Text("Orchestrator chat is stopped").font(.system(size:14,weight:.medium)); Button { Task { await manager.startChat() } } label: { Label? no: Text("▶ Start chat") }.buttonStyle(.plain).padding(.horizontal,16).frame(height:30).background(.white, in: Capsule()).foregroundStyle(.black); if live > 0 { Text("\(live) runs still active · see Runs").onTapGesture { manager.showRunsBoard = true } } }` (singular "1 run still active" is a spec gap; recommend pluralise).

## State of the Art
`@Observable` rejected (repo uses `ObservableObject`); SwiftUI `WebView` macOS 26 not used. Nothing deprecated relevant.

## Assumptions Log
| # | Claim | Section | Risk |
|---|---|---|---|
| A1 | Claude Code working line format `✻ Verb… (41s · ↑ 1.2k tokens · esc to interrupt)` with glyph set and `1m 52s`/`1h 2m` | 5 | Running never detected (degrades to Idle) |
| A2 | Hardware notch spacer ~185px, side budget ~196px, tab ~47px, segment ~104px | 3 | Header fit wrong; verify visually |
| A3 | Menu fits in ~144px with 3px row padding | 4 | Needs tighter rows |
| A4 | `handBack:false` when menu opens during typing is acceptable | 4 | Focus glitch; UAT |

## Open Questions (spec gaps for the user/planner)
1. Tab buttons must shrink (TabButton padding 15 -> ~5) or the segment cannot fit; D-06 says tab icons stay. Recommend approving the 1-line upstream edit.
2. Shell order: MERGE-MAP says stopped before runs board; D-08's "see Runs" link requires runs board first. Recommend runs board first.
3. "Runs N": count of live (running/waiting/stuck) runs; show no number at 0? Recommend omit at 0.
4. Capsule on non-Orchestrator tabs: tap jumps to the Orchestrator tab and opens the menu (recommended) vs menu on any tab (needs ContentView edit).
5. README tab symbols (`house`, `tray`, `terminal`) vs repo (`house.fill`, `tray.fill`, `terminal.fill`): keep repo's (D-06).
6. "1 runs" pluralisation and Stopped-before-NeedsYou precedence (D-04) - confirm.

## Environment Availability
| Dependency | Needed | Available | Note |
|---|---|---|---|
| Xcode (xcodebuild, swiftc 6.2.4) | build + harness | yes | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` |
| Orchestrator serve 127.0.0.1:4777 | read-only GET for fixtures | yes (running) | GET `/api/chat` only; never POST, never `/term` |

## Validation Architecture
| Property | Value |
|---|---|
| Framework | swiftc assert harness (`precondition`), no XCTest target |
| Config | none; command in section 7 |
| Quick run | the swiftc command (about 10s) -> `OK` |
| Full | harness + `xcodebuild ... -derivedDataPath /tmp/notch-dd-p4 build` (BUILD SUCCEEDED) |

| Req | Behaviour | Type | Automated | Exists |
|---|---|---|---|---|
| FND-01 | tokens match hex list | build + grep-based check | xcodebuild | Wave 0 |
| FND-02 | split compiles, behaviour same | harness (detectPrompt/chatTail asserts) + build | harness | existing |
| FND-03/04 | `liveRunCount`, `capsuleState`, ring fraction | unit | harness `runPhase4Tests` | Wave 0 |
| FND-05 | menu visuals, dim, dismissal, 4s confirm | manual (UAT, app not launched by agent) | - | manual |
| FND-06 | stopped/offline/connecting copy | build + manual | - | manual |
| FND-07 | `parseLiveStatus`, `detectPromptCard`, `pollInterval`, `C-u`, ExpandLevel compile | unit + build | harness | Wave 0 |

Sampling: per task commit: harness (pure tasks) or build (view tasks); per wave: both; gate: both green. Wave 0 gaps: `Tests/Phase4..7Tests.swift`, `Tests/fixtures/working.txt`, the three pure stub files, `main.swift` runner calls.

## Security Domain
ASVS: V5 input validation applies to the new `"C-u"` key: it must stay in the closed `allowedKeys` allowlist (server already allows it); no other input surface (no new network calls, no entitlement changes, localhost only). V2/V3/V4/V6 not applicable. Threat: a regex over untrusted screen text (ReDoS) - patterns are anchored, linear, over <=30 lines.

## Sources
- Codebase (HIGH): all files under `boringNotch/Orchestrator/`, `BoringHeader.swift`, `ContentView.swift`, `TabButton.swift`, `TabSelectionView.swift`, `BoringViewModel.swift`, `BoringNotchSkyLightWindow.swift`, `matters.swift`, `project.pbxproj`, `Tests/*`.
- Design: `.planning/design/orchestrator-2a/README.md`, `MERGE-MAP.md`, screenshots 01 and 06 (viewed).
- Live read-only GET `/api/chat` (finished-line format observed).
- Spinner working-line format: training knowledge only (A1), not verified against current Claude Code release notes.

## Metadata
Confidence: stack HIGH, architecture HIGH, pitfalls HIGH (code-derived), header fit LOW-MEDIUM, live-status format MEDIUM. Valid until: ~30 days or any change to Orchestrator files by Phases 5-7.
