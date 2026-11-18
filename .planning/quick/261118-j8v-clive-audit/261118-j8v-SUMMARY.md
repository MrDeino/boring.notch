---
quick_id: 261118-j8v
status: complete
date: 2026-11-18
---

# Quick 261118-j8v: Clive audit (report only)

Wrote `.planning/audits/2026-11-clive-audit.md`: about 45 findings across open/close, chat sync, features, performance, simplification and serve. Each has file:line, trigger, fix and size. Four read-only passes (window/hover, chat/networking, features/perf/dead code, plus serve as part of each); the top findings were re-checked by hand. No code changed, nothing built or run, no requests made to serve.

Top 10: stale full fetch drops newest blocks; merge appends gap blocks at the end; mid-turn send vanishes after 30 s; lock/sleep/display rebuild leaves the panel at 640x210 while still open; expanded→open collapse closes the notch; multi-display close() resets every notch; composer drop closes the notch at 0.5 s; one running:false wipes chat history; building deploys never time out; SSE pushes ~300 KB of full state every 2 s (serve `now` defeats dedupe).
