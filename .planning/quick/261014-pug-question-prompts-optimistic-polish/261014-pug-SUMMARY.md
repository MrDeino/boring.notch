# Quick 261014-pug: Question prompts, optimistic answers, chat polish

Multi-select and multi-question prompts are answerable from the notch; every answer taps hides the card at once and restores it with a "Didn't go through" note if the screen never moved on; expanded view has user bubbles and a fold-out Edit diff card; swipe-close is off on the Orchestrator tab; the dot is 7pt.

Commits: bc092ee (parse + pressKeys + fixtures), 34a0524 (prompt card UI), fbf32be (expanded polish, gesture guard, dot).

## Observed key map (real Claude Code 2.1.299, only server-allowed keys)

- Multi-select rows: `N. [ ] label` / `N. [✔] label`. Digit N toggles row N (cursor stays). Enter toggles the highlighted row. "Type something" also has a `[ ]` prefix (treated as the free-text row, no checkbox).
- Tab = "done, next": moves to the next question chip (ticks kept); from the last question it goes to the review step. Tab on the review step does nothing (no wrap). No Left/Shift-Tab are allowed, so only forward chips are tappable (distance d = d x Tab).
- There is no Submit key on a multi-select question; the "Submit" pill is Tab ("Next" while more questions follow, "Submit" on the last question, which lands on review).
- Chip glyph: a chip turns `☒` as soon as one box is ticked, so `☒` does not mean "left this question". Plain text does not show the current chip; parser heuristic (ponytail comment): first unanswered chip, or last answered one when the shown multi-select has ticks.
- Review step ("Review your answers", summary, "Ready to submit your answers?", `1. Submit answers` / `2. Cancel`) has NO "Esc to cancel" footer; scanPrompt now accepts the "Ready to submit" line instead. Digit 1 submits (unanswered questions are recorded "no answer").
- Single-question multiselect shows chips `☐ Pet  ✔ Submit` and Tab goes straight to review.

Blockers: none. Not possible with allowed keys: going back to an earlier question (chips behind the current one are not tappable).

## Behavior

- Parser: `PromptCardOption.checked`, `PromptCard.multiSelect/tabs/currentTab/review`, `PromptTab`, `mergeChecked`; checkbox glyphs stripped from labels and options so toggling does not change prompt identity; the old "toggle footer -> permission" fallback is gone.
- Manager: `pressKeys([String])` (one `sending` window, stops at first non-200); `optionsLocked`/`lockGen`/`pressOption` removed.
- Controller: optimistic `answer` (pressed at once, card dismissed after ~120ms with spring, stillCurrent check, keys, 2s later fresh refresh; same prompt still up -> restore with note, never auto re-sends). Free text dismisses instantly and restores on failure. Toggles flip instantly (`pending`), reconciled by the screen read inside pressKeys.
- Views: checkbox rows, Next/Submit pill, tab chips (done check, current highlighted, forward chips tappable), review body text, red note above the options.
- Expanded: right-aligned user bubble (80% width), Edit/Write rows with a diff become a fold-out card (`diffRows`); open notch unchanged. `handleUpGesture` guard gained `&& coordinator.currentView != .orchestrator` (ContentView: 1 line). Marker is a 7pt Circle.

## Tests

- swiftc harness: `OK` (QuickPugTests: multiselect-1/toggled/tab2/review/single fixtures, existing fixtures unchanged, mergeChecked, diffRows; Phase6 multi-select assertion updated). Synthetic phase6-multiq fixtures kept (still pass).
- xcodebuild into /tmp/notch-dd: BUILD SUCCEEDED. Snapshot harness: all scenes written, no FAILED.
- PNGs looked at: 15, 16, 17, 18, 19, 20, 21, 22, 23, 24 (checkboxes, toggled boxes, tab chips, review rows, pressed pill, note, bubble, diff card, compact rows unchanged, dot). Fixes from looking: current tab chip was dimmed by `.disabled` (now `allowsHitTesting`); Snap scene arg order.
- Not exercised: live optimistic/restore timing against the real server (no POSTs allowed, app not launched); only the static states.

## Deviations

- Added fixture `multiselect-single.txt` (extra capture) beyond the four planned.
- Multi-select pill is labelled Next/Submit depending on position since Tab is the only forwarding key.
- Used rgb literals for diff colors (`Color(hex:)` is fileprivate in Tokens).
- notch-fixture tmux session killed; `tmux ls` shows only `orchestrator` (untouched); scratch dir removed; no POSTs made.

## Known Stubs

None.
