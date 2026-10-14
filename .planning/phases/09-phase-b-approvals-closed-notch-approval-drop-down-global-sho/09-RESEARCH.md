# Phase 9: Phase B Approvals - Research

**Researched:** 2026-10-14
**Domain:** Carbon global hotkeys (sandboxed), Claude Code hooks, NSPanel frame sizing
**Confidence:** HIGH on hotkeys/frame, MEDIUM on hook payload (docs excerpt, not run)

<user_constraints>
## User Constraints (from 09-CONTEXT.md)
Locked: D-01..D-08, S-01..S-07 as written in 09-CONTEXT.md (approval from stream `approval` event only; answer via existing `POST /api/chat {key}` after freshness re-check; frame 00 drop-down; approval drops over music; hotkeys via installed KeyboardShortcuts, registered only while pending; panel follows content, top edge pinned, minimal hooks; never POST to :4777; no app launch; no new deps; music must not regress; no push).
Discretion: how the drop-down is hosted, within D-08's minimum-hook rule.
Deferred: per-run Allow/Deny; Settings UI for rebinding.
</user_constraints>

<phase_requirements>
| ID | Support |
|----|---------|
| APR-01 | Hook section: use `PermissionRequest` (exists in installed 2.1.299). Contract corrections below. |
| APR-02 | Hosting section: render in ContentView closed branch; fits existing 640 window, no resize needed. |
| APR-03 | Hotkey verdict: KeyboardShortcuts, no permission, Option-only OK on macOS 26. |
| APR-04 | Frame section: one sizer driven by `vm.notchSize.height`, replaces `extra`/grow/shrink bookkeeping. |
</phase_requirements>

## Summary
**Hotkeys.** KeyboardShortcuts calls Carbon `RegisterEventHotKey` (CarbonKeyboardShortcuts.swift:137). No Accessibility or Input Monitoring permission, works sandboxed [VERIFIED: package source]. Its Option-only restriction (`Shortcut.isDisallowed`) is gated to `macOS 15.0 and 15.1` AND sandboxed only (Shortcut.swift:107-125); Recorder.swift:42 documents the same. We run 26.6.2, so the restriction does not apply [VERIFIED: source]. Empirical: a throwaway CLI (/tmp/hk/hk.swift) on macOS 26.6.2 got `noErr` (0) for Option+Return, Option+Escape, Option+Shift+Return, Ctrl+Option+Return/Escape, and even bare Escape [VERIFIED: ran; caveat: CLI is NOT sandboxed, so this proves the OS accepts the combos, not the sandbox path; the sandbox gate is only documented for 15.0/15.1]. Escape is registrable with a modifier. Recommend **⌥⏎ / ⌥⎋** as decided. Safety net: if `ProcessInfo` says macOS 15.0 or 15.1, use ⌃⌥⏎/⌃⌥⎋ and the matching button labels (deployment target is 14, so the user could in principle be there; tiny pure function, assert-testable). Note the package's `isDisallowed` is internal, so re-implement the 3-line check.

**Hooks.** Claude Code 2.1.299 documents `PermissionRequest` [CITED: code.claude.com/docs/en/hooks]. It fires when the permission dialog is about to show. Payload: common fields (`session_id`, `transcript_path`, `cwd`, `permission_mode`, `hook_event_name`) + `tool_name`, `tool_input`, optional `permission_suggestions`. **It has NO `tool_use_id`.** Exit 0 with no output leaves the normal dialog in place (never decides). So no Notification+PreToolUse fallback is needed. `PostToolUse` and `PostToolUseFailure` carry `tool_use_id`; `PreToolUse` too. **No hook fires when the user denies the dialog** (`PermissionDenied` is auto-mode only; `PostToolUseFailure` does not fire on permission denial) [CITED: same page]. Not run live in this session: confirm payload with one logged real event during the serve dispatch.

**Frame.** Window is 640x210 (`windowSize`), borderless nonactivating `BoringNotchSkyLightWindow`. 460px and ~150px tall drop-down fit inside it without any resize. APR-04 is then just: window height = f(`vm.notchSize.height`), set in one place.

**Primary recommendation:** register hotkeys with `KeyboardShortcuts.onKeyDown` once at start, then `enable/disable` the two names on approval set/clear; host the drop-down as a new branch at the top of ContentView's closed-notch `NotchLayout` chain; size the window from `vm.notchSize` through one small sizer replacing `OrchestratorExpand.extra`.

## Contract corrections for 09-CONTEXT.md serve_contract
1. **`id`**: `PermissionRequest` has no `tool_use_id`. Use hash of `session_id + tool_name + canonical JSON(tool_input)` (what the contract already names as fallback; make it the primary). Same command asked twice in a row gets the same id; acceptable, because the gate also checks the screen prompt.
2. **Clearing**: `PostToolUse` / `PostToolUseFailure` have `tool_use_id` but the pending id does not, so match by recomputing the hash from `tool_name`+`tool_input` in that payload, or simply clear on any `PostToolUse`/`PostToolUseFailure`/`Stop` for the chat session (simplest; approvals serialize per session). `PreToolUse` is not needed.
3. **Denied/answered in terminal**: no hook reports it. Serve's own "screen no longer shows a prompt for >2s" clear is therefore REQUIRED, not optional (it is the only clear for a user deny). Notch must also locally clear on its own answer (see D-05).
4. **Hook can be async**: command hook with `"async": true` so Claude never waits on it (docs: async hooks run in background, timeout unenforced). Keep the contract's "1s timeout, exit 0, no output" inside the script as well.
5. **`http` hook type exists** (`type:"http"`); a node script is still fine and lets serve require `x-orch: 1` header. Docs excerpt did not cover http header config, so keep the script.
6. Serve currently has no `approval`/`api/hook` in orch.js (grep clean); Phase 8 SSE is also not there yet. Phase 9 notch work should decode `approval` as optional and treat absence as null.

## Architectural Responsibility Map
| Capability | Primary | Secondary | Rationale |
|---|---|---|---|
| Detect pending approval | Claude Code hook -> serve | notch (decode only) | D-01, never screen-infer |
| Answer | notch -> `POST /api/chat {key}` | serve | existing endpoint |
| Global shortcut | notch app (Carbon) | - | in-process, sandbox ok |
| Drop-down UI | ContentView closed branch | OrchestratorManager state | music-wins exception |
| Panel frame | NSPanel `setFrame` driven by SwiftUI size | - | AppKit owns window |

## Standard Stack
No new packages. `KeyboardShortcuts` (already resolved in SPM checkout) [VERIFIED: checkout present]; URLSession/Codable via `OrchestratorManager`. Package Legitimacy Audit: no new installs, not applicable.

## Architecture Patterns

### Flow
```
Claude Code PermissionRequest -> hook script -> POST /api/hook (serve) -> approval {id,tool,command,...}
  -> SSE/GET /api/chat -> OrchestratorManager.approval (@Published)
     -> ApprovalCenter: enable hotkeys (⌥⏎/⌥⎋) + ContentView drop-down branch (closed notch)
  -> Allow/Deny (button or hotkey) -> gate: refresh(fresh:true); id still current && prompt on screen
     -> POST /api/chat {key:"1"|"Escape"} -> clear local approval optimistically -> hotkeys disabled
```

### Hotkeys (APR-03)
```swift
// new file OrchestratorApprovalKeys.swift (names follow ShortcutConstants.swift pattern)
extension KeyboardShortcuts.Name {
    static let approvalAllow = Self("orchApprovalAllow", default: .init(.return, modifiers: [.option]))
    static let approvalDeny  = Self("orchApprovalDeny",  default: .init(.escape, modifiers: [.option]))
}
// once: KeyboardShortcuts.onKeyDown(for: .approvalAllow) { ... }; then disable immediately
// pending set: KeyboardShortcuts.enable(.approvalAllow, .approvalDeny); cleared: .disable(...)
```
- `enable/disable` (KeyboardShortcuts.swift:233-266) register/unregister the Carbon hot key, so keys are free for other apps when idle [VERIFIED: source]. `onKeyDown` registers immediately; call `disable` right after to start idle. Existing repo precedent: boringNotchApp.swift:355,369.
- `Name` default is stored in UserDefaults on first use; a pre-existing stored value would win. Names are new, so fine. If macOS 15.0/15.1 fallback is used, `setShortcut` the ctrl+opt variants at start (pure `approvalShortcutMods(os:)`).
- Handler must go through the same answer gate as the buttons; ignore if no approval pending (hotkey race right after clear).
- Side effect to tell the user: while pending, ⌥⏎/⌥⎋ are swallowed system-wide (Return with Option has no common global meaning, ok). Registration failure only logs (`print`), so expose no hard dependency; buttons remain.

### Hosting the drop-down (APR-02, Claude's discretion)
Add one branch in ContentView `NotchLayout` closed chain, placed BEFORE the music branch (`MusicLiveActivity`) and after battery/HUD: `else if vm.notchState == .closed && !vm.hideOnClosed && approval != nil { OrchestratorApprovalPanel() }` (new file). No new NotchState. Pieces to handle (each a one-line hook):
- **Shape/radius**: `currentNotchShape` uses closed bottom 14; frame 00 wants 22 -> pass 22 when approval shows (one conditional in that computed property, mirrors the `R.notchExpanded` precedent already there).
- **Width 460**: inner view `.frame(width: 460)`; window is 640 so it fits; `computedChinWidth`/music branch not involved.
- **Hover-open**: `handleHover` opens the notch after `minimumHoverDuration` while closed; hovering the panel would swallow it into the open notch (D-05 says it should stay). Add `approval == nil` to the guard at ContentView:533-535. `onTapGesture { doOpen() }` on the layout would also fire on tapping empty panel areas; the buttons are SwiftUI `Button`s so they take their own taps; acceptable, "More…" calls `coordinator.currentView = .orchestrator; doOpen()` explicitly.
- **Music coexistence (Q4)**: the chain is exclusive if/else, so the approval branch simply replaces `MusicLiveActivity` while pending; music state lives in `musicManager`/coordinator and is untouched, the live activity re-appears when the branch drops. Wings branch (`OrchestratorWingsView`) is also hidden while approval is shown (good: the approval supersedes the "needs you" wing). `OrchestratorClosedIndicators` overlay: hide while approval shows to avoid a dot over the panel.
- **Height**: closed content is `.frame(height: nil)` (ContentView:~92 only fixes height when open), so the panel naturally grows to content (~30+14+10+row+cmd block+10+30+14 ≈ 150 < 190). `vm.notchSize` is not changed for the closed state, so the sizer sees no change; no window resize. Command text must clamp (`lineLimit(3)`, 300 char cap from contract) to keep within 210 window height; with >~190 tall content the clamp is needed or add the sizer floor.
- **Open notch**: if the user opens the notch while an approval is pending, branch is skipped (`notchState == .open`), the Phase 6 screen-parsed card handles it; hotkeys stay enabled and still answer (global). On answered, collapse nothing.
- **Hit-testing/click-through**: window never ignores mouse; drop-down content is opaque black and clickable. Window is nonactivating and `canBecomeKey` only for the keyboard window, so buttons work without stealing focus (SwiftUI Buttons in a non-key nonactivating panel receive the first click; same as existing closed-notch tap). Outside the black shape the hosting view's transparent area is already not-hit (Snap.swift `--hittest` harness from Phase 3 covers this; extend with the drop-down case).

### Panel frame sized to content (APR-04)
Today: `windowSize` 640x210 fixed at creation (boringNotchApp.swift:235); `OrchestratorExpand.grow` computes `extra` (≤300 via `expandedExtra`), `setFrame(pinnedFrame(...windowHeight(...)))` immediately; `collapse` shrinks after a 650ms sleep so the spring finishes; `reset` is immediate; `notchRootFrame` makes the SwiftUI root fill the window top-aligned so the notch top never slides (cdaa3ed).
Recommended minimum hook:
1. Pure function in OrchestratorPure.swift: `panelHeight(notchHeight:) = max(windowSize.height, notchHeight + shadowPadding)` (equals `windowHeight(base:notchHeight:openHeight:)` for all current cases, so existing asserts keep passing; add asserts for the new form).
2. One sizer (an `OrchestratorExpand` method, not a new type): `func fit(vm:window:)` that grows immediately / shrinks after 650ms, using `pinnedFrame`. Call it from a single `.onChange(of: vm.notchSize.height)` in ContentView (needs the window: reuse `register(vm:anchor:)` view-anchor already used for key handling) instead of from `grow/collapse/reset`. Delete the `extra` dictionary; `openSize(for:)` becomes `vm.notchSize` driven by level.
3. `notchRootFrame` already derives from `notchHeight`; unchanged.
Rejected: `NSHostingView.sizingOptions=.preferredContentSize` / `NSHostingController` auto-resize: window changes then lag the spring, risks top-edge slide and fights `positionWindow`; also bigger diff to boringNotchApp.swift. Rejected: separate approval window (new window per screen, SkyLight/space handling).
Because the closed drop-down fits the existing window, APR-04's behavioural requirement is satisfied by step 2 for open/expanded/terminal, and the drop-down needs the same sizer only if it ever exceeds 190pt (add the call for safety: drive via `vm.notchSize` is not used for closed, so also `fit` with `max(notchHeight, approvalPanelHeight)`; keep a floor of `windowSize.height`). Music sizing unchanged because the floor equals today's height. Keep `isOutsideNotch` using `vm.notchSize` as today.

## Don't Hand-Roll
| Problem | Use | Why |
|---|---|---|
| Global hotkeys | KeyboardShortcuts enable/disable | already a dep, no permission |
| Stale-answer guard | `OrchestratorManager.refresh(fresh:true)` then compare id | existing pattern |
| Keypress | `OrchestratorManager.post(.key(...))` / `pressOption` | existing, has lock |
| Top-pinned resize | `pinnedFrame` | existing, tested |

## Common Pitfalls
1. **Stale keypress into input box** (hotkey fires after approval resolved in terminal): gate on fresh read; `optionsLocked` semantics from `pressOption` apply to Allow only if reused; Deny `Escape` has 1s debounce in `pressEscape`, do NOT reuse it for Deny if the debounce could drop a legitimate Deny; post `.key("Escape")` directly through the gate.
2. **Allow digit**: contract says first option `"1"`. PermissionRequest dialogs for Bash always list "1. Yes", but option text varies (e.g. "Yes, and don't ask again" is 2). `1` = plain Yes; verify against screen option 1 label in the gate (screen parser `OrchestratorPromptParse` already yields options; read-only use, do not edit it).
3. **Deny leaves no hook**: do not wait for serve to clear; clear locally on successful POST and ignore the same `id` re-arriving for ~3s (otherwise a poll in flight re-shows the panel).
4. **Hover-open** swallowing the drop-down (above).
5. **Hotkey re-registration leaks**: use `enable/disable` toggling, not repeated `onKeyDown`.
6. **Multiple screens**: one view per screen renders the branch; hotkeys are app-global and bound once in the manager, not per ContentView.
7. Hook output: PermissionRequest hooks that print a `decision` would answer for the user; the script must print nothing.

## Code Examples
Gate (pure, assert-testable):
```swift
func approvalAnswerAllowed(current: String?, answering: String, screenHasPrompt: Bool) -> Bool {
    current == answering && screenHasPrompt
}
func approvalShortcutMods(os: OperatingSystemVersion) -> Bool /* true => use ctrl+opt */ {
    os.majorVersion == 15 && os.minorVersion <= 1
}
```
Model: `struct OrchestratorApproval: Decodable, Equatable { let id: String; let tool: String?; let command: String?; let description: String?; let at: String? }` — all optional except id; `approval` optional on chat/state models.

## Validation Architecture
Framework: existing swiftc assert harness (Orchestrator/Tests, Snapshots/run.sh) plus xcodebuild per S-02. Add: approval decode (present/null/absent/extra fields), `approvalAnswerAllowed`, `approvalShortcutMods`, `panelHeight` equivalence with `windowHeight` for current inputs. Snap harness: add drop-down render and `--hittest` case. Manual (user): ⌥⏎/⌥⎋ with real approval, music playing during approval, notch top edge steady on expand. Quick run: the harness script; full: xcodebuild command from S-02.

## Security Domain
V5 input validation: decode defensively, cap `command` display (300 chars, lineLimit); never execute or interpolate `command`. Answer only via fixed keys `"1"`/`"Escape"` with `x-orch: 1`; loopback only. No new permissions or entitlements (network.client already present). A forged approval event cannot cause more than a displayed prompt, since Allow presses "1" only when the real screen shows a prompt (gate), so keep the screen check mandatory.

## Assumptions Log
| # | Claim | Risk |
|---|---|---|
| A1 | Sandboxed app on macOS 26 accepts Option-only (CLI test was unsandboxed; sandbox gate only documented for 15.0/15.1) | If rejected, Allow/Deny hotkeys silently fail; buttons still work; fallback combo ready. Verify on first run (log shows "Error registering hotkey"). |
| A2 | PermissionRequest payload matches docs (no live capture) | id derivation/clearing; capture one real payload in the serve dispatch |
| A3 | Hover-open guard and branch ordering give the desired look on notchless external displays | cosmetic |
| A4 | Drop-down content stays < 190pt tall with clamped command | window clipping if not |

## Open Questions (RESOLVED)
1. D-04 (approval drops over music): RESOLVED for planning — implemented as written; user confirmation requested in the planning report.
2. RESOLVED (09-CONTEXT R-04): Phase 8 SSE and serve `approval` do not exist yet in orch.js; Phase 9 notch work should be built against the contract with polling `GET /api/chat` `approval` as the minimum path.

## Environment Availability
Xcode and swiftc present (CLI test compiled/ran). macOS 26.6.2, Claude Code 2.1.299. No other dependencies.

## Sources
- KeyboardShortcuts source in DerivedData checkout: Shortcut.swift:107-125, CarbonKeyboardShortcuts.swift:137, Recorder.swift:42, KeyboardShortcuts.swift:233-266 (HIGH)
- /tmp/hk/hk.swift empirical RegisterEventHotKey run (HIGH for OS, caveat unsandboxed)
- https://code.claude.com/docs/en/hooks (MEDIUM: page fetched via summarizer, ~2/3 read)
- Repo: ContentView.swift, boringNotchApp.swift:235, OrchestratorExpand.swift, OrchestratorPure.swift, OrchestratorManager.swift, BoringNotchSkyLightWindow.swift:112

**Valid until:** 2026-11-14
