---
status: complete
---
# 261022-ctx: Session context in the usage menu

- Usage menu (status capsule button) gets a "Session context" row: % bar (same style as the usage bars), `tokens / window`, and "as of <time>" when the chat is not running.
- Manager keeps `lastContext` (serve `context.{percent,tokens,window}`); kept through idle/offline, time moves only when the numbers change. Corner "ctx %" untouched.
- Auto-compact distance: serve sends no such field (only tokens/window/percent), so it is not shown.
- Menu now scrolls inside its box when taller than the open-level tab (ViewThatFits), so the new row does not clip Open terminal/Interrupt/End.
- Tests: Tests/QuickCtxTests.swift (parse, percent fallback, token label). Snapshots 74/75/76 (working, idle "as of", never seen).
- Checks: swiftc harness OK; run.sh default OK; Debug and Release (adhoc, ORCH_NO_SPARKLE, hardened runtime off) BUILD SUCCEEDED, copied to build/notch-rel and build/notch-dbg.
