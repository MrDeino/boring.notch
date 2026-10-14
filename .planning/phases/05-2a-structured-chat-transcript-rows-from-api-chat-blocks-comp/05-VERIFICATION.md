---
phase: 05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp
verified: 2026-10-14T00:00:00Z
status: human_needed
score: 5/5 must-haves verified (code-level); on-device behaviour pending
overrides_applied: 0
human_verification:
  - test: "UAT 1 Rows: user lines '❯ text' dim; Read shows 'N lines'; Edit shows +N/−N and '▸ diff'; prose wraps at most 4 lines"
    expected: "as stated"
    why_human: "visual"
  - test: "UAT 2 Insert motion: new rows slide in from the bottom; opening the notch does not animate the whole list"
    expected: "as stated"
    why_human: "animation"
  - test: "UAT 3 Live status: '✻ Working · m:ss' ticks each second and shimmers; after a turn the dim idle '✻ … for …' line shows"
    expected: "as stated"
    why_human: "real-time"
  - test: "UAT 4 Older serve: against a serve without /api/chat/blocks the tab shows the restyled tail and does not go offline"
    expected: "as stated"
    why_human: "needs a serve lacking the endpoint"
  - test: "UAT 5 Terminal expand: clicking the transcript opens the terminal"
    expected: "as stated"
    why_human: "UI interaction"
  - test: "UAT 6 Composer look and typing: unfocused 30px pill, placeholder, grey send circle; focused accent ring, accent send circle with black arrow, hint row; esc releases keyboard; clicking another app hands focus back"
    expected: "as stated"
    why_human: "visual + key focus"
  - test: "UAT 7 Ghost suggestion: empty field shows ghost + [Tab] keycap; Tab and → accept; a typed letter replaces the ghost"
    expected: "as stated"
    why_human: "key events in a real panel"
  - test: "UAT 8 Ctrl-U: mid-line clears caret to line start; real Claude box cleared too; 'line cleared' tag ~1.2s; ghost returns if field empty"
    expected: "as stated"
    why_human: "needs live Claude session"
  - test: "UAT 9 Terminal draft: type a draft in the terminal, focus the notch field; pulled in with 'from terminal · ' prefix (not sent); sending yields exactly one copy"
    expected: "as stated"
    why_human: "needs live session"
  - test: "UAT 10 No duplicates: after Tab-accept, edit and send, no duplicated or concatenated text in Claude"
    expected: "as stated"
    why_human: "needs live session"
  - test: "UAT 11 Prompt answers: 1-9 / esc still answer prompts (recheck after merging with Phase 6)"
    expected: "as stated"
    why_human: "needs live prompt"
  - test: "UAT 12 Music: play/pause/skip, artwork and closed-notch live activity unchanged with the Orchestrator tab open and closed"
    expected: "as stated"
    why_human: "regression check on device"
  - test: "REVIEW-FIX CR-01: send with text in the real Claude box (C-u then fresh-screen confirm up to 5x); if the box stays non-empty, nothing is sent and the notch draft is kept"
    expected: "box empty before text is sent; no duplicate"
    why_human: "timing against a live session"
  - test: "REVIEW-FIX CR-02: press Enter while another POST (e.g. a key answer) is in flight"
    expected: "Enter ignored (send disabled), line not wiped without sending"
    why_human: "race"
  - test: "REVIEW-FIX WR-03: run /clear in the session, then send a new turn"
    expected: "old transcript is replaced (full fetch + reset), not appended to"
    why_human: "needs live /clear and serve's since semantics"
  - test: "REVIEW-FIX WR-04: leave a terminal draft unpulled, then press Enter in the notch field"
    expected: "draft is put in front with 'from terminal · ' prefix and a second Enter is required; draft not destroyed"
    why_human: "needs live session"
  - test: "REVIEW-FIX WR-05/06/07: break serve's blocks endpoint briefly (transient error, then {} or {error}), and a reset with duplicate ids"
    expected: "rows are held for 1-2 failures, chatTail fallback after 3 or when no blocks yet; no duplicate rows"
    why_human: "needs controlled serve failures"
  - test: "REVIEW-FIX WR-01/WR-02 (skipped, conflict with D-10): decide whether Ctrl-U should post C-u only when an input box is on screen, and whether Tab should POST at all"
    expected: "developer decision; current behaviour matches D-10 (always POST)"
    why_human: "design decision"
---

# Phase 5: 2a Structured chat Verification Report

**Phase Goal:** The chat reads like Claude Code: typed transcript rows from serve's transcript endpoint, a live working status, and a composer that mirrors Claude Code's input box.
**Status:** human_needed (no code gaps found; on-device checks outstanding)
**Re-verification:** No

## Observable Truths

| # | Truth (ROADMAP SC) | Status | Evidence |
|---|---|---|---|
| 1 | Rows come from `GET /api/chat/blocks?since=`, incremental, with fallback | VERIFIED | `OrchestratorChat.swift:88` builds `api/chat/blocks` with `since`; merge/decode/discontinuity in `OrchestratorTranscript.swift`; chatTail fallback (`:198-200`) and `fetchFailed()` (3 failures, or immediately when no blocks yet). Manager calls `OrchestratorTranscriptStore.shared.refresh` (`OrchestratorManager.swift:151`). Fixture-only harness prints OK. |
| 2 | "✻ Working · m:ss esc to interrupt" row from the screen | VERIFIED (visual pending) | Status view `OrchestratorChat.swift:437-458`, elapsed ticks via anchor; idle line via `parseIdleStatus`. |
| 3 | Composer matches frame 02, key-gate logic unchanged | VERIFIED (visual pending) | pill/ring/hint row present; `startTyping` calls `OrchestratorKeyGate.activate()` / `restore` (`:346-373`). |
| 4 | Ghost + Tab/→ accept (POST Tab), ⌃U local + POST C-u + "line cleared", terminal draft "from terminal · " | VERIFIED | Key monitor `:308-321` posts `Tab` and `C-u`; "line cleared" `:266`; "from terminal · " `:217,:257`; `boxIsDraft`, `clearToCaret` pure + tested. |
| 5 | Rows animate in; transcript click opens terminal; music unaffected | VERIFIED (device pending) | `.transition(.move(edge: .bottom).combined(with: .opacity))` `:165`, spring 0.3/0.85 `:71`; `transcriptTapped` `:343`. Music: diff touches no music files. |

**Score:** 5/5

## Requirements Coverage

| ID | Plans | Status |
|---|---|---|
| CHAT-01 | 05-01, 05-02 | SATISFIED (SC1) |
| CHAT-02 | 05-01, 05-02 | SATISFIED (SC2) |
| CHAT-03 | 05-03 | SATISFIED (SC3) |
| CHAT-04 | 05-01, 05-03 | SATISFIED (SC4) |
| CHAT-05 | 05-02 | SATISFIED (SC5) |

All five IDs appear in plan frontmatter and are marked Complete in REQUIREMENTS.md (lines 54-58, 141-145). No orphaned Phase 5 requirements.

## Review fixes (05-REVIEW-FIX.md)

All 7 fix commits present in history: 16d2d20 (CR-01), dd43f35 (CR-02), 00c55cc (WR-03), 935d791 (WR-04), 42ab111 (WR-05), 2ac9689 (WR-06), 8ae3662 (WR-07). Code spot-checks match (`clearRealLineIfNeeded` :101-109, `submit`/`submitting` :117, `fetchFailed`, WR-04 branch :380). WR-01 and WR-02 were skipped by decision (conflict with D-10): a documented design question, not a gap.

## Merge-map scope check

`git diff --name-only 5a22cc9 HEAD -- . ':!.planning'` lists only:
- boringNotch/Orchestrator/OrchestratorChat.swift
- boringNotch/Orchestrator/OrchestratorTranscript.swift
- boringNotch/Orchestrator/Tests/Phase5Tests.swift
- boringNotch/Orchestrator/Tests/fixtures/phase5-blocks.json
- boringNotch/Orchestrator/Tests/fixtures/phase5-blocks-bare.json

All Phase 5 owned (fixtures are test data in the owned Tests folder). No Manager, Models, pbxproj, or music files touched.

## Behavioral checks

| Check | Result |
|---|---|
| swiftc harness (re-run, output /tmp/orch-test-p5) | prints OK |
| xcodebuild | BUILD SUCCEEDED (orchestrator-reported, not re-run) |
| TBD/FIXME/XXX markers in phase files | none |

## Known residual (WARNING, not a gap)

A manager POST starting between C-u and the text still drops the send (draft kept); marked with a ponytail comment at `OrchestratorChat.swift:118`; needs a manager-file edit later.

## Gaps Summary

None. Automated checks pass; status is human_needed solely because of the 12 pending UAT checks plus the review-fix checks above.

_Verifier: Claude (gsd-verifier)_
