---
status: complete
quick_id: 261014-f4d
---
# Summary

- `OrchestratorView.swift`: body is the chat tail at full width; the runs strip (unchanged look, 6 rows) is a top-trailing overlay panel (black 0.9, rounded, faint stroke) shown when `showRuns`. New `OrchestratorRunsButton` (30pt black capsule, `list.bullet.rectangle`, white when open); tap toggles, from another tab it switches to Orchestrator and opens the panel.
- `OrchestratorManager.swift`: `@Published var showRuns = false`.
- `BoringHeader.swift`: gear button block replaced by `OrchestratorRunsButton()` (shown regardless of `settingsIconInNotch`).
- Settings: menu-bar sparkle icon → Settings (⌘,), and right-click on the notch → Settings. Both pre-existing, unchanged. Caveat: if the menu-bar icon is hidden in Settings, right-click on the notch is the remaining path.

Checks: model test OK; xcodebuild (/tmp/notch-dd) BUILD SUCCEEDED. Not launched; visual check pending the user.
