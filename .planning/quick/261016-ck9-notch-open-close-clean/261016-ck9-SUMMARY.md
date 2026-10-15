---
quick_id: 261016-ck9
status: complete
date: 2026-10-16
commits: [a1117f5, 661d8ee]
key-files:
  modified:
    - boringNotch/ContentView.swift (one line: the Orchestrator tab transition)
    - boringNotch/Orchestrator/OrchestratorExpanded.swift
    - boringNotch/Orchestrator/OrchestratorView.swift
    - boringNotch/Orchestrator/Snapshots/{Snap.swift,SnapFrames.swift,run.sh}
  created:
    - boringNotch/Orchestrator/Snapshots/SnapPaint.swift
---

# Quick 261016-ck9: notch open/close look clean

## The three issues: cause and evidence

Recording frames are in `evidence/rec-*.jpg`. Harness strips (`--paint`, every composited frame of one transition) are in `evidence/before-*.jpg` and `evidence/after-*.jpg`.

**1. Open: text over the wallpaper before the black fills in** (`rec-open_seq2.jpg`, 0.74-0.86 s, 120 fps).
On consecutive frames the chat rows and the badge are drawn below the black shape's bottom edge while the shape springs open. The rows are clipped at the shape's sides, but not at its bottom.
- Cause: the Orchestrator tab was inserted with a 0.35 s opacity fade that started at t=0, and its body is laid out at the final size from the first frame (the `held` frame). The transcript rows are AppKit text views, and in the real window they run ahead of the SwiftUI black shape.
- The harness shows the same thing: content reaching the shape's bottom edge while it grows (`before-open-leak-frame.png`; `--paint` before: `open … 218 pt² drawn outside the shape`).

**2. Black box larger than the notch, held, then gone at once** (`rec-col2.jpg`, 4.58-4.80 s, and `rec-exp_seq.jpg`).
On a close from the expanded level:
- The content fades in about 80 ms.
- The shape then freezes mid-spring, at about 620x350 pt (far larger than the open notch), for about 100 ms, with only the badge in it.
- Then it is gone in one step.

The 80 ms is the level-change `fadeOut`. When the tab leaves, `reset()` collapses the level, and `levelChanged()` then ran its hidden swap at 80 ms. That swap re-lays the whole transcript out at the open level while the notch is closing. The main thread is busy for those frames, so the shape's spring has no frames to show and lands at its end state in one jump.

The expand at 1.8 s shows the same empty box with the badge in it. That is the designed 280 ms gap before the expanded content fades in; with the badge gone it is now just the growing shape.

**3. Badge doesn't fade with the rest** (`rec-col2.jpg`, `rec-exp_seq.jpg`; `--paint` before: `badge shown with the content hidden` in expand, collapse and closeExpanded).
- Cause: `OrchestratorUpdateBadge` was an overlay on `OrchestratorView`, outside `OrchestratorExpandedView`'s `.opacity(contentOpacity)`. So every level fade (and the close, which runs one) left it on screen alone.

## Fix (661d8ee)

- `AnyTransition.orchestratorTab` (OrchestratorExpanded.swift), used by ContentView's one Orchestrator transition line:
  - insertion is an opacity fade of 0.15 s after 0.28 s;
  - removal is an opacity fade of 0.08 s;
  - this is the timing a level change already uses, so the black shape always leads and the text is gone before the shape shrinks under it.
- `levelChanged()` does nothing once the notch is closing (`vm.notchState != .open`), and a swap that is still pending also bails. The leaving tab fades out with its own transition.
- The badge overlay moved into `OrchestratorExpandedView`, under `contentOpacity`, at the same position (top, 4 pt).

Unchanged: the top-pinned grow, the open/close and expand springs, the window sizing, and the one-motion expand.

## Regression check (a1117f5): `run.sh --paint`

The FramesRoot panel is parked off screen (x = -6000) at full alpha, and captured as the window server composites it with `CGWindowListCreateImage`. That needs no Screen Recording permission for our own window, and unlike `cacheDisplay` it includes AppKit text. Frames are taken every ~8 ms through open, expand, close from expanded (outside click, hover exit), collapse and close.

It fails when:
- a light pixel is outside the black shape;
- the black shape is more than 8 pt bigger than the layout's notch shape within the last 50 ms;
- update-badge pixels are drawn while the content below the header is hidden.

Strips go to `PAINT_DIR` (default `/tmp/notch-paint`).

- Before the fix: `FAIL: paint in open, expand, closeExpanded, open2, expand2, open3, expand3, collapse`.
- After: `OK: paint` in all 10 transitions.

Limits:
- The harness does not reproduce the ~100 ms freeze of issue 2 (its transcript fixture is lighter than the real one; longest main-thread gap is about 41 ms before and after). That cause comes from the recording's timing plus the code path.
- The screen itself could not be recorded: `screencapture` has no Screen Recording permission here ("could not create image from rect"). The user's app was not touched.

## Checks

- Unit harness (Models, Pure, Transcript, PromptParse, RunsPure, Stream, ComposerInput + Tests/*.swift): OK.
- `run.sh`: OK, composer bottom padding 12 in 33 scenes.
- `--idle`: `OK: idle`.
- `--transition`: top edge pinned, no intermediate-layout frames.
- `--paint` (-O): OK (before: FAIL as above).
- `--hittest`: hangs after "scroll over text works": a synthetic click sits in an AppKit mouse-tracking loop. The same hang happens on an untouched copy of HEAD (a55819a), so it predates this change. Every check printed before it passed.
- Debug build (`-derivedDataPath ./build`): `** BUILD SUCCEEDED **`.
- Release build (`./build`, ad-hoc, `ENABLE_HARDENED_RUNTIME=NO`, ORCH_NO_SPARKLE) copied to `./build/notch-rel/Clive.app`: `** BUILD SUCCEEDED **`, `flags=0x2(adhoc)`. Not launched.

## Deviations

- The plan and the fix were done inline rather than by spawned planner and executor agents, because the task was mostly evidence work on the recording.
- Opening now shows the chat about 0.28 s after the shape starts growing, instead of fading in from the first frame. This is the trade for the shape always leading.
- `graft/` was not committed.

## How to see it in the app (UAT)

Record the notch with QuickTime (File > New Screen Recording, select the top of the screen, 60 fps or more) on `build/notch-rel/Clive.app`:
1. Hover-open on the Orchestrator tab. The black shape grows empty, then the chat fades in inside it. No text appears over the wallpaper.
2. Expand (tap the chat), then move the pointer away to close. The content and the badge fade together, and the shape shrinks smoothly to closed with no held box.
3. Expand, then collapse with ⌘↑. The badge disappears and reappears with the content.
4. Music controls on Home still work.
