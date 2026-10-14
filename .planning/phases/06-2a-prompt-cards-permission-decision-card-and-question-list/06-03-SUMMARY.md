---
phase: 06-2a-prompt-cards-permission-decision-card-and-question-list
plan: 03
subsystem: prompt-card-ui
tags: [swiftui, keyboard, prompt-card]
requires: [06-01, 06-02]
provides: [hover key-take, free-text send]
key-files:
  modified: [boringNotch/Orchestrator/OrchestratorPromptCard.swift]
requirements: [PRM-04, PRM-05]
metrics:
  completed: 2026-10-14
---

# Phase 6 Plan 03: Hover keys and free text Summary

Resting the pointer ~300ms on a prompt card takes the keyboard (beginTyping, KeyGate.activate, makeKey, local keyDown monitor only). 1-9 and esc answer; for questions up/down move the highlight and return sends the highlighted number (never arrow/enter keys). Every key answer goes through the 06-02 refresh-and-compare guard. The session is released on pointer exit, after an answer, prompt gone, resign key, 600ms give-up and last card unmount. "Something else..." field uses the same session; submit sends the option number, waits, then the text with up to 4 retries; empty text sends nothing. Harness OK, xcodebuild BUILD SUCCEEDED. Commit c2651ec.

## Deviations
- The window reaches question-card subviews via a private environment key holding the anchor NSView; `submitFreeText` takes no window argument.
- Pointer exit does not release while a text edit is active (as the composer does).

## Shared-file edits
none (footprint check prints only Phase 6 files; BoringNotchSkyLightWindow, Manager, Terminal untouched).

## Declined upgrade
Awaitable `pressOption`/`refresh` in the manager (not taken; would be a shared-file edit). RESEARCH assumptions A1-A6 remain to confirm on screen (A1: number-then-text acceptance).

## On-screen checks (for the user)
1. Permission card on a real Bash prompt: title, purpose, `$` command, pills, red Deny esc right; tooltip shows full label; chosen pill fills, others dim ~3s.
2. Hover ~0.3s then press 1 or esc answers; moving away returns focus to the previous app; cmd-Tab/cmd-C still work; notch closes normally after.
3. Question list on a real AskUserQuestion: header tag, wrapped question, highlighted row, notch grows then returns; up/down move highlight, return answers; long lists scroll.
4. "Something else...": click it or press its number, type, return: Claude Code receives number then text (A1); "Chat about this" returns to chat.
5. Multi-question: "1 of 2" then "2 of 2"; Q2 answerable by key without moving the mouse.
6. Capture real Edit/Write, WebFetch, MCP, multi-question screens (GET /api/chat only) as fixtures to replace the synthetic phase6-* ones.
7. Music: now-playing, controls, artwork, closed-notch live activity unchanged.

## Self-Check: PASSED
