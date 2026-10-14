# Merge map — Phases 5, 6, 7 in parallel (after Phase 4)

**Decided:** 2026-10-14 (orchestrator, from the user's instruction that 5, 6 and 7 run in parallel on separate branches and are then merged).

Phase 4 lays down every file and hook the three parallel phases need, so each parallel phase mostly **fills in files it owns** and touches shared files only at the merge points listed here. Any edit to a shared file that is not listed must be called out in that plan's `<merge_points>` section and in its SUMMARY.

## Phase 4 pre-creates (empty stubs, registered in project.pbxproj)

Phase 4 adds every file below to the Xcode project (file reference, group entry, Sources build phase) so that **Phases 5–7 never edit `project.pbxproj`**. Each stub compiles (an empty view, `EmptyView()` body, or a function returning today's behaviour).

| File (under `boringNotch/Orchestrator/`) | Owner | Phase 4 content |
|---|---|---|
| `OrchestratorTokens.swift` | Phase 4 | Full design tokens (colours, fonts, radii, spacing). Later phases may **append** tokens at the end only. |
| `OrchestratorView.swift` | Phase 4 (shell) | Thin shell: state switch connecting → offline → stopped → runs board → prompt card → chat. |
| `OrchestratorStatusCapsule.swift` | Phase 4 | Capsule, usage ring, status menu (06), header segment. |
| `OrchestratorStates.swift` | Phase 4 | Stopped (07), offline (08), connecting (09). |
| `OrchestratorChat.swift` | **Phase 5** | Phase 4: today's chat tail + composer moved here, restyled minimally with tokens. |
| `OrchestratorTranscript.swift` | **Phase 5** | Pure: `ChatBlock` decoding, `/api/chat/blocks` merge, `inputLine` parse. Stub types/functions. |
| `OrchestratorPromptCard.swift` | **Phase 6** | Phase 4: today's option buttons + esc moved here. |
| `OrchestratorPromptParse.swift` | **Phase 6** | Pure: `PromptOption`, `PromptCard`, `detectPrompt` moved here from Models, plus `detectPromptCard(screen:) -> PromptCard?` wrapping it (title/purpose nil). |
| `OrchestratorRunsBoard.swift` | **Phase 7** | Phase 4: today's runs strip moved here. |
| `OrchestratorRunsPure.swift` | **Phase 7** | Pure: run elapsed / sorting helpers (stub). |
| `OrchestratorExpanded.swift` | **Phase 7** | Expanded body + runs rail (stub `EmptyView`). |
| `OrchestratorWings.swift` | **Phase 7** | Closed-notch wings (stub). |
| `Tests/Phase4Tests.swift` … `Tests/Phase7Tests.swift` | each phase | `func runPhaseNTests() {}`; `Tests/main.swift` already calls all four. |

The swiftc harness command, fixed in Phase 4 and used unchanged by 5–7:

`mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/OrchestratorStream.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t`

(Pure files import Foundation/CoreGraphics only — never SwiftUI or app types.)

## Shared hooks Phase 4 wires (so 5–7 replace stub bodies, not shared lines)

| Shared file | Hook Phase 4 adds | Who fills it |
|---|---|---|
| `OrchestratorManager.refresh()` | after decoding `/api/chat`: `prompt = running ? detectPromptCard(screen:) : nil` (keeps `promptOptions`), `liveStatus = parseLiveStatus(screen:)`, and one call `await transcript.refresh(...)` into a Phase 5-owned object/function that does nothing in Phase 4 | 5 (transcript), 6 (parser body) |
| `OrchestratorManager` poll loop | interval from `pollInterval(notchOpen:chatRunning:)` in `OrchestratorRunsPure.swift` returning today's 2/10 | 7 (3s closed while running) |
| `OrchestratorModels.allowedKeys` | `"C-u"` added in Phase 4 (serve already allows it) | — |
| `OrchestratorExpand` | `ExpandLevel { open, expanded, terminal }`, `level(for:)`, `setLevel(_:vm:window:)`; today's expand maps to `.terminal`; `.expanded` reuses the same window growth without the terminal | 6 calls it (question card), 7 owns behaviour/animation |
| `BoringHeader.swift` | left: `OrchestratorHeaderSegment()` after `TabSelectionView()`; right: `OrchestratorHeaderTrailing()` (capsule; Phase 7 adds the ⌃ collapse button inside it) | 7 edits inside `OrchestratorStatusCapsule.swift` → **merge point** with nobody else |
| `ContentView.swift` | unchanged in Phase 4 (closed indicators overlay stays) | 7 only |

## Per-phase ownership of shared files

- **Phase 5** edits: `OrchestratorChat.swift`, `OrchestratorTranscript.swift`, `Tests/Phase5Tests.swift`. Shared: `OrchestratorManager.swift` — only stored `@Published` properties it needs (`blocks`, `inputLine`) in a block marked `// Phase 5`, if they can't live on its own object. No edits to Models, Expand, header, pbxproj.
- **Phase 6** edits: `OrchestratorPromptCard.swift`, `OrchestratorPromptParse.swift`, `Tests/Phase6Tests.swift`. Shared: hover key handling may need one hook on the panel/view — keep it inside the Orchestrator folder. Calls `OrchestratorExpand.setLevel(.expanded, …)` for tall questions (API from Phase 4, no edit).
- **Phase 7** edits: `OrchestratorRunsBoard.swift`, `OrchestratorRunsPure.swift`, `OrchestratorExpanded.swift`, `OrchestratorWings.swift`, `OrchestratorExpand.swift`, `OrchestratorCompact.swift`, `OrchestratorTerminal.swift`, `Tests/Phase7Tests.swift`, `OrchestratorModels.swift` (`OrchestratorRun` optional fields only), `ContentView.swift` (wings), a `Defaults` key in its own file, and the trailing header view in `OrchestratorStatusCapsule.swift`.

## Expected merge conflicts (resolve at merge)

1. `OrchestratorManager.swift` — Phase 5 `// Phase 5` property block vs. nothing else expected (7 uses the pure `pollInterval`). If 7 needs manager state (e.g. finished-run tracking for wings) it adds a `// Phase 7` block at a different spot.
2. `Tests/main.swift` — none expected (Phase 4 already calls all runners).
3. `.planning/STATE.md` / `ROADMAP.md` — always; keep both sides.
4. Expanded view embeds `OrchestratorChatView` (Phase 5 rows) and `OrchestratorPromptCard` (Phase 6) by type name, so after merge 7's expanded column shows 5's rows without code changes.

## Post-research amendments (2026-10-14)

- `ExpandLevel` enum lives in `OrchestratorPure.swift` (Phase 4). `OrchestratorExpand` also gets `transcriptTapped(vm:window:)` (Phase 4 → `.terminal`; Phase 7 changes it to `.expanded`). The chat calls it, so Phase 5 never edits for Phase 7.
- The shell renders `OrchestratorExpandedView()` when level != `.open` (Phase 4 hook; stub reproduces today's expanded behaviour). Phase 7 fills it; nobody else edits the shell.
- `OrchestratorChatView(showComposer: Bool = true)` from Phase 4; Phase 5 keeps the parameter.
- Phase 4 may make a one-line padding edit in `TabButton.swift` (header fit).
- `pollInterval(notchOpen:chatRunning:offline:)`.
- (Revision after planning) The shell shows `OrchestratorPromptCard()` **instead of** `OrchestratorChatView()` while `manager.prompt != nil` (README 03: the card replaces the transcript). Phase 7's expanded view must do the same in its conversation column (show `OrchestratorPromptCard()` while a prompt is up) so a question card that raised the notch to `.expanded` stays visible.
- Phase 8 adds `OrchestratorStream.swift` (pure, in the harness command above) and `Tests/Phase8Tests.swift`.
