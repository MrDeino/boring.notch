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
}
