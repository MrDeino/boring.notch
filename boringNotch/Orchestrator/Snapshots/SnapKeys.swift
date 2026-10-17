import Foundation

// run.sh --keymock (ORCH_BASE=http://127.0.0.1:47999): the question card's real tap path (PromptCardController -> key queue -> manager)
// against Tests/key-mock.py, a stateful multi-select. Rapid taps, a swallowed key, and submit ordering. Never touches 4777.
extension Snap {
    static func keyMock() async {
        var fails: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { fails.append(what) } }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-I", "boringNotch/Orchestrator/Tests/key-mock.py"]
        try! proc.run()
        defer { proc.terminate() }
        let b = URL(string: ProcessInfo.processInfo.environment["ORCH_BASE"] ?? "http://127.0.0.1:47999")!
        precondition(b.port != 4777 && OrchestratorManager.baseURL == b, "set ORCH_BASE to the mock")
        let ses = URLSession(configuration: .ephemeral)
        for _ in 0..<50 { if (try? await ses.data(from: b.appendingPathComponent("__log"))) != nil { break }; try? await Task.sleep(for: .milliseconds(100)) }
        func post(_ path: String, _ body: [String: Any] = [:]) async {
            var r = URLRequest(url: b.appendingPathComponent(path)); r.httpMethod = "POST"
            r.httpBody = try! JSONSerialization.data(withJSONObject: body)
            _ = try? await ses.data(for: r)
        }
        func log() async -> [[String: Any]] {
            let (data, _) = try! await ses.data(from: b.appendingPathComponent("__log"))
            return try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        }
        func keys() async -> [String] { await log().map { $0["key"] as! String } }
        let m = OrchestratorManager.shared, c = PromptCardController.shared
        m.snapshotSetStreaming(true)
        func fresh() async -> PromptCard {
            await post("__reset")
            c.snapshotSet()
            await m.refresh(fresh: true)
            try? await Task.sleep(for: .milliseconds(100)) // the $prompt sink hops to the main queue
            return m.prompt!
        }
        func settled(_ secs: Double = 6) async -> Bool {
            for _ in 0..<Int(secs * 20) { if c.pending.isEmpty { return true }; try? await Task.sleep(for: .milliseconds(50)) }
            return false
        }
        func ticks() -> [Int] { (m.prompt?.items ?? []).filter { $0.checked == true }.map(\.number) }

        // 1. Three rapid taps: all three show at once (nothing locked), reach serve in order, all ticked on the screen.
        var card = await fresh()
        check(card.multiSelect, "mock card is multi-select")
        await post("__delay", ["ms": 40])
        let t0 = Date()
        for n in 1...3 { c.choose(n, displayed: card) }
        check(Date().timeIntervalSince(t0) < 0.05, "taps return at once")
        check(c.pending == [1: true, 2: true, 3: true] && !m.sending, "optimistic ticks shown, no lock: \(c.pending) sending=\(m.sending)")
        check(await settled(), "pending clears after the queue drains")
        var l = await log()
        check(l.map { $0["key"] as! String } == ["1", "2", "3"], "keys in tap order: \(l.map { $0["key"]! })")
        let ts = l.map { $0["t"] as! Double }
        print("keymock: 3 keys, gaps \(zip(ts, ts.dropFirst()).map { Int(($1 - $0) * 1000) }) ms (mock latency 40 ms)")
        check(ticks() == [1, 2, 3] && c.note == nil, "all ticked, no notice: \(ticks()) \(String(describing: c.note))")

        // 2. A key the TUI swallowed: the screen's truth is shown with the Re-sync notice, nothing silent.
        card = await fresh()
        await post("__drop", ["keys": ["2"]])
        for n in 1...3 { c.choose(n, displayed: card) }
        check(await settled(10), "pending clears after a lost key")
        check(await keys() == ["1", "2", "3"], "all three keys were sent")
        check(ticks() == [1, 3], "screen truth shown: \(ticks())")
        check(c.note?.hasPrefix("Re-synced") == true, "re-sync notice: \(String(describing: c.note))")

        // 3. Next waits for the ticks: the Tab goes last and serve had both boxes ticked when it arrived.
        card = await fresh()
        await post("__delay", ["ms": 100])
        c.choose(1, displayed: card); c.choose(2, displayed: card)
        c.next(displayed: card)
        for _ in 0..<80 { if (await keys()).contains("Tab") { break }; try? await Task.sleep(for: .milliseconds(50)) }
        l = await log()
        check(l.map { $0["key"] as! String } == ["1", "2", "Tab"], "Tab after both ticks: \(l.map { $0["key"]! })")
        check((l.last?["ticked"] as? [Int]) == [1, 2], "ticks applied before submit: \(String(describing: l.last?["ticked"]))")
        try? await Task.sleep(for: .seconds(2.5)) // the answer's "did the screen move" window

        // 4. Next with a lost tick: not submitted, the screen's state is shown.
        card = await fresh()
        await post("__drop", ["keys": ["2"]])
        c.choose(1, displayed: card); c.choose(2, displayed: card)
        c.next(displayed: card)
        try? await Task.sleep(for: .seconds(3))
        check(await keys() == ["1", "2"], "no Tab after a lost tick: \(await keys())")
        check(ticks() == [1] && c.pending.isEmpty && c.note?.hasPrefix("Re-synced") == true, "truth + notice: \(ticks()) \(String(describing: c.note))")

        if fails.isEmpty { print("OK: keymock") } else { print("FAIL: \(fails.joined(separator: "; "))"); exit(1) }
    }
}
