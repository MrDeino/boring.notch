import Foundation

// run.sh --sendmock (ORCH_BASE=http://127.0.0.1:47999): the composer's real send path against Tests/send-mock.py.
// Idle, mid-turn (no echo for 60 s), pending question card, and a real failure + Retry. Never touches 4777.
extension Snap {
    static func sendMock() async {
        var fails: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { fails.append(what) } }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-I", "boringNotch/Orchestrator/Tests/send-mock.py"]
        try! proc.run()
        defer { proc.terminate() }
        let b = URL(string: ProcessInfo.processInfo.environment["ORCH_BASE"] ?? "http://127.0.0.1:47999")!
        precondition(b.port != 4777 && OrchestratorManager.baseURL == b, "set ORCH_BASE to the mock")
        let ses = URLSession(configuration: .ephemeral)
        for _ in 0..<50 { if (try? await ses.data(from: b.appendingPathComponent("__log"))) != nil { break }; try? await Task.sleep(for: .milliseconds(100)) }
        func post(_ path: String, _ body: [String: Any]) async {
            var r = URLRequest(url: b.appendingPathComponent(path)); r.httpMethod = "POST"
            r.httpBody = try! JSONSerialization.data(withJSONObject: body)
            _ = try? await ses.data(for: r)
        }
        func setScreen(_ screen: String) async { await post("__set", ["running": true, "screen": screen]) }
        func bodies() async -> [String] {
            let (data, _) = try! await ses.data(from: b.appendingPathComponent("__log"))
            return (try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]).map { String(data: try! JSONSerialization.data(withJSONObject: $0["body"] ?? [:], options: .sortedKeys), encoding: .utf8)! }
        }
        let m = OrchestratorManager.shared, s = OrchestratorTranscriptStore.shared
        func row(_ text: String) -> PendingMessage? { s.pending.last { $0.text == text } }
        func waitFor(_ text: String, _ st: PendingMessage.State, _ secs: Double = 5) async -> Bool {
            for _ in 0..<Int(secs * 10) { if row(text)?.state == st { return true }; try? await Task.sleep(for: .milliseconds(100)) }
            return false
        }
        // Like a notch whose SSE stream is up: chat payloads skip the store's blocks fetch (no new prompt).
        m.snapshotSetStreaming(true)

        // 1. Idle.
        await setScreen(fixture("inputbox.txt"))
        await m.refresh(fresh: true)
        s.enqueue("idle hello")
        check(await waitFor("idle hello", .sent), "idle: row sent (got \(String(describing: row("idle hello")?.state)))")
        var log = await bodies()
        check(log.suffix(2) == [#"{"key":"C-u"}"#, #"{"text":"idle hello"}"#], "idle: C-u then text posted: \(log)")

        // 2. Mid-turn: Claude queues typed input, the transcript never echoes it for 60 s.
        await setScreen(fixture("working.txt"))
        await m.refresh(fresh: true)
        s.enqueue("busy hello")
        check(await waitFor("busy hello", .sent), "busy: row sent")
        log = await bodies()
        check(log.last == #"{"text":"busy hello"}"#, "busy: text posted: \(log)")
        var everFailed = false
        for _ in 0..<60 {
            await m.refresh(fresh: true)
            if row("busy hello")?.state == .failed { everFailed = true }
            try? await Task.sleep(for: .seconds(1))
        }
        check(!everFailed, "busy: row never failed while unechoed for 60 s")

        // 3. A question card is up: the text waits (never typed into the card), then goes once it clears.
        await setScreen(fixture("question.txt"))
        await m.refresh(fresh: true)
        check(!m.promptOptions.isEmpty, "card: prompt detected")
        let before = await bodies().count
        s.enqueue("after card")
        try? await Task.sleep(for: .seconds(2))
        check(await bodies().count == before, "card: nothing posted while the card is up")
        check(row("after card").map { $0.state != .failed } ?? false, "card: row kept, not failed")
        await setScreen(fixture("inputbox.txt"))
        await m.refresh(fresh: true)
        check(await waitFor("after card", .sent), "card: sent once the card cleared")
        log = await bodies()
        check(log.last == #"{"text":"after card"}"#, "card: text posted after the card: \(log)")

        // 4. A real failure shows Retry; Retry after serve recovers sends it.
        await post("__fail", ["code": 500])
        s.enqueue("flaky")
        check(await waitFor("flaky", .failed), "fail: 500 -> row failed (Retry)")
        await post("__fail", ["code": 0])
        if let r = row("flaky") { s.retry(r.id) }
        check(await waitFor("flaky", .sent), "fail: Retry -> sent")
        log = await bodies()
        check(log.last == #"{"text":"flaky"}"#, "fail: text posted on Retry: \(log)")

        print("posts: \(log)")
        if fails.isEmpty { print("OK: sendmock") } else { print("FAIL: \(fails.joined(separator: "; "))"); proc.terminate(); exit(1) }
    }
}
