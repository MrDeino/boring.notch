---
phase: quick-261015-kg6
plan: 01
status: complete
subsystem: orchestrator-tab
tags: [bugfix, chat, transcript]
key-files:
  modified:
    - boringNotch/Orchestrator/OrchestratorTranscript.swift
    - boringNotch/Orchestrator/Tests/Phase5Tests.swift
    - boringNotch/Orchestrator/Snapshots/{Snap.swift,run.sh}
  created:
    - boringNotch/Orchestrator/Snapshots/SnapFullText.swift
metrics:
  completed: 2026-10-15
---

# Quick 261015-kg6: long chat rows show their full text

## Root cause

The text was cut before it reached the view. `proseAttributed` truncated prose to `s.prefix(2000)`, a Phase 5 DoS cap (T-05-02), and did it silently. The block in serve's `/api/chat/blocks` is 2070 chars long, and "…merged into your f" ends at exactly char 2000.

The suspected ev9 fit cache (7212ab7) is not involved. It is cleared on every `current` change and keyed by width, line limit and break mode. The new check passes with the cache unchanged.

## Fix (b38b28d)

- The cap is now 20 000 chars. It still bounds a hostile payload. A cut text now ends in "…", so truncation shows.
- Phase 5 unit check: a message of more than 2000 chars comes through whole. A text over the cap is cut to cap + "…".
- `run.sh --fulltext` hosts the prose row layout (marker, then `OrchestratorSelectableText`) in an NSHostingView. At widths 420/560/760/900, after the text grows twice (streaming) and after the 4-line clamp is lifted, it checks three things: the text view holds the whole text, every glyph is laid out, and the used rect fits inside the frame. With the old cap it fails: `chars 2001/2119`.

## Verification

- swiftc unit harness: OK.
- `run.sh --fulltext`: `OK: fulltext`, with all 8 cases ok.
- `--idle` passes at both -Onone and -O, with all latency gates under 16 ms. CPU vs ev9 after:

| Scene | -O ev9 | -O now | -Onone ev9 | -Onone now |
|---|---|---|---|---|
| e expanded, doing ticks | 1.7 | 1.3 | 1.5 | 0.7 |
| f rich tick | 3.5 | 3.2 | 4.0 | 3.2 |
| g typing 10 keys/s | 11.8 | 7.4 | 14.9 | 6.4 |

- `--frames` was not run: that mode exists only on the animation run's branch (quick-hmo 063209c), not on this one.
- `** BUILD SUCCEEDED **`: Release in /tmp/notch-rel (ad-hoc, ENABLE_HARDENED_RUNTIME=NO, ORCH_NO_SPARKLE; codesign `flags=0x2(adhoc)`) and Debug in /tmp/notch-dd. Both built on the first try (no collision). Run 29b9 builds to the same paths, so a later build there replaces these.
- No app was launched or quit, the cursor was not moved, and the stray `graft/` folder was removed. Nothing was pushed.

## Note

The open level still clamps prose to 4 lines with a tail "…" (tap expands), as designed since Phase 5. The expanded level shows everything.
