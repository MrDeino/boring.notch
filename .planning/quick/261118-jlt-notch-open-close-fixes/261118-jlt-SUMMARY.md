---
quick_id: 261118-jlt
status: complete
date: 2026-11-18
commit: da2db57
---

# Quick 261118-jlt summary: notch opens and closes predictably

Audit findings A1-A4 fixed in one code commit (`da2db57`, 8 files, +72/-11).

- **A1:** lock (without show-on-lock-screen), sleep and display changes close every notch first, releasing the expand and typing holds, so a rebuilt 640x210 panel never sits under an open/expanded view model. New panels are registered with `OrchestratorExpand` and sized at once. Wake re-places panels and re-arms drag detectors (also covers A10).
- **A2:** going back from expanded to open (Back button, ⌘↑, dismissing a run log) holds the notch open for 1.2 s or until the next hover-enter. An outside click still collapses and closes at once.
- **A3:** `close()` on an already-closed notch is a size refresh only. `notchOpen` now means "any notch open"; the shared tab, last-used view and sneak peek change only when the last open notch closes.
- **A4:** a drag over the chat box counts as a notch drop target, and a drop there sets `dropEvent`, so the 500 ms drop debounce no longer closes the notch.

## Checks
- swiftc harness: OK (new `Tests/QuickJltTests.swift`: close-keeps-shared-state, hold deadline, rebuilt panel size).
- Snapshots: default (52 scenes), `--transition`, `--idle`: OK.
- Debug and Release (`ENABLE_HARDENED_RUNTIME=NO`, `ORCH_NO_SPARKLE`) builds succeed into `./build`.

## Known limits
- If the pointer ends up outside the notch after the 1.2 s hold, the notch stays open until an outside click or a hover in and out (by design: going back should not close).
- Another display's per-vm fits are still cleared only when the last notch closes; the views re-set them when they reappear.
- A notch open during a display change now comes back closed (not restored).
- The first-launch hello animation's close no longer resets the tab (the notch is closed during it).

## Check by hand
1. Open the notch, expand it (open a run log), lock the screen, unlock: the notch is closed and opens normally on hover at full size. Repeat with sleep/wake, and by plugging or unplugging a display or changing resolution.
2. Expand, then press Back / ⌘↑ / click empty space with the pointer low in the panel: the notch goes back to open and stays open; moving out and back in, then out, closes it. An outside click while expanded still closes it.
3. With "show on all displays" and two displays: open display A on the Orchestrator tab (and expanded), then hover/close display B or change display B's settings: A stays open, on its tab, at its level.
4. Drag a file over the chat box and hold it there for over a second: the notch stays open. Drop it: the chip appears and the notch stays open.
5. Music: now-playing and controls still work in the open and closed notch.
