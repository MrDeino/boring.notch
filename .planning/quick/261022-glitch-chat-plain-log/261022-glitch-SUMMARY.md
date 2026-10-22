---
quick: 261022-glitch
status: complete
---
- No animation on chat growth/pending changes (removed withAnimation in the store, row transitions `.identity`, rows `transaction` animation nil).
- One scroll mechanism: `defaultScrollAnchor(.bottom)` + chatGeometry's single non-animated pin while sticky; removed the pinKey scrollTo and the g.size double scroll. pinKey now only flags unseen rows.
- Status/spinner row is a fixed, always-present slot (blank when idle) and left pinKey.
- `isToolSummary` treats "⏺ Calling X…" / "<Verb>ing…" lines as tool rows, not prose.
- Live row renders through the same markdown renderer as transcript prose (`plain` no longer passed), so the final block replaces it without reflow.
- Tests: QuickGlitchTests (synthetic fixture: tool line + answer, live row = answer only, empty after the block, rows identical before/after). Unit harness OK; Release (ENABLE_HARDENED_RUNTIME=NO) and Debug builds succeeded into ./build. Not launched.
- Not checked on screen: scroll feel under real streaming.
