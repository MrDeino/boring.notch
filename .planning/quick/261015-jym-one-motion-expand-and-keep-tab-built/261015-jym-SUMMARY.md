---
phase: quick-261015-jym
plan: 01
subsystem: orchestrator-tab
tags: [perf, animation, swiftui, harness, merge]
requires: [quick-261015-hmo]
status: incomplete
key-files:
  modified:
    - boringNotch/ContentView.swift
    - boringNotch/Orchestrator/OrchestratorExpand.swift
    - boringNotch/Orchestrator/OrchestratorView.swift
    - boringNotch/Orchestrator/OrchestratorExpanded.swift
    - boringNotch/Orchestrator/OrchestratorChat.swift
    - boringNotch/Orchestrator/OrchestratorPromptCard.swift
    - boringNotch/Orchestrator/Snapshots/{SnapFrames.swift,SnapIdle.swift,run.sh}
metrics:
  completed: 2026-10-15
---

# Quick 261015-jym: one-motion expand (kept-built tab tried, then reverted)

**Partly met.** Width and height move as one in every transition. The views read the new size at once. `origin/main` (PRs #5-#11) is merged. The Orchestrator tab was kept built while the notch was closed, but the user had it **reverted** (2026-10-16, see the last section): it gave no measured gain and raised closed idle CPU from 0.5% to 2-3%. Still not met: the 20 ms frame gate in all four transitions, and the "even" gate for expand. Expand still freezes for about 50 ms at the hidden content swap, then the shape jumps 12-22% of its travel. That pause and jump is the most likely source of the "first wider, then taller" look (see Cause).

The previous executor was killed twice (terminal force-quit, then an API outage). It finished the commits and the merge. The orchestrator ran the post-merge checks, the builds and this summary in the foreground.

## Cause of the "two-phase" expand (evidence)

- **The shape's width and height never split in the harness, not even at baseline.** The new together gate records the animated shape size every frame from an AppKit probe in the shape's background. It shows `togetherGap(max)=0.000` in every baseline and every later run: `/tmp/jym-baseline-{1,2,3,Onone}.txt`, `/tmp/jym-final-*.txt`, `/tmp/jym-post-*.txt`. So the harness never sees the shape go wider first.
- **The motion is split by a stall at the content swap.** About 90-130 ms into expand, one frame takes 40-60 ms (`stalls[at+ms]=92+58`, `128+37`). After it, the shape jumps 0.12-0.29 of its travel in one frame (even gate: `jump=0.197 at=134`, `0.219 at=133`, `0.166 at=131`). A pause then a jump in a diagonal grow reads as two phases. Collapse has the same at about 115 ms, but smaller (jump 0.08-0.12).
- **A stale size read was suspected and is now guarded, but never caught.** At baseline the root-read gate already read the new size within 30 ms with no stale reads (`/tmp/jym-stale-base-*.txt`, `stale=0`). The fix in 41722f7 sends a second `objectWillChange` after the size store and is harmless; after it the size is read within 6-25 ms. It is kept as insurance, not as a measured fix.
- **The open/close numbers come from a copy of the view code, not the real view.** `FramesRoot` copies ContentView's root chain, because the harness can't compile ContentView. If the real app does go sideways first, the copy doesn't reproduce it. Check the real Release app (UAT 1).

## Before / after (`OPT=-O run.sh --frames`, 3 runs each, max ms / p95 ms / frames >20 ms / together gap / even jump)

| Transition | Baseline (4b73476) | After, before merge (1752cc6) | After merge (9c13afc) |
|---|---|---|---|
| open | 118-130 / 8.3 / 3 / 0.000 / 0.02-0.06 | 111-141 / 8.3-13.9 / 1-2 / 0.000 / 0.03-0.06 | 127-164 / 8.3 / 1-2 / 0.000 / 0.02-0.06 |
| expand | 52-136 / 17-46 / 6-9 / 0.000 / **0.18-0.42** | 51-54 / 17-18 / 5-6 / 0.000 / **0.19-0.21** | 58-60 / 16-23 / 5-21 / 0.000 / **0.20-0.25** |
| collapse | 41-47 / 10-27 / 7-10 / 0.000 / **0.13-0.23** | 35-42 / 8.3-12 / 5-7 / 0.000 / **0.13-0.15** | 31-44 / 8.3-20 / 3-9 / 0.000 / 0.10-0.11 |
| close | 20-30 / 8.3 / 0-3 / 0.000 / 0.02-0.08 | 8-34 / 8.3 / 0-2 / 0.000 / 0.03-0.06 | 8-39 / 8.3 / 0-2 / 0.000 / 0.04-0.05 |

Bold = even gate (0.12) failed. At -Onone after the merge: open 128, expand 67 (jump 0.29), collapse 34 (jump 0.12), close 30. The machine was loaded the whole time (load average 3.7-7, other notch runs active), and the same code moves about ±30% between runs (expand over20 was 5, 21 and 6 in three post-merge runs).

Expand's spread and the even jump improved (from up to 136 ms and a 0.42 jump, down to 50-60 ms and about 0.2). Collapse now passes the even gate after the merge. **Keeping the tab built did not measurably shorten open's first frame (about 110-160 ms before and after).** The first-frame and swap hitches remain.

## Closed-notch idle CPU (`run.sh --idle`, process % over 8 s)

| Scene | before jym | after merge -Onone | after merge -O |
|---|---|---|---|
| a / a2 / a3 / a4 closed, running run | 0.5 | 0.5 | 0.3-0.5 |
| b closed, nothing | 0.2 | 0.2 | 0.2 |
| a5 closed, **tab built**, rich feed ticking (new) | (not built) | 3.1, rerun 2.3 (pre-merge 3.0) | 2.8 |
| a6 closed, **tab built**, same payload (new) | (not built) | 2.7, rerun 2.1 (pre-merge 1.8) | 2.1 |
| g expanded, typing stress | | 8.1 | |

The new closed scenes host the copied tab with the tab built and are limited to 3%. a5 sits on that line: the full -Onone `--idle` run failed with a5 at 3.1%. The a5/a6 rerun gave 2.3/2.1 and passed, and the -O run passed. **Keeping the tab built costs about 2-3% CPU while a rich feed ticks with the notch closed, against 0.5% when it is torn down.**

## Commits

| Commit | What |
|---|---|
| 4b73476 | test: per-frame width/height together gate, even gate, content-steady gate, FRAMES_TRACE/PIXELS |
| 41722f7 | fix: second `objectWillChange` after the notch size store + root-read gate (insurance; no stale read seen at baseline) |
| 7072c57 | perf: keep the Orchestrator tab built while closed (`OrchestratorKeptBuilt`: zero size, hidden, no hit testing; closed VStack spacing 0; open/close hooks run on notchState change) |
| 1752cc6 | test: closed tab-built idle scenes a5/a6 (3%) and a close-then-reopen gate |
| 9c13afc | merge origin/main (PRs #5-#11) |

## Merge of origin/main (9c13afc)

origin/main had PRs #5-#11: readable approvals and the AskUserQuestion card, question lead-in, full-length chat rows, question-card chrome fix, composer send retry, type-to-focus composer and first-gesture selection, and the Claude update badge. Three files conflicted: `.planning/STATE.md`, `OrchestratorChat.swift` and `Snapshots/Snap.swift`. The killed executor resolved them by keeping both sides. Afterwards:

- Unit harness: OK.
- `run.sh`: OK, composer bottom padding 12 in 33 scenes.
- `--hittest`: all OK.
- `--transition`: top edge pinned, no intermediate-layout frames.
- `--closed`: no failures, wings centred, music indicator rendered.
- `--idle`: OK at -O. -Onone OK on rerun, after one a5 failure at 3.1% (see above).
- `--frames`: together OK, root read OK; the 20 ms and even gates still fail in REPORT mode, as before the merge.

An earlier unit-harness failure (`QuickMe4Tests.swift:81`) came from a half-merged tree at 17:02 and no longer happens.

## Builds

- Debug `/tmp/notch-dd`: `** BUILD SUCCEEDED **`.
- Release `/tmp/notch-rel`: `clean build`, ad-hoc, `ENABLE_HARDENED_RUNTIME=NO`, ORCH_NO_SPARKLE: `** BUILD SUCCEEDED **`. `-DORCH_NO_SPARKLE` is on the app target's compile lines.
- `codesign -dv`: app `flags=0x2(adhoc)`, no runtime. MediaRemoteAdapter and Lottie are `0x2(adhoc)`. Sparkle.framework keeps its shipped `0x10002(adhoc,runtime)`; Sparkle doesn't start in this build. `codesign --verify --deep --strict` passes.
- Neither app was launched.

## Deviations

- Option (a) was reverted at the user's request (44abd2a, d7407d0).
- The plan's Task 2 fix for the swap hitch (one motion with no stall at the swap) was not finished. The expand even gate still fails.
- A stray `graft/` cache folder appeared several times and was deleted each time. It was never staged.

## UAT

1. Release app: expand and collapse the notch a few times. Does it still look like "wider, then taller", or is it now one grow with a brief catch about a third of the way in?
2. Open and close the Orchestrator tab: the first frame of open is still the longest one (about 120 ms in the harness).
3. With a run active and the notch closed, Activity Monitor should be back near 0.5% CPU.
4. Close and reopen the Orchestrator tab with a composer draft, and type to focus the composer after reopening (merged me4 behaviour). Music controls, Home and Shelf behave as before.
5. Check the merged features: approval/question card, lead-in text, long chat rows, send retry, type-to-focus, the Claude update badge.

## Revert of the kept-built tab (2026-10-16)

The user chose to revert option (a). `git revert`, no history rewrite:

- **44abd2a** reverts 1752cc6 (closed tab-built idle scenes a5/a6 and the reopen gate). Clean.
- **d7407d0** reverts 7072c57 (`OrchestratorKeptBuilt`, closed VStack spacing, notchState open/close hooks). One conflict, in `OrchestratorChat.swift`. The merged me4 type-to-focus hooks are kept: `.onAppear { installTypeMonitor() }` and `.onDisappear { …; removeTypeMonitor() }`. The kept-built `onChange(of: notchState)` and `composerH` are dropped.

Kept as they were: the together, even, content and root-read gates (4b73476), the stale-size guard (41722f7) and the merge (9c13afc).

**Checks after the revert:**
- Unit harness: OK.
- `run.sh`: OK, composer bottom padding 12 in 33 scenes.
- `--idle` -Onone and -O: `OK: idle` in both.

**Closed idle CPU is back down** (-Onone / -O, %):

| Scene | -Onone | -O |
|---|---|---|
| a closed, running, same payload | 0.5 | 0.2 |
| a2 closed, running, `doing` changes | 0.4 | 0.2 |
| a3 closed, running, screen changes | 0.3 | 0.3 |
| a4 closed, running, tokens change | 0.3 | 0.3 |
| b closed, nothing | 0.1 | 0.1 |
| (a5 tab built, rich feed, before revert) | 2.3-3.1 | 2.8 |

**`OPT=-O --frames`, 3 runs** (longest frame ms / 95th-percentile frame ms / frames over 20 ms / together gap / largest mid-spring jump):

| Transition | After revert | Kept-built, after merge |
|---|---|---|
| open | 131-167 / 8.3-16.7 / 3 / 0.000 / 0.06 | 127-164 / 8.3 / 1-2 / 0.000 / 0.02-0.06 |
| expand | 48-64 / 24-26 / 18-26 / 0.000 / **0.20-0.26** | 58-60 / 16-23 / 5-21 / 0.000 / **0.20-0.25** |
| collapse | 32-35 / 14-18 / 7-8 / 0.000 / 0.10-**0.13** | 31-44 / 8.3-20 / 3-9 / 0.000 / 0.10-0.11 |
| close | 32-42 / 8.3-10 / 1-2 / 0.000 / 0.04-0.06 | 8-39 / 8.3 / 0-2 / 0.000 / 0.04-0.05 |

The together gate and root-read gate are OK in every run. Open's first frame is the same with or without the kept-built tab, which confirms the revert loses nothing there. Expand's p95 and its count of frames over 20 ms read higher than before the revert. The machine was busy, though: load average up to 15 during these runs, with another run compiling. Earlier runs of identical code ranged from 5 to 21 frames over 20 ms, so this is within noise and not attributed to the revert. The content-swap stall in expand is unchanged and left for a separate decision.

**Builds after the revert:**
- Debug `/tmp/notch-dd`: `** BUILD SUCCEEDED **`.
- Release `/tmp/notch-rel`: `clean build`, ad-hoc, `ENABLE_HARDENED_RUNTIME=NO`, ORCH_NO_SPARKLE (on the app target's compile lines): `** BUILD SUCCEEDED **`.
- `codesign -dv`: `flags=0x2(adhoc)`, no runtime. `--verify --deep --strict` OK.
- Neither app was launched. No cursor moves. No `graft/` committed.
