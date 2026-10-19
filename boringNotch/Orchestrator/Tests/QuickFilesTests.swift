import Foundation
import AppKit
import Combine

/// Synthetic files only (generated into a temp dir); names and bytes are made up.
func runQuickFilesTests() {
    // Header and wire text
    precondition(orchestratorFilenameHeader("data.csv") == "data.csv" && orchestratorFilenameHeader("my file.csv") == "my file.csv")
    precondition(orchestratorFilenameHeader("caf\u{e9}.csv") == "caf%C3%A9.csv" && orchestratorFilenameHeader("a%b.csv") == "a%25b.csv")
    precondition(orchestratorFilenameHeader("a\r\nx-evil: 1") == "a%0D%0Ax-evil%3A%201")
    let rq = orchestratorFileRequest(name: "data.csv", base: URL(string: "http://127.0.0.1:1")!)
    precondition(rq.httpMethod == "POST" && rq.url!.path == "/api/chat/file" && rq.value(forHTTPHeaderField: "x-orch") == "1")
    precondition(rq.value(forHTTPHeaderField: "x-filename") == "data.csv" && rq.httpBody == nil) // body streams from disk
    precondition(chatTextWithImages("look", paths: ["/a.png"], files: ["/f/data.csv"]) == "look [image: /a.png] [file: /f/data.csv]")
    precondition(chatTextWithImages("", paths: [], files: ["/f/a.csv", "/f/b.mov"]) == "[file: /f/a.csv] [file: /f/b.mov]")
    var m = PendingMessage(id: 1, text: "see", state: .sent, sentAt: Date())
    m.files = [FileChip(id: 1, url: URL(fileURLWithPath: "/x/data.csv"), name: "data.csv", size: 8, state: .done("/f/data.csv"))]
    precondition(m.wireText == "see [file: /f/data.csv]")
    precondition(reconcilePending([m], blocks: [ChatBlock(pendingID: "u1", text: "see [file: /f/data.csv]")], known: [], now: Date()).pending.isEmpty)

    // Routing: images keep the image path, everything else is a file; the shelf only loses drops on the Orchestrator tab
    let u = { (n: String) in URL(fileURLWithPath: "/tmp/\(n)") }
    for n in ["a.png", "b.JPG", "c.heic", "d.gif"] { precondition(orchestratorDropKind(u(n)) == .image) }
    for n in ["data.csv", "clip.mov", "notes.txt", "doc.pdf", "bundle.zip", "noext"] { precondition(orchestratorDropKind(u(n)) == .file) }
    precondition(orchestratorOwnsDrops(orchestratorIsCurrentTab: true))
    precondition(!orchestratorOwnsDrops(orchestratorIsCurrentTab: false)) // home / shelf tab: the shelf keeps its drops
    // Drag routing: selected tab or last-used tab (closed notch) sends to the chat; shelf only when another tab is in use
    precondition(orchestratorOwnsDrops(orchestratorIsCurrentTab: false, lastUsedIsOrchestrator: true)) // closed, last used = Orchestrator
    precondition(orchestratorOwnsDrops(orchestratorIsCurrentTab: true, lastUsedIsOrchestrator: false)) // open on the Orchestrator tab
    precondition(!orchestratorOwnsDrops(orchestratorIsCurrentTab: false, lastUsedIsOrchestrator: false)) // another tab in use: shelf
    precondition(orchestratorSizeLabel(1_500_000).contains("MB"))
}

private func tmpFile(_ dir: URL, _ name: String, bytes: Int) -> URL {
    let u = dir.appendingPathComponent(name)
    try! Data((0..<bytes).map { UInt8($0 & 0xff) }).write(to: u)
    return u
}

/// Round trips against Tests/file-mock.py on 47999 (never the live serve). Only runs with ORCH_FILE_MOCK set.
@MainActor func runQuickFilesMock() async {
    let b = URL(string: "http://127.0.0.1:47999")!
    let ses = URLSession(configuration: .ephemeral)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orch-files-test-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    func log() async -> [[String: Any]] {
        let (d, _) = try! await ses.data(from: b.appendingPathComponent("__log"))
        return try! JSONSerialization.jsonObject(with: d) as! [[String: Any]]
    }
    func entries(_ path: String) async -> [[String: Any]] { await log().filter { $0["path"] as? String == path } }
    final class Rec { var seen: [[FileChip.State]] = []; var sink: AnyCancellable? }
    func makeQueue(_ base: URL = b) -> (OrchestratorFileQueue, Rec) {
        let q = OrchestratorFileQueue(base: { base }, session: { ses })
        let r = Rec()
        r.sink = q.$chips.sink { r.seen.append($0.map(\.state)) }
        return (q, r)
    }

    // CSV
    let csv = tmpFile(dir, "data.csv", bytes: 24)
    var (q, rec) = makeQueue()
    q.add([csv]); precondition(q.blocksSend)
    await q.waitIdle()
    precondition(q.chips.count == 1 && q.chips[0].name == "data.csv" && q.chips[0].size == 24 && q.chips[0].path == "/mock/1-data.csv")
    precondition(!q.blocksSend)
    var f = await entries("/api/chat/file")
    precondition(f.count == 1 && f[0]["filename"] as? String == "data.csv" && f[0]["size"] as? Int == 24 && f[0]["xorch"] as? String == "1")
    precondition(f[0]["ctype"] as? String == "application/octet-stream")
    precondition(rec.seen.contains { $0 == [.uploading(0)] })

    // Video: a few MB streamed from disk, size on the wire is the file's size
    let mov = tmpFile(dir, "clip.mov", bytes: 6 * 1024 * 1024)
    (q, rec) = makeQueue()
    q.add([mov]); await q.waitIdle()
    precondition(q.chips[0].path?.hasSuffix("clip.mov") == true && q.chips[0].size == 6 * 1024 * 1024)
    f = await entries("/api/chat/file")
    precondition(f.last?["filename"] as? String == "clip.mov" && f.last?["size"] as? Int == 6 * 1024 * 1024)
    precondition(rec.seen.contains { s in if case .uploading(let p)? = s.first { return p > 0 }; return false }) // progress moved

    // Two at once: one after another, never overlapping, in drop order
    let a = tmpFile(dir, "alpha.txt", bytes: 10), c = tmpFile(dir, "beta.txt", bytes: 20)
    let before = (await log()).count
    (q, rec) = makeQueue()
    q.add([a, c]); precondition(q.chips.count == 2)
    await q.waitIdle()
    precondition(q.chips.allSatisfy { $0.path != nil })
    precondition(!rec.seen.contains { $0.filter { if case .uploading = $0 { return true }; return false }.count > 1 })
    precondition(rec.seen.contains { $0.count == 2 && $0[0].isDone && $0[1] == .queued }) // the second waited for the first
    let l = await log()
    precondition(l.count == before + 2 && l[before]["filename"] as? String == "alpha.txt" && l[before + 1]["filename"] as? String == "beta.txt")
    let taken = q.take()
    precondition(taken.map(\.name) == ["alpha.txt", "beta.txt"] && q.isEmpty)

    // Image routing: the png goes to /api/chat/image, the csv to /api/chat/file
    let png = tmpPNG(dir, "pic.png")
    let imgBefore = (await entries("/api/chat/image")).count, fileBefore = (await entries("/api/chat/file")).count
    (q, _) = makeQueue()
    var imageURLs: [URL] = []
    orchestratorHandleURLs([png, csv], files: q) { imageURLs.append($0) }
    precondition(imageURLs == [png] && q.chips.map(\.name) == ["data.csv"])
    await q.waitIdle()
    let imgPath = await uploadOrchestratorImage(try! Data(contentsOf: png), base: b, session: ses)
    let total = await log().count, imgAfter = await entries("/api/chat/image"), fileAfter = await entries("/api/chat/file")
    precondition(imgPath == "/mock/\(total)-img.png")
    precondition(imgAfter.count == imgBefore + 1 && fileAfter.count == fileBefore + 1)

    // Folders: a failed chip, never uploaded; files beside it still go
    let folder = dir.appendingPathComponent("somefolder"); try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    (q, _) = makeQueue()
    let n00 = (await log()).count
    orchestratorHandleURLs([folder, csv], files: q) { _ in }
    precondition(q.chips.map(\.name) == ["somefolder", "data.csv"] && q.chips[0].state == .failed("Folders not supported"))
    await q.waitIdle()
    let n01 = await log().count
    precondition(n01 == n00 + 1)

    // Errors: 500, 413, no server, oversize (sparse, never uploaded), then a retry that works
    (q, _) = makeQueue()
    let boom = tmpFile(dir, "boom.bin", bytes: 8), huge = tmpFile(dir, "huge.bin", bytes: 8), flaky = tmpFile(dir, "flaky.bin", bytes: 8)
    let big = dir.appendingPathComponent("big.bin")
    FileManager.default.createFile(atPath: big.path, contents: nil)
    let fh = try! FileHandle(forWritingTo: big); try! fh.truncate(atOffset: UInt64(orchestratorFileMax) + 1); try! fh.close()
    let n0 = (await log()).count
    q.add([boom, huge, flaky, big]); await q.waitIdle()
    precondition(q.chips[0].state == .failed("Upload failed") && q.chips[1].state == .failed("Too big"))
    precondition(q.chips[2].state == .failed("Upload failed") && q.chips[3].state == .failed("Over 200 MB"))
    let n1 = await log().count
    precondition(n1 == n0 + 3) // the oversize file never left the machine
    precondition(q.blocksSend && q.take().isEmpty == true)
    (q, _) = makeQueue()
    let flaky2 = tmpFile(dir, "flaky2.bin", bytes: 8) // the mock fails a flaky name once
    q.add([flaky2, big]); await q.waitIdle()
    precondition(q.chips[0].isFailed && q.blocksSend)
    q.retry(q.chips[0].id); q.retry(q.chips[1].id) // oversize stays failed
    await q.waitIdle()
    precondition(q.chips[0].path != nil && q.chips[1].isFailed)
    q.remove(q.chips[1].id); precondition(!q.blocksSend)
    (q, _) = makeQueue(URL(string: "http://127.0.0.1:47998")!)
    q.add([csv]); await q.waitIdle()
    precondition(q.chips[0].state == .failed("Upload failed") && q.blocksSend)
    q.remove(q.chips[0].id); precondition(q.isEmpty)

    // A file that vanished before its turn
    (q, _) = makeQueue()
    let gone = tmpFile(dir, "gone.txt", bytes: 4)
    q.add([gone]); try? FileManager.default.removeItem(at: gone); await q.waitIdle()
    precondition(q.chips[0].state == .failed("File gone"))

    // Non-ASCII name is percent-encoded on the wire
    (q, _) = makeQueue()
    q.add([tmpFile(dir, "caf\u{e9}.csv", bytes: 4)]); await q.waitIdle()
    let lg = await log()
    precondition(lg.last?["filename"] as? String == "caf%C3%A9.csv" && q.chips[0].path == "/mock/\(lg.count)-caf\u{e9}.csv")
}

private func tmpPNG(_ dir: URL, _ name: String) -> URL {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let u = dir.appendingPathComponent(name)
    try! rep.representation(using: .png, properties: [:])!.write(to: u)
    return u
}

private extension FileChip.State { var isDone: Bool { if case .done = self { return true }; return false } }
