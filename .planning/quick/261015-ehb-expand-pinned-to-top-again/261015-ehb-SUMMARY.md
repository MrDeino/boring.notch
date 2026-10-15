# Quick 261015-ehb: expand pinned to the screen top again

## Root cause
`OrchestratorExpand.animate()` set `vm.notchSize` inside `withAnimation(.spring)` and then grew the panel with `setFrame(..., display: true)`. The window resize landed in the spring's transaction, so SwiftUI animated the root from the vertical centre of the new, taller window up to the top. The notch filled in from the middle instead of growing down.

Evidence (new panel-hosted `--transition` pass, screen height 982):
- At HEAD: window top and host top stay at the screen top, but the shape top is 788.5 at t=23ms (193pt below the top, about 190pt tall, centred in the 609pt window). It reaches 982 at about 350ms.
- Same result with default `sizingOptions` (`TRANSITION_DEFAULT_SIZING=1`), so `fdb2f65` is not the cause.
- The old check could not see this. It measured host-local coordinates with a plain `NSWindow`, no animation, and no `syncWindow`.
- No bisect was needed.

## Harness (commit 2cc1eb5)
The `--transition` live pass now hosts the notch like the real panel:
- panel style mask, level `.mainMenu+3`, `sizingOptions = []`
- ContentView's root chain with the `onChange -> syncWindow` hook
- dense ~16ms samples of window top, host top, shape top and shape bottom in screen space
- hard FAIL if the top leaves the screen top, or the bottom moves the wrong way

The old line is renamed "root-frame-only check". The harness failed at this commit, as required (grow t~25ms: shape top 788.5).

The window level matters. Without it AppKit pushed the panel 33pt below the menu bar, which gave a false window-top failure.

## Fix (commit eab2b2c)
`OrchestratorExpand.swift` only. `animate()` now calls `syncWindow(vm:size:)` before the spring. That call is grow-only and runs outside the animation. The model change and the existing `syncWindow` call follow, so the shrink stays deferred 650ms. `syncWindow` is still the only `setFrame` path. The fade logic and `sizingOptions = []` are untouched.

## Results
- swiftc unit harness: OK.
- `run.sh` normal: `OK: composer bottom padding 12 in 33 scenes`.
- `--hittest`: all 3 OK.
- `--transition`: root-frame-only OK; screen-space top edge pinned through grow and collapse OK; no intermediate-layout frames OK (blank grow 622..865ms, collapse 576..753ms).
- `--closed`: ran clean (wings centre=ok).
- `--idle`: OK, including the outside-click gates and window frame == panelSize (640x210, min size 0) after collapse.
- Viewed `transition-live-grow-120.png` and `transition-live-collapse-450.png`: the shape hugs the top, grows down only, and the content is blank mid-grow (fade intact).
- Fresh Debug build: `** BUILD SUCCEEDED **` at `/tmp/notch-dd/Build/Products/Debug/Boring Notch.app`.
- No bisect worktrees were created. Nothing pushed. Branch unchanged.

## Caveat
The collapse dense samples are sparse (main thread starved by capture). The top edge held in every sample taken, but not at 16ms spacing.

## Check on screen
- Open Orchestrator, then expand (tap transcript or Cmd-Down). The notch top stays at the screen edge and it grows downward only.
- Cmd-Up or an outside click: it shrinks upward, then clicks below the notch reach other apps.
- Music open/close looks the same as before.
