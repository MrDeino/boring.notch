# Quick 261017-snl: dropped/pasted files upload to the chat as real files

Goal: any file dropped on the notch or pasted into the composer goes to POST /api/chat/file (x-orch: 1, x-filename, raw body, <= 200 MB, returns {path}); real images keep /api/chat/image; drops go to the chat, not the shelf, while the Orchestrator tab is current.

Tasks (done inline, one commit):
1. OrchestratorModels.swift: file request, streaming upload with progress, FileChip, serial OrchestratorFileQueue, drop routing helpers.
2. Chat composer: chips (name, size, progress, done/failed), drop + Cmd-V of Finder files, send waits for uploads, `[file: path]` in the wire text.
3. ContentView + OrchestratorView: Orchestrator tab keeps drops (closed-notch drag keeps the tab, drop handled by the tab); other tabs unchanged (shelf).
4. Tests: QuickFilesTests.swift + file-mock.py (47999), snapshot scene 58.
