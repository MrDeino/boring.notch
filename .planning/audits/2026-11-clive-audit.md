# Clive audit — November 2026

Report only. Nothing was changed, built or run, and no requests were made to serve. Every finding was traced in the code; the top ones were checked again by hand. Paths are relative to the repo root (`boringNotch/…`); `orch.js` means the orchestrator's serve, which lives in the orchestrator project, not in this repo.

**Confidence:** *confirmed* = traced end to end in the code; *likely* = the code path is real but depends on timing or on AppKit/SwiftUI behaviour; *speculative* = plausible, not proven.
**Size:** S = under an hour, M = half a day, L = more.

## Top 10

| # | Finding | Symptom | Size | Confidence |
|---|---------|---------|------|------------|
| 1 | A stale full fetch can drop the newest chat blocks for good (B1) | chat: message missing | S-M | likely |
| 2 | The block merge appends unknown blocks at the end, so a filled gap lands out of order (B2) | chat: ordering | S | confirmed |
| 3 | A message sent mid-turn vanishes after 30 s (B3) | chat: message missing | S | confirmed |
| 4 | Lock, sleep or a display change rebuilds the panel at 640x210 while the notch is still open or expanded (A1) | open/close: clipped, stuck open | S | confirmed |
| 5 | Going from expanded back to open often closes the whole notch (A2) | open/close: closes on its own | M | likely |
| 6 | With several displays, closing any notch collapses the open one on another display (A3) | open/close: multi-display | S-M | confirmed |
| 7 | Dropping a file on the composer closes the notch about 0.5 s later (A4) | open/close: closes on drop | S | likely |
| 8 | One `running:false` chat event clears the chat and nothing reloads the history (B4, serve S1) | chat: history missing | S | likely |
| 9 | A deploy marked "building" never times out, in the app or in serve (C1, serve S7) | stale "deploying" wing | S | confirmed |
| 10 | The SSE stream sends the full state (~300 KB+) every 2 s, around the clock, and the app decodes it on the main thread (D1, serve S3) | battery, jank, slow serve (which feeds 1, 5-7 of section B) | M | confirmed |

The first fix to make is #1 together with #2. They are one area (`OrchestratorChat.ingestFull` / `mergeChatBlocks`) and they cover most of the missing and out-of-order messages. #4 to #7 cover the open/close reports. #10 is the cheapest win on the serve side: drop `now` from the SSE state.

---

## A. Open/close, hover, drag, multi-display, sleep/wake

### A1. Lock, sleep or a display change rebuilds the panel at the default size while the view model stays open — High · S · confirmed
- **Where:**
  - `boringNotch/boringNotchApp.swift:99-100`: lock calls `cleanupWindows()`. `showOnLockScreen` defaults to false, so this runs on every lock and on every wake that needs a password.
  - `boringNotchApp.swift:478-483`: a screen change calls `cleanupWindows()` and then `adjustWindowPosition()`.
  - `boringNotchApp.swift:541-551`: the new window is built around the same `vm`, at `windowSize` (`:240`).
  - `boringNotch/ContentView.swift:211`: `onChange(of: vm.notchSize)` has no `initial: true`, so `syncWindow` never runs for the new window.
- **What goes wrong:** the notch is open or expanded when the screen locks or a display comes or goes. The new panel is 640x210 while `vm.notchSize` is still the expanded size, so the content is clipped and clicks below 210 pt miss the panel. `notchState` stays `.open`, and the new window never saw a hover-enter, so no hover-exit closes it either. The notch stays open until the user hovers in and out.
- **Fix:**
  - After `window.contentView = hosting`, call `OrchestratorExpand.shared.syncWindow(vm: viewModel, window: window, now: true)`, or add `initial: true` at `ContentView.swift:211`.
  - In `onScreenLocked` / `cleanupWindows`, reset `OrchestratorExpand`, end typing and call `vm.close()`, so the notch comes back closed.

### A2. Collapsing from expanded back to open often closes the notch — High · M · likely
- **Where:**
  - `boringNotch/Orchestrator/OrchestratorExpand.swift:278-285`: `finish` calls `endInteraction()`, and the session count reaching 0 posts `.sharingDidFinish`.
  - `boringNotch/ContentView.swift:153-166`: that notification closes the notch if `!isHovering`.
  - `ContentView.swift:566-580`: hover-exit closes after 100 ms.
- **What goes wrong:** the expanded level holds `preventNotchClose`. When the level drops back to open with the pointer in the lower part of the panel, the shape shrinks out from under the pointer. Hover-exit fires just as the keep-open session ends, so `vm.close()` runs. To reproduce: open a run log (the notch grows to expanded), then click empty space to dismiss it, or press Back / ⌘↑ with the pointer low. The notch closes instead of going back to open.
- **Fix:** when `collapse(vm:)` targets `.open`, keep one extra `beginInteraction()` until the next hover-enter (or about 1 s), or make the hover-exit close skip the ~700 ms after a level change.

### A3. Multi-display: one view model's `close()` resets every display — High (multi-display) · S-M · confirmed
- **Where:**
  - `boringNotch/models/BoringViewModel.swift:209`: `OrchestratorManager.shared.notchOpen = false`, a global flag.
  - `BoringViewModel.swift:206,217-221`: `close()` writes the shared `coordinator.currentView` and `lastUsedView`.
  - `boringNotch/Orchestrator/OrchestratorManager.swift:137`: `!notchOpen` calls `OrchestratorExpand.shared.reset()`.
  - `boringNotchApp.swift:516-518,548`: `close()` is called on view models that are already closed.
  - `ContentView.swift:250`: the drop debounce calls `close()` without checking the state.
- **What goes wrong:** display A is open or expanded on the Orchestrator tab. A screen-parameter change, a notch-height notification, or display B's drop debounce calls `close()` on B. That sets `notchOpen = false`, so:
  - A collapses to the open level;
  - A's tab jumps;
  - the status menu and notes close;
  - polling drops to the closed cadence.
- **Fix:**
  - In `close()`, if the view model is already closed, only refresh its sizes and return.
  - At `boringNotchApp.swift:516,548`, set the sizes instead of calling `close()`.
  - Make `notchOpen` mean "any view model is open".

### A4. A drop on the composer, or a drag held over it, closes the notch about 0.5 s later — Med-high · S · likely
- **Where:**
  - `boringNotch/Orchestrator/OrchestratorChat.swift:534`: the composer's `onDrop` binds a local `$dropTargeted`.
  - `OrchestratorChat.swift:602`: `handleDrop` never sets `vm.dropEvent`.
  - `boringNotch/ContentView.swift:227-252`: when `anyDropZoneTargeting` goes false, `vm.close()` runs 500 ms later unless `vm.dropEvent` is set.
- **What goes wrong:** the innermost drop target wins, so the outer targets report "not targeted" while the drag is over the composer. 500 ms later the notch closes. This also happens after a successful composer drop.
- **Fix:** set `vm.dropEvent = true` in the composer's drop handler and OR its targeted flag into `vm.dragDetectorTargeting`. Simpler alternative: skip the debounce close while the Orchestrator tab is current.

### A5. The keyboard-shortcut auto-close fires on a notch the user is using (upstream) — Med · S · confirmed
- **Where:** `boringNotchApp.swift:397-414`.
- **What goes wrong:** the toggle shortcut schedules `close()` after 3 s without checking hover, and only the next shortcut press cancels it. Two cases:
  - Open with the shortcut, move into the notch to read: it still closes at 3 s.
  - Shortcut-open, let it close, then hover-open within 3 s: the notch closes "on its own".
  - Also, the outer `Task` at `:379` is not `@MainActor`.
- **Fix:** check the hover state before closing, cancel `closeNotchTask` on hover-enter and in `open()`, and mark the Task `@MainActor`.

### A6. A pending approval blocks hover-open, even when the approval panel is hidden — Med · S · confirmed
- **Where:** `ContentView.swift:549-552` (hover guard `approvals.approval == nil`) versus `:301` (the panel only draws when `!vm.hideOnClosed`).
- **What goes wrong:**
  - In fullscreen with "hide notch" on, a pending run approval makes the notch ignore hover, with nothing visible to explain why.
  - When the approval or a sneak peek clears with the pointer still inside, hover-open does not come back until the pointer leaves and re-enters.
- **Fix:** guard with `approval == nil || vm.hideOnClosed`. When the blocker clears while `isHovering` is true, re-run the hover-open path.

### A7. A scroll gesture interrupted by hover-open leaves the notch scaled and dimmed (upstream) — Med · S · likely
- **Where:** `ContentView.swift:586-592`: `handleDownGesture` returns while open before it resets `gestureProgress` on `.ended`.
- **What goes wrong:** a short two-finger scroll over the closed notch sets `gestureProgress > 0`, then hover-open fires. The open notch keeps the scale (`:87-91`) and the reduced opacity (`:313,380`).
- **Fix:** reset `gestureProgress` on `.ended` before the guard, and on any `notchState` change.

### A8. Wings shift the drawing but not the hover area — Low-med · S · likely
- **Where:** `ContentView.swift:124` (`.offset(x: wings.shiftX)`) comes before `:134-135` (`.contentShape(Rectangle()).onHover`).
- **What goes wrong:** with uneven wings, hovering the far end of the longer wing does not open the notch, but empty space on the other side does.
- **Fix:** move `.offset` after the hover/tap/pan modifiers, or offset the `contentShape` by the same amount.

### A9. Teardown leaves stale `OrchestratorExpand` and typing state — Med when it hits · S · speculative
- **Where:**
  - `boringNotchApp.swift:155-161,492-498`: windows and view models are dropped.
  - `OrchestratorExpand.swift:14-24,133,141`: dictionaries keyed by `ObjectIdentifier(vm)` are never pruned.
  - `OrchestratorManager.swift:149-163`: `typing`.
- **What goes wrong:** a display is unplugged, or the Mac sleeps, while that notch is expanded or typing. `preventNotchClose` can stay latched, so every notch ignores hover-exit. A reused object address can also make a new notch look already expanded.
- **Fix:** when windows are torn down, reset `OrchestratorExpand`, call `endTyping()`, and prune the entries whose view model is gone.

### A10. Nothing re-syncs on wake (upstream gap) — Med · S · speculative
- **Where:** `boringNotchApp.swift:291-362`. There is no `NSWorkspace.didWakeNotification`, `screensDidWakeNotification` or `activeSpaceDidChangeNotification` observer anywhere.
- **What goes wrong:** after a wake where the screen frames match but the menu-bar height changed, `closedNotchSize`, the window position and the drag-detector regions stay stale.
- **Fix:** on wake, run `adjustWindowPosition()` and `setupDragDetectors()`. This is the same hook as D1's sleep/wake stream handling.

### A11. A drag can open the notch with no drop session behind it (upstream) — Low-med · S · likely
- **Where:** `boringNotchApp.swift:217-237`: `onDragExitsNotchRegion` is never set. `DragDetector.swift:92-100`: mouse-up only resets flags.
- **What goes wrong:** a fast drag across the top of the screen opens the notch, and it stays open.
- **Fix:** on drag exit or mouse-up, close if `!vm.dropEvent && !vm.anyDropZoneTargeting`.

### A12. The terminal key gate is global — Low · S · confirmed
- **Where:** `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift:112`, `OrchestratorTerminal.swift:7,87`.
- **What goes wrong:** with the terminal open on display A, clicking display B's notch makes B key, and the terminal loses keystrokes.
- **Fix:** store the terminal's window (weak) and compare it with `=== self`.

### A13. Minor upstream items — Low · S · confirmed
- `boringNotchApp.swift:265`: each new window overwrites `windowScreenDidChangeObserver`, so one observer leaks per display per screen change. Fix: keep the observers per UUID.
- `boringNotchApp.swift:426`: `NSScreen.screens.first!` crashes if the app launches with no display. Fix: `guard`.

---

## B. Chat: missing or duplicated messages, sends, ordering

### B1. A stale full fetch drops the newest blocks — High · S-M · likely
- **Where:**
  - `boringNotch/Orchestrator/OrchestratorChat.swift:66`: a full fetch runs when `needsFull`, and on every 15th poll.
  - `OrchestratorChat.swift:85-86`: `ingestFull` evaluates `reset: !d.blocks.contains { $0.id == blocks.last?.id }` against the store after the await.
  - Callers: `OrchestratorManager.swift:429-431` (`applyChat` → `store.refresh` whenever there is a new prompt), plus the prompt-card checks, `submitFreeText`, `postNow` and `answerApproval`.
- **What goes wrong:**
  1. While SSE is up, a full GET is in flight. On a busy serve that can take up to 20 s.
  2. Meanwhile the stream appends block Z, often the prose Claude Code writes right after a card is answered.
  3. The older snapshot doesn't contain Z, so `ingestFull` treats it as a `/clear` and resets. Z disappears.
  4. Serve's SSE cursor has already moved past Z, so the stream never resends it.
  - Even without a reset, `out[i] = b` overwrites newer blocks with stale copies. For example, a finished tool goes back to "running".
- **Fix:** never full-fetch from `applyChat` while streaming (use `since` only), or capture `blocks.last?.id` before the await and test against that.

### B2. The merge appends unknown blocks at the end — High · S · confirmed
- **Where:** `boringNotch/Orchestrator/OrchestratorTranscript.swift:86`.
- **What goes wrong:** the store holds `[A, C]`, and a fetch returns `[A, B, C]`. B lands after C. Gaps come from B1, B4 and serve S5.
- **Fix:** when the incoming batch overlaps what is held, take the order from the incoming batch: insert each unknown block after its preceding incoming id, and keep only the held blocks newer than the incoming last id.

### B3. A message sent mid-turn vanishes after 30 s — High · S · confirmed
- **Where:** `OrchestratorTranscript.swift:445`: a `.sent` row is dropped after `staleAfter` if no matching user block exists. Its own `ponytail:` comment names the ceiling.
- **What goes wrong:** Claude Code only writes the user line when it takes the queued input, which is after the current turn. Any message sent while a turn has been running for more than 30 s disappears from the chat. It reappears later out of place, or never (serve S2).
- **Fix:** don't time out `.sent` rows while the turn is live; start the 30 s from the end of the turn. The upgrade the comment already names: serve echoes a client id.

### B4. One `running:false` chat event clears the chat and nothing reloads it — Med-high · S · likely
- **Where:** `OrchestratorManager.swift:296,429-430` → `store.refresh(chatRunning:false)` clears the blocks (`OrchestratorChat.swift:57-61`); `OrchestratorStream.swift:88-89`.
- **What goes wrong:** a transient `tmux has-session` failure on serve (S1) sends `running:false` once. The store clears and sets `needsFull`. The next event says `running:true`, but while streaming no fetch runs and serve's blocks cursor never resends the history, so earlier messages are gone.
- **Fix:** on a false→true `chatRunning` change while streaming, do a full `store.refresh`. Serve side: S1.

### B5. A send that timed out after reaching serve shows "Not sent", and Retry types it twice — Med · S · confirmed
- **Where:** `OrchestratorChat.swift:160-161`, `OrchestratorModels.swift:347`.
- **What goes wrong:** a `.timedOut` text POST has `lastPostUnreached == false`, so the row is marked `.failed`, but the text was already typed (serve S4). Retry sends C-u plus the text again into whatever is in the box.
- **Fix:** mark a timeout as "unconfirmed" and hide Retry until a later screen or blocks read shows the text is in neither the transcript nor the input box.

### B6. The prompt card comes back after an answer that landed, so a second tap answers the next prompt — Med · S · likely
- **Where:** `OrchestratorPromptCard.swift:98,105`; `OrchestratorManager.swift:85-88` (`answerApproval` has no `stale` guard).
- **What goes wrong:** the keys get a 200, the follow-up refresh times out, `stale` is set, and the card is restored. The user taps again, and the digit goes to the next question or to the chat input.
- **Fix:** after a 200, keep the card dismissed with "Checking…" until a good read. Refuse answers while `stale`.

### B7. Chat and state are fetched as one unit — Med · S · likely
- **Where:** `OrchestratorManager.swift:349-351` (`try await (chat, state)`), `OrchestratorModels.swift:155-156` (`runs`/`usage` are decoded strictly), `OrchestratorStream.swift:54`.
- **What goes wrong:** a slow `/api/state` (serve's heaviest handler), a `null` run, or an odd `resets_at` throws. The good chat payload is thrown away and the tab goes to "Reconnecting": sends are held and the card restores (B6). On SSE, a state event that fails to decode is dropped silently.
- **Fix:** fetch and apply chat and state independently. Decode `runs` and `usage` leniently with `try?`, as `deploys` already is.

### B8. The stream reader awaits network calls inside its read loop — Med · S-M · likely
- **Where:** `OrchestratorManager.swift:295,300` (applying an event can await a full fetch), `:316` (20 s watchdog), `:262` (fixed 30 s retry).
- **What goes wrong:** a blocks GET longer than 20 s stops `lastStreamLine` from updating. The watchdog kills a healthy stream, there is no stream for 30 s, and the reconnect's `since` usually triggers a full fetch, which is the window where B1 and B2 happen. The 20 s watchdog is also only 5 s above serve's 15 s ping.
- **Fix:** update `lastStreamLine` as bytes arrive, separate from applying events. Retry after 1, 2, 5, 10, then 30 s, and reset the backoff after a healthy minute.

### B9. The live reply row duplicates prose when the markdown differs from the screen — Med-low · S · likely
- **Where:** `OrchestratorTranscript.swift:246-258` (`proseHeld` matches the first and last 40 alphanumerics).
- **What goes wrong:** a reply with a link such as `[docs](https://example.com)` near its start or end. The screen shows "docs"; the block contains the URL. The match fails, and both rows show until the 3 s grace ends.
- **Fix:** strip link URLs and `**`, `#`, list markers and backticks before building `proseKey`.

### B10. The send queue busy-waits, and a waiting row has no way out — Low-med · S · confirmed
- **Where:** `OrchestratorChat.swift:156`; Edit/Cancel only show for `.failed` (`:426`).
- **What goes wrong:** while offline, or while a prompt stays up (even a misparsed one), the loop wakes 20 times a second indefinitely, and the row sits in "sending" with no way to cancel it.
- **Fix:** await a change on `$stale`, `$promptOptions` or `$sending` instead of sleeping, and show Edit/Cancel on waiting rows.

### B11. Smaller send-path risks — Low · S · speculative
- `OrchestratorModels.swift:322-334`: the auto-retry on `.networkConnectionLost` can re-type a message that serve already handled before it dropped. Fix: retry only GETs and keys, not text POSTs.
- `OrchestratorPromptCard.swift:36`: `PromptKeyQueue` posts keys without waiting on the manager's `sending` gate. A tap during a queued send's C-u / text / Enter can land inside the message. Fix: wait for `!sending`.

**Checked and found OK:**
- Only one SSE stream at a time; the reader and watchdog cancel correctly.
- No tight retry loop.
- `@MainActor` use is consistent.
- No leaks that matter (closures capture singletons).
- The regex-guarded force unwraps are safe.
- Blocks are capped at 200.
- The `since` cursor has no off-by-one.

---

## C. Runs, usage, deploy wing, background agents, file drop

### C1. A "building" deploy never times out — High · S · confirmed
- **Where:** `boringNotch/Orchestrator/OrchestratorRunsPure.swift:265-270,300,310` (`DeployWings.building` and `deployRows` take a building deploy whatever its age); `OrchestratorManager.swift:249` (`pollInterval` counts it as activity).
- **What goes wrong:** when GitHub leaves a deployment `in_progress`, the wing reads "app deploying… 3h 12m" indefinitely. The row stays, and whenever SSE is down the app polls every 3 s with the notch closed.
- **Fix:** one pure helper, `deployIsLive(d, now)`, that treats `building` older than about 30 min as stale. Use it in `ingest`, `deployRows` and `pollInterval`, and show stale deploys dimmed as "status unknown" or hide them. Serve side: S7.

### C2. Background agents can never appear with today's serve — Med · S · confirmed
- **Where:** `OrchestratorManager.swift:281,354,381-385`, `OrchestratorStream.swift:66-67`.
- **What goes wrong:** serve has no `/api/chat/agents` route (it returns 404) and never sends `agents` events. The Background row, the card and the blue closed-notch dot never show, and every poll while the chat runs makes a GET that returns 404.
- **Fix:** add the endpoint on serve (S8), or remember the first 404 and stop asking.

### C3. Usage figures go stale after their reset time — Med · S · confirmed
- **Where:** `OrchestratorModels.swift:245-256`, `OrchestratorStatusCapsule.swift:187-188,319-324`, `OrchestratorExpanded.swift:115-116`.
- **What goes wrong:** once `resets_at` has passed, the capsule still shows "95% · resets 3:00pm" in orange. The `at` timestamp serve provides is ignored.
- **Fix:** when `resetsAt < now`, show "reset" with no orange. Decode `at` and dim the figures when they are more than about an hour old.

### C4. Images fail at once while serve is reconnecting; text messages wait — Med · S · confirmed
- **Where:** `OrchestratorChat.swift:147-156`: images upload before the wait-while-stale loop.
- **Fix:** wait for serve (`untilReachable()`) before uploading.

### C5. Dropped or pasted images are decoded and re-encoded on the main thread — Med · S · likely
- **Where:** `OrchestratorChat.swift:691,1397-1406`, `OrchestratorModels.swift:372-388`.
- **What goes wrong:** a large photo goes through `NSImage(contentsOf:)`, a redraw at up to 2000 px and a PNG encode on the main thread. The notch, including the music controls, freezes for a moment.
- **Fix:** do the work in `Task.detached` using `CGImageSourceCreateThumbnailAtIndex` (max pixel size 2000), then attach on the main thread.

### C6. File chips fail while offline and have no automatic retry — Low-med · S · confirmed
- **Where:** `OrchestratorModels.swift:487-495,527-541`.
- **What goes wrong:** a dropped file uploads straight away. If serve is down, the chip shows "Upload failed" and sending stays blocked until each chip is retried by hand.
- **Fix:** `await untilReachable()` before each upload, or re-queue uploads that never reached serve.

### C7. Removing a chip doesn't cancel its upload, and serve keeps partial files — Low · S · likely
- **Where:** `OrchestratorModels.swift:506-510`; on serve, see S9.
- **Fix:** keep the upload `Task` for each chip and cancel it in `remove()`.

### C8. Temporary folders from file-promise drops are never removed — Low · S · confirmed
- **Where:** `OrchestratorChat.swift:1429-1436`, `OrchestratorModels.swift:509,537`: only the file inside `tmp/orch-drop-<UUID>/` is deleted.
- **Fix:** delete the parent folder when the chip is a temporary one.

### C9. One main-thread Task per upload-progress callback — Low · S · likely
- **Where:** `OrchestratorModels.swift:532-534`.
- **What goes wrong:** a large file re-renders the composer thousands of times.
- **Fix:** publish progress only when it has moved by at least 1%.

---

## D. Performance (idle CPU, battery)

### D1. The SSE stream is always on, and serve pushes the full state every 2 s — High · M · confirmed
- **Where:**
  - App: `OrchestratorManager.swift:241-265,284`. The stream never stops and ignores whether the notch is open, and there are no sleep/wake observers.
  - Serve: S3.
- **What goes wrong:**
  - `state` includes a `now` timestamp, so serve's "only send when changed" check never matches. About 300 KB or more (50+ runs with their full prompts and results, the backlog, projects, sessions, layout) goes out every 2 s, with the notch closed or the screen asleep.
  - The app decodes it on the main thread and only needs `runs`, `usage` and `deploys`.
- **Fix:**
  - Serve: S3.
  - App: close the stream after about 60 s with the notch closed and poll every 10 s instead, reopening on open. Also close it on `NSWorkspace.screensDidSleepNotification` / `willSleepNotification` and reopen on wake, sharing the hook with A10.

### D2. SSE events over 2 MB are dropped silently — Med if it happens · S · speculative
- **Where:** `OrchestratorStream.swift:50`.
- **What goes wrong:** the state payload grows with the backlog and run history. Once it passes 2 MB, runs, usage and deploys freeze while the stream still looks healthy, and polling stays off.
- **Fix:** call `refresh()` when a `state` event is dropped for size, and shrink the payload (S3).

### D3. Wings and deploy rows re-render every second when they don't need to — Low-med · S · confirmed
- **Where:**
  - `OrchestratorWings.swift:123,138-143`: the 1 s `TimelineView` wraps every wing kind, but only `.working` and `.deploying` show elapsed time. "Needs you" and the stale deploy wing from C1 tick every second with the notch closed.
  - `OrchestratorExpanded.swift:351-354`: serve always lists deploys, so the 1 s timeline re-parses ISO dates every second whenever the tab is open.
- **Fix:** use the timeline only for the kinds and rows that show a timer.

### D4. The closed-notch indicators observe the whole manager and `MusicManager` — Low · S · confirmed
- **Where:** `OrchestratorCompact.swift:7-11`.
- **What goes wrong:** the overlay is rebuilt on every `screen` and `runs` publish, which undoes the `OrchestratorWingsInputs` split that was made to avoid exactly this.
- **Fix:** add a `bgRunning` Bool to `OrchestratorWingsInputs` and observe only that.

### D5. Timer inventory (informational)
- **Fork:**
  - Poll loop: every 2 s while the stream is up. Otherwise every 0.5 s (notch open, turn live), 2 s (open), 3 s (closed, something running) or 10 s (closed, idle).
  - Stream retry every 30 s; watchdog every 5 s; `untilReachable` every 500 ms; send queue every 50 ms (B10).
  - Run log and terminal checks every 2 s, only while shown.
  - Live status row 1 s; background card 1 s or 60 s; run cards 30 s.
  - The spinner and glow are Core Animation, so they cost no main-thread time.
- **Upstream:**
  - Music visualizer 0.3 s while playing; `NotchHomeView` timelines 0.1 s and 0.25 s, open notch only.
  - `AnimatedFace.swift:49` leaks a repeating timer each time it appears (only with `showNotHumanFace`, off by default).

---

## E. Simplification (keeping the upstream diff small)

### E1. Sparkle points at upstream's update feed unless `ORCH_NO_SPARKLE` is set — Med · S · confirmed
- **Where:** `boringNotchApp.swift:23-29`; `Info.plist:15` (`SUFeedURL` is the upstream appcast). The flag is not in `project.pbxproj`.
- **What goes wrong:** a build made without the flag can offer to replace Clive with upstream Boring Notch.
- **Fix:** set the flag in the project's build settings or an xcconfig, and leave the code alone.

### E2. Upstream features with on-by-default settings Clive likely doesn't need — Low · S each
- **Shelf:** `boringShelf` and `openShelfByDefault` are on (`models/Constants.swift:166-167`). `close()` also switches to the shelf tab when it holds files (`BoringViewModel.swift:216`).
- **Battery:** `showBatteryIndicator` and `showPowerStatusNotifications` are on (`Constants.swift:142-145`).
- **Download listener:** `enableDownloadListener` is on (`Constants.swift:148`), but its settings toggle is commented out (`SettingsView.swift:399`).
- Change the defaults rather than delete the code. Calendar, the webcam mirror, the HUD replacement and YouTube Music are already off by default, but `ContentView.swift:19` always observes `WebcamManager`.

### E3. Repeated networking and state code in `boringNotch/Orchestrator/` — Low (maintenance) · S-M
- **GET and decode, five copies:** `OrchestratorManager.swift:324-328,381-385`, `OrchestratorChat.swift:188`, `OrchestratorRunsBoard.swift:177-183`, `fetchOrchestratorNotes`. One `getJSON(path)` helper on the manager would replace them.
- **URLSession, four setups:** `OrchestratorManager.swift:58-64,229-236` and `OrchestratorChat.swift:10-15`, plus a throwaway session per retry at `OrchestratorModels.swift:331`.
- **Approval state held twice:** `OrchestratorManager.approval` / `rawApproval` and `OrchestratorApprovalCenter.approval`.
- **"Turn live" has three overlapping sources:** `chatLive`, `liveStatus` and `liveReply`. A single computed `turnLive` would replace them.

---

## F. Serve side (`orch.js`, for the orchestrator project; not fixed here)

| # | Where | Behaviour | Feeds | Fix |
|---|-------|-----------|-------|-----|
| S1 | `orch.js:1171`, `:903` | Any `tmux has-session` error reads as "chat stopped", but the SSE blocks cursor isn't reset, so history is never resent | B4 | Debounce `running:false`, or send `reset:true` on the next blocks event |
| S2 | `orch.js:704`, `:725` | Entries without `message`, or with non-human `origin`, are skipped. Input typed mid-turn may be recorded as a different entry type (unverified) and never become a user block | B3 | Check how Claude Code records queued input; map it to a user block |
| S3 | `orch.js:1124`, `:916-918`, `:905-907`, `:758`, `:700-747`, `:196-203` | `now` in `state()` defeats the SSE dedupe, so the full state is sent every 2 s. Synchronous tmux captures every 500 ms. Up to 4 MB of transcript is re-read and re-parsed on each growth. `lastResult` re-reads each live run's whole log on every state build. Together they block the event loop and cause the client timeouts | D1, B5-B8 | Leave `now` out of the SSE state. Send the notch a trimmed state (runs without prompt/result bodies, usage, deploys), e.g. `/api/events?client=notch`. Parse blocks incrementally by byte offset. Use async `execFile` for tmux. Skip or cache `lastResult` for live runs |
| S4 | `orch.js:1336` | The text POST types the text, waits 150 ms, sends Enter and only then replies, so a slow loop times the client out after the text has landed | B5 | Reply 202 right after typing, or accept a client id for idempotency |
| S5 | `orch.js:947`, `:950-952` | The first SSE blocks event and the cursor's `lastId` come from two separate reads, so a block written between them is in neither | B2 | Take both from one read |
| S6 | `orch.js:746-747` | An unknown `since` silently returns the last 80 blocks with no flag | B1 (forces the full fetch) | Return `reset:true` / `found:false` |
| S7 | `orch.js:1071`, `:1088` | A deployment whose latest status is missing, `in_progress`, `queued` or `pending` is reported as `building` indefinitely and re-polled every 20 s | C1 | After ~30 min, report `state:'stale'` and drop back to the 2-min check |
| S8 | `orch.js:1257-1346` | No `/api/chat/agents` route and no `agents` events | C2 | Add them, or the app stops asking |
| S9 | `orch.js:1218-1245` | `chatFile` has no `aborted`/`close` handler, so partial uploads stay in `runs/uploads`, and nothing ever cleans that folder | C7 | `req.on('aborted', …)` to delete the partial file; prune old uploads |
| S10 | `orch.js:935`, `:1253` | `claude` and `backlog` events, and the `layout`/`sessions`/`projects`/`events`/`backlog` state fields, are unused by the notch | D1 | Part of the trimmed notch stream in S3 |
