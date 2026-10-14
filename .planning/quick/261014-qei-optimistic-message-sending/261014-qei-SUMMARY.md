# Quick 261014-qei: Optimistic message sending

Enter clears the composer at once and keeps focus; the message shows as a dimmed pending row, sends queue in order through `sendText`, the real user block replaces the row, and failures show "Not sent" with Retry/Edit.

## Commits
- fbaa7e6: pure PendingMessage / normalizeChatText / reconcilePending + QuickQeiTests
- (second commit, see git log): store queue, optimistic submit, pendingRow UI, snapshot scenes 25-27

## Results
- swiftc harness: OK (runQuickQeiTests covers all behaviours).
- xcodebuild: BUILD SUCCEEDED.
- Snapshots: no FAILED. Looked at 25-chat-pending, 26-chat-not-sent, 27-expanded-pending (dimmed rows, "Not sent / Retry / Edit" readable, not clipped, aligned right in the bubble view and indented under the marker in compact), plus 15 and 23 (unchanged).

## Deviations
None. Removed `store.submit` (only caller was the view); the "Couldn't send" tag path in submit is gone. `flashTag` is still used elsewhere.
