---
status: complete
---
# Quick 261017-snl summary

- Upload: `uploadOrchestratorFile` streams from disk (`URLSession.upload(fromFile:)`, own session with a 60 s request / 1 h resource timeout), progress from the task delegate. `OrchestratorFileQueue` uploads chips one at a time. Over 200 MB fails at once ("Over 200 MB", never sent); 413 -> "Too big"; a vanished file -> "File gone"; anything else "Upload failed" (click the chip to retry, x removes).
- `x-filename`: plain when printable ASCII, else NFC + percent-encoded (serve is not built yet; if it does not decode, ASCII names are unaffected).
- Wire text: `[file: <server path>]`, like `[image: ...]`. Send is disabled / refused while a chip is uploading or failed.
- Routing: image-type files (Finder drop or paste) and non-file images still use /api/chat/image. Finder paste reads file URLs before the image on the pasteboard (that image was the file's icon). File promises (no file URL) are copied to a temp dir and uploaded, then deleted.
- Drops: OrchestratorView takes drops anywhere (composer's own onDrop wins). ContentView: a drag onto the closed notch opens to the shelf only when Orchestrator is not the current tab; a drop on the closed notch goes to the Orchestrator when it is. Home/Shelf tabs are untouched.
- Entitlements: unchanged. `files.user-selected.read-write` was already there; drag/paste URLs arrive with their own sandbox extension and the upload brackets them with start/stopAccessingSecurityScopedResource. Not verified against a real Finder drop/paste in the sandboxed app (no UI session here).
- Tests: `runQuickFilesTests` (unit) and `runQuickFilesMock` with `ORCH_FILE_MOCK=1` against `Tests/file-mock.py`: CSV, 6 MB video, two files at once (sequential, in order), image routing (/api/chat/image vs /api/chat/file), shelf-owns-drops on other tabs (pure predicate), errors (500, 413, no server, oversize, vanished, retry, non-ASCII name). Synthetic files only.
- Checks: swiftc harness OK (plain and with mock); xcodebuild Debug and Release (adhoc, ORCH_NO_SPARKLE, hardened runtime off) BUILD SUCCEEDED, Release copied to build/notch-rel/Clive.app; run.sh default, --idle, --closed, --cardfit pass; snapshot 58 viewed.
- Not covered by automation: the real SwiftUI drag/drop hit-testing and the closed-notch drag-open path (ContentView) — the routing predicate is tested, the wiring is not.
