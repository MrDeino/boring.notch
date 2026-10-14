# Quick 261014-r8w Summary

Question-chip back-navigation (BTab) plus a notes drop-down in the Orchestrator header (GET on open, 1s autosave).

## Commits
- 2fd3f17: tasks 1+2 (back-nav, allowedKeys, notes request/loader, tests, mock round trip). Combined because both touch OrchestratorModels.swift and the test files.
- 6f094c3: task 3 (note button, panel, store, snapshots, hit test).

## Observed (fresh capture, Claude Code 2.1.299, tmux notch-fixture, 3-question AskUserQuestion)
- BTab goes to the previous chip (Q3 -> Q2 -> Q1). Left does the same, Right = Tab. BTab also leaves the review step (review -> Size).
- Ticks survive: Q1's `[✔] apple` was still ticked after BTab back from Q3 (chip stays ☒ Fruit). Fixture: Tests/fixtures/multiq-back.txt.
- Chosen back key: `BTab` (`promptBackKey`). Backward is allowed from review; forward from review is nil.

## Results
- swiftc harness: OK offline; OK with ORCH_NOTES_MOCK=1 against /tmp/orch-notes-mock.py on 47999 (POST+GET round trip of multi-line unicode, empty text, 400 without x-orch). Nothing listening on 47999 afterwards.
- xcodebuild: BUILD SUCCEEDED. Snapshots: 30 written, no FAILED. --hittest: OK, includes "notes button opens panel: true".
- PNGs viewed: 28, 29, 30, 15, 19. Note button is a 24pt circle beside the capsule and fits the header; panel is #1C1C1E, 12pt radius, inside the notch; "Saved" / "Couldn't save" visible; expanded panel clips/scrolls; in 19 the Fruit chip is styled like the other chips (not dimmed). No fixes needed.
- tmux: notch-fixture killed; `tmux ls` shows only `orchestrator`. Temp dir removed. No POST to 4777; app not launched.

## Behavior notes
- Autosave only after a successful GET; text equal to the server copy (`synced`) is not treated as an edit, so loading never triggers a save. A reload while an unsaved/failed edit is pending is skipped. Close/Esc/disappear flush.
- Notch grows to .expanded on open only if body height < 130pt (never triggered in snapshot 28, which fits at the open level); undone on close only if we grew it.
- Live typing/keyboard hand-over (beginTyping, KeyGate) and Esc monitor are built per the chat view pattern but not exercised in the app (no app launch allowed); only compiled and hit-tested.

## Deviations
- Tasks 1 and 2 share one commit (see above).
- Trust-folder prompt in the throwaway tmux claude session was dismissed with Down+Enter; an initial "1" keypress exited that first session, which was restarted.

## Known stubs
None.

## Self-Check: PASSED
