# Phase 2: Sending & Prompt Answers - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator brief (user-approved dispatch) + real screen captures + server source read

<domain>
## Phase Boundary

From the Orchestrator tab the user can: type a one-line message and send it with Enter; tap numbered prompt options (digit sent); press an Esc control; Start the chat when it is not running; End it after an inline confirm. The notch window takes keyboard input only while the message box needs it. Music must not regress. Expand-down, closed-notch indicators and the /term terminal are Phase 3 — out of scope.

</domain>

<decisions>
## Implementation Decisions

### Server API (verified by reading orch.js cmdServe, lines ~514-580)
- D-01: All POSTs go to `http://127.0.0.1:4777` with headers `x-orch: 1` and `Content-Type: application/json`. Host header must be `127.0.0.1:4777` or `localhost:4777` (server returns 403 otherwise) — URLSession sets it from the URL automatically.
- D-02: `POST /api/chat {"text": "..."}` types the text and presses Enter (server adds Enter after 150ms). Empty/whitespace text → 400; never send it. Newlines are collapsed by the server; the box is one line anyway.
- D-03: `POST /api/chat {"key": "<k>"}` presses one key. Allowed keys exactly: `Enter`, `Escape`, `Up`, `Down`, `Tab`, `1`..`9`. Anything else → 400. Option buttons send the digit string (`"1"`..`"9"`); the Esc control sends `"Escape"`.
- D-04: `POST /api/chat` returns 409 when the chat is not running → treat as "not running" (refresh; Start shows), not an error banner.
- D-05: `POST /api/chat/start` (body `{}`) starts the tmux session if absent; `POST /api/chat/stop` (body `{}`) kills it. Both return 200 `{}`.
- D-06: After any successful POST, trigger an immediate `refresh()` so the result shows without waiting for the 2s poll.

### Message box (INT-01, INT-06)
- D-07: One-line text field at the bottom of the chat area in `OrchestratorView`, shown only when online and `chatRunning`. Enter sends (D-02), clears the field on success, keeps the text on failure. Placeholder like "message orchestrator".
- D-08: While the message box is focused/being typed in, the notch must not close. Reuse the existing `SharingStateManager.shared.beginInteraction()` / `endInteraction()` (it drives `preventNotchClose`, which `BoringViewModel.close()` and ContentView's hover-close already respect). Balance begin/end exactly (end on submit, Esc, focus loss, tab switch, view disappear) — never leave it stuck on.

### Keyboard focus — the spike (success criterion 1)
- D-09: The notch panel is `BoringNotchSkyLightWindow` (NSPanel, `.nonactivatingPanel`) with `override var canBecomeKey: Bool { false }` (boringNotch/components/Notch/BoringNotchSkyLightWindow.swift:112). Gate it: `canBecomeKey` returns true only while the Orchestrator message box wants keyboard (a flag owned by the Orchestrator code, e.g. `OrchestratorManager.shared.wantsKeyboard`). Keep that edit to the existing file tiny (one line or so). `canBecomeMain` stays false. Never call `NSApp.activate` — the panel is non-activating so keystrokes reach it without activating the app.
- D-10: Flow: user clicks the message box → set flag true → `window.makeKey()` → focus the field. On submit, Esc in the field, notch close, tab switch, or outside click: flag false and give up key (e.g. `resignKey()` / let it lapse) so the notch never steals typing otherwise. Executor must verify the approach compiles; runtime behaviour is checked by the user (human UAT item).

### Prompt options (INT-02, INT-03)
- D-11: Real screens captured 2026-10-14 from Claude Code v2.1.296 in a throwaway tmux session (190x50, `capture-pane -p -J`), saved as `boringNotch/Orchestrator/Tests/fixtures/question.txt` (AskUserQuestion) and `permission.txt` (Bash permission). Key facts:
  - AskUserQuestion: `❯ 1. apple` then an indented description line `     Apple` under each option, `  4. Type something.`, then a `────` separator line, then `  5. Chat about this`, footer `Enter to select · ↑/↓ to navigate · Esc to cancel`. The current `detectPrompt` resets its run on the description line, so it FAILS on this screen — must be fixed.
  - Permission: ` Do you want to proceed?` / ` ❯ 1. Yes` / `   2. Yes, and always allow access to … from this project` / `   3. Yes, and switch to auto mode · …` / `   4. No`, footer ` Esc to cancel · Tab to amend`. Lines have a leading space; `╌╌╌` dashed rules appear above.
  - The marker is `❯` followed by one space; trailing spaces pad lines to the pane width.
  - The live `/api/chat` screen is `capture-pane -p -J -S -200` (includes scrollback), so detection must only consider the bottom of the screen (keep the suffix window).
- D-12: Tune `detectPrompt` so both fixtures yield all options in order (question: 1 apple, 2 banana, 3 cherry, 4 Type something., 5 Chat about this; permission: 1–4 with their labels), while the idle input box (existing `box` test), a plain `1. foo / 2. bar` list without `❯`, and a lone `❯ 1. x` still yield `[]`. Non-option lines between consecutive options (indented descriptions, `─`/`╌` rules) must not break the sequence; only numbers 1–9 are usable (D-03).
- D-13: When `promptOptions` is non-empty, show a row of buttons (number + truncated label) plus an Esc button. Tapping sends the digit once: disable all option buttons while a send is in flight and until the screen/prompt changes (or a short timeout), so a double tap cannot send twice.
- D-14: The Esc control is shown alongside the options (and may also be shown whenever the chat is running — Claude's discretion), sends `{"key":"Escape"}`.

### Start / End (INT-04, INT-05)
- D-15: When online and `!chatRunning`, replace "chat not running" with that text plus a Start button → `POST /api/chat/start`.
- D-16: When running, an End control asks for inline confirmation (e.g. button turns into "End chat? Yes / No" in place) before `POST /api/chat/stop`. No modal alerts/windows. Confirm state resets after a few seconds or on No.

### Testing (hard rules)
- D-17: NEVER send POSTs to the live orchestrator at 127.0.0.1:4777 during testing (it types into the user's real chat or kills it). GETs to 4777 are fine. Test the POST client against a small mock HTTP server on another port (e.g. python3 one-file server on 127.0.0.1:4799 in /tmp) that records method, path, headers and body. This means the POST code must accept a base URL (default `OrchestratorManager.baseURL`) so the test can point it elsewhere.
- D-18: Tests stay in the existing assert-style harness `boringNotch/Orchestrator/Tests/main.swift` (compiled with swiftc together with the Foundation-only Orchestrator source files; not part of the Xcode target). Add the two real-screen fixtures as detectPrompt cases (load via path relative to `#filePath`). Keep the POST request builder/sender Foundation-only so it can be compiled into that harness.

### Constraints (from brief + PROJECT.md)
- Keep the diff to upstream small: new code in `boringNotch/Orchestrator/`, minimal hooks into existing files (the `canBecomeKey` gate is the only expected new hook).
- Don't break music.
- Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug -derivedDataPath /tmp/notch-dd CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build` (ad-hoc; keep entitlements; don't use CODE_SIGNING_ALLOWED=NO).
- Don't launch apps. Never push. Stay on the current branch; don't create or switch GSD phase/milestone branches.
- No new packages; HTTP only, never spawn processes from the app.

### Claude's Discretion
- Exact layout/sizes of the message box, buttons, Start/End inside the 640x190 notch (chat tail may lose a line or two).
- Whether the Esc button is always visible while running or only with a prompt.
- Whether POST helpers live in OrchestratorModels.swift or a new small file (if new, add it to the pbxproj Orchestrator group like the existing three).

</decisions>

<canonical_refs>
## Canonical References

- `boringNotch/Orchestrator/OrchestratorManager.swift` — polling manager, session, refresh()
- `boringNotch/Orchestrator/OrchestratorModels.swift` — detectPrompt, PromptOption
- `boringNotch/Orchestrator/OrchestratorView.swift` — tab UI
- `boringNotch/Orchestrator/Tests/main.swift` + `Tests/fixtures/*.txt` — assert harness and real screens
- `boringNotch/components/Notch/BoringNotchSkyLightWindow.swift:112` — canBecomeKey
- `boringNotch/models/SharingStateManager.swift` — beginInteraction/endInteraction/preventNotchClose
- `boringNotch/models/BoringViewModel.swift:190-220` — open()/close() hooks
- `/Users/mitch/Documents/Claude/orchestrator/orch.js` lines ~514-580 — server chat API (read-only reference, outside this repo)

</canonical_refs>

<deferred>
## Deferred Ideas

- Closed-notch attention dot, expand-down, live /term terminal — Phase 3.
- Arrow-key navigation / free-text answers to AskUserQuestion beyond tapping "Type something." — not requested.

</deferred>

---

*Phase: 02-sending-prompt-answers*
*Context gathered: 2026-10-14 from the dispatch brief*
