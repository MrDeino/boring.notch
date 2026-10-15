---
quick_id: 261015-me5
slug: claude-update-ready-restart
date: 2026-10-15
status: complete
---

# Claude update ready · Restart

## What changed
- `OrchestratorModels.swift`: `ChatResponse.claude: ClaudeInfo?` (running/installed are version strings; every field
  lossy, so an old serve or a malformed value leaves it nil and never fails the chat decode).
  `OrchestratorPost.restart(force:)` posts `{}` or `{"force":true}` with x-orch/JSON headers. Pure helpers
  `claudeUpdateBadge`, `claudeRestartPhase(afterPost:)` (200 restarting, 409 busy, else idle), `claudeRestartOnChat`.
- `OrchestratorManager.swift`: publishes `claude` from each chat payload (poll and SSE `chat`; the separate SSE
  `claude` event is ignored since `chat` carries the same object). `claudeRestart` state: askRestart -> confirming,
  restartClaude(force:) -> restarting/busy/idle, restarting ends on the first chat payload that says running (30 s cap).
  After a 200 the badge stays hidden for the installed version we restarted onto: serve's `running` comes from the
  transcript and stays on the old version until the new session writes to it.
- `OrchestratorWings.swift`: the closed-notch attention dot also lights for a ready update (not the "Needs you" wing).
- `OrchestratorStatusCapsule.swift` (header file): `OrchestratorUpdateBadge` — badge, "Restart Claude? Restart /
  Cancel", "Claude is busy — restart when idle · Restart anyway / Cancel", "Restarting Claude…".
- `OrchestratorView.swift`: one `.overlay(alignment: .top)` line puts it just under the header. The header row itself
  has no spare width at the open size (tabs + Chat|Runs on the left, capsule + notes on the right).

Not touched: OrchestratorExpand(ed).swift, ContentView.swift, Snapshots/, composer/send path, music.

## Check
- swiftc unit harness (incl. OrchestratorStream.swift, new `QuickClaudeTests.swift`): OK.
- `ORCH_RESTART_MOCK=1` against `Tests/restart-mock.py` (47999, never 4777): old serve without `claude` -> no badge;
  badge shows; asking posts nothing; confirmed restart posts `{}` -> restarting -> running -> idle, badge hidden;
  busy serve -> 409 -> busy, nothing restarted -> Restart anyway posts `{"force":true}` -> 200 -> cleared; all
  requests carry x-orch: 1 + application/json. OK, port free afterwards. RED check: dropping the force body fails it.
- Debug and Release (ENABLE_HARDENED_RUNTIME=NO, ORCH_NO_SPARKLE) into ./build: BUILD SUCCEEDED; Release copied to
  ./build/notch-rel.

Ran directly (no planner/executor agents). Not rendered in the snapshot harness (Snapshots/ is another run's).
UAT: badge placement/width under the header at the open and expanded sizes, closed dot, restart round trip on the
real serve. The running notch (/tmp/notch-current) was not launched or quit.
