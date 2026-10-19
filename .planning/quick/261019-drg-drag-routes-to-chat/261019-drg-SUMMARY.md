---
status: complete
---
# Quick 261019-drg summary

- Cause: the global DragDetector (boringNotchApp `handleDragEntersNotchRegion`) always switched to the shelf, and a closed notch resets its tab, so "current tab" was never Orchestrator on a closed drag.
- Fix: `BoringViewCoordinator.lastUsedView` (set in `BoringViewModel.close`) + `dragsGoToChat` (`orchestratorOwnsDrops(orchestratorIsCurrentTab:lastUsedIsOrchestrator:)`). Detector, ContentView closed-drag open and the closed drop all route by it; shelf only when another tab is current/last-used.
- Folders: `orchestratorHandleURLs` adds a failed chip "Folders not supported" (any drop/paste path); files dropped with it still upload.
- Tests: routing for both tab states and folder chip (QuickFilesTests, synthetic). Unit + ORCH_FILE_MOCK OK; run.sh and --idle OK; Debug and Release builds succeeded (Release at build/notch-rel/Clive.app).
- Not covered: real Finder drag hit-testing in the live app.
