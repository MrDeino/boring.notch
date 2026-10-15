---
quick_id: 261015-tsp
slug: rename-app-to-clive
date: 2026-10-15
---

# Rename the app to Clive

Goal: the app shows as "Clive" wherever the user sees its name; bundle id, project, targets, module, folders and types unchanged.

1. pbxproj (app target, Debug + Release): PRODUCT_NAME, INFOPLIST_KEY_CFBundleName/DisplayName = Clive; product reference -> Clive.app; PRODUCT_MODULE_NAME pinned to the old `Boring_Notch` so the Swift module does not follow the product name.
2. UI text: menu-bar extra title, "Restart Clive", Settings window title, Welcome title, onboarding permission copy, status-item accessibility label.
3. Keep: bundle id, credits/GitHub links/"Made with … not so boring not.people", LICENSE, .github CI, dmg scripts, appcast, Localizable.xcstrings (upstream files).
4. Check: unit harness OK; Debug + Release into ./build (ENABLE_HARDENED_RUNTIME=NO, ORCH_NO_SPARKLE for Release); Release copied to ./build/notch-rel/Clive.app; Info.plist name Clive, id theboringteam.boringnotch.
