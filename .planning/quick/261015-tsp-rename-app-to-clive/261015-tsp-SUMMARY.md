---
quick_id: 261015-tsp
slug: rename-app-to-clive
date: 2026-10-15
status: complete
---

# Rename the app to Clive

## What changed
- `project.pbxproj` (app target, both configs): PRODUCT_NAME / CFBundleName / CFBundleDisplayName = Clive, product
  reference Clive.app. `PRODUCT_MODULE_NAME = Boring_Notch` added: it defaults to PRODUCT_NAME, so without it the Swift
  module would have become `Clive`. Bundle id stays `theboringteam.boringnotch` (Defaults, permissions, login item kept).
- UI text: menu-bar extra "Clive", "Restart Clive", "Clive Settings" window title, Welcome title "Clive", onboarding
  camera/calendar/reminders/accessibility copy, status-item accessibility label.
- Orchestrator tab label is "Orchestrator" (doesn't name the app): unchanged. About shows no app name: unchanged.

Not touched: credits ("Made with … not so boring not.people", GitHub links to TheBoredTeam/boring.notch), LICENSE,
README, .github CI/release workflows and their smoke test (they assert "Boring Notch"; upstream release tooling only),
Configuration/dmg, updater/appcast.xml, Localizable.xcstrings (its "Boring Notch"/"Restart Boring Notch" entries are
now unused; the new English strings show in every language), XPC helper, music.

## Check
- Unit harness (Models, Pure, Transcript, PromptParse, RunsPure, Stream, ComposerInput + Tests/*.swift): OK.
- Debug and Release (ENABLE_HARDENED_RUNTIME=NO, Release with ORCH_NO_SPARKLE) into ./build: BUILD SUCCEEDED;
  module is Boring_Notch.swiftmodule. Release copied to ./build/notch-rel/Clive.app (ad-hoc).
- Info.plist: CFBundleName/DisplayName/Executable = Clive, CFBundleIdentifier = theboringteam.boringnotch.
- grep for "Boring Notch" in tracked app code (excluding .github, docs, appcast, dmg, xcstrings): none.

UAT: the user's running /tmp/notch-current was not touched. Swapping to Clive.app is a new app path: macOS may ask
again for Accessibility/Camera (TCC keys on path + signature), and the login item points at the old app path.
