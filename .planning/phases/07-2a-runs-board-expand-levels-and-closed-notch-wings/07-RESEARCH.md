# Phase 7: 2a Runs Board, Expand Levels & Wings - Research

**Researched:** 2026-10-14
**Domain:** SwiftUI/AppKit (macOS 14 target, Swift 5 mode) in the Boring Notch fork; read-only HTTP data from orchestrator serve
**Confidence:** MEDIUM-HIGH (code and serve verified by reading; Phase 4 seams are assumed from MERGE-MAP because Phase 4 is not built; wing pixel fit and key behaviour need on-screen UAT)

<user_constraints>
## User Constraints (from 07-CONTEXT.md)

### Locked Decisions
- D-01 Runs board cards per README 05: 196px, radius 12, `#1C1C1E`, padding 9/10, gap 5, horizontal scroll beyond three. Line 1: 6px state dot, project (12pt semibold), elapsed right (10pt `#8E8E93`, from `startedAt`). Line 2: short prompt 11pt `#8E8E93`. Line 3: latest action mono 10pt `#D1D1D6` (from `activity.step` / `latest`). Sort live first (`stripRuns`). Colours: running `#30D158`, waiting `#FF9F0A`, failed/stuck `#FF453A`, done `#8E8E93` at 75% with check; stopped = done styling.
- D-02 Waiting card: inset 1px `#FF9F0A` ring; shows the run's question (from `result`, last lines, and/or `denials` tool names) and ONE button that sends that context into the orchestrator chat ("Ask in chat" -> `sendText`, one-line message naming run id, project and question; serve collapses newlines). NO Allow/Deny/resume of runs from the notch. Button disabled when chat isn't running (offer Start instead); copy is Claude's discretion, keep short.
- D-03 Extend `OrchestratorRun` with optional `startedAt`, `lastOutput`, `result`, `denials`, `latest`, `activity{step, agents}` (all optional; existing decoding tests still pass).
- D-04 Bottom row on Runs board: composer pill collapses to one line "(asterisk) Orchestrator: <status>" (e.g. "waiting on run x7f2"), derived from `manager.liveStatus` / `needsAttention`.
- D-05 Own Phase 4 `ExpandLevel` API: open (640x190) -> expanded (640x~440, content up to ~45% of screen) -> terminal (mode inside expanded). Triggers: click transcript or cmd-down -> expanded; esc or cmd-up back one level; Terminal pill / cmd-T -> terminal; click outside closes fully. Keep existing outside-click, monitor and key-release logic in `OrchestratorExpand`. Cmd-shortcuts only work while the panel is key; research how far that holds and document the limit; no Accessibility permission.
- D-06 Motion: height is one continuous spring (response 0.4, damping 0.82); content cross-fades in after ~120ms, 0.18s ease-out. Bottom radius 26 when expanded.
- D-07 Expanded body: header capsule + 24px collapse button (inside `OrchestratorHeaderTrailing` in `OrchestratorStatusCapsule.swift`); conversation column embeds `OrchestratorChatView`; runs rail 178px with "Runs · N active", compact cards, 5h/7d usage bars pinned bottom; bottom row composer (32px) + "Terminal cmd-T" pill. Waiting rail cards: same "Ask in chat" button (no Allow/Deny).
- D-08 Terminal: existing ttyd `WKWebView` in a `#0B0B0C` frame radius 12 with inset 1px `#1C1C1E`; toolbar 11pt `#8E8E93`: green dot, "Terminal · keyboard captured", "Collapse" pill; in use / unavailable replace body with message + Retry pill. WebView still created only in terminal mode.
- D-09 Rail collapse (12b): 30px strip with back button, one 22px circle per run with 7px state dot (waiting = inset orange ring), usage ring at bottom; button or cmd-\ re-expands; hover a dot peeks that run's card. Persist in `Defaults` key `orchRunsRailCollapsed` (declared in a Phase 7 file's `extension Defaults.Keys`). Auto re-open when a run newly enters waiting unless user collapsed it this session. Width animates spring 0.3/0.85.
- D-10 Wings per README 00: grow sideways from hardware notch like music live activity, black, 32px tall, radius 12, padding 0 12 0 14. Working (285): asterisk `#D97757` 15pt rotating slowly | elapsed mono 11pt medium `#AEAEB2`. Needs you (305): 8px orange dot with pulsing glow (1.2s) | pill with tool name + "?" (from `manager.prompt?.title`, Phase 6 enriches; fall back to "Needs you") 11pt medium `#FFB35C` on `#3A2410`, radius 9, padding 2/8. Run finished (285): check `#30D158` 13pt | project name 11pt `#AEAEB2`, fades after 4s. Wings spring out 0.35/0.8.
- D-11 Music wins: while the music live activity shows, wings do not show; music keeps album art and visualizer; a 7px orange dot appears before the visualizer when needs-you. Current attention dot + usage hairline (2px, inset 14, track white 12%, fill white 50%, orange >=80%) stay. ContentView edits minimal; music sizing/behaviour unchanged.
- D-12 Closed polling 3s while `chatRunning` (via `pollInterval` in `OrchestratorRunsPure.swift`), 10s otherwise; 2s open.
- D-13 Files owned: `OrchestratorRunsBoard.swift`, `OrchestratorRunsPure.swift`, `OrchestratorExpanded.swift`, `OrchestratorWings.swift`, `OrchestratorExpand.swift`, `OrchestratorCompact.swift`, `OrchestratorTerminal.swift`, `Tests/Phase7Tests.swift`; plus `OrchestratorRun` fields in Models, `ContentView.swift` wing hook, trailing header view. Any other shared edit is a declared merge point in the plan's `<merge_points>`.
- S-01 NEVER POST to 127.0.0.1:4777; do not load `/term`. S-02 do not launch apps; build only with `-derivedDataPath /tmp/notch-dd-p7`. S-03 new files under `boringNotch/Orchestrator/`, minimal upstream hooks, no deps, HTTP only, Swift 5, `ObservableObject` + `@Published`, `@MainActor`. S-04 music must not regress. S-05 never push, stay on branch. S-06 pure logic gets assert checks in the swiftc harness. S-07 follow the design handoff exactly.

### Claude's Discretion
- How to measure "45% of screen" and the expanded height cap against `expandedExtra`.
- Hover-peek implementation for rail dots.

### Deferred Ideas (OUT OF SCOPE)
- Allow/Deny on run cards and rail (dropped). Expanded Edit diff card, streaming caret (Phase 8). Approval drop-down, content-sized frame (Phase 9). Transcript rows/composer (5), prompt cards (6).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RUN-01 | Runs board frame 05 cards; waiting card shows question + button sending context to chat | Run fields (serve), `latestAction`/`waitingQuestion`/`askInChatMessage` pure helpers, POST text semantics |
| RUN-02 | open -> expanded -> terminal with triggers and motion, keeping monitor/key-release logic | State machine, height function, spring, key-limit analysis |
| RUN-03 | Expanded (12): conversation column, rail with usage bars, Terminal pill; terminal (10) framed toolbar + in use/unavailable + Retry | Expanded layout, embed rules, terminal mode |
| RUN-04 | Rail collapses to 30px strip, persisted, auto re-open on newly waiting unless collapsed this session | Defaults key, session flag, transition detector |
| RUN-05 | Closed wings Working/Needs you/Finished + hairline; music unchanged apart from 7px dot; 3s closed polling while chat runs | ContentView hook, width math, finished detector, pollInterval |
</phase_requirements>

## Summary

Everything the phase needs already exists in the repo or in serve; no packages are added. Serve's `/api/state` already carries all run fields D-03 names (verified live by GET and in `orch.js` `runState()` / `state()`). The two non-obvious facts: `latest` is a **truncated** tool-call string, not valid JSON (`[Bash] {"command":"cd /Users/...` cut at 160/300 chars), so it must be regex-parsed, never `JSONDecoder`d; and `startedAt` has **fractional seconds**, which the default `ISO8601DateFormatter` rejects.

The closed notch is a content-hugging layout: `NotchLayout()` in ContentView is an if/else-if chain (hello -> battery -> inline HUD -> music -> face -> blank), and the black `NotchShape` simply wraps whatever the chain renders plus a 14px horizontal inset (`cornerRadiusInsets.closed.bottom`). Wings therefore go in as **one new `else if` placed after the music branch and before the face branch**: music wins by construction, hello/battery/HUD also win. The 7px music dot is an `.overlay` on the visualizer container so music sizing is untouched.

Expand levels: Phase 3's `expand/collapse/reset` becomes a per-view-model level map. Window growth, pinned frame, monitors, one `SharingStateManager` begin/end per expanded session and `releaseKey` all stay. Terminal is a mode inside the already-grown window (no second resize). Keyboard: cmd shortcuts reach the app **only while the notch panel is key**, which in this app means composer typing or terminal; esc cannot do "back one level" because it already means "release typing" (composer) and "interrupt" (terminal). Document, do not work around.

**Primary recommendation:** Build pure helpers first (elapsed/latest/question/message/pollInterval/finished-transition/rail-auto-open/expandedHeight/level-transition/shortcut-map/wing-width/clock) in `OrchestratorRunsPure.swift` with asserts in `Phase7Tests.swift`; then views; hook ContentView at exactly three spots (wing branch + 1 observed property, 26px radius, music dot overlay); keep wing/finish tracking in `OrchestratorWings.swift` via a Combine sink on `manager.$runs` so the manager needs no `// Phase 7` block.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Run state, elapsed inputs, latest, denials | serve (`/api/state`) | App decode | App only reads; derive display strings client-side in pure helpers |
| Waiting-question text, ask-in-chat message | App pure helper | serve POST /api/chat | Message is built locally; delivered via existing `manager.sendText` |
| Level state machine, window resize, key gate | AppKit (`OrchestratorExpand`) | SwiftUI views | Window frame/key are AppKit; views only read level |
| Cross-fade, rail width, wing spring | SwiftUI | - | Pure view animation |
| Wing visibility/priority, finished detection | `OrchestratorWingsModel` (Combine on manager) | ContentView branch | Keeps manager untouched; ContentView only branches |
| Closed polling cadence | Manager poll loop calling pure `pollInterval` | - | Phase 4 already wires the call |

## Standard Stack

All system frameworks, nothing to install. [VERIFIED: repo inspection, CLAUDE.md Technology Stack]

| Item | Use |
|------|-----|
| SwiftUI + AppKit (`NSEvent` local monitor, `NSWindow.setFrame`) | Views, level machine, shortcuts |
| URLSession/Codable (existing `OrchestratorManager`) | Decode extra run fields; `sendText` for Ask in chat |
| `Defaults` 9.0.6 (`@Default(.key)` is already used in ContentView/BoringViewCoordinator) | `orchRunsRailCollapsed` |
| Combine (`manager.$runs.sink`) | Finished-run detection without editing the manager |
| `ISO8601DateFormatter` with `.withFractionalSeconds` | Parse `startedAt`/`lastOutput` |

**Package Legitimacy Audit:** no external packages are installed in this phase. Packages removed (slopcheck [SLOP]): none. Flagged [SUS]: none.

## Run fields (serve), verified

[VERIFIED: orch.js `runState()` lines 139-155, `state()` 556-559; live GET of /api/state 2026-10-14]

| Field | Type / sample | Notes |
|-------|---------------|-------|
| `startedAt` | `"2026-10-14T02:45:42.415Z"` | **Fractional seconds**. Parse with `.withInternetDateTime,.withFractionalSeconds`, fall back to no-fraction |
| `lastOutput` | ISO string (log mtime) | Also fractional. For finished runs it approximates the end time |
| `state` | running/stuck/waiting/done/failed/stopped | `stuck` = alive and no output for 15 min (`STUCK_MS`) |
| `result` | `""`/text/null | Last `result` event text across invocations. Present while running too (empty string possible) |
| `denials` | `["Bash"]` (tool names only) | `[]` when none |
| `latest` | `"[Bash] {"command":"cd /Users/...` or assistant text or result text | Max 300 chars; tool JSON additionally cut at 160 -> **truncated JSON, never decode** |
| `activity` | `{step: "plan-phase"|null, agents:[{type,desc}]}` or `null` | Only for running/stuck. `step` has the `gsd-`/`gsd:` prefix stripped. `null` for other states |
| `waiting` rule | `!acknowledged && (denials>0 || result ends with "?")` | So a "waiting" run is either denied tools or Claude's last message is a question |

Model: add to `OrchestratorRun` (all optional, `Decodable, Equatable` stays synthesized): `startedAt: String?`, `lastOutput: String?`, `result: String?`, `denials: [String]?`, `latest: String?`, `activity: RunActivity?` with `RunActivity { step: String?; agents: [RunAgent]? }`, `RunAgent { type: String?; desc: String? }`. Existing `mk()` helper and JSON tests keep working (they decode a subset). Note: `activity: null` must decode to nil (optional handles it).

Equality note: `lastOutput` changes every poll for a live run, so `runs != rs` republishes every 2-3s while any run is live. Acceptable (already true today via nothing? today only id/state compared; this is new). Wing/finished logic must not rely on `runs` identity changes; it sinks and compares states.

### Derivations (all pure, in `OrchestratorRunsPure.swift`)

- `runElapsed(run, now) -> String`: live (running/waiting/stuck) = now - startedAt; finished (done/failed/stopped) = lastOutput - startedAt (duration, not growing). Format: `<60s -> "<1m"`, `<60m -> "Nm"`, else `"Nh"` or `"NhMm"`. Card right label: `stuck` (red `#FF453A`, replaces elapsed) for stuck, `failed` for failed, else elapsed. Cards need a `TimelineView(.periodic(from:.now, by: 30))` so labels advance between polls.
- `latestAction(run, now) -> String` (line 3, one line, mono):
  - stuck -> `"no output for \(minutes)m"` (from `lastOutput`; matches the mock).
  - `latest` starting `[Tool] ` -> `Bash` -> `"$ " + command`; `Edit/Write/Read` -> `"Tool path"`; `Grep/Glob` -> `"Tool pattern"`; other -> `"Tool"`. Extract with regex on the truncated string (`"command":"((?:[^"\\]|\\.)*)` tolerant of a missing closing quote), unescape `\"`/`\\`/`\n`. Never `JSONSerialization`.
  - `latest` plain text -> first non-empty line.
  - If result is empty and `activity.step` exists -> `"gsd " + step` (+ `" · N agents"` when agents non-empty). Rule: tool line beats step; step beats nothing.
  - done/failed/stopped -> first line of `result` ?? `latest`; failed with nothing -> `"see log"`.
- `waitingQuestion(result:denials:) -> String`: strip markdown (`**`, backticks, leading `- `/`> `), take the last 2 non-empty lines of `result`, join with a space, collapse whitespace, cap 160 chars for the card and 300 for the chat message (cut on a word boundary + "…"). If `result` is empty or has no `?` and denials exist -> `"Needs permission: Bash, Edit"` (dedupe, preserve order).
- `askInChatMessage(run) -> String`: `"Run <id> on <project> is waiting: <question>"` plus `" (denied: Bash)"` when denials; **always a single line, must start with a letter** (a leading `/` or `!` would trigger a Claude Code slash command or bash mode). Newline-free by construction (serve also collapses `\s*\n\s*` to one space, so this is belt and braces). Short copy for the button: "Ask in chat".

### Ask-in-chat transport (verified in orch.js 639-655)

`POST /api/chat {text}` types the text with `tmux send-keys -l` and then **presses Enter 150ms later** — it submits immediately. Consequences for planning:
- Fire only on an explicit tap (never automatically); POST once (`manager.sendText` is already guarded by `sending`). Disable the button while `manager.sending`.
- Disable (and show Start instead) when `!manager.chatRunning`. Also disable while `!manager.promptOptions.isEmpty` / `manager.prompt != nil`: typing text onto a live permission/question screen is not an answer and could land in the wrong place.
- An unsent draft already typed in the Claude box would be prepended to the message; unavoidable, mention in the plan as a known limit.
- 409 is handled by the existing `post` (refreshes, returns false). On success, do not switch tabs; optionally flip the card button to "Sent" for ~2s (local `@State`).
- Verification must NOT exercise this (S-01); test only the pure builder.

## Closed notch: how music wings work today (ContentView.swift)

[VERIFIED: ContentView.swift lines 40-125, 247-340, 392-490]

- `NotchLayout()` is a `VStack` whose first child is the if/else-if chain. Order: `helloAnimationRunning` -> battery notification -> inline HUD -> **music** (`(!expandingView.show || type == .music) && closed && (isPlaying || !isPlayerIdle) && musicLiveActivityEnabled && !hideOnClosed`) -> face animation (`!expandingView.show && closed && music idle && showNotHumanFace && !hideOnClosed`) -> `.open` header -> blank `Rectangle` (`closedNotchSize.width - 20`).
- Width is **content-driven**: `MusicLiveActivity()` = `HStack { art (h-12=20) ; black Rectangle (closedNotchSize.width - 6); visualizer container (20) }` with default HStack spacing 8. The black `NotchShape` (`clipShape`) hugs it after `.padding(.horizontal, cornerRadiusInsets.closed.bottom)` (14 each side when closed). Total visible width = layout width + 28.
- The whole `mainLayout` has `.contentShape(Rectangle()).onHover/.onTapGesture`, so a wider layout automatically gets the hover/click area. `computedChinWidth` only sizes the invisible chin rectangle when `vm.chinHeight > 0`; leave it alone (optional follow-up: add the wing width for parity).
- `OrchestratorClosedIndicators` is an `.overlay { }` on `mainLayout` (no layout effect): attention dot top-trailing + 2px usage hairline; already hidden during hello and offline.

### Wing hook (smallest diff)

1. In the chain, **after the music branch, before the face branch**:
   `} else if vm.notchState == .closed && !vm.hideOnClosed && !coordinator.expandingView.show && wings.kind != nil { OrchestratorWingsView() }`
   plus one stored property `@ObservedObject private var wings = OrchestratorWingsModel.shared` so the branch re-evaluates. Publish only `kind` (an enum with the label payload) from the model; keep the ticking elapsed clock inside the wing view via `TimelineView(.periodic(from: .now, by: 1))` so ContentView does not re-render every second.
2. Music wins by construction (earlier branch). Also wins over hello/battery/HUD. Music live activity is also "showing" when paused-but-not-idle (`!isPlayerIdle`); wings stay hidden then. That matches D-11 "while the music live activity is showing".
3. Music dot: `.overlay(alignment: .leading) { OrchestratorMusicNeedsDot().offset(x: -8) }` on the visualizer container `HStack` (the one with `.frame(width: h-12, ...)`). `OrchestratorMusicNeedsDot` is a self-observing view in `OrchestratorWings.swift` (`manager.needsAttention`, 7x7 orange circle). It lives in the 8px HStack gap, so **no layout change** (do not add it as an HStack child: that widens music's notch, violating S-04). Visibility inside the gap is a UAT item (the gap is 8px, dot is 7px).
4. Radius 26: change the `bottomCornerRadius` expression in `currentNotchShape` (lines 55-57) to use `vm.notchSize.height > openNotchSize.height + 1 ? 26 : 24` for the open branch. No manager observation needed; `NotchShape.animatableData` is a (top, bottom) pair, so it animates inside the same `withAnimation` that grows `notchSize`.

Sneak peek / hello: both are earlier chain branches, so wings never compete. `.conditionalModifier(...).fixedSize()` on the HUD case is unaffected.

### Wing width math (needs on-screen tuning)

README widths 285/305 are outer black widths. The shape adds 14px each side around the layout, so the layout frame is `W - 28` and each wing layout width is `(W - 28 - closedNotchSize.width)/2` (= 36 for working, 46 for needs-you on a 185 notch, equal to README 50/60 outer). Wings **must be symmetric** around the centre spacer (hardware notch is at window centre) — compute `wing = max(minWing, needed content width)` for both sides, with the pill width estimated as `chars * 6.5 + 16` (11pt medium; add a `ponytail:` comment, estimate). Leading padding in the layout is therefore ~0 (README's 14/12 are measured from the outer edge); verify visually. Pure function `wingWidth(kind:label:notchWidth:) -> CGFloat` is test-friendly. Wing animation: model sets `kind` inside `withAnimation(.spring(response: 0.35, dampingFraction: 0.8))`; the branch swap gives a `.transition(.opacity)`; width interpolation between branches is not guaranteed by SwiftUI (UAT item; fallback = accept fade).

### Wing content rules

- Kind priority: `needsYou` (manager.needsAttention) > `finished` (within 4s) > `working` > nil. Guard all with `manager.hasLoaded && !manager.offline`.
- Working = `manager.chatRunning && manager.liveStatus != nil` (Phase 4 `LiveStatus` text + elapsed seconds). Do **not** treat running dispatched runs as "working" (Open Question 1). Elapsed shown `m:ss` (`h:mm:ss` above an hour): keep `(elapsedAtPoll, receivedAt)` in the view and display `elapsed + now - receivedAt` so it ticks between 3s polls; re-anchor when the poll value changes.
- Needs-you label: `manager.prompt?.title`-derived tool name if present, else the first waiting run's `denials.first`, else `"Needs you"`; render `"<Tool>?"` (pure `wingLabel(...)`: take the title's first word, strip trailing "?"). "Needs you" fallback does not fit the pill at 60px: render the fallback without the pill chrome shrink (or at 10pt) and rely on `wingWidth` growth. Pulsing glow: `Circle` + `.shadow` radius animated with `.easeInOut(duration: 1.2).repeatForever` started `onAppear`, stopped by view removal.
- Finished: see next section. Rotating asterisk: `Text("✻").rotationEffect(.degrees(spin))` driven by `.linear(duration: 8).repeatForever(autoreverses: false)` in `onAppear`.
- Corner attention dot (`OrchestratorClosedIndicators`) overlaps the needs-you pill and duplicates the music dot. D-11 says it stays; recommendation (flag to user): keep it only when neither wings nor the music dot is rendering (e.g. idle face case); otherwise hide. Default if unanswered: follow D-11 literally except hide it when the wing is in needs-you state.

## Finished-run detection (4s wing) and polling

- `OrchestratorWingsModel.shared` (in `OrchestratorWings.swift`, `@MainActor ObservableObject`) subscribes `manager.$runs.sink { old/new }` (it keeps its own `previous: [id: state]`) — **no `OrchestratorManager` edit**. If the plan prefers manager state, add a `// Phase 7` block at a different spot than Phase 5's (MERGE-MAP #1), but the sink avoids it.
- Pure `finishedTransition(old: [String: String], new: [OrchestratorRun]) -> OrchestratorRun?`: returns a run whose id was in `old` as running/stuck (also waiting? no) and is `done` in `new`. Rules: ignore ids absent from `old` (first load after launch, or runs repopulating after an offline gap, which sets `runs = []` — see manager catch block); `failed`/`stopped` do not fire (not "finished" per spec); multiple at once -> most recently started. Baseline: first non-empty snapshot is stored without firing.
- On fire: `withAnimation(spring 0.35/0.8) { finished = (project, id) }`, then a `Task` sleeps 4s and clears it iff still the same id (generation counter). Keep latency in mind: closed polling is 3s, so the wing appears up to 3s after completion.
- `pollInterval(notchOpen:chatRunning:) -> Int` (Phase 4 hook; Phase 7 body): open 2; closed && chatRunning 3; else 10. Caveat: on a fetch error the manager does not reset `chatRunning`, so an offline serve with stale `chatRunning == true` polls every 3s while closed. Mention to Phase 4/planner (cheap: offline also yields 10 if Phase 4 adds an `offline` argument; otherwise accept).

## Expand levels

### Current code (verified)
`OrchestratorExpand` (per-`ObjectIdentifier(vm)` maps): `expand()` computes `expandedExtra`, `setFrame(pinnedFrame(... windowHeight(...)))`, inserts into `expanded`, installs global+local mouse monitors, `SharingStateManager.shared.beginInteraction()`, springs `vm.notchSize` to open+extra. `collapse()` = `finish()` (one `endInteraction`, `releaseKey`) + spring back + a 450ms-delayed window shrink. `reset()` = same, no animation (notch closed or tab left; called from `OrchestratorManager.notchOpen` didSet and the overlay's `.onDisappear`). `BoringViewModel.open()` reads `OrchestratorExpand.shared.openSize(for:)`. `ContentView` already allows the taller window: `.frame(maxWidth: windowSize.width, maxHeight: windowSize.height + max(0, vm.notchSize.height - openNotchSize.height))` and `.frame(height: open ? vm.notchSize.height : nil)`. Window is `[.borderless, .nonactivatingPanel, ...]`; `canBecomeKey = keyboardWindow === self || terminalWantsKey`.

### State machine (on Phase 4's seam; names assumed from MERGE-MAP)
```
levels: [ObjectIdentifier: ExpandLevel]   // absent == .open
.open --setLevel(.expanded)--> .expanded --setLevel(.terminal)--> .terminal
.open --setLevel(.terminal)--> (grow + terminal)      // cmd-T from open is allowed
.terminal --back--> .expanded --back--> .open
any --outside click--> collapse everything, then vm.close()
reset() --> .open immediately (no animation)
```
- Pure `nextLevel(_ l: ExpandLevel, _ e: LevelEvent) -> ExpandLevel` with `LevelEvent { deeper, back, terminal }` (`deeper`: open->expanded, expanded stays; `terminal`: any->terminal; `back`: terminal->expanded, expanded->open, open stays). **Put `ExpandLevel` and `LevelEvent` in `OrchestratorRunsPure.swift`** (harness compiles only Foundation/CoreGraphics files; `OrchestratorExpand.swift` imports SwiftUI). Phase 4 will probably define `ExpandLevel` in `OrchestratorExpand.swift`; since Phase 7 owns both files, move the declaration. Phase 6 only calls the API by name, so no conflict.
- Bookkeeping invariant (preserve Phase 3 CR-fixes): **exactly one** `beginInteraction`/`endInteraction` per leaving-and-returning-to-open cycle; `.expanded <-> .terminal` neither begins nor ends. Window frame is set to the expanded height on the first transition out of `.open` and shrunk (delayed) only when returning to `.open`. Monitors are installed on first leave of open and removed on return. `releaseKey` on terminal -> expanded as well (terminal dismantle already calls it).
- Legacy callers: the Phase 5 chat tap-to-expand currently calls `expand(vm:window:)` and means "terminal". Post-Phase-4 that shim maps to `.terminal`; D-05 wants click-transcript -> `.expanded`. **Make any legacy `expand(vm:window:)` entry point map to `.expanded`** (Expand.swift is Phase 7's), and verify after Phase 4 lands which call the chat tap makes (Open Question 3).
- Phase 6 contract (06-RESEARCH): `setLevel(.expanded, ...)` for tall question cards, then back to `.open` only if it raised the level and the level is still `.expanded`. Requirements on Phase 7: `setLevel` idempotent (same level = no-op, no double begin), `.expanded` shows no terminal, and never reset a user-chosen `.terminal`.

### Height (discretion): use a new pure function, leave `expandedExtra`
`Phase3Tests` asserts `expandedExtra(1080, 190) == 300` etc., and Phase 7 may only edit `Tests/Phase7Tests.swift`. So add `expandedHeight(screenHeight:) = max(300, min(440, 0.45 * screenHeight))` (README 440 target, 45% cap, 300 floor so the rail + composer still fit) and `extra = expandedHeight - 190` in `OrchestratorExpand`; leave `expandedExtra` in place (dead but tested; remove in a later cleanup). Measure with `window.screen?.frame.height ?? 900` as today. Typical results: 14" (982) -> 440, 13" Air (900) -> 405, 1080p external -> 440. Window height = `windowHeight(base: 210, notchHeight: 440, openHeight: 190)` = 460. Content-sized frame is Phase 9; do not attempt.

### Motion
- Height: `withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { vm.notchSize = ... }` for both directions (replaces 0.38/0.8). One animation for open<->expanded; `.expanded<->.terminal` changes no size, only content.
- Cross-fade: expanded content view uses `@State shown = false`; `.task(id: level)` sets `shown = false`, sleeps 120ms, `withAnimation(.easeOut(duration: 0.18)) { shown = true }`; body `.opacity(shown ? 1 : 0)`. Reset immediately on level change.
- Delayed window shrink: spring (0.4/0.82) settles in ~0.6-0.7s; raise the 450ms shrink delay to ~650ms so the window does not clip the tail (still cancelled by the per-key `shrinkTasks`).
- Radius 26: ContentView one-liner above (animates with the notch spring).

### Mounting the expanded body
Today the expand overlay is `.overlay { OrchestratorExpandOverlay() }` on the tab content, drawing opaque black over the chat only when expanded. If Phase 7 simply swaps its body for `OrchestratorExpandedView`, the shell's chat (Phase 5 composer with `@FocusState`, window anchor, `allowsHitTesting(manager.wantsKeyboard)`) stays mounted underneath: **two live composers** if the expanded column embeds `OrchestratorChatView` too. Recommended fix, declared in `<merge_points>`: the shell (`OrchestratorView.swift`, Phase 4) renders `OrchestratorExpandedView()` **instead of** its normal switch when `level != .open` and keeps `.onDisappear { expand.reset() }`. That is a ~4-line edit to a Phase 4-owned file, conflict-free because Phases 5/6 do not touch the shell body. Alternative with no extra edit (if Phase 4 keeps the overlay): leave it, accept the double mount, and verify typing focus on device (risky). Pick the shell edit.

### Expanded layout (frame 12)
- Header stays (Phase 4 `BoringHeader`); body = `HStack(spacing: 12)`, padding `6/0/10`. Left = conversation column; right = rail (178px, left border 1px `#1C1C1E`, padding-left 12) or strip (30px).
- Left column content: `if manager.prompt != nil { OrchestratorPromptCard() } else { OrchestratorChatView() }` — both by type name with default initialisers (MERGE-MAP #4; Phase 6 research asks the card initialiser stay parameterless; `OrchestratorChatView` name comes from MERGE-MAP only, verify when Phase 4 lands). Phase 5 owns the composer, which lives inside that view.
- Bottom row spec (composer 32px + Terminal pill) cannot be built from Phase 5's single view. Fallback that stays inside owned files: composer stays inside the chat view (left column); the **Terminal pill sits at the bottom of the rail column**, under the usage bars (the mock places the pill under the rail anyway; the composer is slightly wider in the mock). When the rail is collapsed, put the pill in the 30px strip's column as an icon-only `terminal` button, or float it bottom-trailing. Better (needs a Phase 5 API ask): `OrchestratorChatView(showComposer:)` + separate `OrchestratorComposer`. Raise in the plan as a cross-phase gap.
- Segment: the header Chat|Runs segment is meaningless while expanded (rail shows runs); the shell replaces the body anyway; leave the segment as is.
- Terminal mode: replace the left column with the framed terminal; rail stays. `OrchestratorTerminalView` remains created only when `level == .terminal`; `termState`/`termID` reset on entering terminal; toolbar row (green dot, "Terminal · keyboard captured", "Collapse" pill calling `setLevel(.expanded)`); in use/unavailable -> message + Retry pill (existing logic, restyle).
- Collapse button (24px chevron.up) in `OrchestratorHeaderTrailing`: visible when `level != .open`, calls `back`. At `.open` the capsule is alone. The tab/offline states: collapse any level when `offline` or chat stops? Keep terminal usable even when stopped; reset only on tab leave/close (existing).
- When a question card raises `.expanded`, the 178px rail leaves the card ~420px wide (README 04 assumed full width). Open Question 2.

### Rail (12b)
- `@Default(.orchRunsRailCollapsed)`; declare in `OrchestratorExpanded.swift`: `extension Defaults.Keys { static let orchRunsRailCollapsed = Key<Bool>("orchRunsRailCollapsed", default: false) }` (needs `import Defaults`; keep out of the pure files).
- Session flag + auto-open live in a small `OrchestratorRailState` singleton in the same file: `userCollapsedThisSession: Bool` (set true only by the user's collapse action), `autoOpened: Bool` transient override. `effectiveCollapsed = Defaults[...] && !autoOpened`. Recommendation: auto-open does **not** write Defaults (it is a transient reveal; the persisted value stays the user's last explicit choice).
- Pure `shouldAutoOpenRail(old: [String: String], new: [OrchestratorRun], userCollapsedThisSession: Bool) -> Bool`: true when any run is `waiting` in `new` and not `waiting` in `old` (absent id counts as new, except the first baseline snapshot after launch/offline, same baseline rule as finished detection) and `!userCollapsedThisSession`. Fed from a `manager.$runs` sink like wings (share one sink/previous-state map in one object to avoid two copies).
- Spring for width: `.animation(.spring(response: 0.3, dampingFraction: 0.85), value: collapsed)`; rail content cross-fades, width via `.frame(width: collapsed ? 30 : 178)`.
- Hover peek: per-dot `@State hovered: String?` + `.popover`-free approach: an `.overlay` card anchored to the dot, offset leftwards (`alignment: .topTrailing`, `offset(x: -178-12)`), rendered above siblings with `.zIndex(1)`; `onHover` sets/clears `hovered`. Do NOT use `.popover` (opens an outside window, as Phase 4 D-07 already noted). The panel is non-activating, but `onHover` works without key status (the notch itself uses it).
- Compact rail cards reuse the board card view with a `compact` flag (radius 10, padding 8/10, no line 3 unless waiting).

## Keyboard shortcuts: what is feasible

[VERIFIED: BoringNotchSkyLightWindow.swift:112, OrchestratorView typing logic, OrchestratorTerminal key gate; AppKit behaviour = ASSUMED from training, confirm on device]

- The panel is a `.nonactivatingPanel` whose `canBecomeKey` is true only while a composer typing session is active (`keyboardWindow === self`) or the terminal is showing (`terminalWantsKey`). The app is otherwise never active. `NSEvent.addLocalMonitorForEvents(.keyDown)` only sees events delivered to this app, so shortcuts work **only while typing or in terminal mode**. A global key monitor would need Accessibility/Input Monitoring: out of scope (D-05).
- Install a `.keyDown` local monitor next to the existing mouse monitors in `installMonitors()` (same lifetime: only while level != open), and remove it in `removeMonitors()`. Act only when `event.window` is the tracked notch window; swallow handled events (`return nil`), pass everything else.
- Mapping (pure `shortcut(keyCode:chars:commandOnly:) -> Shortcut?` in RunsPure): cmd-down (keyCode 125) -> `deeper`; cmd-up (126) -> `back`; cmd-T (`charactersIgnoringModifiers == "t"`) -> `terminal`; cmd-\ (`"\\"`) -> toggle rail. Require exactly `.command` (no shift/option/control). Use characters (not keyCode) for T and backslash so non-US layouts still work.
- Per state: typing (composer key): all four work; cmd-up/down steal the TextField's go-to-start/end (single-line field, acceptable). Terminal (WKWebView first responder): the local monitor runs before the web view, so all four work and cmd-up exits the terminal to expanded. Not key (hover only, expanded without typing): **none work**; the user must use the buttons (header chevron, Terminal pill, rail toggle) or click outside.
- **esc cannot be "back one level"** in practice: in the composer esc already means release typing (`.onExitCommand`, hint text "esc release"), after which the panel is not key; in the terminal esc must reach Claude Code (interrupt). Intercepting it would break both. Document: back-one-level = cmd-up or the chevron; esc keeps its existing meanings. The alternative of making the panel key while expanded (activating our app and stealing focus whenever the user expands) contradicts Phase 3's focus-restore design; do not do it without user say-so.
- Phase 6's "1-9/esc while hovered" uses its own gated key take; any `releaseKey` side effects from my level changes (clearing `terminalWantsKey`, `restore`) must stay idempotent so the two do not fight.

## Architecture Patterns

```
serve /api/state --(poll 2s open / 3s closed+chat / 10s)--> OrchestratorManager.runs, liveStatus, prompt
                                       |-- sink --> OrchestratorWingsModel (kind: needsYou|finished|working, 4s timer)
                                       |-- sink --> OrchestratorRailState (auto-open)
ContentView NotchLayout (closed) --- else-if after music --> OrchestratorWingsView
ContentView MusicLiveActivity visualizer --- overlay --> OrchestratorMusicNeedsDot
Open notch -> shell: level == .open ? board/chat/... : OrchestratorExpandedView
OrchestratorExpand.setLevel -> window frame (pinned) + vm.notchSize spring + monitors + SharingState + key gate
```

Recommended file layout (all under `boringNotch/Orchestrator/`, already stubbed by Phase 4): `OrchestratorRunsPure.swift` (all pure helpers, incl. `ExpandLevel`), `OrchestratorRunsBoard.swift` (board + `OrchestratorRunCard` reused compact in the rail), `OrchestratorExpanded.swift` (expanded view, rail, strip, Defaults key, `OrchestratorRailState`), `OrchestratorWings.swift` (model, wings view, music dot), `OrchestratorExpand.swift` (level machine, monitors), `OrchestratorTerminal.swift` (frame/toolbar/state UI), `OrchestratorCompact.swift` (hairline/dot rules).

Board layout: `ScrollView(.horizontal)` with `LazyHStack(spacing: 8)` of 196px cards, `stripRuns(manager.runs, limit: 10)`; empty state "no runs" (README has none; keep today's text). Bottom row: 30px pill, `#1C1C1E`, "(asterisk) Orchestrator: <status>" where status = `needsAttention` ? (first waiting run -> `"waiting on run <id.suffix>"`; else prompt -> "needs you") : `liveStatus?.text` ?? (chatRunning ? "idle" : "stopped"). Send arrow disabled/omitted (this row is informational). Run id display: the last 4 hex chars (ids are `YYMMDDHHMMSS-xxxx`; mock shows "x7f2").

### Anti-Patterns
- Decoding `latest` as JSON (truncated; will fail on every long Bash command).
- Adding the music dot as an HStack child (changes music width).
- Putting ticking elapsed state in a `@Published` property read by ContentView (re-renders the whole notch every second).
- Calling `releaseKey`/`endInteraction` in per-level transitions instead of once per open<->expanded cycle (re-opens the Phase 3 CR-01/WR-03 bugs).
- Using `.popover` for rail hover peek or any menu (outside window).

## Don't Hand-Roll

| Problem | Don't build | Use instead |
|---------|-------------|-------------|
| ISO date parsing | regex/manual | `ISO8601DateFormatter` with `.withFractionalSeconds` + fallback |
| Persisted rail flag | UserDefaults wrapper | `Defaults` `Key<Bool>` + `@Default` |
| Keep-open while expanded | new timer/hover logic | existing `SharingStateManager` begin/end (one per cycle) |
| Window pinning | manual y math | existing `pinnedFrame`/`windowHeight` |
| Finished-run diff | manager state | Combine sink on `$runs` + pure diff func |
| Offline fast-fail | new session | existing 3s-timeout `session` in the manager |

## Common Pitfalls

1. **Truncated `latest`**: regex extraction only; unit-test with a cut-off string.
2. **Fractional-second ISO dates**: default formatter returns nil -> elapsed "0"/blank. Test with the real sample `2026-10-14T02:45:42.415Z`.
3. **Ask in chat submits instantly** (Enter after 150ms) and can land in a live prompt or append to a typed draft: gate the button (chat running, no prompt, not sending), start the message with a letter.
4. **Double composer** if expanded embeds the chat while the shell chat stays mounted: use the shell swap.
5. **Level bookkeeping** (begin/end interaction, monitors, key release) must stay once per cycle; `reset()` must also clear levels and set `notchSize` for open vms (Phase 3 CR-01).
6. **Wing asymmetry** shifts content onto the hardware notch: symmetric wings only.
7. **`expandedExtra` is test-pinned** (Phase3Tests): add `expandedHeight`, do not change the old function.
8. **First-snapshot/offline gaps** produce false "finished"/"newly waiting" events: baseline rule in both detectors.
9. **Stale `chatRunning` while offline** keeps 3s closed polling; wings must also guard `!offline`.
10. **Spring settle vs window shrink**: shrink only after ~650ms or the closing animation clips.
11. **cmd-up/down in a TextField**: monitor intercepts them (acceptable); but do not intercept esc.
12. **Rail auto-open vs persisted preference**: transient override, do not overwrite Defaults.

## Merge risks (Phases 5 and 6)

- **Phase 5**: none in files; compile-level dependency on the name `OrchestratorChatView` (and its composer). Tap-to-expand call target (see legacy shim). Phase 7's `OrchestratorRun` model edit vs Phase 5's `OrchestratorManager` `// Phase 5` block: different files. Phase 7 touches `OrchestratorView.swift` (shell swap, 4 lines) which MERGE-MAP gives Phase 4; declare it. `OrchestratorModels.swift`: Phase 7 edits only `OrchestratorRun`; Phase 6 moves `detectPrompt`/`PromptOption` out in Phase 4 already, so no overlap.
- **Phase 6**: depends on `setLevel` semantics above; both embed by type name. ContentView: only Phase 7 edits it.
- `STATE.md`/`ROADMAP.md` always conflict (keep both). `Tests/main.swift` already calls `runPhase7Tests()` (Phase 4).
- Phase 4 is unbuilt: every name taken from MERGE-MAP (`ExpandLevel`, `level(for:)`, `setLevel(_:vm:window:)`, `pollInterval(notchOpen:chatRunning:)`, `manager.prompt`, `manager.liveStatus`, `LiveStatus`, `OrchestratorHeaderTrailing`, `OrchestratorChatView`, `OrchestratorPromptCard`) must be re-checked against the merged Phase 4 code before writing tasks.

## Code Examples

Level transition + shortcut map (pure, harness-testable):
```swift
// OrchestratorRunsPure.swift
enum ExpandLevel: Equatable { case open, expanded, terminal }
enum LevelEvent { case deeper, back, terminal }
func nextLevel(_ l: ExpandLevel, _ e: LevelEvent) -> ExpandLevel {
    switch (l, e) {
    case (_, .terminal): return .terminal
    case (.open, .deeper): return .expanded
    case (.terminal, .back): return .expanded
    case (.expanded, .back): return .open
    default: return l
    }
}
func pollInterval(notchOpen: Bool, chatRunning: Bool) -> Int { notchOpen ? 2 : (chatRunning ? 3 : 10) }
func expandedHeight(screenHeight: CGFloat) -> CGFloat { max(300, min(440, 0.45 * screenHeight)) }
```
Fractional ISO date:
```swift
func parseISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}
```
Local key monitor (inside `installMonitors()`, Expand.swift):
```swift
keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
    guard let self, let s = shortcut(keyCode: e.keyCode, chars: e.charactersIgnoringModifiers,
        commandOnly: e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command) else { return e }
    return self.handle(s, event: e) ? nil : e   // handle() checks e.window is a tracked notch window
}
```
ContentView hook (shape radius, one expression): `bottomCornerRadius: open && scaling ? (vm.notchSize.height > openNotchSize.height + 1 ? 26 : cornerRadiusInsets.opened.bottom) : cornerRadiusInsets.closed.bottom`.

## State of the Art

| Old | Current | Impact |
|-----|---------|--------|
| Expand = terminal only (Phase 3) | Levels open/expanded/terminal | Window growth moves to `.expanded`; terminal no longer resizes |
| Runs strip overlay | Board behind Runs segment + rail | Strip view reused as card |
| Closed: dot + hairline only | Wings + dot + hairline | New chain branch |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Phase 4 will expose `ExpandLevel`, `level(for:)`, `setLevel(_:vm:window:)`, `OrchestratorChatView`, `OrchestratorPromptCard()`, `manager.prompt`, `manager.liveStatus` exactly as MERGE-MAP/Phase 4 CONTEXT describe | Expand levels, mounting | Plan tasks reference wrong names; re-verify after Phase 4 |
| A2 | Local `NSEvent` keyDown monitor receives cmd shortcuts while the non-activating panel is key (composer or terminal), and runs before WKWebView | Keyboard | Shortcuts silently dead in terminal; fallback = buttons only |
| A3 | Wing layout width = `W - 28 - notchWidth` over 2 matches README's 285/305 outer widths, and 8px HStack gap fits the 7px dot | Wings | Visual misfit; needs on-device tuning (wing width constants isolated in `wingWidth`) |
| A4 | SwiftUI interpolates the notch width when the wing branch inserts under `withAnimation`; otherwise only fades | Wings | Pop-in instead of spring-out |
| A5 | `Bash?` style label derivable from `prompt.title` first word (Phase 6 titles like "Bash command") | Wings | Wrong/long pill text; fallback "Needs you" |
| A6 | 440 target / 45% cap / 300 floor interpretation of "up to ~45%" | Height | Layout cramped or too tall on small screens |
| A7 | Auto-open should not overwrite the persisted Defaults value | Rail | If user wants persistence of auto-open, one-line change |

## Open Questions

1. **Does a dispatched running run (no chat activity) ever drive the Working wing?** Spec only describes chat "Working"; recommendation: no (wings reflect the orchestrator chat, runs appear via needs-you/finished). User may want "N runs working".
2. **Question card (Phase 6) in `.expanded` shares width with the 178px rail.** Recommendation: keep spec, check on device; fallback auto-strip the rail while a question card shows.
3. **What does the Phase 5/4 chat tap call (`expand` vs `setLevel(.terminal)`)?** Needs `.expanded`; verify after Phase 4.
4. **Composer + Terminal pill bottom row** needs a Phase 5 API (`showComposer:`) for fidelity; fallback = pill in the rail column.
5. **Corner attention dot** vs wings/music dot duplication (see Wing content rules).
6. **Waiting-first ordering**: mock shows the waiting card first; `stripRuns` keeps serve (newest-first) order within live. Locked as `stripRuns` per D-01; optional follow-up `boardRuns` promoting waiting.

## Environment Availability

| Dependency | Required By | Available | Notes |
|------------|------------|-----------|-------|
| Xcode / xcodebuild at /Applications/Xcode.app | Build (S-02) | assumed per CLAUDE.md; not re-probed | `-derivedDataPath /tmp/notch-dd-p7` |
| swiftc harness | Pure tests | as used in Phase 3 | Command in MERGE-MAP |
| serve at 127.0.0.1:4777 | Fixture capture (GET only) | yes (responded 2026-10-14) | Never POST, never `/term` |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | swiftc assert harness (`precondition`), `Tests/main.swift` calls `runPhase7Tests()` |
| Config | none; command from MERGE-MAP.md |
| Quick run | `mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t` |
| Full | the same + `xcodebuild ... -derivedDataPath /tmp/notch-dd-p7 build` (command in 07-CONTEXT S-02) |

### Phase Requirements -> Test Map
| Req | Behaviour | Type | Where |
|-----|-----------|------|-------|
| RUN-01 | decode extra run fields (nulls, missing, `activity:null`); `runElapsed` (live vs finished, "<1m", "12m", "1h 5m"); `latestAction` (truncated Bash JSON, Edit path, stuck minutes, step fallback, plain text); `waitingQuestion` (last lines, markdown strip, denials-only, cap); `askInChatMessage` (single line, starts with a letter, no `\n`); `stripRuns` unchanged | unit | Phase7Tests |
| RUN-02 | `nextLevel` table; `expandedHeight` (982->440, 900->405, 400->300); `shortcut` map (cmd-only, wrong modifiers rejected, `t`, `\`) | unit | Phase7Tests |
| RUN-03 | (visual) expanded/terminal layout | manual UAT | build only |
| RUN-04 | `shouldAutoOpenRail` (new waiting, already waiting, baseline, session-collapsed) | unit | Phase7Tests |
| RUN-05 | `pollInterval` table; `finishedTransition` (running->done fires; absent/first snapshot/failed do not); `wingKind` priority; `wingWidth` symmetric + monotonic; `formatClock` (0:41, 1:52, 1:05:02); `wingLabel` | unit | Phase7Tests |

### Wave 0 Gaps
None for framework (Phase 4 stubs `Tests/Phase7Tests.swift` and `main.swift`). Phase 3's existing asserts must still pass (do not change `expandedExtra`, `stripRuns`).
Manual UAT (human, cannot be automated without launching the app): wing fit, music dot visibility, cross-fade, key shortcuts while typing/terminal, rail auto-open, no duplicate composer.

## Security Domain

| ASVS | Applies | Control |
|------|---------|---------|
| V5 Input validation | yes | Ask-in-chat text is built from server-supplied run text: strip control characters/newlines, cap length, start with a letter; `OrchestratorPost.request` already rejects empty text |
| V4/V2/V3/V6 | no | No auth/session/crypto in this phase |

Threat: a malicious/odd run `result` text (prompt injection) forwarded into the orchestrator chat by a user tap. Mitigation: explicit user tap only, visible short label, message framed as "Run X is waiting: ..." (content is quoted data, but the orchestrator model will read it; unavoidable by design D-02). Terminal: WKWebView navigation already restricted to 127.0.0.1:4777/about:blank (keep).

## Sources

### Primary (HIGH)
- `/Users/mitch/Documents/Claude/orchestrator/orch.js` (read-only): `runState`, `latestOutput`, `gsdActivity`, `state()`, `/api/chat` POST handler; live `GET /api/state`.
- Repo: ContentView.swift, BoringViewModel.swift, sizing/matters.swift, NotchShape.swift, BoringNotchSkyLightWindow.swift, OrchestratorExpand/Terminal/Compact/Manager/Models/Pure/View, Phase3Tests/main.swift.
- `.planning/design/orchestrator-2a/README.md`, `MERGE-MAP.md`, screenshots 00, 05, 12, 12b; Phase 3/4/5/6 CONTEXT and Phase 6 RESEARCH.

### Secondary / Tertiary
- NSEvent local monitor and non-activating-panel key behaviour: training knowledge (MEDIUM), flagged A2.

## Metadata
**Confidence:** stack HIGH; serve fields HIGH; wings hook HIGH, pixel fit MEDIUM; key shortcuts MEDIUM; Phase 4 seams LOW-MEDIUM until built.
**Research date:** 2026-10-14. **Valid until:** until Phase 4 merges (re-verify names), else 30 days.
