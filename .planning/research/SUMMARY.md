# Project Research Summary

**Project:** Boring Notch — Orchestrator Fork
**Researched:** 2026-10-14
**Confidence:** MEDIUM-HIGH (repo hooks and API shapes verified from source and the live server; AppKit focus/resize and Claude Code prompt layout unverified)

## Executive Summary

Small feature on an existing app: one tab, one `@MainActor ObservableObject` singleton polling 127.0.0.1:4777, a closed-notch dot, and an expand-down mode with a ttyd terminal. System frameworks only (URLSession, Codable, Task loop, WKWebView via NSViewRepresentable). No entitlement or Info.plist change: `network.client` and `NSAllowsArbitraryLoads` already present. All code in a new `boringNotch/Orchestrator/` folder registered once as a `PBXFileSystemSynchronizedRootGroup` (like `boringNotch/private`, pbxproj:325), plus ~6 small hooks.

The hard parts are window behaviour, not networking: (1) notch windows hard-code `canBecomeKey = false`, so typing needs a gated override; (2) notch closes 100 ms after mouse exit — reuse `SharingStateManager.beginInteraction()/endInteraction()`; (3) window is fixed 640x210 and ContentView clamps to it — expand needs a top-anchored resize; (4) prompt detection by screen-scraping — the idle input box also starts with `❯`.

## Key Findings

### Stack
- Dedicated URLSession, ~3s timeout (offline shows fast). Codable with optional fields; run field is `state`; `resets_at` epoch seconds; `usage.at` may be stale/missing.
- One `Task` + `Task.sleep` poll loop, no overlap; ~2s open, ~10–15s closed; immediate poll after any POST; publish only on change.
- WKWebView at exactly `http://127.0.0.1:4777/term`; SwiftUI `WebView` unavailable (target macOS 14).
- Swift 5 mode, `ObservableObject` (match upstream). No new packages.
- Build: ad-hoc `CODE_SIGN_IDENTITY=-` (proven). Never `CODE_SIGNING_ALLOWED=NO` (drops sandbox).

### Features
- Table stakes: chat tail (trim 190-col padding, ~20 lines, lineLimit 1), runs strip (state dot, project[:ws], one-line prompt, ~4 rows), usage bars 5h/7d with relative reset, three states (offline / not running / no runs), one-line message box, prompt digit buttons + always-present Esc + double-tap guard, Start + End with inline confirm (no NSAlert — steals focus), attention dot, polling.
- Differentiators: expand-down larger chat, WKWebView `/term` (fallback for multi-select/>9 options), closed 5h usage indicator.
- Anti-features: Claude Code hooks, spawning processes, run controls in notch, auto-approve, ANSI emulator, multi-line composer, notifications, separate terminal window.
- ttyd runs `-m 1` (one client): create web view only while expanded; show "terminal in use" otherwise.

### Architecture
`OrchestratorClient` (HTTP, models, `x-orch: 1` header, 409 → not running) · `OrchestratorManager` (poll loop, state, `detectPrompt(screen)` pure fn, `needsAttention`, `wantsKeyboard`, expand state) · `OrchestratorTabView` · `OrchestratorClosedIndicator` · `OrchestratorTerminalView` + `NotchWindowResizer`.

| Hook | Location | Change |
|------|----------|--------|
| H1 | `enums/generic.swift:27` | `.orchestrator` case, appended last |
| H2 | `TabSelectionView.swift:17` | one tab entry |
| H3 | `ContentView.swift:347` | one switch case |
| H4 | `ContentView.swift:293` | closed indicator after music branch |
| H5 | `ContentView.swift:206` | relax height clamp |
| H6 | `BoringNotchSkyLightWindow.swift:112` | gated `canBecomeKey` |
| H7 | pbxproj | synchronized group |

Not touched: `BoringViewModel`, `boringNotchApp.swift`, `sizing/matters.swift`, `openNotchSize`, `MusicManager`, `Localizable.xcstrings` (use `Text(verbatim:)`).

### Critical Pitfalls
1. Panel can't become key — gate on `wantsKeyboard`, never unconditional, never `NSApp.activate`; return focus on close.
2. Notch closes mid-typing or sticks open — paired begin/endInteraction; release on submit, Esc, outside click, lock, close.
3. Prompt false positives / double sends — bottom-anchored rule: consecutive options from 1, exactly one `❯`, no input-box rule pair below; send digit only (no Enter); disable buttons until prompt clears or ~3s. Fixtures from real captures.
4. Music regression — enum case last, indicator after music branch; every phase's UAT includes a music check.
5. Traps — ad-hoc rebuilds can reset TCC (looks like broken music); Sparkle can install stock upstream over the fork (turn off auto-check).

## Implications for Roadmap

Dependency chain: build → manager → (input | indicators) → expand. Spike key-window early in the phase that first needs typing. Research flags: key-window on macOS 26, real prompt captures before finalising the matcher, window resize/multi-display/click-through and ttyd single-client for expand.

## Gaps
- Prompt fixtures not captured beyond idle — capture from live `GET /api/chat`.
- Tabs only render when Shelf is enabled (`BoringHeader.swift:19`) — document, or one extra hook.
- Whether the dot shows while music plays — default: music wins (no dot) in v1.
- Local Network prompt for loopback — expected none; verify on first run.

---
*Research completed: 2026-10-14 — full detail in STACK.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md*
