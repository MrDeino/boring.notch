---
phase: quick-261015-jym
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - boringNotch/Orchestrator/Snapshots/SnapFrames.swift
  - boringNotch/Orchestrator/Snapshots/SnapIdle.swift
  - boringNotch/Orchestrator/Snapshots/Snap.swift
  - boringNotch/Orchestrator/Snapshots/run.sh
  - boringNotch/Orchestrator/OrchestratorExpand.swift
  - boringNotch/Orchestrator/OrchestratorExpanded.swift
  - boringNotch/Orchestrator/OrchestratorView.swift
  - boringNotch/ContentView.swift
  - boringNotch/Orchestrator/OrchestratorChat.swift
  - boringNotch/Orchestrator/OrchestratorStatusCapsule.swift
  - boringNotch/Orchestrator/OrchestratorPromptCard.swift
autonomous: true
requirements: [QUICK-261015-jym]

must_haves:
  truths:
    - "Expand (open->expanded) is one motion: on every frame the notch shape's width progress and height progress are within tolerance of each other; no frame where one moves and the other holds still"
    - "Collapse (expanded->open) and close (open->closed) pass the same width/height-together check"
    - "The top edge stays pinned to the screen top and the content still fades through level changes and open/close"
    - "The Orchestrator tab stays built while the notch is closed; opening no longer builds the transcript on the trigger frame"
    - "Closed-notch idle CPU stays under the existing --idle limits, including a new closed scene with the tab kept built and transcript/SSE ticks arriving"
    - "Close/open hooks still work: click monitors removed after close, expand.reset on close, typing ended, notes flushed, run log closed, keep-open sessions back to 0, composer/notes/prompt fit re-applied on reopen"
    - "Home/Shelf and the music player behave exactly as before (they are still removed when closed, with upstream's scale+fade)"
  artifacts:
    - path: "boringNotch/Orchestrator/Snapshots/SnapFrames.swift"
      provides: "--frames per-frame shape size capture + width/height-together gate"
      contains: "together"
    - path: "boringNotch/ContentView.swift"
      provides: "Orchestrator tab body kept mounted while closed (hidden, zero layout contribution)"
    - path: "boringNotch/Orchestrator/OrchestratorView.swift"
      provides: "open/close hooks driven by notch open state instead of onAppear/onDisappear"
  key_links:
    - from: "boringNotch/ContentView.swift"
      to: "OrchestratorView"
      via: "tab body branch kept in the tree when currentView == .orchestrator and the notch is closed"
    - from: "boringNotch/Orchestrator/Snapshots/SnapFrames.swift FramesRoot"
      to: "boringNotch/ContentView.swift root chain"
      via: "mirror kept in sync (keep-mounted branch, fade, frames)"
---

<objective>
Make expand, collapse and close ONE even motion (width and height on the same spring from top-centre, no sideways step, no hitch at the content swap), and keep the Orchestrator tab built while the notch is closed so open stops paying the 80-150 ms first-frame build, without raising closed-notch idle CPU or breaking the tab's open/close hooks.

Purpose: the user saw expand go "wider first, then taller" and residual choppiness in the Release build after quick 261015-hmo.
Output: --frames with a width/height-together gate, the fix, a kept-mounted tab, a new closed idle scene, before/after numbers, fresh Release (/tmp/notch-rel) and Debug (/tmp/notch-dd) builds.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@./CLAUDE.md
@.planning/STATE.md
@.planning/quick/261015-hmo-notch-animation-frame-rate/261015-hmo-SUMMARY.md
@.planning/quick/261015-ehb-expand-pinned-to-top-again/261015-ehb-SUMMARY.md
@boringNotch/Orchestrator/OrchestratorExpand.swift
@boringNotch/Orchestrator/OrchestratorExpanded.swift
@boringNotch/Orchestrator/OrchestratorView.swift
@boringNotch/Orchestrator/Snapshots/SnapFrames.swift
@boringNotch/Orchestrator/Snapshots/run.sh

<facts>
Verified by the planner (read, not guessed):

- Sizes: open 640x190 (`openNotchSize`, sizing/matters.swift). Expanded = `expandedSize(screen:openWidth:)` in OrchestratorRunsPure.swift:171 = width min(850, screen.w-80), height max(520, 0.6*screen.h). So expand is +210 pt wide (+33%) and about +400 pt tall (+210%).
- One notch-size change path: `OrchestratorExpand.animate(_:to:)` (OrchestratorExpand.swift:63). It calls `syncWindow(vm:size:)` first (a grow-only `setFrame(display: true)` outside the animation, ehb fix), then `withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { vm.notchSize = target }`, then `syncWindow(vm:)` (shrink deferred 650 ms).
- Where the shape gets its size (ContentView.swift ~line 100-135 and 210): HEIGHT = `mainLayout ... .frame(height: open ? vm.notchSize.height : nil)`. WIDTH has no explicit frame on mainLayout. It is the proposal from `.notchRootFrame(notchSize:)` (OrchestratorExpand.swift:294, `maxWidth: max(windowSize.width, notchSize.width)` inside the window-wide frame). The tab body and header are flexible (`maxWidth: .infinity`). So width and height come from two different frames at two different levels of the tree, driven by the same `vm.notchSize` change, while the window has already grown to the full expanded width before the spring.
- Content hold (hmo 74b995c, OrchestratorExpanded.swift:153-213): the column is laid out at `held`. At the hidden swap (fadeOut 0.08 s) `held = slot`, which is the slot's in-between size at about 80 ms. After that, `shown == level`, so every slot change starts a fresh `withAnimation(.spring(response: 0.4...)) { held = s }`. The content chases the shape on its own springs, re-starting each frame, and keeps growing after the shape has settled. That is a candidate for "then it opens up further": the composer/rows bottom arrives later than the shape bottom. It also brings back per-frame relayout after the swap.
- Collapse candidate: `reset()`/`finish` and the open-level fits. The composer re-asserts its fit (`fitComposer`, OrchestratorChat.swift:506/513) after the swap, at the open level. That can start a second height-only spring (`setFit` -> `animate`) after the collapse spring.
- Open/close: ContentView.swift:350 `if vm.notchState == .open { VStack { switch coordinator.currentView { ... case .orchestrator: OrchestratorView() } } .transition(orchestrator ? .opacity.animation(.smooth(duration: 0.35)) : .scale(0.8)+opacity) }`. The tab is built on the open trigger frame and torn down on close.
- Hooks that fire only on insert/remove today (all must keep working with the tab kept built):
  - OrchestratorView.swift:78 `onAppear { expand.tabOpened(vm:anchor:) }`
  - OrchestratorView.swift:83 `onDisappear { expand.tabClosed; notes flush; statusMenuOpen/notesOpen false; runLog.close(); escMonitor removed; restoreLevel nil }`
  - OrchestratorExpanded.swift:214 `onAppear { shown = level }` and :219 `onDisappear { expand.reset() }` (reset clears every fit and collapses)
  - OrchestratorChat.swift:343 `onDisappear { stopTyping(); removeKeyMonitor() }`
  - OrchestratorChat.swift:506/513: composer fit set on appear/height change, cleared on disappear
  - OrchestratorStatusCapsule.swift:372/377: notes `fitNotch()` on appear; `stopTyping(); setFit("notes", 0)` on disappear
  - OrchestratorExpanded.swift:287/288: PromptContextView fit on appear, 0 on disappear
  - OrchestratorPromptCard.swift:320/321: `ctl.appeared()` / `ctl.disappeared()` (a mount count; on 0 it drops hover/dwell and calls release())
  - OrchestratorStatusCapsule.swift:81: `expand.register(vm:anchor:)` on appear
- Harness mirrors of ContentView's root (keep in sync with any ContentView change): `FramesRoot` (SnapFrames.swift), `NotchReplica.core` (Snap.swift:26), `LiveRoot` (Snap.swift:437), `IdleRoot` (SnapIdle.swift:9). The closed --idle scenes (a-*, b-*) host `ClosedReplica` only, so today they never measure a mounted tab.
- run.sh builds the harness from `Orchestrator*.swift + Snapshots/*.swift + NotchShape.swift`. ContentView.swift is NOT compiled into it, so any ContentView change must be mirrored by hand in FramesRoot (and IdleRoot/LiveRoot where relevant).
- Build recipes (from ev9/hmo, plus this task's flags):
  - Release: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Release -derivedDataPath /tmp/notch-rel CODE_SIGN_IDENTITY=- ENABLE_HARDENED_RUNTIME=NO 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ORCH_NO_SPARKLE' clean build > /tmp/notch-rel-build.log 2>&1`
  - Debug: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/notch-dd CODE_SIGN_IDENTITY=- build > /tmp/notch-dd-build.log 2>&1`
  - The harness links `$DD/Build/Products/Debug/Defaults.o`. A parallel run may rebuild /tmp/notch-dd, so measure with your own dirs: `SNAP_BUILD=/tmp/jym-snap-build DD=/tmp/jym-dd` (copy or build Defaults.o there once, as hmo did with /tmp/hmo-dd).
</facts>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Measure the two-phase expand: per-frame width/height capture, a together-gate that fails, baseline, cause</name>
  <files>boringNotch/Orchestrator/Snapshots/SnapFrames.swift, boringNotch/Orchestrator/Snapshots/run.sh</files>
  <action>
Evidence first. Do not change app code in this task.

1. In `FramesRoot`, record the notch shape's laid-out size on every layout pass. Add `.onGeometryChange(for: CGSize.self) { $0.size }` on `mainLayout` after its `.shadow` (the black clipped shape, before `.frame(height:)`). Push `(CACurrentMediaTime(), size)` into a recorder owned by the harness, the same way `FrameRecorder` is.
   - Also record the content's `held` box. A second `onGeometryChange` on the `OrchestratorView` wrapper is enough; it reports where the visible column's bottom is.
   - Also record the window frame in `FrameRecorder.tick`, so the report shows when the window grows relative to the shape.
   - First check that the shape samples really are per frame: the probe must give at least about 20 samples across a spring. hmo proved that SwiftUI re-lays an animated frame on every frame. If it is not per frame, add a fallback. Read the shape's left/right/top/bottom from a pixel row and column, with `cacheDisplay`, on the panel like `--transition`'s dense pass, in a separate pass after the timing pass so captures never touch the interval numbers. Say in the summary which source you used.

2. Together-check, one pure function in SnapFrames.swift, applied per transition.
   - From the start size A (the sample before the trigger) and the end size B (the last sample in the 900 ms window), compute `pw = (w - A.w)/(B.w - A.w)` and `ph = (h - A.h)/(B.h - A.h)` per sample. Only do this when both |B-A| > 1 pt.
   - FAIL a transition when any sample has `|pw - ph| > 0.08`.
   - Also FAIL when any consecutive pair inside (0.02, 0.98) progress has one dimension moving more than 0.5 pt while the other moves less than 0.05 pt.
   - Print per transition: `together <name> maxGap=<x> at=<ms> stuck=<n> samples=<n>`, plus the first sample where the two diverge most.
   - Gate it for expand, collapse and close. Report open as well, and gate it too if it passes after the fix. `FRAMES_REPORT=1` still never fails.
   - Add one `assert`-style self-check of the pure function, run at the start of `--frames`: a synthetic together series passes; a series with width first and height after fails.
   - Update run.sh's usage comment for the new check.

3. Baseline. Run `OPT=-O SNAP_BUILD=/tmp/jym-snap-build DD=/tmp/jym-dd boringNotch/Orchestrator/Snapshots/run.sh --frames > /tmp/jym-baseline-1.txt 2>&1` 3 times (files -1..-3), and once at -Onone. Redirect to a file, never pipe.

4. Diagnose and record the cause in your notes for the summary, with the numbers. Likely candidates (verify, don't assume):
   - (a) The shape's width and height are animated by two different frames (notchRootFrame's maxWidth vs mainLayout's `.frame(height:)`), and the window is already full width before the spring. Look for width progress leading or lagging height.
   - (b) The content (`held`) chasing the slot with per-frame restarted springs after the swap. The visible content grows after the shape is done: "opens up further".
   - (c) On collapse, a second height-only spring from a fit re-asserted after the swap.
   - (d) The deferred 650 ms window shrink.
   - If the shape check PASSES at baseline in the mirror, the two-phase look comes from the content, not the shape. Then also gate the content box: its bottom must track the shape bottom (same progress tolerance) once it fades in, and must not grow after the shape has settled.
   - Re-read ContentView's real root chain against FramesRoot for anything the mirror leaves out that could split width from height (BoringHeader sizing, chin, conditional modifiers). Mirror the relevant part if you find one.
   - The new check must FAIL at baseline on whatever is the real two-phase source. Commit with the failing check in place: `test(quick-jym): per-frame width/height together check in --frames`, explicit paths.
  </action>
  <verify>
    <automated>OPT=-O SNAP_BUILD=/tmp/jym-snap-build DD=/tmp/jym-dd FRAMES_REPORT=1 boringNotch/Orchestrator/Snapshots/run.sh --frames > /tmp/jym-baseline-check.txt 2>&1; grep -E "^together (expand|collapse|close)" /tmp/jym-baseline-check.txt</automated>
  </verify>
  <done>--frames prints the frame-interval lines plus `together` lines for all four transitions. The self-check of the pure function passes. Baseline files /tmp/jym-baseline-{1,2,3}.txt and -Onone exist. At least one of expand/collapse fails the together check (shape, or content if the shape passes) and the cause is identified with sample evidence. The harness commit exists. No app source changed.</done>
</task>

<task type="auto">
  <name>Task 2: One motion: width and height on one spring, content laid out once at its final size, swap hitch reduced</name>
  <files>boringNotch/Orchestrator/OrchestratorExpand.swift, boringNotch/Orchestrator/OrchestratorExpanded.swift, boringNotch/ContentView.swift, boringNotch/Orchestrator/Snapshots/SnapFrames.swift</files>
  <action>
Fix the cause Task 1 found. Each change is kept only if `--frames` (together lines and intervals) improves. Otherwise revert it and note it under rejected experiments.

- If the cause is (a), width and height on different frames:
  - Drive both from the same `vm.notchSize` frame at one tree level, inside the same transaction. The smallest diff is an explicit width on the mainLayout height frame for the Orchestrator tab only, i.e. `.frame(width:height:)` in place of `.frame(height:)` with the width taken from `vm.notchSize.width` when open and the tab is .orchestrator. Home/Shelf must keep upstream's layout exactly; the open width for them is 640 either way, but keep the condition so their tree is unchanged.
  - Keep the pre-spring window grow outside the animation (ehb). That is what keeps the top pinned.
  - Mirror the change in FramesRoot.
- If the cause is (b), content chasing the slot:
  - At the hidden swap, lay the content out ONCE at its FINAL size, not at the slot's in-between size. Capture at rest the constant offset `restingNotch - restingSlot` (header + outer paddings; the same at every level because the level paddings are inside `held`). At the swap, set `held = vm.notchSize - offset`, without animation.
  - Then suppress the per-frame follow while the shape spring runs. For example, follow with animation only when `vm.notchSize` itself changes at a settled level (the open-level fit growth), not on every slot change.
  - The clipped OrchestratorView reveals the final layout as the shape grows, with the existing fade intact.
- If the cause is (c), a second spring on collapse: make the collapse target include the fit that will be re-asserted (openSize already adds fitHeight). Stop the post-swap re-assert from starting a second spring when the value is unchanged.
- Swap hitch (hmo: 45-60 ms on expand, rows re-render plus the rail insert): with held = final size the swap does one relayout instead of one per frame. If the rail insert is still a long frame, try keeping the rail built at the open level at zero width and hidden. Keep that only if the swap frame drops AND the open-level `--idle` scenes (c, c2) stay under 3%.
- Expand first frame (window grow with `display: true` plus a full layout): hmo found `display: false` did not help. Only retry it if the new structure changes that, and measure.

Constraints:
- No new files unless needed; Swift 5 mode; no new deps.
- Spring stays `.spring(response: 0.4, dampingFraction: 0.82)`.
- The fade timings in OrchestratorExpanded.swift (fadeOut/fadeInDelay/fadeIn) are unchanged.
- The ehb pinned-top behaviour holds (`--transition` must stay OK).

Commit each kept fix: `perf(quick-jym): ...`, explicit paths.
  </action>
  <verify>
    <automated>OPT=-O SNAP_BUILD=/tmp/jym-snap-build DD=/tmp/jym-dd boringNotch/Orchestrator/Snapshots/run.sh --frames > /tmp/jym-fix2.txt 2>&1; grep -E "^together|^summary|^OK|^FAIL" /tmp/jym-fix2.txt; SNAP_BUILD=/tmp/jym-snap-build DD=/tmp/jym-dd boringNotch/Orchestrator/Snapshots/run.sh --transition > /tmp/jym-transition-2.txt 2>&1; tail -5 /tmp/jym-transition-2.txt</automated>
  </verify>
  <done>Expand, collapse and close pass the together check (maxGap within 0.08, no stuck frames) in 3 -O runs. `--transition` reports the top edge pinned and no intermediate-layout frames. Expand/collapse swap frames are no worse than the hmo final numbers. Every rejected attempt was reverted and is listed with its numbers.</done>
</task>

<task type="auto">
  <name>Task 3: Keep the Orchestrator tab built while closed (hooks and idle intact), all gates, rebuilds, summary</name>
  <files>boringNotch/ContentView.swift, boringNotch/Orchestrator/OrchestratorView.swift, boringNotch/Orchestrator/OrchestratorExpanded.swift, boringNotch/Orchestrator/OrchestratorChat.swift, boringNotch/Orchestrator/OrchestratorStatusCapsule.swift, boringNotch/Orchestrator/OrchestratorPromptCard.swift, boringNotch/Orchestrator/Snapshots/SnapFrames.swift, boringNotch/Orchestrator/Snapshots/SnapIdle.swift, boringNotch/Orchestrator/Snapshots/Snap.swift</files>
  <action>
This is hmo option (a), the user's choice.

1. Keep the tab built (ContentView.swift, ~line 350).
   - Keep the tab-body VStack in the tree when `vm.notchState == .open || coordinator.currentView == .orchestrator`. Home/Shelf keep the exact upstream `if open` insertion and the scale+fade transition.
   - The node must keep its structural identity between open and closed. Do not move it into an overlay, or it is rebuilt.
   - While closed:
     - It contributes zero layout. The closed notch shape must be pixel-identical: same width and height, wings centred.
     - The VStack's default spacing must not add a gap. Use `spacing: closed && orchestratorMounted ? 0 : nil` or equivalent; nil keeps upstream's default spacing when open.
     - The tab must not take the 640 proposal width. Give the wrapper a zero frame, clipped; the content inside keeps its last open-level `held` size so nothing re-lays out.
     - `opacity 0`, `allowsHitTesting(false)`, and `accessibilityHidden(true)`.
   - Fade: since the node is no longer inserted, drive `.opacity(open ? 1 : 0)` with `.animation(.smooth(duration: 0.35), value: vm.notchState)`. That is the same fade as today's transition.
   - OrchestratorExpanded.swift: ignore slot changes while closed (`guard vm.notchState == .open`), so `held` never follows the zero frame and never springs on close/open.
   - Mirror this structure in FramesRoot, NotchReplica.core/LiveRoot (where they model open/closed) and IdleRoot.

2. Hooks (OrchestratorView.swift).
   - Move the open/close bodies from `onAppear`/`onDisappear` to `.onChange(of: vm.notchState == .open, initial: true)`. Open: `expand.tabOpened`. Close: `expand.tabClosed`, notes flush, menus off, `runLog.close()`, escMonitor removed, restoreLevel nil, `expand.reset()`, `OrchestratorManager.shared.endTyping()`.
   - Keep `onDisappear` doing the same, for tab switches (Home/Shelf), which still remove the view.
   - Subview hooks that only ran on remove now need the close signal too. Use one source: they already have `vm` as EnvironmentObject, so add `onChange(of: vm.notchState == .open)` next to their existing onDisappear/onAppear, sharing the same body:
     - chat `stopTyping(); removeKeyMonitor()` on close
     - composer/notes/PromptContext: re-assert their fit on reopen, because `reset()` cleared every fit on close and their heights did not change, so `onChange(height)` will not fire
     - prompt card: `ctl.disappeared()` on close, `appeared()` on reopen, keeping the mount count balanced
     - `expand.register` on reopen
   - List every hook you changed in the summary.
   - That touches OrchestratorChat.swift, OrchestratorStatusCapsule.swift and OrchestratorPromptCard.swift. Each is a one-line onChange added beside the existing hook; add them to the commit's explicit paths.

3. Idle (SnapIdle.swift).
   - Add closed scenes hosting FramesRoot (the mirror with the tab kept built), not ClosedReplica:
     - `a5-closed-tab-built-rich`: transcript blocks plus status ticking every second, same feed as f
     - `a6-closed-tab-built-same`
   - Limit 3% (the existing closed limit). Do not raise it.
   - If a5 is over, stop the hidden tab re-rendering while closed. The `ModelSlice` signals (OrchestratorChat.swift:212) can drop changes while the tab is hidden and send one `objectWillChange` on reopen. The transcript-store observation in the chat view needs the same treatment.
   - Add a gate: close then reopen with a 3-line composer draft. Afterwards `monitorsActive` is false while closed, `sessions == 0`, level `.open`, and on reopen the notch height equals open + composer fit.

4. Gates, in your own dirs (`SNAP_BUILD=/tmp/jym-snap-build DD=/tmp/jym-dd`):
   - `OPT=-O --frames` x3 (files /tmp/jym-final-{1,2,3}.txt) and -Onone x1
   - `--idle` and `OPT=-O --idle`
   - `--transition`
   - `--hittest`
   - `--closed` (view closed-*.png: the closed shape is unchanged)
   - plain `run.sh`
   - the swiftc unit harness used by hmo/ev9

   The 20 ms interval gate and the together gate stay as written. If either is still unmet, report plainly which frames and why; do not loosen it.

5. Builds: the Release `clean build` and the Debug build from <facts>. Both must print `** BUILD SUCCEEDED **`. `codesign -dv` on `/tmp/notch-rel/Build/Products/Release/Boring Notch.app` shows ad-hoc and no `runtime` flag; the build log's swiftc line contains `-D ORCH_NO_SPARKLE`. Do not launch either app, and do not quit or touch the user's running notch. Never move the real cursor.

6. Cleanup and commits:
   - No `graft/` folder or `.ignore` left in the worktree or committed (`git status --porcelain` shows neither).
   - No PROBE/EXPERIMENT lines left.
   - Commit code per change with explicit paths (`perf(quick-jym): keep the Orchestrator tab built while closed`, `test(quick-jym): closed tab-built idle scenes and reopen gate`).
   - Do NOT commit PLAN/SUMMARY/STATE. Stay on the current branch; never push.

7. Write 261015-jym-SUMMARY.md: before/after table (intervals: max/p95/over20 per transition, together maxGap/stuck), the cause with evidence, fixes kept (commits), rejected experiments, hooks moved, idle numbers for a5/a6 and the existing scenes, unmet items stated plainly, UAT steps for the Release app.
  </action>
  <verify>
    <automated>OPT=-O SNAP_BUILD=/tmp/jym-snap-build DD=/tmp/jym-dd boringNotch/Orchestrator/Snapshots/run.sh --idle > /tmp/jym-idle-O.txt 2>&1; tail -3 /tmp/jym-idle-O.txt; grep -E "^together|^summary|^OK|^FAIL" /tmp/jym-final-1.txt; grep -c "BUILD SUCCEEDED" /tmp/notch-rel-build.log /tmp/notch-dd-build.log; codesign -dv "/tmp/notch-rel/Build/Products/Release/Boring Notch.app" 2>&1 | grep -E "flags|Signature"; git status --porcelain | grep -E "graft|\.ignore" ; true</automated>
  </verify>
  <done>
- The open first frame is no longer the tab build. Its interval drops well below hmo's 80-150 ms; give the numbers.
- Together gate OK for expand/collapse/close.
- `--idle` (-Onone and -O) prints `OK: idle`, including a5/a6 under 3% and the reopen gate.
- `--transition`, `--hittest`, `--closed` and `run.sh` are OK, and the closed shape and wings are unchanged.
- Both builds succeeded; Release has no hardened runtime and is ad-hoc signed.
- No graft/ or .ignore anywhere; nothing pushed; branch unchanged.
- SUMMARY written with before/after, and anything unmet reported plainly.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| none new | UI/layout and harness changes only. No new network, process or file I/O paths in the app. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-jym-01 | Information disclosure | Hidden kept-mounted tab while closed | mitigate | opacity 0, allowsHitTesting(false), accessibilityHidden(true), zero frame clipped: the transcript is never drawn or hit-testable while closed |
| T-jym-02 | Denial of service (CPU) | Hidden tab re-rendering on SSE ticks | mitigate | new closed idle scenes a5/a6 gated at 3%; signals gated while hidden if needed |
| T-jym-03 | Elevation | Release build without hardened runtime | accept | local, unsigned or ad-hoc personal build at the user's request; the shipped project settings are unchanged (command-line override only) |
</threat_model>

<verification>
- `OPT=-O run.sh --frames`: together OK for expand/collapse/close. Interval numbers compared with the hmo final numbers; an unmet 20 ms gate is reported plainly.
- `--idle` (both opts), `--transition`, `--hittest`, `--closed`, `run.sh`, and the unit harness are all OK.
- Release `clean build` (ENABLE_HARDENED_RUNTIME=NO, ad-hoc, ORCH_NO_SPARKLE) and the Debug build both succeeded. Neither app was launched.
</verification>

<success_criteria>
- Expand/collapse/close are one motion by the per-frame together check (shape, and content if that was the cause).
- The Orchestrator tab is kept built while closed. Closed idle CPU is within the gates, and every open/close hook still runs.
- Music, Home and Shelf are unchanged, and the top stays pinned with the fade intact.
- Before/after numbers are in the SUMMARY; unmet gates are reported, not loosened.
</success_criteria>

<output>
Create `.planning/quick/261015-jym-one-motion-expand-and-keep-tab-built/261015-jym-SUMMARY.md` when done (not committed by the executor).
</output>
