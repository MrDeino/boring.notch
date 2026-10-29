import AppKit

// run.sh --slowmock (ORCH_BASE=http://127.0.0.1:47999): the real poll loop and SSE stream against Tests/slow-mock.py.
// A 10 s /api/state is not offline; serve killed -> chat and question card stay, the typed answer waits;
// serve back -> answer posted exactly once; a stream reconnect resumes with `since` and never shrinks the chat. ~60 s.
extension Snap {
    static func slowMock() async {
        var fails: [String] = []
        func check(_ ok: Bool, _ what: String) { print((ok ? "ok: " : "FAIL: ") + what); if !ok { fails.append(what) } }
        let b = URL(string: ProcessInfo.processInfo.environment["ORCH_BASE"] ?? "http://127.0.0.1:47999")!
        precondition(b.port != 4777 && OrchestratorManager.baseURL == b, "set ORCH_BASE to the mock")
        let ses = URLSession(configuration: .ephemeral)
        func launch() async -> Process {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            p.arguments = ["-I", "boringNotch/Orchestrator/Tests/slow-mock.py"]
            try! p.run()
            for _ in 0..<50 { if (try? await ses.data(from: b.appendingPathComponent("__log"))) != nil { break }; try? await Task.sleep(for: .milliseconds(100)) }
            return p
        }
        func post(_ path: String, _ body: [String: Any]) async {
            var r = URLRequest(url: b.appendingPathComponent(path)); r.httpMethod = "POST"
            r.httpBody = try! JSONSerialization.data(withJSONObject: body)
            _ = try? await ses.data(for: r)
        }
        func get(_ path: String) async -> [Any] {
            guard let (data, _) = try? await ses.data(from: b.appendingPathComponent(path)) else { return [] }
            return (try? JSONSerialization.jsonObject(with: data) as? [Any]) ?? []
        }
        func until(_ secs: Double, _ cond: () -> Bool) async -> Bool {
            for _ in 0..<Int(secs * 10) { if cond() { return true }; try? await Task.sleep(for: .milliseconds(100)) }
            return cond()
        }
        func blk(_ id: String, _ kind: String, _ text: String) -> [String: Any] { ["id": id, "kind": kind, "text": text] }
        var blocks = [blk("u1", "user", "synthetic question"), blk("p1", "prose", "synthetic reply one")]
        let idle = fixture("inputbox.txt"), before = fixture("freetext-1q-before.txt"), focused = fixture("freetext-1q-focused.txt")

        var proc = await launch()
        await post("__set", ["chat": ["running": true, "screen": idle], "blocks": blocks])
        let m = OrchestratorManager.shared, s = OrchestratorTranscriptStore.shared, ctl = PromptCardController.shared
        m.notchOpen = true
        m.start()
        check(await until(10) { m.streaming && s.blocks.count == 2 }, "stream up with the chat (\(s.blocks.count) rows)")
        // From here the chat must never shrink or vanish.
        var shrank = false, lastCount = s.blocks.count
        let watch = Task { @MainActor in
            while !Task.isCancelled {
                if s.blocks.count < lastCount { shrank = true }
                lastCount = s.blocks.count
                try? await Task.sleep(for: .milliseconds(50))
            }
        }

        // 1. A slow serve: the refresh after a POST waits 10 s for /api/state and stays online.
        await post("__set", ["delay": 10])
        let t0 = Date()
        await m.refresh(fresh: true)
        check(Date().timeIntervalSince(t0) > 9, "slow /api/state took ~10 s (\(Int(Date().timeIntervalSince(t0))) s)")
        check(!m.offline && !m.reconnecting && !m.runs.isEmpty, "one slow response: not offline, runs kept")
        await post("__set", ["delay": 0])

        // 2. Stream reconnect: resumes after our last block, appends, never clears.
        blocks.append(blk("p2", "prose", "synthetic reply two"))
        await post("__set", ["blocks": blocks])
        check(await until(5) { s.blocks.count == 3 }, "new block arrives (\(s.blocks.count))")
        await post("__drop", [:])
        var evs: [String] = []
        for _ in 0..<90 { // fixed 30 s stream retry; polling covers the gap
            evs = await get("__events").compactMap { $0 as? String }
            if evs.count >= 2 && m.streaming { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        check(evs.count >= 2 && m.streaming, "stream reconnected")
        check(evs.first == "" && evs.dropFirst().allSatisfy { $0 == "p2" }, "reconnect sent since=<last block id>: \(evs)")
        check(s.blocks.map(\.id) == ["u1", "p1", "p2"] && !s.fallback, "chat kept after reconnect: \(s.blocks.map(\.id))")

        // 3. A question card up, then serve goes away.
        await post("__set", ["chat": ["running": true, "screen": before], "on_key": ["3": focused], "on_text": idle])
        check(await until(5) { m.prompt != nil }, "question card up")
        guard let card = m.prompt else { return finish(fails, proc) }
        proc.terminate(); proc.waitUntilExit()
        try? await Task.sleep(for: .seconds(1))
        ctl.freeText = "synthetic answer"
        ctl.submitFreeText(displayed: card)
        try? await Task.sleep(for: .seconds(5))
        check(m.prompt == card && ctl.dismissed == nil, "unreachable: card stays on screen")
        check(!m.offline && m.reconnecting, "unreachable for 6 s: reconnecting, not offline")
        check(s.blocks.count == 3, "unreachable: chat stays (\(s.blocks.count) rows)")
        check(ctl.freeText == "synthetic answer" && ctl.note == "Waiting for the orchestrator…", "typed answer kept, waiting (note: \(ctl.note ?? "nil"))")

        // 4. Serve back: the answer goes exactly once.
        proc = await launch()
        await post("__set", ["chat": ["running": true, "screen": before], "blocks": blocks, "on_key": ["3": focused], "on_text": idle])
        check(await until(30) { ctl.freeText.isEmpty }, "answer sent once serve is back")
        try? await Task.sleep(for: .seconds(3))
        let log = (await get("__log")).compactMap { $0 as? [String: String] }
        check(log.filter { $0["text"] == "synthetic answer" }.count == 1, "text posted exactly once: \(log)")
        check(log.contains { $0["key"] == "3" }, "free-text row selected first")
        check(m.prompt == nil && !m.stale, "card gone after the answer")
        watch.cancel()
        check(!shrank, "chat never shrank")
        finish(fails, proc)
    }

    private static func finish(_ fails: [String], _ proc: Process) {
        proc.terminate()
        if fails.isEmpty { print("OK: slowmock") } else { print("FAILED: \(fails.joined(separator: "; "))"); exit(1) }
    }
}
