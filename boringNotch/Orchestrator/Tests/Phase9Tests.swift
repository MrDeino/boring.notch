import Foundation

func runPhase9Tests() {
    func dec(_ j: String) -> ChatResponse { try! d.decode(ChatResponse.self, from: Data(j.utf8)) }
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/phase9-chat.json")
    let f = try! d.decode(ChatResponse.self, from: Data(contentsOf: url))
    precondition(f.hasApproval && f.approval?.tool == "Bash" && f.approval?.id.hasPrefix("9f2c") == true)
    precondition(f.approval?.command == "git -C /Users/mitch/x status --short" && f.approval?.description == "Show working tree status" && f.approval?.at != nil)
    let o = dec(#"{"running":true,"screen":""}"#)
    precondition(o.approval == nil && !o.hasApproval)
    let n = dec(#"{"running":true,"approval":null}"#)
    precondition(n.approval == nil && n.hasApproval)
    let b1 = dec(#"{"running":true,"approval":{"tool":"Bash"}}"#)
    precondition(b1.running == true && b1.approval == nil)
    let b2 = dec(#"{"running":true,"approval":42}"#)
    precondition(b2.running == true && b2.approval == nil)
    let m = dec(#"{"approval":{"id":"z","extra":1}}"#)
    precondition(m.approval?.id == "z" && m.approval?.tool == nil && m.approval?.command == nil)

    let perm = detectPrompt(screen: fixture("permission")), q = detectPrompt(screen: fixture("question"))
    precondition(approvalAnswer(allow: true, pendingId: "a", answeringId: "a", options: perm) == .send("1"))
    precondition(approvalAnswer(allow: true, pendingId: "a", answeringId: "a", options: q) == .openCard)
    precondition(approvalAnswer(allow: false, pendingId: "a", answeringId: "a", options: perm) == .send("Escape"))
    for allow in [true, false] {
        precondition(approvalAnswer(allow: allow, pendingId: "b", answeringId: "a", options: perm) == .skip)
        precondition(approvalAnswer(allow: allow, pendingId: nil, answeringId: "a", options: perm) == .skip)
        precondition(approvalAnswer(allow: allow, pendingId: "a", answeringId: "a", options: []) == .skip)
    }
    precondition(approvalAnswer(allow: true, pendingId: "a", answeringId: "a", options: [PromptOption(number: 1, label: " yes ")]) == .send("1"))
    precondition(approvalAnswer(allow: true, pendingId: "a", answeringId: "a", options: [PromptOption(number: 1, label: "Yes, and don't ask again")]) == .openCard)

    let ap = OrchestratorApproval(id: "a", tool: "Bash", command: "x", description: nil, at: nil)
    let t0 = Date(timeIntervalSince1970: 1000), until = t0 + 3
    precondition(visibleApproval(ap, ignoredId: "a", until: until, now: t0) == nil)
    precondition(visibleApproval(ap, ignoredId: "a", until: until, now: until) == ap)
    precondition(visibleApproval(ap, ignoredId: "b", until: until, now: t0) == ap)
    precondition(visibleApproval(nil, ignoredId: "a", until: until, now: t0) == nil)

    precondition(approvalCommandLine(OrchestratorApproval(id: "a", tool: nil, command: "  a\n\tb  \n c ", description: "d", at: nil)) == "a b c")
    precondition(approvalCommandLine(OrchestratorApproval(id: "a", tool: nil, command: String(repeating: "x", count: 400), description: nil, at: nil)).count == 300)
    precondition(approvalCommandLine(OrchestratorApproval(id: "a", tool: nil, command: nil, description: "desc", at: nil)) == "desc")
    precondition(approvalCommandLine(OrchestratorApproval(id: "a", tool: nil, command: " ", description: nil, at: nil)) == "")

    var p = SSELineParser()
    _ = p.feed("event: approval")
    if case .approval(let a)? = p.feed(#"data: {"id":"q","tool":"Bash","command":"ls","description":null,"at":"t"}"#) { precondition(a?.id == "q") } else { preconditionFailure() }
    _ = p.feed("event: approval")
    if case .approval(let a)? = p.feed("data: null") { precondition(a == nil) } else { preconditionFailure() }
    _ = p.feed("event: approval")
    precondition(p.feed("data: {bad") == nil)
    _ = p.feed("event: approval")
    precondition(p.feed(#"data: {"tool":"Bash"}"#) == nil)

    for (maj, min, want) in [(15, 0, true), (15, 1, true), (15, 2, false), (14, 6, false), (26, 6, false), (16, 0, false)] {
        precondition(approvalNeedsCtrlFallback(major: maj, minor: min) == want)
    }
    precondition(approvalKeyLabels(ctrl: false).allow == "⌥⏎" && approvalKeyLabels(ctrl: false).deny == "⌥⎋")
    precondition(approvalKeyLabels(ctrl: true).allow == "⌃⌥⏎" && approvalKeyLabels(ctrl: true).deny == "⌃⌥⎋")
}

/// Approval answer round trip against Tests/approval-mock.py on 47999 (never the live serve). Only runs with ORCH_APPROVAL_MOCK set.
/// Mirrors OrchestratorManager.answerApproval: fresh GET, approvalAnswer gate, then POST {key}.
func runPhase9Mock() async {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    proc.arguments = ["-I", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("approval-mock.py").path]
    try! proc.run()
    defer { proc.terminate() }
    let b = URL(string: "http://127.0.0.1:47999")!
    let ses = URLSession(configuration: .ephemeral)
    for _ in 0..<50 { if (try? await ses.data(from: b.appendingPathComponent("__log"))) != nil { break }; try! await Task.sleep(for: .milliseconds(100)) }

    func setChat(_ j: String) async {
        var r = URLRequest(url: b.appendingPathComponent("__set")); r.httpMethod = "POST"; r.httpBody = Data(j.utf8)
        _ = try! await ses.data(for: r)
    }
    func answer(allow: Bool, answeringId: String) async -> ApprovalAnswer {
        let (data, _) = try! await ses.data(from: b.appendingPathComponent("api/chat"))
        let c = try! d.decode(ChatResponse.self, from: data)
        let ans = approvalAnswer(allow: allow, pendingId: c.approval?.id, answeringId: answeringId, options: detectPrompt(screen: c.screen ?? ""))
        if case .send(let k) = ans { let code = try! await sendOrchestratorPost(.key(k), base: b, session: ses); precondition(code == 200) }
        return ans
    }
    func posts() async -> [[String: Any]] {
        let (data, _) = try! await ses.data(from: b.appendingPathComponent("__log"))
        return try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
    }
    let screen = "Do you want to proceed?\\n❯ 1. Yes\\n  2. Yes, and don't ask again\\n  3. No, and tell Claude what to do differently (esc)\\n Esc to cancel · Tab to amend\\n"
    let ap = #""approval":{"id":"a1","tool":"Bash","command":"ls"}"#

    await setChat(#"{"running":true,"screen":"\#(screen)",\#(ap)}"#)
    do { let r = await answer(allow: true, answeringId: "a1"); precondition(r == .send("1")) }
    do { let r = await answer(allow: false, answeringId: "a1"); precondition(r == .send("Escape")) }
    let p = await posts()
    precondition(p.count == 2)
    precondition((p[0]["body"] as! [String: String]) == ["key": "1"] && (p[1]["body"] as! [String: String]) == ["key": "Escape"])
    for e in p { precondition(e["xorch"] as? String == "1" && e["ctype"] as? String == "application/json") }

    // Changed approval id (a newer prompt replaced the one the user saw): nothing posted.
    await setChat(#"{"running":true,"screen":"\#(screen)","approval":{"id":"a2","tool":"Bash","command":"rm"}}"#)
    do { let r = await answer(allow: true, answeringId: "a1"); precondition(r == .skip) }
    do { let r = await answer(allow: false, answeringId: "a1"); precondition(r == .skip) }
    // No prompt on screen, or no approval at all: nothing posted.
    await setChat(#"{"running":true,"screen":"just output\\n",\#(ap)}"#)
    do { let r = await answer(allow: true, answeringId: "a1"); precondition(r == .skip) }
    await setChat(#"{"running":true,"screen":"\#(screen)","approval":null}"#)
    do { let r = await answer(allow: false, answeringId: "a1"); precondition(r == .skip) }
    let n = await posts().count; precondition(n == 2)
}
