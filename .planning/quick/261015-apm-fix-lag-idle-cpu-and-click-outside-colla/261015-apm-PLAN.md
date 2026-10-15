---
phase: quick-261015-apm
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - boringNotch/Orchestrator/Snapshots/SnapIdle.swift
  - boringNotch/Orchestrator/Snapshots/Snap.swift
  - boringNotch/Orchestrator/Snapshots/run.sh
  - boringNotch/Orchestrator/Snapshots/Stubs.swift
  - boringNotch/Orchestrator/*.swift (only the files the bisect points at; expected among OrchestratorExpanded.swift, OrchestratorView.swift, OrchestratorRunsBoard.swift, OrchestratorWings.swift, OrchestratorManager.swift, OrchestratorExpand.swift, OrchestratorChat.swift)
autonomous: true
requirements: [quick-261015-apm]

must_haves:
  truths:
    - "Closed notch with a running run (working wing + elapsed) idles at low CPU (harness --idle < 3%; per-frame root render only while something visibly animates)"
    - "Open notch on the Orchestrator tab, idle, with a running run: harness --idle < 3%"
    - "Repeated identical SSE/state payloads do not re-publish manager/store/wings state (no ContentView.body re-evaluation for unchanged data)"
    - "Click outside the notch closes it at open level and at expanded level, with the run-log overlay never opened and after open+close"
    - "Fade on level change, run-log overlay (cards + rail dots, Esc/X/backdrop), blue activity line and wings still work"
    - "Fresh Debug build exists at /tmp/notch-dd/Build/Products/Debug"
  artifacts:
    - path: "boringNotch/Orchestrator/Snapshots/SnapIdle.swift"
      provides: "run.sh --idle: on-screen near-invisible root, CPU % over an idle window per scene, plus the outside-click/close-gate checks"
      contains: "static func idle"
    - path: "/tmp/notch-dd/Build/Products/Debug/Boring Notch.app"
      provides: "fresh Debug build"
  key_links:
    - from: "Snap.swift main()"
      to: "SnapIdle.idle()"
      via: "--idle argument dispatch"
      pattern: "--idle"
    - from: "OrchestratorExpand.collapseIfOutside / ContentView hover-exit close"
      to: "SharingStateManager.preventNotchClose"
      via: "balanced begin/endInteraction"
      pattern: "endInteraction"
---

<objective>
Find, by bisecting 618f1fb^..HEAD, what made the notch laggy (~17% idle CPU, continuous root re-render) and stopped click-outside from closing it; fix the root causes; keep the x18 features (fade, run log overlay, activity line) and the wings working.

Purpose: the notch must be smooth and close on outside clicks again; music must not regress.
Output: harness --idle mode (CPU + outside-click checks), root-cause fix commit(s), fresh Debug build in /tmp/notch-dd.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/quick/261014-x18-expand-gap-and-fade-run-log-viewer-activ/261014-x18-01-SUMMARY.md
@.planning/quick/261014-x18-expand-gap-and-fade-run-log-viewer-activ/261014-x18-02-SUMMARY.md
@.planning/phases/09-phase-b-approvals-closed-notch-approval-drop-down-global-sho/09-03-SUMMARY.md
@.planning/quick/261014-q90-live-activity-wings (SUMMARY: wings, spinner/glow)
@.planning/quick/261014-tmq-live-status-scroll-segment-selection-too (SUMMARY: shimmer/pulse TimelineView)
@boringNotch/Orchestrator/Snapshots/run.sh
@boringNotch/Orchestrator/Snapshots/Snap.swift
@boringNotch/Orchestrator/Snapshots/SnapClosed.swift
@boringNotch/Orchestrator/Snapshots/Stubs.swift

<evidence>
User's running Debug build (pid 33500, built at ~70ecc08, notch closed, this run active so the working wing shows), sampled read-only by the orchestrator:
- `ps -o %cpu` 16.7-17.5% steady. Full sample: /tmp/notch-sample.txt; main thread only: /tmp/notch-main.txt (read them; do not re-sample unless needed, read-only `sample 33500 5` is allowed).
- Main thread ~20% busy: CA::Transaction::flush_as_runloop_observer -> NSDisplayCycleFlush -> NSWindow layoutIfNeeded -> NSHostingView.layout() -> +[NSAnimationContext runAnimationGroup:] -> ViewGraphRootValueUpdater.render (~165-180 samples / 5s), with TimelineView<>.UpdateFilter.updateValue and FluidSpringAnimation.animate in hot stacks: something animates at display rate while idle and costs a full root render every frame.
- Per SSE event: OrchestratorManager.runStream closure -> applyChat -> OrchestratorTranscriptStore.applyScreen -> parseIdleStatus/chatTail, detectPrompt/scanPrompt, parseLiveStatus, OrchestratorRun.init(from:) decoding, OrchestratorWingsModel.recompute, OrchestratorApprovalCenter.approval.setter, and ContentView.body / OrchestratorClosedIndicators.body / OrchestratorWingsView.body re-evaluated: the whole root re-renders on every stream tick.
</evidence>

<suspects>
Not conclusions; the bisect decides.
- Display-rate animations always mounted: OrchestratorWings.swift WingSpinner (`.linear(duration: 8).repeatForever` rotation) and WingGlowDot (`repeatForever` shadow radius); OrchestratorChat.swift:966 `TimelineView(.animation(minimumInterval: 1/30))` shimmer and :990 `repeatForever` pulse (check whether the Orchestrator tab stays mounted while closed); NotchHomeView TimelineViews (upstream, music: do not change behaviour). Under ContentView's root `.compositingGroup()`/`.shadow`, each animated frame re-renders the whole root.
- ceccbde fade (OrchestratorExpandedView): `.onChange(of: expand.level(for: vm))` -> levelChanged() withAnimation on contentOpacity + Task; `shown` @State lagging the live level; `.onAppear { shown = ... }` on remount. Check it cannot re-trigger itself or leave an animation running.
- 247bca8 overlay (OrchestratorView): `@ObservedObject runLog` added to OrchestratorView (every runLog publish re-renders the tab); escMonitor local keyDown monitor; `.allowsHitTesting(... && runLog.runID == nil)`; backdrop `Color.clear.contentShape`; logChanged grows to expanded via setLevel (begins a SharingStateManager interaction in grow) and restores on close; onDisappear clears restoreLevel without collapsing. OrchestratorRunLog.poll 2s loop.
- 6bec3e8 activity line: `RunActivity.doing` changes every SSE tick -> `runs` array differs every tick -> manager re-publishes runs -> wings recompute + every observer body re-evaluates, even when nothing visible changed (closed notch shows no activity line).
- Close path: at open level the notch closes on hover-exit (ContentView.handleHover -> vm.close() unless SharingStateManager.preventNotchClose); at expanded/terminal level OrchestratorExpand's global/local mouseDown monitors -> collapseIfOutside -> collapse + vm.close(). A leaked beginInteraction (grow without finish, beginTyping without endTyping) or monitors removed while still expanded, or a window that never shrinks (09-03 syncWindow 650ms shrink re-reading target), would each break outside-click closing.
</suspects>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Idle/outside-click harness mode and bisect 618f1fb^..HEAD</name>
  <files>boringNotch/Orchestrator/Snapshots/SnapIdle.swift, boringNotch/Orchestrator/Snapshots/Snap.swift, boringNotch/Orchestrator/Snapshots/run.sh, boringNotch/Orchestrator/Snapshots/Stubs.swift</files>
  <action>
Harness (new file SnapIdle.swift as `extension Snap { static func idle() async }`, one dispatch line in Snap.swift main: `--idle`, one usage line in run.sh's header; Stubs.swift only if a stub needs a counter):
- Build the root the way gapPass/runLogPass already do (NotchReplica core + `.padding(.bottom, 8).notchRootFrame(notchSize:).compositingGroup()`, plus OrchestratorClosedIndicators and OrchestratorWingsView in the closed scene, mirroring SnapClosed's closed root). Host it in an on-screen window at alphaValue 0.01, ignoresMouseEvents (the livePass technique from x18-01, so springs/display link actually tick). Use only APIs that exist at c0ec48b (618f1fb^) so the same file can be dropped into older worktrees.
- Scenes, each idled ~8s after a 1s settle: (a) closed, running run + working chat (SnapClosed's `working` fixture + a running run), (b) closed, no runs, chat idle, (c) open on the Orchestrator tab at level .open, running run, (d) same at .expanded. While idling, keep feeding `OrchestratorManager.snapshotApply` the same payload once a second (simulates SSE ticks with unchanged data) and, in a variant of (a), with only `activity.doing` changing each tick.
- Report per scene: process CPU % over the window from `getrusage(RUSAGE_SELF)` user+sys delta / wall time; print the harness pid at start so the executor can `sample <pid> 3` it from bash when a scene is hot.
- Outside-click/close-gate checks (snapshot-only hook `#if ORCH_SNAPSHOT` in OrchestratorExpand if needed to call collapseIfOutside with a given point): register the harness window via `syncWindow(vm:window:)`; for (1) open level, overlay never opened, (2) grow to expanded then outside point, (3) open run log at open level (OrchestratorRunLog.shared.open) then close it, then outside point, (4) open log, then notch closes (OrchestratorExpand.reset + onDisappear path) then reopen and outside point: assert the interaction count is back to 0 (`SharingStateManager.shared.preventNotchClose == false`, add a counter to the stub if it has none), the expand monitors are installed exactly while expanded, the level ends .open, and after 700ms the window frame equals `panelSize(notch:base:openHeight:)` for the current notch size. Print `OK: idle` / `FAIL: ...` and exit non-zero on failure (CPU threshold: < 3% per scene, except report-only on the bisect worktrees).

Bisect (never checkout/switch in this worktree): build Defaults once with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild ... -derivedDataPath /tmp/notch-bisect-dd build` (not /tmp/notch-dd). For each of c0ec48b (618f1fb^), 618f1fb, ceccbde, 6bec3e8, 247bca8, 70ecc08: `git worktree add --detach /tmp/notch-bisect-<sha> <sha>`, copy SnapIdle.swift in, insert the `--idle` dispatch line with sed, run `DD=/tmp/notch-bisect-dd /tmp/notch-bisect-<sha>/boringNotch/Orchestrator/Snapshots/run.sh --idle > /tmp/notch-bisect-<sha>.log 2>&1` (redirect to a file, never pipe). Record CPU per scene and close-gate results per commit in a table for the SUMMARY. If every commit is equally bad, the cause predates the batch: extend the bisect to 3121105^ (before 09-03 syncWindow) and the q90/s3q wings commits, and say so. Use `sample` on the harness pid for the hot scene to name the view that animates. Remove every temp worktree afterwards (`git worktree remove --force /tmp/notch-bisect-<sha>`, then `git worktree prune`); leave no background processes. Commit the harness alone: `test(quick-apm): idle CPU and outside-click harness mode`.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && DD=/tmp/notch-bisect-dd boringNotch/Orchestrator/Snapshots/run.sh --idle > /tmp/notch-idle-head.log 2>&1; grep -E "cpu|OK|FAIL" /tmp/notch-idle-head.log; git worktree list | grep -c notch-bisect | grep -qx 0</automated>
  </verify>
  <done>--idle prints per-scene CPU and close-gate results at HEAD (expected FAIL before the fix); a per-commit table names the commit(s) introducing the CPU regression and the click-outside regression, with the hot view from `sample`; no /tmp/notch-bisect-* worktrees remain; harness committed.</done>
</task>

<task type="auto">
  <name>Task 2: Fix the root causes at their source</name>
  <files>Only the Orchestrator files the bisect implicates (expected among OrchestratorExpanded.swift, OrchestratorView.swift, OrchestratorRunsBoard.swift, OrchestratorWings.swift, OrchestratorManager.swift, OrchestratorExpand.swift, OrchestratorChat.swift)</files>
  <action>
Fix what the bisect found, one atomic commit per cause (`fix(quick-apm): ...`). No symptom patches (no lowering poll rates, no removing the fade/overlay/activity line/wings, no forced vm.close calls). Guidance per likely cause, apply only what the evidence supports:
- Display-rate animation while idle: an animation must run only while its view is actually visible and its state calls for it (e.g. spinner only while the wing is shown as working; shimmer/pulse not mounted while the notch is closed or the tab hidden). If a visible spinner is the only animator and still forces a full root render per frame, isolate it so the frame update does not invalidate the root (e.g. drive it from a low-rate `TimelineView(.periodic)` or keep the rotation as a render-only effect outside layout-affecting modifiers); state in the SUMMARY what the per-frame cost is with the wing visible.
- Per-SSE-tick re-render: publish only on change. Guard each `@Published` write in OrchestratorManager.applyChat / applyState, OrchestratorTranscriptStore.applyScreen, OrchestratorWingsModel.recompute, OrchestratorApprovalCenter with an equality check (the codebase already does `if l != lines { lines = l }` in OrchestratorRunLog.poll; reuse that idiom). Skip re-parsing the screen (detectPrompt, parseIdleStatus, chatTail, parseLiveStatus) when `screen` is unchanged. If `runs` changes only in `activity`, that publish is real data for the board/overlay; keep it, but make sure closed-notch views (ContentView, wings, closed indicators) do not depend on fields that don't change what they show (e.g. wings recompute output equal -> no publish).
- Fade (ceccbde): if implicated, make levelChanged fire only on a real level change and let `shown`/`contentOpacity` settle; no animation left running after ~300ms.
- Overlay (247bca8): if implicated, keep `@ObservedObject runLog` out of views that don't need it (observe only `runID != nil` where the hosting decision is made), ensure escMonitor/backdrop are removed on close and on disappear, and that a log opened at open level is fully collapsed (finish -> endInteraction) on every close path including notch close.
- Click-outside: whichever of interaction-count leak, monitors not installed/removed, or window not shrinking the harness shows; fix it in the shared path (OrchestratorExpand.finish/grow/syncWindow or OrchestratorManager begin/endTyping) so every caller is covered.
Keep ContentView/boringNotchApp edits to zero unless the cause is there (then one line). Do not touch music code.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261014083623-80d8 && DD=/tmp/notch-bisect-dd boringNotch/Orchestrator/Snapshots/run.sh --idle > /tmp/notch-idle-fixed.log 2>&1 && grep -q "OK: idle" /tmp/notch-idle-fixed.log && ! grep -q FAIL /tmp/notch-idle-fixed.log</automated>
  </verify>
  <done>--idle passes at HEAD: every scene < 3% CPU, close-gate checks OK (interaction count 0, monitors match level, window shrinks to the shape) for overlay-never-opened and after open+close; each cause fixed in its own commit.</done>
</task>

<task type="auto">
  <name>Task 3: Regression passes and fresh Debug build</name>
  <files>(no source changes expected; harness only if a pass needs a fixture update caused by Task 2)</files>
  <action>
Run, each redirected to a file (never piped): run.sh (normal, composer 12 in all scenes), --hittest (draft survives, gap 12, run log open/close via card, dot, X, Esc), --transition (no intermediate-layout frames, top edge pinned), --closed (wings + music indicator, 0 failures), --idle; the swiftc unit tests the earlier summaries use (boringNotch/Orchestrator/Tests/main.swift, incl. QuickX18Tests). View PNGs 06, 10, 53-57, closed-* and transition-live-grow-280 to confirm overlay, activity line, wings and fade still render. Then build the app fresh into /tmp/notch-dd: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/notch-dd CODE_SIGN_IDENTITY=- build > /tmp/notch-dd-build.log 2>&1` (match the scheme/flags earlier summaries used). Do not launch the app and do not touch pid 33500. Optionally `rm -rf /tmp/notch-bisect-dd` once done. Record in the SUMMARY: bisect table, root cause(s), before/after CPU per scene, close-gate results, and that UAT is needed in the real app (idle CPU in Activity Monitor with a running run; click outside at open and expanded level; expand/collapse smoothness; music controls).
  </action>
  <verify>
    <automated>grep -q "BUILD SUCCEEDED" /tmp/notch-dd-build.log && test -d "/tmp/notch-dd/Build/Products/Debug/Boring Notch.app" && grep -q "OK: idle" /tmp/notch-idle-fixed.log</automated>
  </verify>
  <done>All harness passes and unit tests green; BUILD SUCCEEDED with the app at /tmp/notch-dd/Build/Products/Debug; no temp worktrees or background processes left; nothing pushed; branch unchanged.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| notch app -> 127.0.0.1:4777 | local serve API (GET /api/state, /api/chat, /api/log, SSE) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-apm-01 | Denial of service | SSE handling in OrchestratorManager | mitigate | equality guards so unchanged payloads cost no publish/render (Task 2) |
| T-apm-02 | Tampering | harness / bisect | accept | harness has no POST path (snapshot build); bisect worktrees are temp, detached, removed |
</threat_model>

<verification>
- --idle: all scenes < 3% CPU, close-gate OK.
- normal, --hittest, --transition, --closed pass; unit tests OK.
- /tmp/notch-dd/Build/Products/Debug/Boring Notch.app freshly built.
- `git worktree list` shows no /tmp/notch-bisect-*; `git branch --show-current` = orch/261014083623-80d8; no push.
</verification>

<success_criteria>
Idle CPU low (~<3%) with a running run, smooth expand/collapse, click outside collapses (overlay never opened and after open+close), fade/overlay/activity line/wings intact, fresh Debug build at /tmp/notch-dd/Build/Products/Debug.
</success_criteria>

<output>
Create `.planning/quick/261015-apm-fix-lag-idle-cpu-and-click-outside-colla/261015-apm-SUMMARY.md` when done (bisect table, causes, before/after numbers, human UAT items).
</output>
