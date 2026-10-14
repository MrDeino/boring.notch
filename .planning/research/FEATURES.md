# Feature Research

**Domain:** macOS notch companion for a Claude Code orchestrator (Boring Notch fork, Orchestrator tab)
**Researched:** 2026-10-14
**Confidence:** MEDIUM-HIGH (API shapes verified against the live `orch.js serve`; Claude Code prompt layout from a live screen capture plus training knowledge; competitor behaviour from vendor pages)

## Verified facts that change the spec

- **Run field is `state`, not `status`.** Live `GET /api/state` returns runs with `id, project, ws, agent, prompt, state, latest, activity, denials, ...`. PROJECT.md says `status`; the decoder must use `state`. Values: running, waiting, done, failed, stopped, stuck.
- **`usage` carries an `at` timestamp** (ISO) besides `five_hour`/`seven_day` `{used_percentage, resets_at}`. It is written by a usage tap and can be stale or missing. Decode every usage field as optional.
- **`/api/chat` screen** is `tmux capture-pane -p -J -S -200`: plain text, no ANSI escapes, lines right-padded with spaces to the pane width (190 cols when started by the API). Trim trailing whitespace per line and drop trailing blank lines before showing or parsing.
- **The idle input box also starts with `❯`.** Live capture shows the normal state as a `───` rule, a line `❯ <typed text>`, another `───` rule, then a status footer (`Opus ... │ orchestrator ███ 16%`, `⏵⏵ auto mode on ...`). A prompt detector keyed on `❯` alone will fire permanently.
- **ttyd runs with `-m 1` (max one client).** If the browser dashboard has `/term` open, the notch WKWebView connection is refused (and vice versa). Expand-to-terminal must handle that, and should only load the web view while expanded.
- `POST /api/chat {text}` collapses newlines to spaces and sends Enter itself; `{key}` accepts only Enter, Escape, Up, Down, Tab, 1–9 (400 otherwise); 409 when the chat is not running.

## Prompt detection (the one non-trivial parser)

Claude Code shows two kinds of numbered choice on screen, and both replace the input box while active:

1. **Permission prompt**: tool header (e.g. `Bash command`, the command), `Do you want to proceed?`, then `❯ 1. Yes`, `  2. Yes, and don't ask again for ...`, `  3. No, and tell Claude what to do differently (esc)`. Older builds draw it inside `╭│╰` box borders; newer ones are borderless with a footer like `Esc to cancel`.
2. **AskUserQuestion**: question line (sometimes a `☐ Header` tab row for multi-question), options `❯ 1. Label` each optionally followed by indented description lines, usually a trailing free-text option ("Type something" / "Chat about this"), footer `Enter to select · ↑/↓ to navigate · Esc to cancel`. Multi-select variant shows `[ ]`/`[✔]` checkboxes and a Submit step.

**Recommended rule (bottom-anchored, all must hold):**
- Work on the last ~30 non-blank lines after trimming; strip leading `│` and trailing `│` box characters.
- Option line regex: `^\s*(❯\s*)?(\d)\.\s+(.+)$`.
- There is a run of ≥2 option lines numbered consecutively from 1, and exactly one carries the `❯` cursor. Indented non-numbered lines between options are descriptions (skip them, do not break the run).
- Nothing below the run except blank lines, description lines, footer hint lines (`Esc to cancel`, `Enter to select`, `Tab to amend`, `↑/↓`), or box bottom border. In particular, **no input-box rule pair (`───` / `❯ ...` / `───`) below the options.** This excludes Claude's own markdown numbered lists in chat history (no cursor, input box below them).
- Labels: strip trailing `(esc)` and similar shortcut hints; truncate to one line in the button, full text in `.help()` tooltip. Show the question line (nearest non-option line above the run) as the prompt title.
- Options numbered >9 are not reachable by digit; show 1–9 only and rely on expand-to-terminal for the rest.
- Multi-select (`[ ]` present): don't render digit buttons (a digit toggles, it doesn't submit); show "Answer in terminal" + expand button instead.

**Behaviour after a tap:** send `{key: "<n>"}`, then disable all option buttons until a poll returns a screen without that same prompt block (or ~3 s timeout). Without this, a double tap sends the second digit into the next prompt or into the input box. Always also show an **Esc** button (`{key:"Escape"}`) while a prompt is visible: it is the universal "no / cancel" and costs nothing.

Confidence: MEDIUM. Exact wording and borders change across Claude Code releases; the structural rule (consecutive numbered run + single `❯` cursor + no input box below) is the stable part. Ship a unit-testable pure function `detectPrompt(screen) -> Prompt?` with fixtures captured from the real screen (idle, permission, AskUserQuestion, multi-select, numbered list in chat history).

## Feature Landscape

### Table Stakes

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Command-line build (xcodebuild, unsigned) | Nothing else can be verified without it | MEDIUM | Sparkle/signing settings in the project may need overriding (`CODE_SIGN_IDENTITY=-`). |
| Orchestrator tab beside home/shelf | Entry point | LOW | One enum case + one tab button + one `case` in ContentView; everything else in new files. |
| Chat tail view | Core "read the orchestrator" | LOW | Monospaced, small font, last ~15–25 trimmed lines, pinned to bottom. Lines are 190 cols wide; truncate (`.lineLimit(1)`, tail) rather than wrap, or the view becomes unreadable. Drop the status footer lines below the input box. |
| Prompt option buttons + Esc | Core value: answer without a terminal | MEDIUM | See detection section. Buttons replace or sit above the message box while a prompt is up. |
| One-line message box, Enter sends | Steer the orchestrator | MEDIUM | Clear field only on 200; keep text and show inline error otherwise. Disabled with placeholder "Orchestrator not running" when `running == false`. Known risk: the notch panel must become key to take keyboard input (see PITFALLS). |
| Runs strip | See what's happening | LOW | One row per non-finished run first (running/waiting/stuck), then a few recent done/failed: coloured state dot, project (`project:ws` if ws), prompt truncated to one line. Cap ~4 rows. Read-only. |
| Usage bars 5h / 7d with reset time | Usage is the main budget constraint | LOW | Percent + relative reset ("resets in 2h 14m", from `resets_at` epoch seconds). Hide the bars (not show 0%) when usage is missing; dim them when `at` is older than ~15 min. |
| Three distinct empty/offline states | Avoid a blank or misleading tab | LOW | (1) **serve unreachable** (connection refused/timeout): "Orchestrator offline" + hint "`node orch.js serve` (LaunchAgent)". (2) **serve up, chat not running** (`running:false`): runs/usage still shown, chat area shows **Start** button. (3) **no runs**: strip says "No runs". Never show stale data as live after a failed poll; one failed poll = offline is fine at 2 s cadence (or require 2 in a row to avoid flicker). |
| Start / End | Lifecycle without terminal | LOW | Start: POST, then poll quickly (screen takes a few seconds to appear; show "Starting…"). End: **inline two-step confirm** (button becomes "End chat? Confirm · Cancel", auto-reverts after ~5 s). Do not use NSAlert/sheets: they steal focus and the notch collapses. Copy should say dispatched runs keep going. |
| Attention dot on closed notch | Know when you're needed without opening | MEDIUM | Lit when any run `state == "waiting"` OR `detectPrompt(chat.screen) != nil`. Requires polling `/api/chat` while closed too, not just `/api/state`. Must coexist with the music closed-notch activity (do not replace album art / visualiser). |
| Small usage indicator on closed notch | Glanceable budget | MEDIUM | 5h percent only (tiny ring or number). Same coexistence issue with music; consider showing it only when music isn't playing, or only the dot when it is. |
| Polling cadence | Freshness vs cost | LOW | ~2 s while the Orchestrator tab is open; ~10–15 s while closed (state + chat for the dot); stop chat polling when the notch is open on another tab beyond what the dot needs. Also poll immediately after any POST. |
| Music unaffected | Core constraint | LOW (if isolated) | Orchestrator code never touches MusicManager; closed-notch indicator added alongside, not in place of, music views. |

### Differentiators

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Expand-down live terminal (WKWebView on `/term`) | Full fidelity fallback for anything the parser can't handle (multi-select, >9 options, scrolling back) | HIGH | Same window grows downward; click outside collapses. Create the WKWebView on expand, tear it down on collapse (frees the single ttyd slot, avoids a hidden live websocket). Show "Terminal in use elsewhere" if ttyd refuses. Keyboard focus into the web view has the same key-window issue as the message box. |
| Larger chat view in expanded mode | More scrollback without the terminal | LOW | Same text view with more lines; cheap once expand exists. Could replace the terminal entirely if WKWebView proves troublesome. |
| Prompt title + context lines | Know what you're approving (the command, the file) | LOW | Show the 1–3 lines above "Do you want to proceed?" (tool name + command) above the buttons. Approving blind is the main risk of a tiny UI. |
| Distinct dot colour for stuck/failed | Separate "needs answer" from "needs a look" | LOW | Orange = waiting/prompt (actionable), red = failed/stuck. Optional; dashboard already treats waiting/stuck/failed as attention. |
| Auto-open notch to the tab when a prompt appears | Zero-click awareness | MEDIUM | Nice but intrusive; make it a Defaults toggle, default off. |

### Anti-Features

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Claude Code hooks / Unix socket (Vibe Notch approach) | Exact, structured prompt events instead of screen scraping | App is sandboxed; would write into `~/.claude`, which the orchestrator rules forbid; adds a second integration path | Screen parser over `/api/chat`; terminal expand as fallback |
| Spawning tmux/node/claude from the app | "Just start it" | Sandbox; explicitly out of scope | `POST /api/chat/start`; offline hint tells the user how to start serve |
| Run controls in the notch (stop, resume, dispatch, merge, PR) | Everything from the notch | Bypasses the orchestrator's approval flow; destructive actions in a tiny UI | Read-only runs strip; ask the orchestrator via the message box |
| Auto-approve / "always Yes" button | Fewer clicks | Silently approves commits and pushes; defeats the permission prompt | One tap per prompt with context lines visible |
| SwiftUI ANSI terminal emulator / chat bubble parsing | Prettier chat | Large, fragile parser of an unstable TUI | Plain trimmed text tail; WKWebView for real terminal |
| Multi-line composer, history, attachments | Richer chat | API flattens newlines anyway; notch is the wrong place | One line; use the terminal for long input |
| Notifications / sounds | Don't miss prompts | Duplicates dashboard; needs notification permissions; noisy | Attention dot (optionally auto-open toggle) |
| Separate window or popover for terminal | Easier sizing | Rejected design decision | Expand downward in the same window |
| Per-option arrow-key navigation UI | Mirrors terminal | Digits already select directly | Digit buttons; Up/Down/Enter only via terminal |

## Feature Dependencies

```
xcodebuild CLI build
    └──> Orchestrator tab (enum/tab/ContentView hooks)
            └──> API client (URLSession, ATS NSAllowsLocalNetworking, x-orch header)
                    ├──> Poller (2s open / slow closed)
                    │       ├──> Offline / not-running / empty states
                    │       ├──> Chat tail ──> detectPrompt() ──> Option buttons + Esc
                    │       │                        └──> Attention dot (closed notch)
                    │       ├──> Runs strip ────────────────┘ (waiting → dot)
                    │       └──> Usage bars ──> Closed-notch usage indicator
                    └──> Message box, Start, End (inline confirm)
Notch sizing changes ──> Expand-down ──> Larger chat view
                                    └──> WKWebView /term
Key-window focus fix ──> Message box, terminal typing
Closed-notch indicators ──conflicts──> music closed-notch activity (shared space)
```

- `detectPrompt` is pure and needs only the screen string: build and test it before any UI.
- The closed-notch dot needs both the poller running while closed and `detectPrompt`.
- Expand-down depends on understanding `boringNotch/sizing/`; it is independent of the parser and can be its own phase.

## MVP Definition

### Launch With (v1)
- [ ] CLI build — gate for everything
- [ ] Tab + API client + poller + offline/not-running/empty states
- [ ] Chat tail, runs strip, usage bars
- [ ] Message box (with focus fix), Start, End with inline confirm
- [ ] `detectPrompt` + option buttons + Esc + double-tap guard
- [ ] Closed-notch attention dot

### Add After Validation (v1.x)
- [ ] Expand-down with larger chat view — once the tab is in daily use
- [ ] WKWebView terminal in the expanded area — when the parser's gaps (multi-select, >9) actually bite
- [ ] Closed-notch usage indicator — after the music coexistence layout is settled
- [ ] Prompt context lines — if approving from the button alone feels blind (likely; cheap, could move to v1)

### Future Consideration
- [ ] Auto-open on prompt toggle, colour-coded dot

Note: PROJECT.md lists expand/terminal and the usage indicator as Active; the split above is ordering advice, not a scope cut.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Prompt buttons + Esc | HIGH | MEDIUM | P1 |
| Attention dot | HIGH | MEDIUM | P1 |
| Chat tail | HIGH | LOW | P1 |
| Message box | HIGH | MEDIUM | P1 |
| Offline/not-running states | HIGH | LOW | P1 |
| Start / End (confirm) | MEDIUM | LOW | P1 |
| Runs strip | MEDIUM | LOW | P1 |
| Usage bars | MEDIUM | LOW | P1 |
| Expand-down + larger chat | MEDIUM | MEDIUM | P2 |
| WKWebView terminal | MEDIUM | HIGH | P2 |
| Closed usage indicator | LOW | MEDIUM | P2 |
| Prompt context lines | MEDIUM | LOW | P2 |
| Auto-open toggle | LOW | MEDIUM | P3 |

## Competitor Feature Analysis

| Feature | Vibe Notch (OSS) | Vibe Island (commercial) | Our Approach |
|---------|------------------|--------------------------|--------------|
| Prompt source | Claude Code hooks → Unix socket | Hooks, multi-agent | Screen parse of `/api/chat` (sandbox, no `~/.claude` writes) |
| Approve UI | Notch expands with Approve/Deny | Allow/Deny + AskUserQuestion options | Digit buttons mirroring the real options + Esc |
| Scope | Any Claude Code session | Claude, Codex, Gemini, Cursor | One orchestrator session + its dispatched runs (read-only) |
| Terminal | No | No | Expand-down ttyd web view |

## Sources

- Live `http://127.0.0.1:4777/api/state` and `/api/chat` responses, and `orch.js` serve code (`/Users/mitch/Documents/Claude/orchestrator/orch.js` lines ~514–590) — HIGH
- [Vibe Notch (farouqaldori/vibe-notch) docs](https://docsearch.algolia.com/mcp/docs/repo/farouqaldori/vibe-notch) — MEDIUM
- [Vibe Island — Claude Code](https://vibeisland.app/claude-code/) — LOW (marketing page)
- [Claude Code permissions docs](https://code.claude.com/docs/en/permissions) — option set (Yes / Yes don't ask again / No) — MEDIUM
- Exact prompt wording/borders: training knowledge + one live idle capture — LOW-MEDIUM; capture real fixtures before finalising the parser

---
*Feature research for: Boring Notch Orchestrator tab*
*Researched: 2026-10-14*
