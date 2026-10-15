import Foundation

// run.sh --askmock (ORCH_BASE=http://127.0.0.1:47999): AskUserQuestion approvals open the card, not the drop-down,
// and answers from the card reach the mock serve as keys. Never touches 4777.
extension Snap {
    static func askMock() async {
        var fails: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { fails.append(what) } }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-I", "boringNotch/Orchestrator/Tests/approval-mock.py"]
        try! proc.run()
        defer { proc.terminate() }
        let b = URL(string: ProcessInfo.processInfo.environment["ORCH_BASE"] ?? "http://127.0.0.1:47999")!
        let ses = URLSession(configuration: .ephemeral)
        for _ in 0..<50 { if (try? await ses.data(from: b.appendingPathComponent("__log"))) != nil { break }; try? await Task.sleep(for: .milliseconds(100)) }
        func setChat(_ screen: String, _ ap: [String: Any]) async {
            var r = URLRequest(url: b.appendingPathComponent("__set")); r.httpMethod = "POST"
            r.httpBody = try! JSONSerialization.data(withJSONObject: ["running": true, "screen": screen, "approval": ap] as [String: Any])
            _ = try? await ses.data(for: r)
        }
        func bodies() async -> [String] {
            let (data, _) = try! await ses.data(from: b.appendingPathComponent("__log"))
            return (try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]).map { String(data: try! JSONSerialization.data(withJSONObject: $0["body"] ?? [:], options: .sortedKeys), encoding: .utf8)! }
        }
        let m = OrchestratorManager.shared, c = OrchestratorApprovalCenter.shared, pc = PromptCardController.shared
        _ = pc
        let c0 = c.cardRequest
        await setChat(fixture("question.txt"), ["id": "q1", "tool": "AskUserQuestion", "command": "{}"])
        await m.refresh(fresh: true); try? await Task.sleep(for: .milliseconds(100))
        check(m.prompt?.kind == .question, "prompt is a question")
        check(c.approval == nil, "no drop-down for question")
        check(c.cardRequest == c0 + 1, "cardRequest +1 (got \(c.cardRequest - c0))")
        await m.refresh(fresh: true); try? await Task.sleep(for: .milliseconds(100))
        check(c.cardRequest == c0 + 1, "second refresh does not bump")
        if let p = m.prompt { pc.choose(2, displayed: p) }
        try? await Task.sleep(for: .seconds(3))
        var log = await bodies()
        check(log.contains { $0.contains(#""key":"2""#) }, "key 2 posted: \(log)")

        await setChat(fixture("multiselect-1.txt"), ["id": "q2", "tool": "AskUserQuestion", "command": "{}"])
        await m.refresh(fresh: true); try? await Task.sleep(for: .milliseconds(100))
        if let p = m.prompt { pc.choose(1, displayed: p) }
        try? await Task.sleep(for: .seconds(1))
        if let p = m.prompt { pc.next(displayed: p) }
        try? await Task.sleep(for: .seconds(3))
        log = await bodies()
        let i1 = log.firstIndex { $0.contains(#""key":"1""#) }, it = log.firstIndex { $0.contains(#""key":"Tab""#) }
        check(i1 != nil && it != nil && i1! < it!, "key 1 then Tab: \(log)")

        await setChat("Do you want to proceed?\n❯ 1. Yes\n  2. No\n Esc to cancel\n", ["id": "b1", "tool": "Bash", "command": "ls"])
        await m.refresh(fresh: true); try? await Task.sleep(for: .milliseconds(100))
        check(c.approval?.id == "b1", "Bash approval still shows drop-down")

        print("posts: \(log)")
        if fails.isEmpty { print("OK: askmock") } else { print("FAIL: \(fails.joined(separator: "; "))"); exit(1) }
    }
}
