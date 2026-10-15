---
phase: 08-phase-b-live-data-sse-push-streaming-caret-diff-expansion-su
verified: 2026-10-14T00:00:00Z
status: human_needed
score: 5/5 must-haves verified
human_verification:
  - test: "Open the notch with serve running; watch chat while Claude replies"
    expected: "Rows appear within about a second without the 2 s poll cadence (SSE); stopping serve flips to offline/polling, and a restart resumes streaming within about 30 s"
    why_human: "Live network behaviour; no app launch allowed here"
  - test: "During a live turn, look at the newest assistant prose row"
    expected: "7x13 #D97757 blinking block follows the last glyph; disappears when the turn ends or a prompt card is pending"
    why_human: "Visual"
  - test: "Click ▸ diff on an Edit row (open chat) and view an Edit in expanded chat"
    expected: "Frame 12 diff card with removed/added/context colours; toggles ▾ diff"
    why_human: "Visual match to frame 12"
  - test: "Type a draft in Claude's box vs leave Claude's dim suggestion"
    expected: "Suggestion shows as ghost text; a typed draft shows as a draft (exact via serve's suggested flag)"
    why_human: "Needs live tmux pane"
  - test: "Watch the Running capsule while the chat runs"
    expected: "Shows 'ctx N%' (currently serve reports 40%), orange when high; music controls and now-playing unaffected"
    why_human: "Visual and music regression check"
---

# Phase 8 Verification

**Goal:** The notch updates live from serve pushes instead of polling, with streaming text, inline diffs, an exact suggestion flag and context usage.
**Status:** human_needed (all automated checks pass; on-screen checks remain)

## Truths

| # | Truth | Status | Evidence |
|---|---|---|---|
| 1 | SSE stream with polling fallback (LIVE-01) | VERIFIED | `OrchestratorManager.runStream` uses `URLSession.bytes` on `api/events`; 200 required, returns on 404/error/20 s silence; poll loop skips only while `streaming`; `SSELineParser` and `streamHealthy` in `OrchestratorStream.swift`. Live serve at 127.0.0.1:4777 emits `event: state` on `/api/events`. |
| 2 | Streaming caret 7x13 #D97757 (LIVE-02) | VERIFIED | `caretVisible` is wired in `OrchestratorChat.swift:333` using `manager.chatLive`; the CALayer is 7x13 with `OT.C.claude`, blinking (`OrchestratorChat.swift` ~1005-1029). Visual check pending. |
| 3 | ▸ diff expands Edit row into frame 12 card (LIVE-03) | VERIFIED | `canDiff`, `diffToggle`, `diffCard` and `diffLine` exist for Edit, Write and MultiEdit rows; they use `OT.C.diffCard` and `diffRows`. |
| 4 | Ghost text from serve `{text, suggested}` (LIVE-04) | VERIFIED | `ChatInput` model decodes `input`; `resolveInput` uses `suggested` when the key is present and falls back to the heuristic on old serve. Real `/api/chat` returns `input:{text,suggested}`. |
| 5 | Running capsule "ctx N%"; music unaffected (LIVE-05) | VERIFIED (music by diff only) | `OrchestratorStatusCapsule.swift:132` renders "ctx N%". The manager takes `context.percent` from the real payload (`context:{percent:40}`). The only upstream-file diff vs main in the checked paths is a 2+/1- change to `ContentView.swift`. |

## Automated checks

- swiftc harness (models, pure, transcript, promptparse, runspure, stream and all Tests): compiled and the last line is `OK`.
- Real `/api/chat` shape (`running, screen, live, input, context, approval`) matches the decoders' CodingKeys. `/api/events` streams SSE.
- Requirements: LIVE-01..05 are all claimed by plans 08-01 (LIVE-04, 05), 08-02 (LIVE-01) and 08-03 (LIVE-02, 03). All five are in REQUIREMENTS.md and marked Complete. No orphaned IDs.
- No debt markers (TBD/FIXME/XXX) were checked exhaustively; none surfaced in the greps run. No stubs were seen in the Phase 8 code paths.

## Gaps

None found. The `blocks` and `chat` SSE event shapes were not observed live (only `state` was seen in a 3 s sample), so they are covered by the fixture tests only.
