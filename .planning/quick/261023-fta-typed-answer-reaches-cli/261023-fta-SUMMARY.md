---
status: complete
---
# Typed answer in the question card reaches the CLI

Reproduced on a live Claude Code 2.1.309 AskUserQuestion (2 questions): pressing the free-text row's number only moves the ❯ onto an inline input (label stays "Type something.", footer gains "ctrl+g to edit in Vim"). The prompt identity does not change, so `submitFreeText`'s "select list has left the screen" wait never succeeded and it restored with "Didn't go through". Typing text + Enter into the field then advances to the next question (or ends the prompt).

Fix: `freeTextFocused` (OrchestratorPromptParse.swift) = ❯ on the free-text row; `submitFreeText` waits for that instead (and skips the digit if the ❯ is already there), keeps the card up on multi-question prompts (`hidesOnAnswer`), and after sending checks the screen moved on, else restores with "Didn't go through" and the typed text.

Tests: QuickFreetextTests (1q and 2q fixtures from the real capture). swiftc harness OK; Debug and Release (ENABLE_HARDENED_RUNTIME=NO) BUILD SUCCEEDED in ./build.
