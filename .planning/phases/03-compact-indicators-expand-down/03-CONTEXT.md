# Phase 3: Compact Indicators & Expand-Down - Context

**Gathered:** 2026-10-14
**Status:** Ready for planning
**Source:** Orchestrator dispatch brief (user decisions relayed from the orchestrator chat)

<domain>
## Phase Boundary

Closed-notch indicators (attention dot, optional tiny usage) and an expand-down mode in the Orchestrator tab that grows the same notch window further down to show the live terminal (`http://127.0.0.1:4777/term` in a WKWebView), collapsing via the control or a click anywhere outside the notch. Phase 2 (message box, prompt option buttons, Esc, Start/End, gated key-window/canBecomeKey for the message box) is being built IN PARALLEL on another branch and is OUT of scope here.

</domain>

<decisions>
## Implementation Decisions

### Closed-notch indicators (CMP-01, CMP-02)
- D-01: Attention dot on the closed notch whenever `OrchestratorManager.shared.needsAttention` is true — shown EVEN while music plays (small dot at the notch edge alongside the music activity). A waiting question is never hidden (user decision 2026-10-14).
- D-02: Tiny usage indicator on the closed notch only if it fits without hurting music (music closed-notch activity, artwork, sizing must be unchanged). If it cannot fit cleanly, it may be shown only when no music activity is visible, or skipped with a note — Claude's discretion, record the choice.

### Expand-down (EXP-01, EXP-02, EXP-03)
- D-03: An expand control in the Orchestrator tab grows the SAME notch window further DOWN (not a separate window/popover). Top edge stays pinned.
- D-04: Expanded view shows the live terminal: WKWebView on `http://127.0.0.1:4777/term`, created only while expanded and torn down on collapse (ttyd allows one viewer). If the single client is taken / the page fails, show "terminal in use" (or offline) gracefully instead of a broken view.
- D-05: Collapse via the same control, or by clicking anywhere outside the notch. Closing the notch also collapses.
- D-06: The terminal WebView needs keyboard input while expanded. Implement narrowly (panel may become key only while expanded/terminal shown) and isolate it so it merges cleanly with Phase 2's own key-window gating. Note it explicitly in the summary for the merge.

### Merge hygiene with Phase 2 (parallel branch)
- D-07: Put new code in new files under `boringNotch/Orchestrator/`. Keep edits to `OrchestratorView.swift`, `OrchestratorManager.swift` and the window/panel focus code (`BoringNotchWindow`/`canBecomeKey`) minimal, small and isolated (few lines, ideally one hook each). Do not build any Phase 2 feature.
- D-08: Keep the diff to upstream small: minimal hooks into existing files (ContentView, sizing, boringNotchApp panel frame, closed-notch view).

### Safety
- D-09: NEVER POST to 127.0.0.1:4777 (it types into or ends the user's real chat). GETs are fine (but NOT /term: loading /term in a real WebView would connect a ttyd client that can type; do not load it during build/verification; only the user loads it at runtime).
- D-10: Don't launch apps. Build with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-p3 build` (Phase 2 uses /tmp/notch-dd — do not use it).
- D-11: Music must not regress (now-playing, controls, artwork, closed-notch music activity).
- D-12: Never push; stay on the current branch; don't create or switch GSD phase/milestone branches.

### Claude's Discretion
- Expanded height (fit on screen; e.g. ~+300pt), animation, exact dot placement/colour, expand control icon.
- How "terminal in use" is detected (WKNavigationDelegate failure, page content check via JS, or a plain overlay message on load failure).
- Whether a "larger chat view" is also shown when expanded (roadmap EXP-01) — terminal is the primary content; a larger chat tail may be shown when the terminal can't load.
- Tests: pure-function logic (e.g. expanded size/frame math) gets an assert check in the existing `boringNotch/Orchestrator/Tests/main.swift` swiftc harness.

</decisions>

<canonical_refs>
## Canonical References

- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md` (CMP-01, CMP-02, EXP-01..03)
- `.planning/research/` (STACK, ARCHITECTURE, PITFALLS)
- `.planning/phases/01-read-only-orchestrator-tab/` (01-CONTEXT, summaries, verification)
- `boringNotch/Orchestrator/*`, `boringNotch/ContentView.swift`, `boringNotch/sizing/matters.swift`, `boringNotch/boringNotchApp.swift`, `boringNotch/components/Notch/BoringNotchWindow.swift`, `boringNotch/models/BoringViewModel.swift`

</canonical_refs>

<deferred>
## Deferred Ideas

- Message box, prompt option buttons, Esc, Start/End, message-box key-window gating — Phase 2 (parallel branch)

</deferred>

---

*Phase: 03-compact-indicators-expand-down*
*Context gathered: 2026-10-14 from dispatch brief*
