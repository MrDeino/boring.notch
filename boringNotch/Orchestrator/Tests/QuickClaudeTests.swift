import Foundation

// Claude Code update badge + restart (serve's `claude`, POST /api/chat/restart).
func runQuickClaudeTests() {
    let d = JSONDecoder()
    func chat(_ j: String) -> ChatResponse { try! d.decode(ChatResponse.self, from: Data(j.utf8)) }
    // Old serve: no `claude` key, no badge. Malformed `claude` never fails the chat decode.
    precondition(chat(#"{"running":true,"screen":"x"}"#).claude == nil)
    precondition(!claudeUpdateBadge(chat(#"{"running":true}"#).claude, restartedOnto: nil))
    let bad = chat(#"{"running":true,"screen":"x","claude":{"running":1,"installed":"2.1.9","updateReady":"yes"}}"#)
    precondition(bad.screen == "x" && bad.claude == ClaudeInfo(running: nil, installed: "2.1.9", updateReady: nil))
    precondition(chat(#"{"running":true,"claude":7}"#).claude == nil && chat(#"{"running":true,"claude":7}"#).running == true)
    let ready = ClaudeInfo(running: "2.1.8", installed: "2.1.9", updateReady: true)
    precondition(chat(#"{"running":true,"claude":{"running":"2.1.8","installed":"2.1.9","updateReady":true}}"#).claude == ready)
    precondition(claudeUpdateBadge(ready, restartedOnto: nil))
    precondition(!claudeUpdateBadge(ClaudeInfo(running: "2.1.9", installed: "2.1.9", updateReady: false), restartedOnto: nil))
    precondition(!claudeUpdateBadge(ClaudeInfo(running: nil, installed: "2.1.9", updateReady: false), restartedOnto: nil))
    // Restarted onto 2.1.9: hidden while the transcript still says 2.1.8; a newer install shows it again.
    precondition(!claudeUpdateBadge(ready, restartedOnto: "2.1.9"))
    precondition(claudeUpdateBadge(ClaudeInfo(running: "2.1.8", installed: "2.2.0", updateReady: true), restartedOnto: "2.1.9"))
    // SSE chat events carry it too.
    var p = SSELineParser()
    _ = p.feed("event: chat")
    if case .chat(let r) = p.feed(#"data: {"running":true,"claude":{"running":"2.1.8","installed":"2.1.9","updateReady":true}}"#) { precondition(r.claude == ready) } else { preconditionFailure("sse chat") }
    _ = p.feed("event: claude")
    precondition(p.feed(#"data: {"running":"2.1.8","installed":"2.1.9","updateReady":true}"#) == nil) // own event ignored: chat carries it

    precondition(claudeRestartPhase(afterPost: 200) == .restarting && claudeRestartPhase(afterPost: 409) == .busy)
    precondition(claudeRestartPhase(afterPost: 500) == .idle && claudeRestartPhase(afterPost: nil) == .idle)
    precondition(claudeRestartOnChat(.restarting, running: true, posting: false) == .idle)
    precondition(claudeRestartOnChat(.restarting, running: true, posting: true) == .restarting)
    precondition(claudeRestartOnChat(.restarting, running: false, posting: false) == .restarting)
    precondition(claudeRestartOnChat(.busy, running: true, posting: false) == .busy)

    let b = URL(string: "http://127.0.0.1:4799")!
    for (force, body) in [(false, "{}"), (true, #"{"force":true}"#)] {
        let r = OrchestratorPost.restart(force: force).request(base: b)!
        precondition(r.httpMethod == "POST" && r.url!.path == "/api/chat/restart" && String(data: r.httpBody!, encoding: .utf8) == body)
        precondition(r.value(forHTTPHeaderField: "x-orch") == "1" && r.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }
}

/// The manager's restart flow, step for step, against Tests/restart-mock.py.
func runQuickClaudeMock() async {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    proc.arguments = ["-I", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("restart-mock.py").path]
    try! proc.run()
    defer { proc.terminate() }
    let b = URL(string: "http://127.0.0.1:47999")!
    let ses = URLSession(configuration: .ephemeral)
    for _ in 0..<50 { if (try? await ses.data(from: b.appendingPathComponent("__log"))) != nil { break }; try! await Task.sleep(for: .milliseconds(100)) }
    func set(_ j: String) async {
        var r = URLRequest(url: b.appendingPathComponent("__set")); r.httpMethod = "POST"; r.httpBody = Data(j.utf8)
        _ = try! await ses.data(for: r)
    }
    func getChat() async -> ChatResponse {
        let (data, _) = try! await ses.data(from: b.appendingPathComponent("api/chat"))
        return try! JSONDecoder().decode(ChatResponse.self, from: data)
    }
    func log() async -> [[String: Any]] {
        let (data, _) = try! await ses.data(from: b.appendingPathComponent("__log"))
        return try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    }
    let oldVer = #"{"running":true,"screen":"x","claude":{"running":"2.1.8","installed":"2.1.9","updateReady":true}}"#
    // After a restart the transcript keeps the old version until the new session writes to it.
    let after = #"{"running":true,"screen":"y","claude":{"running":"2.1.8","installed":"2.1.9","updateReady":true}}"#

    // Old serve: no claude field, no badge.
    await set(#"{"chat":{"running":true,"screen":"x"}}"#)
    var c = await getChat()
    precondition(c.claude == nil && !claudeUpdateBadge(c.claude, restartedOnto: nil))

    // Badge shows, confirmed restart posts {} once, then restarting until the chat runs; badge clears.
    await set(#"{"chat":\#(oldVer),"busy":false,"after":\#(after)}"#)
    c = await getChat()
    precondition(claudeUpdateBadge(c.claude, restartedOnto: nil))
    var phase = ClaudeRestart.idle
    let none = await log()
    precondition(none.isEmpty) // asking alone posts nothing
    var code = try! await sendOrchestratorPost(.restart(force: false), base: b, session: ses)
    precondition(code == 200)
    phase = claudeRestartPhase(afterPost: code)
    precondition(phase == .restarting)
    var restartedOnto = c.claude?.installed
    c = await getChat()
    phase = claudeRestartOnChat(phase, running: c.running ?? false, posting: false)
    precondition(phase == .idle && c.screen == "y")
    precondition(!claudeUpdateBadge(c.claude, restartedOnto: restartedOnto))
    await set(#"{"chat":{"running":true,"claude":{"running":"2.1.9","installed":"2.1.9","updateReady":false}}}"#)
    c = await getChat()
    precondition(!claudeUpdateBadge(c.claude, restartedOnto: nil))

    // Mid-turn: 409 -> busy; Restart anyway sends force -> 200 -> restarting -> cleared.
    await set(#"{"chat":\#(oldVer),"busy":true,"after":\#(after)}"#)
    c = await getChat()
    precondition(claudeUpdateBadge(c.claude, restartedOnto: nil))
    code = try! await sendOrchestratorPost(.restart(force: false), base: b, session: ses)
    phase = claudeRestartPhase(afterPost: code)
    precondition(code == 409 && phase == .busy)
    let still = await getChat()
    precondition(claudeUpdateBadge(still.claude, restartedOnto: nil) && still.screen == "x") // nothing restarted
    code = try! await sendOrchestratorPost(.restart(force: true), base: b, session: ses)
    phase = claudeRestartPhase(afterPost: code)
    precondition(code == 200 && phase == .restarting)
    restartedOnto = c.claude?.installed
    c = await getChat()
    precondition(claudeRestartOnChat(phase, running: c.running ?? false, posting: false) == .idle && !claudeUpdateBadge(c.claude, restartedOnto: restartedOnto))

    let l = await log()
    precondition(l.count == 3)
    precondition((l.map { $0["body"] as! [String: Bool] }) == [[:], [:], ["force": true]])
    for e in l { precondition(e["xorch"] as? String == "1" && e["ctype"] as? String == "application/json") }
}
