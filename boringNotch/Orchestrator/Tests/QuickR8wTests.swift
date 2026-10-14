import Foundation

func runQuickR8wTests() {
    precondition(tabKeys(from: 2, to: 0, review: false) == [promptBackKey, promptBackKey])
    precondition(tabKeys(from: 0, to: 2, review: false) == ["Tab", "Tab"])
    precondition(tabKeys(from: 1, to: 1, review: false) == nil)
    precondition(tabKeys(from: 3, to: 3, review: true) == nil)
    precondition(tabKeys(from: 2, to: 3, review: true) == nil) // forward from review: nothing
    precondition(tabKeys(from: 3, to: 1, review: true) == ["BTab", "BTab"]) // observed: BTab leaves review
    for (a, b, r) in [(2, 0, false), (0, 2, false), (3, 1, true)] {
        precondition(tabKeys(from: a, to: b, review: r)!.allSatisfy { OrchestratorPost.allowedKeys.contains($0) })
    }
    let base = URL(string: "http://127.0.0.1:1")!
    for k in ["BTab", "Left", "Right"] {
        let r = OrchestratorPost.key(k).request(base: base)!
        precondition(String(data: r.httpBody!, encoding: .utf8) == "{\"key\":\"\(k)\"}")
    }
    precondition(OrchestratorPost.key("x").request(base: base) == nil)

    let back = detectPromptCard(screen: fixture("multiq-back"))!
    precondition(back.kind == .question && back.multiSelect && back.currentTab == 0 && !back.review)
    precondition(back.tabs.map(\.label) == ["Fruit", "Color", "Size", "Submit"])
    precondition(back.items.first?.checked == true) // ticks survive going back

    let text = "a\nb ü"
    let n = OrchestratorPost.notes(text).request(base: base)!
    precondition(n.httpMethod == "POST" && n.url!.path == "/api/notes" && n.value(forHTTPHeaderField: "x-orch") == "1")
    precondition(n.value(forHTTPHeaderField: "Content-Type") == "text/plain; charset=utf-8" && n.httpBody == Data(text.utf8))
    precondition(OrchestratorPost.notes("").request(base: base) != nil)
    precondition(OrchestratorPost.notes(String(repeating: "a", count: 1_000_001)).request(base: base) == nil)
    precondition(OrchestratorPost.notes(String(repeating: "a", count: 1_000_000)).request(base: base) != nil)
}

/// Round trip against /tmp/orch-notes-mock.py on 47999 (never the live serve). Only runs with ORCH_NOTES_MOCK set.
func runQuickR8wMock() async {
    let b = URL(string: "http://127.0.0.1:47999")!
    let ses = URLSession(configuration: .ephemeral)
    let text = "line one\nline two ü 日本 \"quoted\"\n"
    var code = try! await sendOrchestratorPost(.notes(text), base: b, session: ses)
    precondition(code == 200)
    var got = try! await fetchOrchestratorNotes(base: b, session: ses)
    precondition(got == text)
    code = try! await sendOrchestratorPost(.notes(""), base: b, session: ses)
    precondition(code == 200)
    got = try! await fetchOrchestratorNotes(base: b, session: ses)
    precondition(got == "")
    var bare = URLRequest(url: b.appendingPathComponent("api/notes"))
    bare.httpMethod = "POST"; bare.httpBody = Data("x".utf8)
    bare.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
    let (_, resp) = try! await ses.data(for: bare)
    precondition((resp as! HTTPURLResponse).statusCode == 400)
}
