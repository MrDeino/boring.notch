---
quick_id: 261017-key
---

# Quick 261017-key: question card taps are instant and queued

Goal: ticking several options quickly all apply, in order, with no lock. Optimistic ticks; one ordered key queue (`PromptKeyQueue`) sends to serve back-to-back; after the drain the screen is compared with the ticks (reconcile, "Re-synced" notice on a lost key); Next/Submit settles the queue and verifies before sending Tab. Digits and clicks share `toggle`/`answer`.
