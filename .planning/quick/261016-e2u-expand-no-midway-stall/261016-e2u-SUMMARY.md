---
quick_id: 261016-e2u
status: incomplete
date: 2026-10-16
commits: [cf1790d, 200f4d2]
key-files:
  modified:
    - boringNotch/Orchestrator/OrchestratorExpanded.swift (swap timing: swapAt 0.24)
    - boringNotch/Orchestrator/Snapshots/SnapFrames.swift (even gate per transition: expand 0.05)
    - boringNotch/Orchestrator/Snapshots/run.sh (--frames comment)
---

# Quick 261016-e2u: expand without the midway stall

**Status: incomplete.** The midway stall is fixed. The expand jump is 0.022-0.024 (was 0.155-0.386), and the even gate (0.05) passes. The 20 ms frame gate still fails. The level swap is a single 43-64 ms block of main-thread work, and the constraints on this task rule out the only changes that could split it below one frame (see "Why the 20 ms gate is still red").

## Cause

The cause is the hidden level swap in `OrchestratorExpandedView.levelChanged()`: `withTransaction { shown = level; held = slot }`. It re-lays out the whole column at the expanded size in one main-thread pass. That pass covers:
- the chat rows at the new width;
- the expanded row branches: user bubbles and diff cards, which are new `OrchestratorSelectableText` NSTextViews;
- the runs rail and the terminal pill.

The swap ran 80 ms after the click, right after the fade-out. That is where the notch spring (response 0.4, damping 0.82) moves fastest. SwiftUI springs are time-based, so the shape held still for the 40-60 ms block and then jumped 0.15-0.39 of its travel.

Evidence:
- **Bisect.** Each variant used `OPT=-O FRAMES_ONLY=expand`, 2 runs x 3 expands, with temporary env toggles that were reverted afterwards:

  | variant | swap stall (ms, at ~85-140 ms) | expand jump |
  |---|---|---|
  | HEAD (none) | 43-57 | 0.123-0.219 |
  | (a) no swap at all | none (0+ first frame only) | **0.022** in all 6 |
  | (b) swap, no rail/terminal pill | 30-49 | 0.083-0.104 |
  | (c) swap, chat kept at open flags (lineLimit 4, expanded false) | 27-45 | 0.083-0.179 |
  | (b)+(c) with 8 rows | 18-30 | 0.066-0.105 |
  | (d) no shadow in FramesRoot | 43-53 | 0.142-0.179 |

  The swap is the whole stall. The rail is about 10-15 ms of it, the expanded chat rows another 10-15 ms, and the column re-layout at the new size about 10-20 ms. The shadow is not a factor. In the optimised harness nothing besides the swap made frames over 20 ms: p95 is 8.3 ms at load 3-5, and the higher p95 in the first baseline runs came with load 6-20.
- **Forced timing** (a temporary `layoutSubtreeIfNeeded` plus `CATransaction.flush` straight after the swap, 29-block fixture):
  - full swap: layout 31-41 ms, flush 4-8 ms, next runloop turn 3-10 ms;
  - with 8 rows, no rail, open flags: layout 4-10 ms.
  - Text measuring in `OrchestratorSelectableTextView.fit` is only about 5 ms of the full swap (58 calls).
- **Profile** (`sample` on a loop that toggled the swap every 60 ms, `build/e2u-sample-sl.txt`): main-thread time is mostly SwiftUI graph/layout. The biggest single item is `OrchestratorSelectableText.makeNSView -> apply -> NSTextStorage replaceCharactersInRange`, about 22% of busy samples. That is new NSTextViews being created for the expanded branches (diff-card lines, user bubbles). Xcode Time Profiler (`xctrace`) sampled too sparsely under the machine's load to isolate the window, so I didn't use it.

## Fix

The swap now runs at `swapAt = 0.24` s instead of at `fadeOut` (0.08 s). That is one constant and two sleep lines in `levelChanged`.

The content is still hidden from 80 ms on, so nothing reflows on screen. By 240 ms the spring is in its tail, so the same 40-60 ms block moves the shape by at most about 0.02-0.03. A trace measured the step size by swap time: 0.20 s gives <= 0.049, 0.22 s <= 0.031, 0.24 s <= 0.021.

Everything else is unchanged: the fade-in at 0.28 s, the spring, the top-pinned grow, one motion for width and height, and the ck9 guards. The `notchState == .open` and `fadeGen` checks still run after the sleep, so a close during the first 240 ms skips the swap, which is what ck9 wants.

Why this option:
- **A** (split the swap) was tried twice and dropped:
  1. Building the rail hidden at the click and lagging the chat flags by one step: the click frame grew to 27-62 ms, the steps were 24-46 ms each, and the jump was 0.11-0.24.
  2. Seven steps (8 rows, then the hidden rail, swap, chat flags, rows back in eights): every step still cost 21-39 ms, because each chat change re-lays out the full chat and creates new NSTextViews. The jump was 0.064-0.125 and the frame gate still failed.
- **B** (swap before the spring) would hold the shape for 80 + ~50 ms after the click. It would also fail the 20 ms gate, because the swap block is the same size.
- Moving the swap to the tail is option C's idea without C's cost. The swap happens near the end of the spring, but the fade-in stays at 0.28 s instead of moving to about 0.5 s.

Timing change:
- Click-to-motion: unchanged.
- Fade-in: still asked for at 0.28 s. When the swap block runs past that, the fade-in starts when the block ends, about 0.28-0.30 s.

## Before / after

Optimised harness (`OPT=-O`), 3 expands per run. Load is `vm.loadavg` (1/5/15 min) at the start of each run. The display is 120 Hz: the idle cadence is 8.3 ms.

| run | load | expand max ms | p95 | over20 | expand jump (at ms) | swap stall at+ms | collapse jump |
|---|---|---|---|---|---|---|---|
| base-gatecheck | 16.23 15.16 15.72 | 64.7 | 8.4 | 5 | 0.301@167, 0.183@123, 0.155@131 | 121+65, 91+47, 98+49 | - |
| base-1 | 11.82 14.10 15.24 | 162.0 | 24.8 | 14 | 0.236@143, 0.374@265, 0.223@126 | 96+63, 107+162, 100+42 | 0.104-0.105 |
| base-2 | 6.35 11.65 14.17 | 63.9 | 20.0 | 12 | 0.253@143, 0.161@123, 0.183@125 | 100+64, 86+49, 80+57 | 0.083-0.166 |
| base-3 | 20.28 17.62 16.35 | 419.9 | 22.6 | 5 | 0.248@147, 0.161@123, 0.386@584 | 101+68, 91+44, (0+420 load spike) | 0.063-0.083 |
| bis-none-1 (HEAD) | 4.69 10.35 13.48 | 190.3 | 10.6 | 8 | 0.161, 0.123, 0.123 | 123+46, 118+40, 87+43 | - |
| after-1 | 2.54 3.65 4.57 | 63.8 | 8.3 | 4 | 0.024, 0.022, 0.022 | 252+64, 246+43, 274+44 | 0.022 |
| after-2 | 3.09 3.54 4.43 | 53.9 | 8.3 | 4 | 0.022, 0.022, 0.024 | 253+54, 248+45, 275+46 | 0.022 |
| after-3 | 3.67 3.73 4.42 | 48.5 | 8.3 | 4 | 0.022, 0.022, 0.022 | 254+46, 260+46, 246+49 | 0.022-0.031 |
| gate-1 (strict) | 3.30 3.62 4.30 | 55.6 | 8.3 | 4 | 0.022 x3 | 254+56, 252+43, 278+37 | - |
| gate-2 (strict) | 2.83 3.37 4.13 | 55.2 | 8.3 | 4 | 0.022, **0.065@110**, 0.022 | 251+55, 285+46, 246+51 | - |
| gate-3 (strict) | 2.60 3.18 3.99 | 59.1 | 8.3 | 3 | 0.022 x3 | 256+59, 245+46, 248+40 | - |

How to read it:
- **The stall did not shrink. It moved.** It is still 37-64 ms, but it now lands at 245-285 ms instead of 80-140 ms, so the shape moves 0.022 per step instead of 0.15-0.39.
- **Load.** The baseline ran at a higher load (6-20) than the after runs (2.5-3.7). The `bis-none` HEAD run at load 4.7 shows the same stall and jump as the high-load baselines. The no-swap bisect gave 0.022 at loads 5-13.
- **Over 20 ms, after.** The over20 counts are the swap frame plus, in about 1 in 3 transitions, the first frame after the trigger (`0+23` to `0+51`). That first-frame stall is the synchronous `setFrame(display: true)` window grow. It is present at HEAD in both expand and collapse, so it predates this change and is out of scope here.
- **The one 0.065 (gate-2)** is at 110 ms, well before the swap. It belongs to the same expand that had a 0+44 first-frame stall. Jumps of that size also show up with no swap at all under load (`nosw-1`: 0.056, 0.104, 0.064, with every frame at 8.3 ms). At 120 Hz a clean frame at peak speed already moves 0.043-0.045, so 0.05 leaves no slack. Over the 18 after/gate expands, 17 were 0.022-0.024.
- **Collapse got better,** not worse: jump 0.022-0.031 (was 0.063-0.166). Its over20 is 3-4 per run, the same as the baseline, and the swap frame there is now 23-31 ms at about 250 ms.

## Why the 20 ms gate is still red

To pass, every main-thread chunk in the 900 ms window has to stay under about 12 ms. The swap is 31-41 ms of layout plus a commit.

Splitting it does not work. Every step that touches the chat re-lays out the whole chat and builds the expanded rows' NSTextViews. Even "add 8 rows" or "flip the chat flags" cost 21-39 ms per frame (try 2 above).

Getting the swap under one frame needs one of these changes in the row views:
- a `LazyVStack` row list;
- diff cards and bubbles that don't create a fresh NSTextView per line on a level change;
- creating those views once and keeping them.

This task ruled all of them out, because the streaming run is working in `ChatBlockRow`, `OrchestratorChatView`'s row list and `OrchestratorSelectableText`. Option E (a fit cache) wouldn't help: `fit` is about 5 ms of the swap, and the view already caches per width.

The 0.05 jump limit **is** reachable on this 120 Hz display. A clean expand peaks at 0.022 per layout sample and about 0.045 per frame. It has no slack for a dropped frame at peak, though, so a load spike can still trip it (see the no-swap runs).

## Gates

- `--frames OPT=-O FRAMES_ONLY=expand` (strict), 3 runs:
  - **FAIL (frames)**: 3-4 expands over 20 ms per run, the swap frame and the first frame.
  - **even**: OK in runs 1 and 3. Run 2 FAILed at 0.065 at 110 ms (before the swap; see above).
  - together, content and rootread: OK.
- Full `OPT=-O FRAMES_REPORT=1 --frames` (`build/e2u-fullframes.txt`):
  - close: max 8.3 ms, 0 over 20, jump 0.034.
  - open: max 117 ms (first frame `0+65..0+117`, the known first-frame hitch, not touched here); jump 0.021.
  - expand/collapse as above.
  - together, even, content and rootread: OK.
  - idle cadence: 8.3 ms.
- `OPT=-O --paint`: **OK: paint**. The "longest main-thread gap" is 67-73 ms both before and after, at 650-960 ms. That is the capture loop itself, not the swap, so this probe can't see the change.
- `--idle` (-Onone): **OK: idle**, closed scenes 0.2-0.7%.
- `OPT=-O --idle`: the first run FAILed on `e-expanded-running-doing 5.9%` (limit 5). The same scene was 0.9% at -Onone. The scene waits 1 s after the level change, so the swap at 240 ms is outside its window. The next two -O runs gave **OK: idle** (2.9%, 3.4%), with closed scenes 0.1-0.6%.
- `--transition`: **OK** (top edge pinned in both checks; no intermediate-layout frames, blank grow 298..574, collapse 559..666 ms).
- Plain `run.sh`: **OK** (composer bottom padding 12 in 33 scenes).
- `--hittest`: it hangs after "scroll over text works", the same place as in ck9, which predates this change. It was killed at 240 s, and every check printed before the hang passed.
- Unit harness (Models, Pure, Transcript, PromptParse, RunsPure, Stream, ComposerInput + Tests):
  - The last test, `runQuickMe4SelectionTest`, fails on "focus opens the session once" (3 tries). It is a key-window/mouse test. None of the compiled sources differ from ccfc727, because this task changed no file in that build, so the failure is environmental.
  - With only that test skipped (`build/unit2`), every other test passes: `OK`.
- Builds:
  - Debug: `** BUILD SUCCEEDED **` (`build/dd.log`).
  - Release: `** BUILD SUCCEEDED **` (`build/rel.log`, swiftc has `-DORCH_NO_SPARKLE`). Copied to `build/notch-rel/Clive.app`. `codesign -dv`: `flags=0x2(adhoc)`, no runtime flag.
  - Neither app was launched.

## Deviations

- Two option-A attempts (above) were measured and reverted. Their patches are in `build/e2u-try1.patch` and `build/e2u-try2.patch`.
- All bisect and timing edits were temporary env toggles and were reverted. None were committed.
- The swap moved to the spring's tail (a variant of C that keeps the fade-in at 0.28 s) instead of B. B can't pass the 20 ms gate either, and it adds about 130 ms of click-to-motion delay.
- Xcode Time Profiler sampled too sparsely under the machine's load, so `sample` on swap loops was used instead.

## UAT (your Release app)

1. Install `build/notch-rel/Clive.app` the usual way (the running copy wasn't touched).
2. Record the notch at 60 fps or more.
3. Open the Orchestrator tab and click the transcript to expand, 5 times or more, with a long transcript that includes diff cards.
4. Expected: width and height grow in one continuous spring, with no pause and no "wider, then taller". The content fades back in as the shape settles, as before.
5. Collapse with ⌘↑ or an outside click: still smooth.

## Self-Check: PASSED

- cf1790d (gate) and 200f4d2 (fix) are on orch/261016000802-4a79.
- `graft/` is untracked and not staged.
- SUMMARY, STATE and PLAN are left for the orchestrator to commit.
