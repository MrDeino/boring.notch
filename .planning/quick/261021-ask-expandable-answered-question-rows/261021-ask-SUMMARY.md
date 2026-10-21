---
quick: 261021-ask
status: complete
---
# Expandable answered question rows

- `OrchestratorAsk.swift` (new, also in the Xcode project): lossy decoding of `questions` / `answers`, and `askRow(_:)`, the pure row model (answers matched to questions by text, falling back to position; `Other` text counts as the pick; `answers: []` = dismissed; nil for waiting, no questions, other tools).
- `ChatBlock` decodes both fields as optional.
- Chat row: a card with chevron + one summary line per question; tap anywhere on it toggles the full view. Open state lives in `OrchestratorTranscriptStore.askOpen` (survives level changes and tab switches, cleared when the chat stops). A toggle holds the scroll logic for 0.5 s (no jump to bottom, no "new messages" pill). The card is a Button, so the tap does not reach `expandChat`.
- Live question cards untouched.

## Checks
- Unit harness (Models, Pure, Transcript, Ask, PromptParse, RunsPure, Stream, ComposerInput, KeyQueue + Tests/*.swift, run from the repo root): OK. `Tests/QuickAskTests.swift`: single, multi-question (answers out of order), multi-select, "Other" + notes, dismissed and partly answered, fallbacks (waiting, absent fields, other tool), lossy types.
- Snapshots (`run.sh`, scenes 70-73, synthetic fixture, written to /tmp, not committed): closed and opened at the open and expanded sizes viewed; long questions and option descriptions wrap.
- Debug (`build/dd`) and Release (`./build`, ad-hoc, `ENABLE_HARDENED_RUNTIME=NO`, ORCH_NO_SPARKLE): BUILD SUCCEEDED; Release copied to `build/notch-rel/Clive.app`.

## Not verified
- A real click and scroll-offset behaviour in the running app (snapshots are static; `--hittest` not extended). Not run against a real serve.
