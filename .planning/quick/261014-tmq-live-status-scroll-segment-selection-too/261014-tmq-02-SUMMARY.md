---
phase: quick-261014-tmq
plan: 02
subsystem: orchestrator-chat
tags: [appkit, nstextview, selection, clipboard]
key-files:
  modified:
    - boringNotch/Orchestrator/OrchestratorChat.swift
    - boringNotch/Orchestrator/Snapshots/Snap.swift
metrics:
  tasks: 2
  completed: 2026-10-14
---

# Quick 261014-tmq Plan 02: drag-select transcript text

Drag across transcript text highlights it, copies it to the clipboard on mouse-up and shows a brief "Copied" toast; a plain click still expands the chat.

## Commits
- 7acf696 feat: OrchestratorSelectableText (prose, user compact and bubble), toast, hit-test checks
- c7d4dec feat: tool target (middle truncation for paths), tool result, Edit diff line text

## Design
- `OrchestratorSelectableTextView` (NSTextView subclass, TextKit 1, non-editable, transparent, no link/data detection) + `OrchestratorSelectableText` (NSViewRepresentable) at the end of OrchestratorChat.swift. No new files. `mouseDown` runs `super` (AppKit tracking until mouse-up), then: selection > 0 -> private-able `OrchestratorSelectableText.pasteboard` write + `onCopied`; else `onClick` (= expandChat).
- `sizeThatFits` measures in a fresh text stack (resizing the live container leaves `usedRect` stale, which made the bubble wrong); width = min(used, proposed), so single-line rows truncate and the bubble hugs short text. Baseline via `.alignmentGuide(.firstTextBaseline) { font.ascender }`.
- Prose keeps bold/italic/code from `proseAttributed`; links already stripped (T-tmq-04). The text view never opens the key gate (T-tmq-06). Clipboard written only after a non-empty selection (T-tmq-05).

## Deviations
- [Rule 1] A selectable NSTextView that always accepts first responder made AppKit swallow the next click on the composer/segment (composer click never started typing). `acceptsFirstResponder` is now true only while `mouseDown` tracks.
- [Rule 1] While the "New messages" pill shows, rows get `allowsHitTesting(false)`: AppKit text views win hit tests over SwiftUI overlays, so the pill would have expanded the chat instead of jumping to the bottom. Selecting is unavailable only while the pill is visible.
- Harness: a text view's tracking loop stops the main run loop when it ends, which ended the async `@main` (exit 0, output lost). `--hittest` now drives its own `RunLoop.main.run` spin around `hitTest()`; stdout unbuffered. Settle sleeps after remount (500 -> 1500 ms) and notes open (400 -> 1200 ms) lengthened: the first click after them was lost with text views present (timing in the harness, not seen with real events).
- "Scroll over text works": synthetic wheel events do not move any scroll view in this harness (plan 01 found the same), so the check asserts a text view forwards `scrollWheel` to its enclosing scroll view (spy NSScrollView) rather than driving the real transcript.
- Selection is per row; the toast sits top-centre of the transcript and can overlap the first visible row.

## Verification
swiftc harness OK; xcodebuild BUILD SUCCEEDED; run.sh normal (no FAILED), --hittest (drag copies, drag does not expand, plain click expands, tool target drag copies, scroll over text works, plan 01 scroll lines still true, OK), --transition (both OK), --closed clean. Viewed hittest-selection.png (grey highlight visible in the non-key panel, Copied toast) and before/after of 02, 15, 16, 23, 24: fonts, colours, wrapping, line counts, marker alignment unchanged; text sits up to 1px lower in a few rows (user compact line, diff lines).

## Human UAT
- In the real panel drag-select a prose line, a user message, a tool target and a diff line: highlight is visible and "Copied" shows; Cmd-V elsewhere pastes the text.
- Plain click on the same text still expands; a drag never does.
- Scroll with the pointer over text; the composer and Chat|Runs segment respond on the first click after selecting.

## Known Stubs
None.

## Self-Check: PASSED
