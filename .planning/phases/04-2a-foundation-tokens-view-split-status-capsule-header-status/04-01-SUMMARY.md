---
phase: 04-2a-foundation-tokens-view-split-status-capsule-header-status
plan: 01
subsystem: ui
tags: [swift, swiftui, pbxproj, tokens, harness]
requires: []
provides:
  - pure seams (live status, capsule state, poll interval, prompt card)
  - OT design tokens
  - 11 registered Orchestrator files (Phases 5-7 never edit project.pbxproj)
  - manager and ExpandLevel hooks
affects: [04-02, 04-03, 05, 06, 07]
tech-stack:
  added: []
  patterns: [pure Foundation-only helpers covered by swiftc harness]
key-files:
  created: [OrchestratorTokens, OrchestratorPromptParse, OrchestratorRunsPure, OrchestratorTranscript, OrchestratorChat, OrchestratorExpanded, OrchestratorStatusCapsule, OrchestratorStates, OrchestratorPromptCard, OrchestratorRunsBoard, OrchestratorWings, Tests/Phase4-7Tests, Tests/fixtures/working.txt]
  modified: [OrchestratorModels, OrchestratorPure, OrchestratorManager, OrchestratorExpand, OrchestratorView, project.pbxproj]
key-decisions:
  - "Contract signatures unchanged; no deviations"
requirements-completed: [FND-01, FND-07]
duration: 15min
completed: 2026-10-14
---

# Phase 4 Plan 01: Foundation seams Summary

Shared seams for Phases 5-7: pure helpers with harness asserts, OT tokens, 11 files registered in project.pbxproj, manager and ExpandLevel hooks, "C-u" allowed key. User-visible behaviour unchanged.

## Commits
- 93b4770 test(04-01): failing harness asserts (RED)
- 4d67bea feat(04-01): pure seams (GREEN)
- 31870e3 feat(04-01): tokens, stubs, pbxproj registration
- a20c6b1 feat(04-01): manager hooks and ExpandLevel API

## Verification
Harness prints OK; xcodebuild into /tmp/notch-dd BUILD SUCCEEDED; plutil OK; 44 pbxproj ID lines; no file outside boringNotch/Orchestrator/ and project.pbxproj changed (no music files); no POST sent, no app launched.

## Deviations from Plan
None - plan executed as written (derived data path /tmp/notch-dd per instruction). Not assertable in harness: `grow` is a no-op without a window, so `terminal` only gets the key when `expanded` contains it.

## Known Stubs
OrchestratorExpandedView (EmptyView), OrchestratorTranscriptStore.refresh (empty), and the five comment-only SwiftUI files are intentional; filled by 04-02, 04-03 and Phases 5-7.

## API contract (binding for 04-02, 04-03, Phases 5-7)

` below exists and compiles; Plans 02 and 03 and Phases 5–7 code against it. Behaviour visible to the user is unchanged.
Output: new pure/stub/tokens files, Tests/Phase4..7Tests.swift, fixture working.txt, pbxproj registration, manager + expand hooks.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/phases/04-2a-foundation-tokens-view-split-status-capsule-header-status/04-CONTEXT.md
@.planning/phases/04-2a-foundation-tokens-view-split-status-capsule-header-status/04-RESEARCH.md
@.planning/design/orchestrator-2a/MERGE-MAP.md
@.planning/design/orchestrator-2a/README.md

<safety>
- NEVER POST to 127.0.0.1:4777 (it types into or ends the user's real chat). Never load /term. GET /api/chat is allowed only for capturing fixtures.
- Do not launch the app or any app. Build only.
- Never push. Stay on the current branch. No GSD phase/milestone branches.
- Music must not regress: touch no file outside boringNotch/Orchestrator/ and project.pbxproj in this plan.
</safety>

<commands>
HARNESS (MERGE-MAP, fixed; Phases 5–7 use it unchanged):
mkdir -p /tmp/orch-test && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swiftc -o /tmp/orch-test/t boringNotch/Orchestrator/OrchestratorModels.swift boringNotch/Orchestrator/OrchestratorPure.swift boringNotch/Orchestrator/OrchestratorTranscript.swift boringNotch/Orchestrator/OrchestratorPromptParse.swift boringNotch/Orchestrator/OrchestratorRunsPure.swift boringNotch/Orchestrator/Tests/*.swift && /tmp/orch-test/t
(expected last line: OK)

BUILD:
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -derivedDataPath /tmp/notch-dd-p4 build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -20
(expected: BUILD SUCCEEDED, no error: lines)
</commands>

<api_contract>
BINDING for Plans 04-02, 04-03 and Phases 5, 6, 7. Names and signatures are final; later phases add, never rename.

OrchestratorPure.swift (Phase 4; Foundation + CoreGraphics only):
- enum ExpandLevel: Equatable { case open, expanded, terminal }
- struct LiveStatus: Equatable { let text: String; let elapsed: TimeInterval? }   // text = spinner verb, e.g. "Working…"; elapsed seconds parsed from the parenthesised duration
- func parseLiveStatus(screen: String) -> LiveStatus?   // nil unless a line in the last 30 matches the glyph line AND its paren part contains "esc to interrupt"
- func formatElapsed(_ seconds: TimeInterval) -> String   // 41 -> "0:41", 112 -> "1:52", 3720 -> "1:02:00"
- enum CapsuleState: Equatable { case connecting, offline, stopped, needsYou, running, idle }
- func capsuleState(hasLoaded: Bool, offline: Bool, chatRunning: Bool, needsAttention: Bool, working: Bool) -> CapsuleState   // D-04 order: connecting, offline, stopped, needsYou, running, idle
- func liveRunCount(_ runs: [OrchestratorRun]) -> Int   // state in running/waiting/stuck
- func fiveHourFraction(_ u: OrchestratorUsage?) -> Double?   // 5h used_percentage / 100 clamped 0...1, nil when unknown (usageFraction stays max(5h,7d) for the closed hairline)
- func usageIsHigh(_ percent: Double?) -> Bool   // percent >= 80

OrchestratorPromptParse.swift (Phase 6 owns after Phase 4; Foundation only):
- struct PromptOption: Equatable { let number: Int; let label: String }   // moved verbatim from Models
- func detectPrompt(screen: String) -> [PromptOption]   // moved verbatim
- struct PromptCard: Equatable { enum Kind: Equatable { case permission, question }; var title: String? = nil; var purpose: String? = nil; var body: String? = nil; var options: [PromptOption]; var kind: Kind; var header: String? = nil; var progress: String? = nil }   // memberwise init PromptCard(options:kind:) works; Phase 6 adds fields only with defaults
- func detectPromptCard(screen: String) -> PromptCard?   // nil when detectPrompt is empty; Phase 4 kind = .question if any label == "Type something." else .permission; title/purpose/body/header/progress nil

OrchestratorRunsPure.swift (Phase 7 owns after Phase 4; Foundation only):
- func pollInterval(notchOpen: Bool, chatRunning: Bool, offline: Bool = false) -> TimeInterval   // Phase 4: offline 10, open 2, else 10 (chatRunning unused; Phase 7 makes closed+running 3)

OrchestratorTranscript.swift (Phase 5 owns; Foundation only): empty in Phase 4 except `import Foundation` and an owner comment.

OrchestratorModels.swift: OrchestratorPost.allowedKeys gains "C-u".

OrchestratorTokens.swift (Phase 4; later phases append at end only): `enum OT` with nested enums, plus `fileprivate extension Color { init(hex: UInt32) }` at the bottom of the file:
- OT.C (Color): notch #000000, raised #1C1C1E, diffCard #141416, terminal #0B0B0C, selected #2C2C2E, selected2 #3A3A3C, divider #1C1C1E, divider2 #2C2C2E, text #FFFFFF, text1 #E5E5EA, text2 #D1D1D6, text3 #C4C4C6, text4 #AEAEB2, text5 #8E8E93, text6 #636366, claude #D97757, green #30D158, orange #FF9F0A, orangeText #FFB35C, orangeBg #3A2410, red #FF453A, redText #FF6961, redBg #2A1A19
- OT.F (Font): title .system(size: 14, weight: .semibold), stateTitle .system(size: 14, weight: .medium), prose 13, ui 12, uiMedium .system(size: 12, weight: .medium), meta 11, hint 10, tiny 9, monoCommand .system(size: 12, design: .monospaced), monoPath 11 mono, monoChip 10 mono
- OT.R (CGFloat): notchOpen 24, notchExpanded 26, dropdown 22, notchClosed 12, cardL 12, cardM 10, cardS 9, pill30 15, pill28 14, keycap 4
- OT.S (CGFloat): header 34, padTop 0, padH 14, padBottom 12, gapS 5, gapL 9

OrchestratorManager (shared file; new members in one `// Phase 4` block):
- @Published var showRunsBoard = false   // renamed from showRuns (Chat | Runs segment state)
- @Published var statusMenuOpen = false   // reset to false when notchOpen becomes false and on refresh error
- @Published private(set) var prompt: PromptCard? = nil   // running ? detectPromptCard(screen:) : nil; promptOptions kept as is
- @Published private(set) var liveStatus: LiveStatus? = nil   // running ? parseLiveStatus(screen:) : nil
- var capsuleStatus: CapsuleState { capsuleState(hasLoaded: hasLoaded, offline: offline, chatRunning: chatRunning, needsAttention: needsAttention, working: liveStatus != nil) }
- refresh() calls `await OrchestratorTranscriptStore.shared.refresh(base: Self.baseURL, session: session, screen: s, chatRunning: running)` once per successful poll (after prompt/liveStatus are set)
- poll loop sleeps `pollInterval(notchOpen: notchOpen, chatRunning: chatRunning, offline: offline)` seconds
- Existing unchanged: offline, chatRunning, screen, runs, usage, promptOptions, needsAttention, hasLoaded, notchOpen, wantsKeyboard, sending, optionsLocked, keyboardWindow, beginTyping(in:), endTyping(), sendText(_:), pressEscape(), startChat(), stopChat(), pressOption(_:), refresh(), start()

OrchestratorChat.swift (Phase 5 owns; Phase 4 creates):
- @MainActor final class OrchestratorTranscriptStore: ObservableObject { static let shared = OrchestratorTranscriptStore(); func refresh(base: URL, session: URLSession, screen: String, chatRunning: Bool) async {} }   // Phase 5 fills the body; must keep class name, `shared` and this signature (the call site in the manager is shared with Phase 6)
- (Plan 04-02 adds) struct OrchestratorChatView: View { init(showComposer: Bool = true) }

OrchestratorExpand (Phase 7 owns behaviour after Phase 4):
- @Published private(set) var terminal: Set<ObjectIdentifier>   // per-vm terminal flag, subset of `expanded`
- func level(for vm: BoringViewModel) -> ExpandLevel
- func setLevel(_ level: ExpandLevel, vm: BoringViewModel, window: NSWindow?)   // .open = collapse; .expanded = grow window (same growth as today), no terminal; .terminal = grow + terminal; invariant terminal ⊂ expanded: insert into `terminal` only when `expanded.contains(k)` after grow (grow is a no-op when window is nil)
- func transcriptTapped(vm: BoringViewModel, window: NSWindow?)   // Phase 4: setLevel(.terminal); Phase 7 changes to .expanded. The chat calls only this.
- `expand(vm:window:)` is removed (its body becomes the private grow step); kept: isExpanded(_:), openSize(for:), collapse(vm:refocus:), reset(), releaseKey(_:refocus:)
- OrchestratorExpandOverlay shows the terminal only when level(for: vm) == .terminal

Stub views created here, filled later:
- OrchestratorExpanded.swift: struct OrchestratorExpandedView: View   // Phase 4 body EmptyView; Plan 04-02 sets today's behaviour; Phase 7 replaces
- OrchestratorStatusCapsule.swift, OrchestratorStates.swift, OrchestratorPromptCard.swift, OrchestratorRunsBoard.swift, OrchestratorWings.swift: `import SwiftUI` + owner comment only (filled by 04-02 / 04-03 / Phase 7)

Tests:
- Tests/Phase4Tests.swift `func runPhase4Tests()`, Tests/Phase5Tests.swift `func runPhase5Tests() {}`, Tests/Phase6Tests.swift `func runPhase6Tests() {}`, Tests/Phase7Tests.swift `func runPhase7Tests() {}`; main.swift calls runPhase3Tests(), runPhase4Tests(), runPhase5Tests(), runPhase6Tests(), runPhase7Tests() then print("OK"). Later phases add fixtures as Tests/fixtures/phaseN-*.txt/json and may use the global `fixture(_:)` helper from main.swift (reads .txt only).

project.pbxproj IDs (file ref / build file), group 0A1C00000000000000000007, Sources phase 14CEF40E2C5CAED300855D72:
OrchestratorTokens 0A1C00000000000000000401/451, OrchestratorStatusCapsule 402/452, OrchestratorStates 403/453, OrchestratorChat 404/454, OrchestratorTranscript 405/455, OrchestratorPromptCard 406/456, OrchestratorPromptParse 407/457, OrchestratorRunsBoard 408/458, OrchestratorRunsPure 409/459, OrchestratorExpanded 410/460, OrchestratorWings 411/461 (all prefixed 0A1C00000000000000000, i.e. 24 hex chars).

## Self-Check: PASSED
