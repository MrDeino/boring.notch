---
status: pending
phase: 05-2a-structured-chat-transcript-rows-from-api-chat-blocks-comp
source: [05-01-PLAN.md, 05-02-PLAN.md, 05-03-PLAN.md]
started: 2026-10-14
updated: 2026-10-14
---

## How to run the built app

Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-p5 build`. Quit the installed Boring Notch, start `node orch.js serve`, then launch the built app yourself from /tmp/notch-dd-p5/Build/Products/Debug. Ad-hoc builds may re-trigger privacy prompts; that is not a regression.

## Tests

### 1. Rows
expected: User lines show "❯ text" dim; Read shows "N lines"; Edit shows +N/−N and "▸ diff"; prose wraps at most 4 lines.
result: pending

### 2. Insert motion
expected: New rows slide in from the bottom; opening the notch does not animate the whole list.
result: pending

### 3. Live status
expected: While Claude works, "✻ Working · m:ss" ticks each second and shimmers; after a turn the dim idle "✻ … for …" line shows.
result: pending

### 4. Older serve
expected: Against a serve without /api/chat/blocks, the tab shows the restyled tail and does not go offline.
result: pending

### 5. Terminal expand
expected: Clicking the transcript opens the terminal.
result: pending

### 6. Composer look and typing
expected: Unfocused: 30px pill, "Message orchestrator" placeholder, grey send circle. Focused: accent ring, accent send circle with black arrow, hint row "⏎ send · ⌃U clear line · esc release". Typing activates and releases the keyboard as before (esc releases; clicking another app hands focus back).
result: pending

### 7. Ghost suggestion
expected: With a Claude suggestion in its box and the field empty: ghost text plus a [Tab] accept keycap. Tab accepts, → accepts, a typed letter replaces the ghost.
result: pending

### 8. Ctrl-U
expected: With text in the field, ⌃U mid-line clears from the caret to the line start; the real Claude box is cleared too; a "line cleared" tag shows about 1.2 s; the ghost returns if the field ends up empty.
result: pending

### 9. Terminal draft
expected: Type a draft in the terminal, then focus the notch field: it is pulled in with "from terminal · " prefix (not sent). Sending produces exactly one copy in the transcript.
result: pending

### 10. No duplicates
expected: After Tab-accept, edit and send: no duplicated or concatenated text in Claude.
result: pending

### 11. Prompt answers
expected: 1-9 / esc prompt answers still work when a prompt shows (check again after merging with Phase 6).
result: pending

### 12. Music
expected: play/pause/skip, artwork and the closed-notch music live activity are unchanged with the Orchestrator tab open and closed.
result: pending

### 13. Send clears the real box safely (CR-01)
expected: With a two-line draft in the Claude box, or the cursor moved mid-line, sending from the notch sends nothing and keeps the notch draft. A normal send still works and the extra screen read (up to ~750ms) does not feel slow.
result: pending

### 14. Enter while busy (CR-02)
expected: Pressing Enter while a prompt-option POST is in flight does nothing; the field stays focused and the Claude box is untouched.
result: pending

### 15. /clear (WR-03)
expected: After /clear with the notch open and a new message, the transcript shows only the new conversation within ~2s; normal turns still append with the slide-in, no full-list flash.
result: pending

### 16. Unseen terminal draft (WR-04)
expected: Type in the terminal, wait >2s, focus the notch with text already in the field and press Enter: the terminal draft is put in front with "from terminal · "; a second Enter sends the combined text.
result: pending

### 17. Brief serve outage (WR-05)
expected: Stopping serve for one poll keeps the rows; they switch to the raw tail only after ~3 failed polls (or at once if no rows were loaded).
result: pending

## Summary
total: 17
passed: 0
issues: 0
pending: 17

## Gaps
