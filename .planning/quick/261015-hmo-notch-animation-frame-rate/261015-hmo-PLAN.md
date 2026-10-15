---
phase: quick-261015-hmo
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - boringNotch/Orchestrator/Snapshots/SnapFrames.swift
  - boringNotch/Orchestrator/Snapshots/Snap.swift
  - boringNotch/Orchestrator/Snapshots/run.sh
  - boringNotch/Orchestrator/OrchestratorExpand.swift
  - boringNotch/Orchestrator/OrchestratorExpanded.swift
  - boringNotch/Orchestrator/OrchestratorView.swift
  - boringNotch/ContentView.swift
autonomous: true
requirements: [QUICK-261015-hmo]

must_haves:
  truths:
    - "open (closed->open), expand (open->expanded), collapse (expanded->open) and close (open->closed) each run in the -O harness with no frame interval over 20 ms"
    - "the baseline per-transition frame numbers were recorded before any fix, and every fix maps to evidence (display-link stall timestamps, signposts, sample or xctrace output)"
    - "the look stays the same: the top edge stays pinned while the notch grows down, the content fades between levels, and the springs keep their response and damping"
    - "music controls and the Home/Shelf tabs behave as before (no upstream behaviour change)"
    - "/tmp/notch-rel (Release, ORCH_NO_SPARKLE) and /tmp/notch-dd (Debug) are freshly built; neither app is launched"
  artifacts:
    - path: "boringNotch/Orchestrator/Snapshots/SnapFrames.swift"
      provides: "--frames mode: drives the four transitions in-process on a panel-hosted root, records display-link frame intervals, prints max/p95/count>20ms per transition, FAILs over the gate"
      contains: "--frames"
    - path: "boringNotch/Orchestrator/Snapshots/run.sh"
      provides: "usage line for --frames (OPT=-O)"
      contains: "--frames"
  key_links:
    - from: "boringNotch/Orchestrator/Snapshots/Snap.swift main()"
      to: "SnapFrames frames()"
      via: "CommandLine.arguments.contains(\"--frames\")"
      pattern: "--frames"
    - from: "SnapFrames transitions"
      to: "OrchestratorExpand.shared.setLevel / vm.notchState + vm.notchSize"
      via: "same calls the app uses"
      pattern: "setLevel"
---

<objective>
The notch's open, expand and both collapse animations are choppy. Make all four run at a steady display frame rate in the Release build. Measure first, then fix only what the measurement shows.

Purpose: the transitions are the one part of the notch that still feels janky.
Output: a `--frames` harness mode with a 20 ms gate, evidence-based fixes, before/after numbers, and fresh Release and Debug builds.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@./CLAUDE.md
@.planning/STATE.md
@.planning/quick/261015-ev9-expanded-responsiveness-release-build/261015-ev9-SUMMARY.md
@.planning/quick/261015-ehb-expand-pinned-to-top-again/261015-ehb-SUMMARY.md
@boringNotch/Orchestrator/Snapshots/run.sh
@boringNotch/Orchestrator/Snapshots/Stubs.swift

<interfaces>
How the harness and the animations fit together (taken from the code):

- `run.sh` compiles `boringNotch/Orchestrator/Orchestrator*.swift` plus `Snapshots/*.swift` with `-D ORCH_SNAPSHOT`, `$OPT` (set `OPT=-O` for Release-like code) and links `$DD/Build/Products/Debug/Defaults.o`. It does NOT compile ContentView.swift or BoringViewModel.swift. `Stubs.swift` provides `BoringViewModel` (`notchState`, `notchSize`, `closedNotchSize`, `close()`), `openNotchSize` 640x190, `windowSize`, `cornerRadiusInsets`, `SharingStateManager`.
- `Snap.swift`: `main()` dispatches on `--transition`, `--hittest`, `--closed`, `--idle`. `NotchReplica(vm:).core` is ContentView's mainLayout (header + `OrchestratorView()`, paddings, black, clipShape, `.frame(height: vm.notchSize.height)`). `private struct LiveRoot` (line ~436) is ContentView's root chain: `.padding(.bottom, 8).notchRootFrame(notchSize:).onChange(of: vm.notchSize) { syncWindow }.compositingGroup().scaleEffect(anchor: .top)`. `livePass` (line ~498) shows how to host it like the real panel: `KeyablePanel` with `[.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]`, `level = .mainMenu + 3`, `alphaValue = 0.01`, `ignoresMouseEvents = true`, `host.sizingOptions = []`, `orderFrontRegardless()`; an on-screen (alpha 0.01) window is needed so the display link ticks. `livePass` captures bitmaps (`cacheDisplay`) which stall the main thread for ~100 ms: the frame mode must NOT capture.
- `OrchestratorExpand.shared.setLevel(.expanded | .open, vm:, window:)` drives expand/collapse. `animate()` calls `syncWindow(vm:size:)` (grow-only `setFrame(..., display: true)`, outside the animation), then `withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { vm.notchSize = target }`, then `syncWindow(vm:)`; shrinks are deferred 650 ms then `setFrame(..., display: true)`. `syncWindow` is the only `setFrame` path. `reset()` collapses with no animation. `orchPerf` is an `OSSignposter(subsystem: "boringnotch.orch", category: "perf")` with an `expand` interval already.
- `OrchestratorExpanded.swift` line ~10: level-change fade `fadeOut = 0.08, fadeInDelay = 0.28, fadeIn = 0.15`; `contentOpacity` @State, `fadeGen`; "lay out once at the new level while invisible" happens between fade-out and fade-in (inside the spring).
- ContentView.swift (upstream, app only): `mainLayout ... .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)` with `.animation(open ? .spring(response: 0.42, dampingFraction: 0.8) : .spring(response: 0.45, dampingFraction: 1.0), value: vm.notchState)`; the notch shape gets `.shadow(color: open||hover ? .black.opacity(0.7) : .clear, radius: 6 or 4)`; the root has `.compositingGroup()` and `.scaleEffect(gestureScale, anchor: .top)`. BoringViewModel.open() sets `notchSize = OrchestratorExpand.shared.openSize(for:)` then `notchState = .open`; close() sets `notchSize` to the closed size then `notchState = .closed`. The tab body is inserted on open and removed on close.
- Build recipes (from ev9): Debug `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/notch-dd CODE_SIGN_IDENTITY=- build > /tmp/notch-dd-build.log 2>&1`. Release `... -configuration Release -derivedDataPath /tmp/notch-rel CODE_SIGN_IDENTITY=- 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) ORCH_NO_SPARKLE' build > /tmp/notch-rel-build.log 2>&1`.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: --frames harness mode and baseline</name>
  <files>boringNotch/Orchestrator/Snapshots/SnapFrames.swift, boringNotch/Orchestrator/Snapshots/Snap.swift, boringNotch/Orchestrator/Snapshots/run.sh</files>
  <action>
Add a new file `SnapFrames.swift` (an `extension` of the Snap main type, or a free `@MainActor` func), dispatched from `main()` in Snap.swift with `if CommandLine.arguments.contains("--frames") { await frames(); return }`. That is the only change to Snap.swift, apart from making `LiveRoot`/`KeyablePanel` non-private if you need to reuse them. Add one usage line to run.sh: `OPT=-O run.sh --frames -> frame intervals per transition, FAIL over 20 ms`.

What the mode does:
- Hosts the notch like `livePass`: same panel flags, level, alpha 0.01, ignoresMouseEvents, `sizingOptions = []`, on-screen. Use an empty fixture and a realistic transcript fixture (reuse an existing Snap fixture with several chat blocks, a running run, and usage) so the text layout cost is real.
- The open/close root mirrors ContentView's chain for `notchState`, because ContentView is not compiled here. Put a frames-only root in SnapFrames.swift that copies ContentView's modifiers in the same order: the tab body is shown only when `notchState == .open`; the shape is a closed-size black pill when closed; `.frame(height: open ? notchSize.height : nil)`; the shadow (0.7 black, radius 6) when open; the open/close springs keyed on `notchState` (0.42/0.8 and 0.45/1.0); then the `LiveRoot` tail (`padding(.bottom, 8)`, `notchRootFrame`, `onChange -> syncWindow`, `compositingGroup`, `scaleEffect(anchor: .top)`). Header comment: "mirror of ContentView.swift root chain; keep in sync". Drive open and close like BoringViewModel: open sets `notchSize = OrchestratorExpand.shared.openSize(for: vm)` then `notchState = .open`; close sets `notchSize = closedNotchSize` then `notchState = .closed`. Do not call `vm.close()` (the stub only counts calls).
- Sequence: close, then open, then expand (`setLevel(.expanded)`), then collapse (`setLevel(.open)`), then close. Run each transition 3 times with a 1.2 s settle between runs.
- Measurement: no bitmap captures during a transition. Record frame timestamps with a display link on the host view (`host.displayLink(target:selector:)`, macOS 14; add it to `.main` in `.common` mode) from the trigger until 900 ms after it (or until 650 ms + 200 ms for collapse/close, so the deferred shrink `setFrame` is covered). Per transition, print one line: `frames <name> n=<frames> max=<ms> p95=<ms> over20=<count> worst@<ms since trigger>`. Also list the offset of each frame over 20 ms, so a stall can be matched to a cause (trigger frame, fade-out end at ~80 ms, re-layout at the new level, fade-in at ~280 ms, deferred shrink at 650 ms). Add `orchPerf` signposts (`frame-stall` event) at each stall only in the harness, not in app code.
- A display link catches main-thread stalls, not render-server hitches. As a cross-check, try once: `xcrun xctrace record --template 'Animation Hitches' --output /tmp/hmo-hitches.trace --launch -- /tmp/notch-snap-build/snap --frames`, then `xcrun xctrace export` to read the hitch table. If the template or recording does not work, say so in the summary and rely on the display link plus `sample` of the harness process (`IDLE_SAMPLE`-style: `sample <harness pid> 3 -file /tmp/hmo-sample-<transition>.txt` while it loops one transition; FRAMES_ONLY=<name> and FRAMES_LOOP=1 env vars make this possible).
- Gate: print `OK: frames` when every transition has over20 == 0, otherwise `FAIL: frames ...` with the offenders. `FRAMES_REPORT=1` prints without failing (use it for the baseline).

Baseline: build Debug once if `/tmp/notch-dd/Build/Products/Debug/Defaults.o` is missing. Run `OPT=-O FRAMES_REPORT=1 boringNotch/Orchestrator/Snapshots/run.sh --frames > /tmp/hmo-baseline-O.txt 2>&1` and the same without OPT (`/tmp/hmo-baseline-Onone.txt`). Then capture evidence for every transition that has stalls (stall offsets, sample call trees, xctrace hitches). Write down what the evidence points to for each stall before touching app code. Do not move the cursor and do not post CGEvents. Do not launch, quit or attach to the user's running Boring Notch; `sample` only the harness process. Commit only the harness files: `test(quick-hmo): --frames transition frame-interval harness`.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261015024118-29b9 && OPT=-O FRAMES_REPORT=1 boringNotch/Orchestrator/Snapshots/run.sh --frames > /tmp/hmo-baseline-O.txt 2>&1; grep -c '^frames ' /tmp/hmo-baseline-O.txt</automated>
  </verify>
  <done>`--frames` prints 4 transitions x 3 runs of max/p95/over20 lines in -O and -Onone. The baseline files exist. Each stall has an offset and a cause backed by evidence (call tree, signpost, or hitch row). Only the harness commit was made.</done>
</task>

<task type="auto">
  <name>Task 2: Fix the measured causes</name>
  <files>boringNotch/Orchestrator/OrchestratorExpand.swift, boringNotch/Orchestrator/OrchestratorExpanded.swift, boringNotch/Orchestrator/OrchestratorView.swift, boringNotch/ContentView.swift, boringNotch/Orchestrator/Snapshots/SnapFrames.swift</files>
  <action>
Fix only causes that Task 1's evidence shows. Fix one cause at a time and re-run `OPT=-O FRAMES_REPORT=1 run.sh --frames` after each change. Keep a change only if the numbers improve, and record the numbers for each change. Revert any experiment that does not help, and list it in the summary as rejected, like ev9 did with DraftScope.

Candidates to test against the evidence, not to apply blindly:
- `setFrame(..., display: true)` in `syncWindow` forces a synchronous full redraw at the trigger and at the deferred 650 ms shrink. Try `display: false`, or do the grow resize in a frame before the spring starts. The window grow must stay outside the spring transaction (ehb root cause), and the top must stay pinned.
- The new level's full layout (transcript text, rail) runs inside one frame in the middle of the spring, or the tab body is built on the open trigger frame. Options: do the expensive layout while the content is invisible but before the spring's visible motion; avoid re-measuring text whose width did not change (the ev9 fit cache is keyed by width); keep the expanded subtree alive instead of rebuilding it, if the sample shows rebuild cost.
- The shadow (radius 6) on a shape whose size changes every frame, under `.compositingGroup()`, re-rasterises an offscreen pass each frame. Options: `.drawingGroup()` on the shape only, or a cheaper shadow path with the same look. This is in ContentView.swift. Keep that edit to the smallest hook, change the mirror root in SnapFrames.swift the same way, and keep the closed/open/hover shadow look the same.
- Fade and spring overlap that causes two layout passes. Retime only if needed, keeping fadeOut/fadeIn feel (same durations; you may move the delay). Do not change the spring response or damping values.

Rules: no new dependencies, Swift 5 mode, no process spawning. Keep upstream ContentView/boringNotchApp edits minimal and Orchestrator-specific where possible; music and the Home/Shelf tabs must behave the same. Never move the cursor. Commit each kept fix on its own: `perf(quick-hmo): <cause>`. Never stage graft/ or any .ignore file; use `git add <explicit paths>`.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261015024118-29b9 && OPT=-O boringNotch/Orchestrator/Snapshots/run.sh --frames > /tmp/hmo-after-O.txt 2>&1; grep -E '^(OK|FAIL): frames' /tmp/hmo-after-O.txt && boringNotch/Orchestrator/Snapshots/run.sh --transition > /tmp/hmo-transition.txt 2>&1; grep -E '^(OK|FAIL)' /tmp/hmo-transition.txt</automated>
  </verify>
  <done>`OPT=-O run.sh --frames` prints `OK: frames` (no frame over 20 ms in any transition). `--transition` still prints the top-edge-pinned and no-intermediate-layout OKs. Each kept fix is its own commit and has before/after numbers.</done>
</task>

<task type="auto">
  <name>Task 3: Regression gates and fresh builds</name>
  <files>boringNotch/Orchestrator/Snapshots/SnapFrames.swift</files>
  <action>
Run the full suite and fix any regression:
- the swiftc unit harness (Orchestrator pure files + `Tests/*.swift`, as in ev9);
- `run.sh` (composer padding scenes), `--hittest`, `--transition`, `--closed` (wings, music indicator);
- `--idle` and `OPT=-O --idle` (latency and CPU gates);
- `--frames` in both -O and -Onone, 3 runs of -O to check it is stable.

The gate is for -O. If -Onone stays over 20 ms, report it and do not gate it. If the gate flakes under 3 clean runs, report it and do not loosen the threshold silently.

View the PNGs `transition-live-grow-120.png`, `transition-live-collapse-450.png` and `closed-1.png` to confirm the look is unchanged. Then rebuild Debug to `/tmp/notch-dd` and Release to `/tmp/notch-rel` with the recipes in the interfaces block; both must show `** BUILD SUCCEEDED **`. Launch neither app. Do not touch the user's running app.

Commit any harness tweak as `test(quick-hmo): ...`. Do not commit PLAN, SUMMARY or STATE. In the SUMMARY, include:
- a before/after table per transition: n, max, p95 and over20 for -O, and -Onone for reference;
- each root cause with its evidence file (`/tmp/hmo-*.txt`, the trace);
- rejected experiments;
- UAT steps for the real Release app: open, expand, collapse, close; music open/close; and Instruments "Animation Hitches" on the user's own run.
  </action>
  <verify>
    <automated>cd /Users/mitch/Documents/Claude/orchestrator/worktrees/notch-261015024118-29b9 && for i in 1 2 3; do OPT=-O boringNotch/Orchestrator/Snapshots/run.sh --frames > /tmp/hmo-final-$i.txt 2>&1; grep -E '^(OK|FAIL): frames' /tmp/hmo-final-$i.txt; done; grep -l 'BUILD SUCCEEDED' /tmp/notch-dd-build.log /tmp/notch-rel-build.log</automated>
  </verify>
  <done>3 runs of `OK: frames` in -O. The other harness modes still pass. Both build logs show BUILD SUCCEEDED. `git status` shows no graft/ or .ignore staged. The summary holds the before/after table and the evidence.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| none new | Local animation/perf work. No new network, input parsing or entitlements. |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-hmo-01 | Denial of Service | Real user session | mitigate | The harness never warps the cursor or posts CGEvents, and never launches, quits or attaches to the user's Boring Notch. `sample` and xctrace target only the harness binary. |
| T-hmo-02 | Tampering | git history | mitigate | Use explicit `git add` paths only. Never stage graft/ or .ignore. Never push or switch branches. |
| T-hmo-03 | Information Disclosure | signposts | accept | The new signposts live in the harness only and carry timings, not content. |
</threat_model>

<verification>
- `OPT=-O run.sh --frames`: OK 3 times, with no frame over 20 ms in open, expand, collapse or close.
- `--transition`, `--hittest`, `--closed`, `--idle` (both opt levels), the composer scenes and the unit harness all pass.
- Both builds are fresh. Neither app was launched.
</verification>

<success_criteria>
The before/after table shows every transition at over20 = 0 in the -O harness. Every kept fix comes from recorded evidence. The look (pinned top, fade, springs) and the music behaviour are unchanged. /tmp/notch-rel and /tmp/notch-dd are rebuilt.
</success_criteria>

<output>
Create `.planning/quick/261015-hmo-notch-animation-frame-rate/261015-hmo-SUMMARY.md` when done (not committed by the executor).
</output>
