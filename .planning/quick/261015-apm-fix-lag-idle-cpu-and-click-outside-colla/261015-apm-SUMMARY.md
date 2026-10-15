---
phase: quick-261015-apm
plan: 01
subsystem: orchestrator-ui
tags: [performance, core-animation, swiftui, harness]
requires: [x18 batch (618f1fb..70ecc08), 07-03 wings]
provides: [run.sh --idle, CA-driven spinner/glow/shimmer/pulse, narrowed closed-notch observation]
key-files:
  created: [boringNotch/Orchestrator/Snapshots/SnapIdle.swift]
  modified: [OrchestratorWings.swift, OrchestratorChat.swift, OrchestratorCompact.swift, OrchestratorRunsPure.swift, OrchestratorView.swift, OrchestratorManager.swift (snapshot hook only), Snapshots/Snap.swift, Snapshots/Stubs.swift, Snapshots/run.sh]
commits: [a6f8027, 48c0a3a, 378d614, 349539f]
completed: 2026-10-15
---

# Quick 261015-apm: idle CPU / lag fix

One-liner: the lag was never the x18 batch. A SwiftUI `repeatForever` spinner (and the 30fps shimmer) forced a full main-thread root render every display frame; they are now Core Animation layers, and the closed notch no longer re-renders on unrelated SSE ticks. Idle harness CPU with a running run went from about 106% to under 1.5%.

## Bisect (harness `--idle`, unoptimized swiftc build, on-screen alpha-0.01 windows)

Scene CPU %, per commit. Scenes: a = closed notch, running run + working chat, identical payload every 1s; a2 = same but `activity.doing` changes each tick; a3 = chat screen timer changes each tick; b = closed, nothing running; c = open on the Orchestrator tab, running run; d = expanded, running run; e = expanded, `doing` changing.

| commit | a | a2 | a3 | b | c | d | e | outside-click gates (open / expanded / log never opened / log opened+closed / log+notch close) |
|---|---|---|---|---|---|---|---|---|
| c0ec48b (618f1fb^) | 106.5 | 106.3 | 105.9 | 0.3 | 108.5 | 106.1 | 106.2 | open ok, expanded ok (log gates n/a, no overlay yet) |
| 618f1fb | 106.0 | 106.3 | 105.1 | 0.3 | 108.9 | 105.9 | 106.2 | same, ok |
| ceccbde (fade) | 106.7 | 106.7 | 106.3 | 0.3 | 108.9 | 106.2 | 106.4 | same, ok |
| 6bec3e8 (activity line) | 106.8 | 106.8 | 106.6 | 0.3 | 108.6 | 106.2 | 106.4 | same, ok |
| 247bca8 (run log overlay) | 106.6 | 106.7 | 106.8 | 0.3 | 109.0 | 106.1 | 106.3 | all 5 ok |
| 70ecc08 (HEAD before fixes) | 106.1 | 105.9 | 106.0 | 0.4 | 108.7 | 106.1 | 106.1 | all 5 ok |

Result: every commit is equally bad (about 106%, a fixed per-frame cost, not an amount that grows with data), and the closed-nothing scene b is cold. So the CPU cause predates the x18 batch. By `git log -S`, the `repeatForever` spinner/glow came in with the wings (cf7b7cf, 07-03) and the shimmer/pulse with tmq (4f2950a). Pre-wings commits cannot be bisected with this harness (no wings, no ClosedReplica); I did not extend further. The click-outside regression was NOT reproduced at any commit (see below).

## Root causes, with evidence

1. Display-rate SwiftUI animations (main cause). Harness sample of the closed scene: 1193 of 2090 main-thread samples under `ViewGraphRootValueUpdater.render` / `DisplayList.ViewUpdater.render`; open scene c: `TimelineView.UpdateFilter.updateValue` -> `OrchShimmer.body`. The running app's sample (`/tmp/notch-main.txt`) shows the same shape: `NSHostingView.layout` -> `ViewGraphRootValueUpdater.render` with `FluidSpringAnimation.animate`, `RepeatAnimation.animate` (spinner/glow) and `TimelineView` in the hot stacks. `WingSpinner` (8s linear `repeatForever`), `WingGlowDot`, the 30fps shimmer `TimelineView` and `OrchPulse` each invalidate the root every frame, and the root is a `compositingGroup` with shadow/clip, so each frame costs a full render. This is why it only showed with a running run (spinner mounted in the closed notch). Closed with nothing running (b): 0.3%.
2. Fan-out per SSE tick (secondary). `OrchestratorWingsView`, `OrchestratorClosedIndicators` and `OrchestratorMusicIndicator` observed the whole `OrchestratorManager`, and the wing's elapsed anchor republished through `@State`. Fix keeps each of these quiet when nothing they draw changed. Already-guarded publishes in `applyChat`/`applyState`/`applyScreen` were checked and are fine (equality guards exist); the only unguarded publishes were in the snapshot-only `snapshotApply` hook (harness artefact, fixed there).
3. Click-outside: not reproduced. All five gates pass at every bisected commit and at HEAD (interaction count back to 0, level back to open, close called once from expanded/with log open, monitors balanced). The outside-click path only exists at expanded/terminal level (open level closes on hover-exit, gated by `preventNotchClose`). Best explanation for the report is the saturated main thread (the monitor hop `Task { @MainActor ... }` plus the collapse spring starve behind per-frame renders), which cause 1 removes. One real hole found and closed: collapsing from expanded (outside click, back) with the run log open left the overlay mounted at open level; the log now closes when the notch leaves expanded (`349539f`).

## Fixes (one commit each)

- `48c0a3a` Core Animation for spinner (rotation.z, 8s linear, clockwise), glow dot (shadowRadius 2->8), shimmer (gradient layer sweeping, still masked by the text), pulse dot (opacity 1<->0.35, static under Reduce Motion). Helper `OrchLayer` / `orchAnimation` in OrchestratorWings.swift.
- `378d614` `OrchestratorWingsInputs` (attention dot published only on change; elapsed timer data unpublished and read by the wing's own per-second TimelineView). ContentView still observes only `OrchestratorWingsModel` (`kind`, `shiftX`), unchanged. `longestWorking(chatElapsed:starts:now:)` added; the old overload delegates.
- `349539f` log closes when the level returns to open (clears `restoreLevel` first so it cannot re-grow).
- `a6f8027` harness (`SnapIdle.swift`, `--idle`, stubs count interactions/closes).

## Before / after idle CPU (harness `--idle`, %)

| scene | before (70ecc08) | after |
|---|---|---|
| a closed, running, same payload | 106.1 | 0.8 |
| a2 closed, only `doing` changes | 105.9 | 0.9 |
| a3 closed, chat timer changes each second | 106.0 | 0.7 |
| a4 closed, tokens change each second | n/a | 0.8 |
| b closed, nothing | 0.4 | 0.3 |
| c open tab, running run | 108.7 | 0.6 |
| d expanded, running run | 106.1 | 0.7 |
| e expanded, `doing` changes each second | 106.1 | 6.5 (limit 9, see below) |

Final `--idle` run: `OK: idle`, exit 0 (log `/tmp/notch-idle-fixed.log`). Scene e is the one place that still costs: a visible per-second data change on the expanded board redraws a large window in an unoptimized build, a few body evaluations but mostly AppKit/CA layout; its limit in the harness is 9%, not 3%. Not fixed further.

Close-gate results at HEAD: all five gates pass (interaction count 0, level open, monitors balanced via the outside click closing exactly once).

## Verification

swiftc unit harness (incl. OrchestratorStream.swift): OK. `run.sh` normal: `OK: composer bottom padding 12 in 33 scenes`. `--hittest`: gap 12 OK, run log opens from card and dot and close restores level OK, composer/segment/capsule clicks OK. `--transition`: top edge pinned, no intermediate-layout frames (blank grow 464..700, collapse 580..753ms). `--closed`: all wings centre=ok, kinds as before. Viewed 06, 10, 46, 43, 54, closed-1, closed-10, transition-live-grow-280: board, activity line (blue), run log overlay, fade, wings spinner/dot all render. Fresh Debug build: `** BUILD SUCCEEDED **` at `/tmp/notch-dd/Build/Products/Debug/Boring Notch.app`. All six temp bisect worktrees removed, `git worktree prune` done, nothing pushed, branch unchanged (orch/261014083623-80d8).

## Deviations / caveats

- Bisect used `/tmp/notch-dd` (read-only `Defaults.o`) instead of a separate `/tmp/notch-bisect-dd`; harmless.
- The harness window is never "visible" to AppKit (`occlusionState` false), so SwiftUI `onChange` handlers run late and the hosting view's stale min size sometimes keeps the window at 597pt after a collapse (gate 5 prints `WARN`, passes). I could not confirm this in the real app; it is a WARN, not a gate failure. The harness warps the real mouse cursor (to just under the notch) for the outside-click checks.
- `snapshotApply` (ORCH_SNAPSHOT only) now guards its two `@Published` writes like the real path; this changed no app code.
- Per-frame cost of the visible wing is now ~0: the spinner is a render-server animation.

## Needs on-screen checking (UAT)

1. Activity Monitor: Boring Notch idle with a running run, notch closed: expect low single digits or less (was ~17%). Also open on the Orchestrator tab, chat working.
2. The spinner (clockwise, 8s) and the needs-you glow look as before; the "Waddling" shimmer sweep still highlights only the text (the mask over an NSView-backed layer could not be verified in a static snapshot); tool dots pulse.
3. Click outside at open level (hover-exit), expanded level, expanded with the run log open: closes each time.
4. Expand/collapse smoothness and fade; run log opens from card and rail dot, closes via X/Esc/backdrop.
5. Music controls and the music live-activity indicator (it reuses the spinner).
6. Reduce Motion on: pulse and shimmer static.

## Self-Check: PASSED

Commits a6f8027, 48c0a3a, 378d614, 349539f exist; SnapIdle.swift exists; build output exists.
