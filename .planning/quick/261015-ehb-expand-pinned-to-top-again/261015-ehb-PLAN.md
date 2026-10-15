---
phase: quick-261015-ehb
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - boringNotch/Orchestrator/Snapshots/Snap.swift
  - boringNotch/Orchestrator/Snapshots/SnapIdle.swift
  - boringNotch/Orchestrator/OrchestratorExpand.swift
  - boringNotch/boringNotchApp.swift
  - boringNotch/ContentView.swift
autonomous: true
requirements: [QUICK-261015-ehb]

must_haves:
  truths:
    - "Expanding the Orchestrator notch keeps its top edge at the screen top in every frame and grows downward only"
    - "Collapsing keeps the top edge at the screen top in every frame and shrinks upward only"
    - "The x18 fade (content out, single layout at the final level, fade in) still happens"
    - "After a collapse the panel frame shrinks back to panelSize (click-outside below the notch still reaches other apps)"
    - "Music / stock open-close looks the same as before"
  artifacts:
    - path: "boringNotch/Orchestrator/Snapshots/Snap.swift"
      provides: "--transition live pass hosted like the real panel, screen-space top/bottom assertions"
      contains: "screen top"
    - path: "/tmp/notch-dd/Build/Products/Debug/Boring Notch.app"
      provides: "fresh Debug build with the fix"
  key_links:
    - from: "boringNotch/Orchestrator/Snapshots/Snap.swift livePass"
      to: "boringNotch/boringNotchApp.swift createBoringNotchWindow"
      via: "same panel style mask, sizingOptions = [], root chain as ContentView (panelHost helper)"
      pattern: "panelHost|sizingOptions"
    - from: "OrchestratorExpand.syncWindow"
      to: "pinnedFrame(current:newSize:)"
      via: "the only setFrame path, top pinned"
      pattern: "pinnedFrame"
---

<objective>
The expanded notch fills in from the middle of the screen again instead of staying pinned to the top edge and growing down. Find the real cause with a harness that models the real panel and fails on the bug, then fix it at its source with the smallest hook. Keep the x18 fade and keep the apm click-outside fix (window shrinks back to panelSize, no min-size clamp).

Purpose: the current `--transition` prints "OK: top edge pinned" while the user sees the bug, so the check does not model the app. Make the check honest first, then fix.
Output: honest `--transition` live pass, root-cause fix, fresh Debug build at /tmp/notch-dd/Build/Products/Debug.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/quick/261015-apm-fix-lag-idle-cpu-and-click-outside-colla/261015-apm-SUMMARY.md
@.planning/quick/261014-x18-expand-gap-and-fade-run-log-viewer-activ/261014-x18-01-SUMMARY.md
@.planning/quick/261014-s3q-wings-fit-smooth-bigger-expand-notes-dra/261014-s3q-02-SUMMARY.md
(also the 09-03 SUMMARY under .planning/phases/09-*/)
@boringNotch/Orchestrator/OrchestratorExpand.swift
@boringNotch/Orchestrator/Snapshots/Snap.swift
@boringNotch/Orchestrator/Snapshots/SnapIdle.swift

History (read with `git show`): cdaa3ed (original fix: notchRootFrame top-aligned fill so NSHostingView never resizes the window from the content), f0e8bd2 (pinnedFrame + notchRootFrame(notchSize:)), 3121105 (syncWindow = only setFrame path: grow at once, shrink after 650ms), ceccbde (x18 fade: lagging `shown` level + fadeGen in OrchestratorExpandedView), fdb2f65 (`hosting.sizingOptions = []` on the real panel, boringNotchApp.swift createBoringNotchWindow).

<interfaces>
Real panel (boringNotchApp.swift ~235-255): BoringNotchSkyLightWindow(contentRect: windowSize rect, styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]); BoringNotchWindow (NSPanel) sets isFloatingPanel, isOpaque=false, backgroundColor=.clear, level .mainMenu+3, hasShadow=false; then `NSHostingView(rootView: ContentView().environmentObject(viewModel))`, `hosting.sizingOptions = []`, contentView = hosting. Origin y = screen.maxY - window.frame.height (line ~278).

ContentView root chain (ContentView.swift ~95-215): mainLayout (NotchLayout, paddings, .background(.black), .clipShape(currentNotchShape), shadow) -> .frame(height: vm.notchState == .open ? vm.notchSize.height : nil) -> inside ZStack(alignment: .top){ VStack } -> .padding(.bottom, 8) -> .notchRootFrame(notchSize: vm.notchSize) -> .onChange(of: vm.notchSize){ syncWindow(vm:) } -> .compositingGroup() -> .scaleEffect(anchor: .top).
The hittest root (Snap.swift hitTest ~595) and IdleRoot (SnapIdle.swift) already mirror this chain.

OrchestratorExpand: animate(vm,to:) = withAnimation(.spring(response: 0.4, dampingFraction: 0.82)){ vm.notchSize = target } + syncWindow(vm:). syncWindow(vm:window:now:) grows the frame immediately via pinnedFrame, shrinks after 650ms. setLevel(_:vm:window:). notchRootFrame(notchSize:) extension at the bottom of the file.

OrchestratorPure: pinnedFrame(current:newSize:) keeps maxY + midX; panelSize(notch:base:openHeight:).

SnapIdle.swift: `private func panelHost(_:)` builds NSHostingView with sizingOptions = [] unless env IDLE_DEFAULT_SIZING is set; `KeyablePanel` (Snap.swift ~955) is the harness NSPanel.

Current livePass (Snap.swift ~444): plain NSWindow, plain NSHostingView (DEFAULT sizingOptions), LiveRoot = NotchReplica.core + notchRootFrame (no ZStack/padding/compositingGroup/scaleEffect, no onChange->syncWindow), measures only in host-local coordinates at 10 coarse times. It cannot see the window top moving in screen space, nor the shape's top relative to the screen.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Make --transition model the real panel, fail on the bug, and identify the cause</name>
  <files>boringNotch/Orchestrator/Snapshots/Snap.swift, boringNotch/Orchestrator/Snapshots/SnapIdle.swift</files>
  <action>
Rework `livePass` (keep the existing fade classification and its OK/FAIL line) so it hosts the notch exactly like createBoringNotchWindow:
- Window: KeyablePanel (or an NSPanel subclass) with styleMask [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow], isOpaque=false, backgroundColor=.clear, hasShadow=false, alphaValue 0.01, ignoresMouseEvents, on screen at origin y = screen.maxY - windowSize.height (same as the real app; keep it on screen so the display link ticks).
- Host: reuse SnapIdle's `panelHost` (drop `private` so Snap.swift can call it; sizingOptions = [] unless an env override). Add one env switch, e.g. TRANSITION_DEFAULT_SIZING=1, honoured by panelHost too (or reuse IDLE_DEFAULT_SIZING), so the fdb2f65 suspect can be A/B tested in one binary without a worktree.
- Root: the ContentView chain (ZStack(alignment: .top){VStack{core with .frame(height: vm.notchSize.height)}} -> .padding(.bottom, 8) -> .notchRootFrame -> .onChange(of: vm.notchSize){ OrchestratorExpand.shared.syncWindow(vm: vm) } -> .compositingGroup() -> .scaleEffect(x:1,y:1,anchor:.top)), like the hittest root. Register the window with OrchestratorExpand via setLevel(window:) as now, so syncWindow drives the real frame.
- Sampling: in addition to the existing 10 captures, a cheap dense pass (every ~16ms for 0..800ms of grow and of collapse) that reads only the centre column: shapeTopScreen = window.frame.maxY - (first opaque black row from the top of the host bitmap, in points) and shapeBottomScreen likewise (last opaque black row), plus windowTop = window.frame.maxY and host.frame vs window.contentView bounds/contentLayoutRect (catches a hosting view that does not fill the window or is offset). Keep each dense sample to one column so it does not starve the spring.
- Assertions (hard FAIL lines): windowTop == screen.maxY ±0.5 in every sample; shapeTopScreen == screen.maxY ±0.5 in every sample; during grow shapeBottomScreen is non-increasing (only moves down, allow 0.5pt and spring overshoot tolerance: monotonic until the first sample where height reaches the final height), during collapse non-decreasing likewise. Print a compact per-sample line (t, window frame, host frame, shapeTop, shapeBottom, vm.notchSize.height) and the first offending sample.
- Also keep the existing static grow/collapse/stock-open table, but stop it claiming the app is OK: rename its result line to make clear it is the root-frame-only check.

Then diagnose, do not guess. Run `run.sh --transition > /tmp/ehb-head.log` at HEAD (needs /tmp/notch-dd build products; if Defaults.o is missing run one Debug build first). Then:
1. A/B the sizing suspect in the same binary: TRANSITION_DEFAULT_SIZING=1.
2. If the HEAD harness still passes, the harness is still missing something the app does; keep closing the gap before touching app code: check the real ContentView hooks the replica skips (vm.notchState == .open frame, gestureScale, chin, `.animation` modifiers), host.layerContentsPlacement / layerContentsRedrawPolicy (AppKit default .scaleAxesIndependently stretches the stale layer when setFrame(display:true) grows the window before SwiftUI redraws), and whether syncWindow's immediate grow happens before or after SwiftUI has laid out the new frame. Each hypothesis gets a measured yes/no in the log.
3. Bisect with the new harness only if steps 1-2 do not pin it: `git worktree add --detach /tmp/notch-bisect-<sha> <sha>` for ceccbde^, ceccbde, fdb2f65^, fdb2f65; copy the new harness files in (drop lines that do not compile on older commits, as apm did with //RUNLOG), build with DD=/tmp/notch-dd (read-only use of Defaults.o) or a separate /tmp/notch-bisect-dd, record pass/fail per commit, then `git worktree remove --force` each and `git worktree prune`. Never checkout/switch in this worktree.
Record the root cause with the measured evidence (which commit, which mechanism) for the SUMMARY. Commit the harness alone: `test(quick-ehb): --transition hosts the real panel and checks the screen-space top edge`. The harness must FAIL at this commit (it reproduces the bug); say so in the commit body.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && boringNotch/Orchestrator/Snapshots/run.sh --transition > /tmp/ehb-head.log 2>&1; grep -E "^(OK|FAIL)" /tmp/ehb-head.log</automated>
  </verify>
  <done>At HEAD (before the fix) the live pass prints a FAIL naming the first sample where the shape top or window top leaves the screen top (or the bottom edge moves the wrong way). The root cause is identified with measured evidence (A/B and/or bisect table). Any bisect worktrees are removed and pruned (`git worktree list` shows only the original entries). Harness committed.</done>
</task>

<task type="auto">
  <name>Task 2: Fix the root cause at its source, rerun every harness mode, fresh Debug build</name>
  <files>boringNotch/Orchestrator/OrchestratorExpand.swift, boringNotch/boringNotchApp.swift, boringNotch/ContentView.swift</files>
  <action>
Fix exactly the mechanism Task 1 measured, in the one place every path routes through, with the smallest diff to upstream files. Candidates, pick by evidence only:
- Hosting view placement/alignment: if the hosting view or root is not top-anchored when the window is taller than the shape, fix it in `notchRootFrame` (OrchestratorExpand.swift, already used by ContentView and all harness roots) or one line next to `hosting.sizingOptions = []` in createBoringNotchWindow (e.g. `hosting.layerContentsPlacement = .top` if stale-layer stretching on immediate grow is the cause).
- sizingOptions: if sizingOptions = [] is the cause, restore only the subset that keeps the top pinned without copying the content's min size to the window (never `.minSize`; the apm assertion "window frame == panelSize and min size not above it" must keep passing).
- Window timing: if the frame change and the SwiftUI layout land in different display frames, fix the order inside `syncWindow` (it is the only setFrame path; do not add a second one).
Do not reintroduce view animation on level change and do not touch the fade logic in OrchestratorExpandedView (x18). Keep the grow-now / shrink-after-650ms behaviour of syncWindow and the shrink back to panelSize. Do not edit music or stock open/close code. Comment the fix in one or two lines saying why (mention the regression so nobody removes it again).
Then rerun everything, redirecting to files: swiftc unit harness (as in apm SUMMARY, incl. OrchestratorStream.swift); `run.sh` (normal, expect `OK: composer bottom padding`); `run.sh --hittest`; `run.sh --transition` (new live pass must print OK plus the fade OK line); `run.sh --closed`; `run.sh --idle` (outside-click gates and the window-shrink/min-size assertion must pass). View transition-live-grow-*.png and -collapse-*.png at a couple of times to confirm the shape hugs the top. Then a fresh Debug build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/notch-dd CODE_SIGN_IDENTITY=- build` (match the scheme/flags used by earlier quick tasks). Commit: `fix(quick-ehb): expand/collapse stays pinned to the screen top again` with the root cause in the body. Do not launch Boring Notch.app, do not kill processes you did not start, leave no background processes, never POST to 127.0.0.1:4777, never push.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && boringNotch/Orchestrator/Snapshots/run.sh --transition > /tmp/ehb-fix.log 2>&1; grep -E "^(OK|FAIL)" /tmp/ehb-fix.log; boringNotch/Orchestrator/Snapshots/run.sh --idle > /tmp/ehb-idle.log 2>&1; tail -3 /tmp/ehb-idle.log; ls -d "/tmp/notch-dd/Build/Products/Debug/Boring Notch.app"</automated>
  </verify>
  <done>--transition live pass: OK, top edge and window top at screen top in every dense sample through grow and collapse, bottom edge moves one way, fade OK line still OK. --idle: OK incl. outside-click gates and window frame == panelSize after collapse. Normal, --hittest, --closed and swiftc harness OK. `** BUILD SUCCEEDED **` with a fresh app at /tmp/notch-dd/Build/Products/Debug. Two commits on orch/261014083623-80d8, nothing pushed, branch unchanged.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| none new | Layout/window-frame change and a local test harness; no new input, network or process boundary |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-ehb-01 | Denial of Service | panel frame (click-outside) | mitigate | --idle asserts window frame == panelSize and min size not above it after collapse; never restore `.minSize` sizing option |
| T-ehb-02 | Tampering | orchestrator API | accept | harness uses snapshot hooks only; no POST to 127.0.0.1:4777 |
</threat_model>

<verification>
- Harness commit fails at HEAD-before-fix; fix commit makes it pass.
- All harness modes OK; fresh Debug build present.
- `git worktree list` has no /tmp/notch-bisect-* entries; `git branch --show-current` = orch/261014083623-80d8.
</verification>

<success_criteria>
A --transition snapshot shows the top edge fixed at the screen top through the whole expand and collapse, the fade intact, click-outside intact, and a fresh Debug build at /tmp/notch-dd/Build/Products/Debug.
</success_criteria>

<output>
Create `.planning/quick/261015-ehb-expand-pinned-to-top-again/261015-ehb-SUMMARY.md` with the root cause, the evidence (A/B and/or bisect table), the fix, harness results, and UAT items (watch expand/collapse on the real notch; click outside after collapse).
</output>
