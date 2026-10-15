---
phase: quick-261015-hmo
plan: 01
subsystem: orchestrator-tab
tags: [perf, swiftui, animation, frame-rate, harness]
requires: [quick-261015-ev9, quick-261015-ehb]
provides:
  - run.sh --frames: display-link frame intervals for open/expand/collapse/close with a 20 ms gate
  - expand/collapse no longer re-lay the tab content out on every spring frame
  - Orchestrator tab open/close no longer re-lays AppKit-backed views out on every frame
key-files:
  created:
    - boringNotch/Orchestrator/Snapshots/SnapFrames.swift
  modified:
    - boringNotch/Orchestrator/Snapshots/Snap.swift
    - boringNotch/Orchestrator/Snapshots/run.sh
    - boringNotch/Orchestrator/OrchestratorExpanded.swift
    - boringNotch/ContentView.swift
metrics:
  completed: 2026-10-15
---

# Quick 261015-hmo: notch animation frame rate

The springs themselves are smooth now: every transition's p95 frame interval went from 18-44 ms down to 8.3 ms (one frame at 120 Hz). **The 20 ms gate is NOT met.** Each transition still has one or two long frames, all at fixed points: when the transition starts, and for expand/collapse also when the content swaps to the new level while it is hidden. Open is the worst at 80-150 ms on its first frame. Details are under "Not met" below.

## Before / after (`run.sh --frames`, panel-hosted, alpha 0.01, 120 Hz display)

Each cell covers 3 runs of each transition. max = worst interval, p95 = worst run's p95, >20 = total frames over 20 ms in the 3 runs, n = average frames in the 900 ms window (about 108 is a clean 120 Hz).

| Transition | -O before (2 runs of 3) | -O after (3 runs of 3) | -Onone before | -Onone after |
|---|---|---|---|---|
| open (closed->open) | max 144-172, p95 24-25, >20 13-15, n 79 | max 137-150, p95 8.3, >20 3-4, n 100 | max 165, p95 18.7, >20 7 | max 139, p95 8.3, >20 3 |
| expand (open->expanded) | max 88-90, p95 39-44, >20 43-50, n 60 | max 52-57, p95 8.3, >20 4-6, n 109 | max 93, p95 40.0, >20 49 | max 51, p95 8.3, >20 6 |
| collapse (expanded->open) | max 62-254, p95 9-34, >20 8-31, n 63-104 | max 39-53, p95 8.3, >20 6, n 108 | max 49, p95 13.7, >20 7 | max 32, p95 8.3, >20 6 |
| close (open->closed) | max 30-36, p95 21-25, >20 13-19, n 87 | max 30-33, p95 8.3, >20 3, n 110 (one outlier run below) | max 32, p95 24.6, >20 17 | max 36, p95 8.3, >20 2 |

Files: `/tmp/hmo-baseline-O.txt`, `/tmp/hmo-baseline-O-2.txt`, `/tmp/hmo-baseline-Onone.txt`, `/tmp/hmo-final-{1,2,3}.txt`, `/tmp/hmo-final-Onone.txt`.

Noise: another dispatched notch run was building and running its own harness on this machine the whole time (load average 5-8). In final run 2, one close measured max 123 / p95 102 (33 frames). That same run's idle step also stalled (21.7 ms), so I count it as machine load, not the code. In both baseline runs, collapse swung between clean and a 200-250 ms stall. Single numbers move by about ±30%. The trends in the table hold across every run.

## Root causes (with evidence)

1. **Expand/collapse: the whole tab column was laid out again on every spring frame.** SwiftUI interpolates a changed frame, and it re-lays out the subtree inside that frame at each in-between size. So every transcript row's NSTextView was measured again at a new width on every frame.
   - A temporary probe in `OrchestratorSelectableTextView.fit` counted 2240-2720 cache misses per expand/collapse. One row's width went 534->607, then 433->571 with spring overshoot, frame by frame.
   - Time Profiler (`/tmp/hmo-tp.trace`, `/tmp/hmo-tp-prof.xml`): one continuous 380 ms main-thread run in expand, 136 ms of it in `fit(width:)`.
   - Fix: the content keeps an explicit size that changes only at the hidden level swap. After the fix: 58 misses per expand, 31 per collapse.
2. **Open/close: the tab body's `.scale(0.8)` transition moved every AppKit-backed view on every frame.** That is the transcript's NSScrollView and the NSTextView rows. Each frame ran `GeometryReaderLayout.placeSubviews -> ScrollViewUtilities.sizeThatFits` (the scroll content measured again), plus `setFrameTransform`/`setFrame` on the NSViews. Evidence: `/tmp/hmo-tp-fix3.xml` (149 of 441 samples in the open windows) and the A/B run `/tmp/hmo-exp-noscale.txt` (open/close p95 17-18 -> 8.3 ms).
3. **Remaining trigger and swap frames (not fixed, see below).**
   - Open, first frame: building the whole tab. About 34% is the chat ScrollView measuring all its rows; about 17% is building 29 `ChatBlockRow`s (platform view hosts, TextKit stacks, font descriptors); about 8% is `fit` misses on the new text views. Evidence: `/tmp/hmo-tp-fix3-seg.txt`, and `/tmp/hmo-exp-rows6.txt` (with 6 rows instead of 29 the first frame was 50-96 ms).
   - Expand/collapse first frame (30-55 ms): the window grows with `setFrame(display: true)`, then the whole window is laid out and rendered at the new size.
   - Swap (30-60 ms): the rows render again for the new level, and on expand the rail is added.

## Fixes kept (commits)

| Commit | What | Effect (-O) |
|---|---|---|
| 063209c | `test`: `--frames` harness. `FramesRoot` mirrors ContentView's root chain (shape, shadow, open/close springs, tab transition, root tail). Also `FRAMES_REPORT`/`FRAMES_ONLY`/`FRAMES_LOOP`, `frame-stall` signposts, `SNAP_BUILD=<dir>`, and NotchShape compiled into the harness. | baseline above |
| 74b995c | `perf`: `OrchestratorExpandedView` holds the content at an explicit size (`held`). It changes only at the hidden level swap. At the open level (composer, prompt context) the content still follows the notch with the same spring. | expand p95 39-44 -> 8.3, >20 43-50 -> 6-7; collapse p95 -> 8.3 |
| 452db22 | `test`: step-coded Time Profiler markers (`FRAMES_MARK=1`) | - |
| 4786629 | `perf`: the Orchestrator tab fades in and out without the 0.8 scale. One ternary in ContentView; Home/Shelf keep upstream's scale plus fade. The harness mirror changed the same way. | open/close p95 17-18 -> 8.3, close >20 13-19 -> 3 |

## Rejected experiments (reverted)

- **FrozenLayout** (an animatable Layout that fed the child "live proposal + frozen - animated notch"): no change, and the probe showed it caused the varying proposals itself. The live proposal was already constant; the cost came from the animated frame inside it.
- **`setFrame(display: false)` everywhere in `syncWindow`**: collapse got worse (after the 650 ms deferred shrink, a run of 26-30 ms frames, p95 28-31). Expand's first frame did not improve. `/tmp/hmo-exp-nodisplay.txt`.
- **`display: false` on the pre-spring grow only**: expand first frame 30-41 ms vs 30-55, which is within noise. `/tmp/hmo-exp-growdisp-{1,2}.txt`.
- **LazyVStack for the transcript rows**: open's first frame 73-110 ms vs 80-150 ms, which is small and noisy. Not worth the risk to the bottom-pinned scroll, the "new messages" logic and the content-height tracking. `/tmp/hmo-exp-lazy.txt`.
- **Fewer rows (6) at the open level**: measurement only, to size the row cost. It would change scrollback behaviour.

## Not met: frames over 20 ms that remain (-O, 3 runs)

| Transition | Remaining long frames | Cause |
|---|---|---|
| open | first frame 80-150 ms (sometimes one more of 21-25 ms) | the tab body is built on the trigger frame (`if vm.notchState == .open { ... }` in ContentView): 29 rows, the chat ScrollView measure, the composer |
| expand | first frame 30-55 ms, swap (~100-130 ms) 45-60 ms | window grow plus a full layout and render at the new size; at the swap the rows render again for the expanded level and the rail is added |
| collapse | first frame 30-45 ms, swap (~110-125 ms) 30-35 ms | the same, in the other direction |
| close | first frame 25-35 ms | the removal pass on the trigger frame |

I did not loosen the gate: `OPT=-O run.sh --frames` still prints `FAIL: frames over 20 ms in close, collapse, expand, open`. Getting under 20 ms needs one of these, and each changes structure or behaviour, so they need your call:

- (a) Keep the Orchestrator tab mounted while the notch is closed (hidden, zero height). The open trigger would cost about the expand trigger. But the tab's appear/disappear hooks (click monitors, `expand.reset`, typing, notes flush) and closed-notch idle CPU (the ev9 gates) would all have to be redone.
- (b) Build the transcript lazily or in batches after the spring. This risks the bottom-pinned scroll jumping, and it only roughly halves the open frame.
- (c) Split the swap over two hidden frames (rows, then rail). The swap's long frame would drop to about 30 ms, still over 20.

## Deviations

- **[Rule 1] The plan expected display-link and signpost evidence; xctrace "Animation Hitches" gave none.** The first recording ran the wrong binary: a parallel run had overwritten `/tmp/notch-snap-build/snap`, so the trace (`/tmp/hmo-hitches.trace`) is of the PNG mode. I did not repeat it: its `hitches` table was empty, and `hitches-renders` showed no offscreen passes. Time Profiler with `FRAMES_MARK` markers was used instead (`/tmp/hmo-tp*.trace`). os_signposts were not recorded by the Time Profiler template.
- **[Rule 3] Shared harness paths.** Another dispatched notch run was writing `/tmp/notch-snap-build/snap` and rebuilding `/tmp/notch-dd`. run.sh now takes `SNAP_BUILD=<dir>`. I measured with `SNAP_BUILD=/tmp/hmo-snap-build DD=/tmp/hmo-dd` (a copied Defaults.o). The default paths are unchanged.
- **[Look] The Orchestrator tab's open/close no longer scales its content from 0.8.** It fades only; the notch shape's spring, pinned top and fade are unchanged. This is the one visible difference. Reverting it is one line in ContentView (the ternary in the tab body's `.transition`).
- The harness mirror compiles `NotchShape.swift` too, so the shape path, radii and shadow are the real ones.
- An untracked `graft/` cache folder (MCP index) was in the worktree. I removed it; it was never staged.

## Final verification

- swiftc unit harness (Models, Pure, RunsPure, PromptParse, Transcript, Stream + `Tests/*.swift`): `OK`.
- `run.sh`: `OK: composer bottom padding 12 in 33 scenes`.
- `--hittest`: gap 12, run log open/close, and composer/segment/capsule/notes clicks all OK.
- `--transition`: top edge pinned (host-local and panel-hosted); no intermediate-layout frames; blank grow 307..544, collapse 344..462 ms. Two earlier `--transition` runs flaked on the capture-starved blank-window check, both before and after the fix (`/tmp/hmo-transition-base.txt` failed on HEAD too). The next three runs were OK.
- `--closed`: wings centred, music scenes rendered, no failures.
- `--idle` and `OPT=-O --idle`: `OK: idle`.
- `--frames` -O, 3 runs: FAIL as described above. -Onone: same pattern. -Onone is not gated.
- PNGs viewed: `transition-live-grow-1200` (expanded column, rail, composer), `transition-live-collapse-1200` (open level, newest row above the composer), `closed-1-working-chat` (wings). All look as before.
- `** BUILD SUCCEEDED **` for Debug (`/tmp/notch-dd`, 14:04) and Release (`/tmp/notch-rel`, `ORCH_NO_SPARKLE`, 14:05). Neither app was launched. The running Release copy (pid 26947) was not touched; its bundle on disk was replaced by the rebuild, so quit and reopen it to get the new build.

## UAT (real Release app)

1. Quit the running Boring Notch, then open `/tmp/notch-rel/Build/Products/Release/Boring Notch.app`. Run only one copy at a time.
2. Orchestrator tab, with a long transcript:
   - open (closed->open): the shape springs down from the top and the content fades in. The content no longer scales in; tell me if you want the scale back.
   - expand (tap the transcript or ⌘↓), collapse (⌘↑ or click outside), close: the shape should move at a steady rate. Expect one small catch at the start, and on expand/collapse one while the content is hidden.
3. Typing a long draft at the open level still grows the notch smoothly. The composer rides the bottom edge.
4. Music: open and close the notch on Home while music plays. Home/Shelf still scale in and out as before. The music controls and the closed-notch music indicator are unchanged.
5. Optional: Instruments > Animation Hitches on the running app, then open/expand/collapse/close a few times. Hitch rows should cluster at the start of each transition only.

## Self-Check: PASSED

Commits 063209c, 74b995c, 452db22 and 4786629 exist on orch/261015024118-29b9. No PROBE or EXPERIMENT lines are left in the tree. Nothing was pushed; the branch is unchanged.
