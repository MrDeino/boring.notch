# Handoff: Orchestrator notch redesign (option 2a, all features)

## Overview
This is a redesign of the Orchestrator tab in the Boring Notch fork (`boringNotch/Orchestrator/*`). The goal is to make the Claude Code integration feel native and smooth. Today the tab is a raw terminal tail, a row of plain buttons and four header controls, and states swap abruptly. The target is **option 2a** in the design file, which combines options 1a–1f. The handoff file contains only 2a; mentions of 1a–1f below note which original option a piece came from.

Every current feature must still work. See "Coverage" below. The constraints in `CLAUDE.md` still apply:
- Keep upstream mergeable (new files, minimal hooks).
- Don't break music.
- No new dependencies.
- Talk to the orchestrator over HTTP only.
- Stay on Swift 5 mode with `ObservableObject`.

## About the design files
`Orchestrator Notch Options.dc.html` is a **design reference built in HTML**. Open it in a browser with `support.js` next to it. Don't port the HTML. Rebuild it in SwiftUI using the repo's existing patterns (`OrchestratorManager.shared`, `BoringViewModel`, `Defaults`, SF Symbols).

## Fidelity
**High fidelity.** Sizes, colours, type sizes, radii and copy are intended to be final. All mocks are drawn at 1× real size: the open notch is 640×190 and the closed notch is 32px tall. The icons in the HTML are simple SVG stand-ins. Use the SF Symbols named below.

## Phasing
Each frame is tagged **works today** or **needs rework**.
- **Phase A (no server or window change):** frames 00 (live-activity wings only), 01 (parsed rows), 02, 02b (local parts), 03, 04, 06, 07, 08, 09, 10, and 12/12b using the existing expand-down.
- **Phase B (rework):**
  - Serve pushes structured events over SSE (1d): streaming text, diffs, exact prompt options, a `suggested` flag for the input box.
  - Per-run endpoints (1f): inline Allow/Deny on run cards, focusing a run.
  - A Claude Code PreToolUse/Notification hook posts to serve, which feeds the approval drop-down and global shortcuts (1e).
  - Panel frame sized to content (1e): replaces the fixed `windowSize` and the separate window-then-content expand step.

---

## Screens / views (2a)

Every open-notch frame has the same structure: a header row 34px tall, then content, then the composer. Notch padding is 0 14px 12px and the bottom corners have a 24px radius (26px when expanded).

### Header (all open states)
- **Left:**
  - Existing tab buttons, 24×24 circles. The selected one has a `#2C2C2E` background and a white icon; unselected icons are `#636366`. Icons: `house`, `tray`, `terminal`.
  - Then a segmented control **Chat | Runs N**: 6px left margin, `#1C1C1E` track with 12px radius and 2px padding, 11pt text.
    - Selected segment: `#3A3A3C` background, white text, 10px radius, padding 2px 9px.
    - The N count is `#FF9F0A` while any run is waiting, otherwise `#8E8E93`.
    - Hidden while offline.
- **Centre:** 185px spacer for the hardware notch.
- **Right:** a single **status capsule**: 24px tall, 12px radius, padding 0 10px 0 8px, 7px gap, 11pt text. It replaces `OrchestratorUsageBadge`, `OrchestratorChatButton` and `OrchestratorRunsButton`.

Status capsule variants:

| State | Dot | Label | Extras | Background |
|---|---|---|---|---|
| Running | `#30D158` | Running | divider (1×10 `#3A3A3C`), "ctx 38%" in `#8E8E93`, 12px usage ring | `#1C1C1E` |
| Idle | `#30D158` | Idle | usage ring | `#1C1C1E` |
| Needs you | `#FF9F0A` | Needs you (`#FFB35C`) | — | `#3A2410` |
| Stopped | `#8E8E93` | Stopped (`#AEAEB2`) | usage ring | `#1C1C1E` |
| Offline | `#FF453A` | Offline (`#AEAEB2`) | — | `#1C1C1E` |
| Connecting | `#636366` | Connecting (`#8E8E93`) | — | `#1C1C1E` |

- Dot is 6px.
- Usage ring is a 12px conic fill of the 5h `used_percentage`: white on `#3A3A3C`, `#FF9F0A` at 80% or above.
- Context % is Phase B only.
- Clicking the capsule opens the status menu (frame 06).

### 00 · Closed notch (live activity)
The closed notch is black, 32px tall, with 12px bottom radius. Wings grow sideways from the hardware notch, the same way the music live activity does. Wing padding is 0 12px 0 14px.

States:

| State | Width | Left wing | Right wing |
|---|---|---|---|
| Working | 285 | ✻ in `#D97757`, 15pt | elapsed `0:41`, mono 11pt medium, `#AEAEB2` |
| Needs you | 305 | 8px `#FF9F0A` dot with 8px glow | tool name pill: "Bash?", 11pt medium, `#FFB35C` on `#3A2410`, 9px radius, padding 2px 8px |
| Run finished | 285 | ✓ in `#30D158`, 13pt | project name, 11pt, `#AEAEB2`. Fades after 4s |
| Music playing + needs you | — | music keeps its album art | music keeps its visualizer; add a 7px orange dot before it |

- **Usage hairline:** kept from today. 2px tall, inset 14px each side, track `rgba(255,255,255,.12)`, fill `rgba(255,255,255,.5)`, orange at 80% or above.
- **Approval drop-down** (Phase B):
  - Panel 460px wide, 22px bottom radius, padding 30px 16px 14px, 10px gap.
  - Title row: 7px orange dot, "Orchestrator wants to run" (13pt semibold), tool name on the right (11pt, `#636366`).
  - Command block: mono 12pt `#E5E5EA` on `#1C1C1E`, 8px radius, padding 7px 10px.
  - Buttons, 30px tall pills:
    - **Allow ⌥⏎**: white background, black text, flex 1.
    - **Deny ⌥⎋**: `#1C1C1E` background, `#FF6961` text, flex 1.
    - **More…**: opens frame 03.

### 01 · Chat, streaming
Content area padding is 0 6px 8px with a 5px gap, and rows sit at the bottom. Row types:
- **User prompt** (❯): 12pt `#8E8E93`, one line, ellipsis.
- **Tool row** (⏺ + ⎿):
  - Chip: mono 10pt medium, `#C4C4C6` on `#1C1C1E`, 5px radius, padding 2px 6px. Label is the tool name (Read, Edit, Bash, Grep, Dispatch).
  - Then the target in mono 11pt `#D1D1D6`.
  - Then the result in 11pt `#636366`.
  - Edit rows add `+12` in `#30D158` and `−4` in `#FF6961` (mono 10pt), plus "▸ diff", which expands in Phase B.
- **Assistant prose:** SF Pro 13pt white, line-height 1.35.
- **Status** (✻): 11pt `#D97757`, "✻ Working · 0:41", followed by "esc to interrupt" in `#636366`. The text shimmers while live.
- **Streaming caret** (Phase B): 7×13 block in `#D97757`, 1px radius.

Clicking anywhere on the transcript opens the terminal (frame 10).

### 02 · Typing
- **Composer:** 30px tall pill, 15px radius, `#1C1C1E`, padding 0 6px 0 14px, 12pt.
  - Placeholder "Message orchestrator" in `#636366`.
  - Send button: 20px circle, `#3A3A3C` background with an `#8E8E93` ↑.
- **Focused:**
  - Ring: `box-shadow 0 0 0 1.5px #D97757`.
  - Text white, 1.5×13 caret.
  - Send button turns `#D97757` with a black ↑.
- **Hint row** under the composer: 10pt `#636366`, right-aligned, 12px gap. Text: "⏎ send · ⌃U clear line · esc release".
- **Keyboard handling:** focus uses the existing `OrchestratorKeyGate`, `beginTyping` and `endTyping` logic, unchanged.

### 02b · Message box: suggestion and line edit
This mirrors Claude Code's input box. States:
- **a. Suggestion:** when the box is empty, Claude Code's recommended prompt shows as ghost text in `#636366` after the caret. The right side shows `[Tab] accept` (10pt `#636366`).
- **b. Accepted:** Tab or → fills it in as editable white text.
- **c. Typing over it:** any other character replaces the suggestion.
- **d. After ⌃U:** clears from the cursor to the start of the line. Show a "line cleared" tag (10pt `#8E8E93` on `#2C2C2E`, 8px radius) for about 1.2s. The suggestion comes back if the box is empty.
- **e. Terminal draft:** text left in the real Claude box is pulled into the field on focus, prefixed in the UI with "from terminal · " in `#8E8E93`.

Keycap style: mono 10pt medium, padding 1px 5px, 4px radius. Dark keycaps are `#AEAEB2` on `#3A3A3C`; light ones are black on `#E5E5EA`.

Implementation:
- `chatTail` currently strips the input box. Add a parser for the box's `❯` line and expose it as `inputLine`.
- Plain screen text can't tell a dim suggestion from a typed draft. Phase B: serve returns `{text, suggested}` for the box, read from `tmux capture-pane -e` attributes.
- **⌃U:** handle it locally in the field, and also POST `{key:"C-u"}` so the real box stays in sync. Add `C-u` to `OrchestratorPost.allowedKeys` and to serve's allowlist.
- **Accept:** POST `{key:"Tab"}` (Tab is already allowed) as well as filling the field.

### 03 · Permission (decision card)
Shown when `detectPrompt` returns options. The card replaces the transcript.
- **Title row:** title in 14pt semibold (e.g. "Bash command"), then the purpose in 12pt `#8E8E93` ("Write current date to stamp file").
- **Command block:** mono 12pt `#E5E5EA` on `#1C1C1E`, 8px radius, padding 8px 10px, single line with ellipsis, `$ ` prefix in `#636366`.
- **Option pills**, 30px tall with 15px radius, 6px gap, bottom-aligned:
  - Option 1: white background, black text, weight 500, light keycap "1".
  - Other options: `#1C1C1E` background, white text, dark keycap with the number.
  - Deny (the last "No" option): pushed right, `#FF6961` text, keycap "esc".
  - Labels are shortened ("Yes, and always allow access to X" becomes "Always in X…"; "switch to auto mode" becomes "Auto mode"). The full label is the tooltip.
- **After a press:** the chosen pill fills and the others dim to 40% for the existing 3s `optionsLocked` window.
- **Keys:** 1–9 and esc work while the pointer is over the notch.

Parser change: `detectPrompt` must also return the title and body lines between the `───` rule and "Do you want to proceed?". Sample screens are in `Tests/fixtures/permission.txt` and `question.txt`.

### 04 · Question (AskUserQuestion), stacked vertically
Questions are often long, so options are a **vertical list** and the notch grows to fit using the existing expand-down. The mock is 640×400, and the list scrolls if it still overflows.
- **Top row:** header tag (e.g. "Window strategy"; 11pt `#8E8E93` on `#1C1C1E`, 8px radius, padding 1px 8px) and the progress "1 of 2" (11pt `#636366`) for prompts with several questions.
- **Question:** 14pt semibold, line-height 1.35, wraps fully.
- **Option rows:** 10px radius, padding 8px 10px, 5px gap.
  - Label: 12pt semibold, line-height 1.3.
  - Description: 11pt, line-height 1.4, `#8E8E93`.
  - Keycap on the right.
  - The highlighted row (Claude Code's ❯ default) has a white background, black label, `#48484A` description and light keycap. Other rows have a `#1C1C1E` background.
  - ↑/↓ move the highlight and ⏎ selects.
- **Footer row:** 28px pills.
  - "Something else…" free-text field with keycap 4. This replaces "Type something.", which is filtered out today. Send the option number, then the text.
  - "Chat about this" with keycap 5.
  - esc.

### 05 · Runs board (Chat | Runs → Runs)
- **Cards:** 196px wide, 12px radius, `#1C1C1E`, padding 9px 10px, 5px gap. They scroll horizontally beyond three.
  - Line 1: 6px state dot, project name (12pt semibold), elapsed time right-aligned (10pt `#8E8E93`).
  - Line 2: short prompt, 11pt `#8E8E93`.
  - Line 3: latest action, mono 10pt `#D1D1D6`.
- **Waiting card:** inset 1px `#FF9F0A` ring, plus Allow/Deny (11pt, 11px radius) in Phase B.
- **Sorting:** live runs first, as in `stripRuns`.
- **State colours:** running `#30D158`, waiting `#FF9F0A`, failed or stuck `#FF453A`, done `#8E8E93` (shown at 75% opacity with a ✓).
- **Bottom row:** the orchestrator collapses to one line in the composer pill: "✻ Orchestrator: waiting on run x7f2".

### 06 · Status menu
- **Popover** under the capsule: 232px wide, `#1C1C1E`, 12px radius, shadow `0 0 0 1px #2C2C2E, 0 10px 30px rgba(0,0,0,.6)`, padding 5px, 12pt rows (padding 3px 8px). It must stay inside the notch.
- **Rows, top to bottom:**
  - "5-hour usage" with "9% · resets 3:00 pm" on the right, then a 3px bar.
  - "7-day usage" with "14% · Thu 9:00", then a 3px bar.
  - Divider.
  - "Open terminal" with the hint "click transcript".
  - "Interrupt" with keycap esc. Keep the existing 1s debounce so a double esc doesn't open Claude Code's rewind.
  - "End chat?" row in `#FF6961` on `#2A1A19`, with an **End** pill (`#FF453A` background, black text) and a **Cancel** pill. It reverts after 4s, as today.
- **While the menu is open:** the transcript dims to 35%.
- **When stopped:** the menu shows "Start chat" in place of End.

### 07 · Chat stopped
Centred content:
- "Orchestrator chat is stopped" (14pt medium).
- A white **▶ Start chat** pill: 30px tall, padding 0 16px, black 12pt medium text.
- "2 runs still active · see Runs" in 11pt `#636366`.

### 08 · Offline
Centred content:
- "Can't reach the orchestrator" (14pt medium).
- A mono chip "node orch.js serve · 127.0.0.1:4777" (11pt, `#D1D1D6` on `#1C1C1E`, 7px radius).
- "Retrying every 10s" in 11pt `#636366`.

### 09 · Connecting
Shown until `hasLoaded`. Four skeleton bars (9px tall, 5px radius, `#1C1C1E`; widths 48/30/62/40%), bottom-aligned, plus the composer.

### 10 · Terminal expanded
This is the existing ttyd `WKWebView` inside a frame:
- Frame: `#0B0B0C`, 12px radius, inset 1px `#1C1C1E` border.
- Toolbar: 11pt `#8E8E93`, bottom border `#1C1C1E`. Contents: green dot, "Terminal · keyboard captured", and a "Collapse ⌃" pill on the right (`#1C1C1E`, 9px radius).
- "In use" and "unavailable" replace the frame body with the message and a Retry pill.
- Mock height is 360.

### 11 · Click open → expand (flow)
Closed (live activity) → open (640×190 chat) → expanded (640×440, full conversation and runs).

| Step | Trigger |
|---|---|
| Closed → open | hover or click on the notch, as today |
| Open → expanded | click the transcript or ⌘↓ |
| Back one level | esc or ⌘↑ |
| Close fully | click outside |

Animation:
- Height is one continuous spring (response 0.4, damping 0.82).
- Content cross-fades in after the shape settles (about 120ms delay, 0.18s ease-out).
- Terminal is a mode inside Expanded.

### 12 · Expanded view (runs rail open)
Notch 640×440, 26px radius.
- **Header:** the status capsule plus a 24px "⌃" collapse button on the right.
- **Body:** horizontal flex, 12px gap, padding 6px 0 10px.
- **Conversation column** (flex 1):
  - User bubble: right-aligned, max 80% width, `#1C1C1E`, radius 12/12/4/12, padding 6px 10px, 12pt `#D1D1D6`.
  - Tool rows as in frame 01.
  - **Expanded Edit card:** `#141416`, 9px radius.
    - Header: ▾, "Edit", file name, +/−.
    - Diff lines: mono 10pt, line-height 1.5, padding 0 10px.
    - Removed lines: `rgba(255,105,97,.12)` background, `#FF9D97` text.
    - Added lines: `rgba(48,209,88,.12)` background, `#7EE69A` text.
    - Context lines: `#636366`.
- **Runs rail:**
  - 178px wide, left border 1px `#1C1C1E`, padding-left 12px.
  - Header: "Runs · 3 active" with a 20px **›** collapse button.
  - Compact run cards: 10px radius, padding 8px 10px.
  - Usage bars for 5h and 7d (10pt) pinned to the bottom.
- **Bottom row:** composer pill (32px) and a "Terminal ⌘T" pill.
- **Height:** follows the content up to about 45% of the screen height, then the conversation scrolls.

### 12b · Expanded, runs collapsed
- **Rail:** collapses to a **30px strip**:
  - ‹ expand button (20px).
  - One 22px circle per run with a 7px state dot. A waiting run gets an inset 1px orange ring.
  - The usage ring at the bottom.
- **Conversation:** takes the full width.
- **Rail toggle:** ‹ or ⌘\ re-expands; hovering a dot peeks that run's card. Persist the open/closed choice in `Defaults` (`orchRunsRailCollapsed`).
- **Auto re-open:** a run that starts waiting opens the rail automatically, unless the user collapsed it during this session.
- **Animation:** collapse and expand animate the width with a spring (0.3 / 0.85).

---

## Interactions and motion (summary)
- **New transcript rows:** keyed by a content hash, inserted with `.move(edge: .bottom).combined(with: .opacity)` (spring 0.3 / 0.85).
- **Prompt card:** rises out of the composer using `matchedGeometryEffect`. It shrinks back after a press.
- **Closed wings:** spring out (0.35 / 0.8). The ✻ rotates slowly while working. The needs-you dot pulses its glow at 1.2s.
- **State changes:** status capsule label changes cross-fade.
- **Expand and collapse:** keep the existing outside-click, monitor and key-release logic in `OrchestratorExpand`.

## State management
Additions to `OrchestratorManager`:
- `blocks: [ChatBlock]` (enum: `user`, `tool(name, target, result, added, removed)`, `prose`, `status(text, live)`).
- `inputLine: (text, suggested)?`.
- `prompt: PromptCard?` (`title`, `purpose`, `body`, `options`, `kind: permission/question`, `progress`).
- `elapsed` for the live status.
- Phase B: `contextPercent`.

UI state:
- `showRunsBoard` (the Chat | Runs segment).
- `statusMenuOpen`.
- `expandLevel` (`open`/`expanded`/`terminal`).
- `runsRailCollapsed` (Defaults).

Polling: 2s while open, as today. Closed polling drops from 10s to 3s while `chatRunning`, so the wings stay live. Phase B replaces polling with SSE (`URLSession.bytes`).

## Coverage: every current feature

| Current | Where in 2a |
|---|---|
| Chat tail | 01 |
| Message field and focus | 02 |
| — (new) suggested prompt, Tab to accept, ⌃U, terminal draft | 02b |
| Permission options 1–9, esc, 3s lock | 03 |
| AskUserQuestion; "Type something." | 04 |
| Runs overlay and header runs button | 05, 12 rail |
| Start / End chat with confirm | 06, 07 |
| 5h/7d usage, hover reset times, orange at 80% or above | capsule ring, 06 |
| Offline / connecting | 08, 09 |
| ttyd expand; in use / unavailable / retry | 10 |
| Closed attention dot and usage hairline | 00 |
| Esc debounce (rewind guard) | 06 |
| Music player unaffected | 00 |

## Design tokens
- **Surfaces:**
  - Notch `#000000`.
  - Raised surfaces: `#1C1C1E`, `#141416` (diff card), `#0B0B0C` (terminal).
  - Selected `#2C2C2E` / `#3A3A3C`.
  - Divider `#1C1C1E` / `#2C2C2E`.
- **Text:** primary `#FFFFFF`. Secondary text uses these grays from lightest to darkest: `#E5E5EA`, `#D1D1D6`, `#C4C4C6`, `#AEAEB2`, `#8E8E93`, `#636366`.
- **Accent:** Claude `#D97757`, used for ✻, the focus ring, the send button and the caret.
- **Status:** green `#30D158`, orange `#FF9F0A` (text `#FFB35C`, background `#3A2410`), red `#FF453A` (text `#FF6961`, background `#2A1A19`).
- **Type:**
  - SF Pro: 14 semibold (titles), 13 (prose), 12 (UI and composer), 11 (meta), 10 (hints), 9 (tiny).
  - SF Mono: 12 (commands), 11 (paths), 10 (chips, diffs, keycaps).
  - Mono is only for paths, commands, diffs and keycaps.
- **Radii:**
  - Notch bottom: 24 open, 26 expanded, 22 drop-down, 12 closed.
  - Cards 12/10/9; pills 15 (30px tall) and 14 (28px tall); keycaps 4.
- **Spacing:** notch padding 0 14 12; content gaps 5–9; header height 34.

## Assets
None besides SF Symbols. Suggested symbols: `terminal.fill` (tab), `house`, `tray`, `chevron.left` / `chevron.right` (rail), `chevron.up` (collapse), `arrow.up` (send), `checkmark`, `play.fill`, `stop.fill`. Draw ✻ as a text glyph in `#D97757`.

## Files
- `Orchestrator Notch Options.dc.html`: option 2a only (turn 2), the build target. All frames referenced above are in it.
- `support.js`: needed to open the HTML locally.
- `screenshots/`: a 2× PNG of each frame, named to match the frame numbers: `00-closed`, `01-chat-streaming`, `02-typing`, `02b-message-box`, `03-permission`, `04-question`, `05-runs-board`, `06-status-menu`, `07-stopped`, `08-offline`, `09-connecting`, `10-terminal`, `11-open-expand-flow`, `12-expanded`, `12b-expanded-runs-collapsed`.

Code to touch: `OrchestratorView.swift` (split it into Chat, PromptCard, RunsBoard, StatusCapsule), `OrchestratorCompact.swift` (live activity), `OrchestratorModels.swift` (`ChatBlock` parser, `PromptCard`, `inputLine`, `C-u`), `OrchestratorManager.swift`, `OrchestratorExpand.swift` (expand levels), and `BoringHeader.swift` (swap the three header controls for one `OrchestratorStatusCapsule`).
