import Foundation

func runPhase6Tests() {
    // permission.txt
    let p = detectPromptCard(screen: fixture("permission"))!
    precondition(p.kind == .permission)
    precondition(p.title == "Bash command")
    precondition(p.purpose == "Write current date to stamp file")
    precondition(p.body == "date > /tmp/notch-fixture.WJuB/stamp.txt")
    precondition(p.question == "Do you want to proceed?")
    precondition(p.items.map { $0.number } == [1, 2, 3, 4])
    precondition(p.items.map { $0.role } == [.normal, .normal, .normal, .deny])
    precondition(p.items.allSatisfy { $0.detail == nil })
    precondition(p.highlighted == 1)
    precondition(p.header == nil && p.progress == nil)
    precondition(p.options == detectPrompt(screen: fixture("permission")))

    // question.txt
    let q = detectPromptCard(screen: fixture("question"))!
    precondition(q.kind == .question)
    precondition(q.title == nil)
    precondition(q.header == "Fruit")
    precondition(q.progress == nil)
    precondition(q.question == "Which fruit do you like?")
    precondition(q.items.map { $0.label } == ["apple", "banana", "cherry", "Type something.", "Chat about this"])
    precondition(q.items.map { $0.detail } == ["Apple", "Banana", "Cherry", nil, nil])
    precondition(q.items.map { $0.role } == [.normal, .normal, .normal, .freeText, .chat])
    precondition(q.highlighted == 1)

    // synthetic multi-question
    let m1 = detectPromptCard(screen: fixture("phase6-multiq-1"))!
    precondition(m1.kind == .question)
    precondition(m1.header == "Window")
    precondition(m1.progress == "1 of 2")
    precondition(m1.question == "How should the notch grow when the conversation is open and the expanded view needs more height than the panel allows?")
    precondition(m1.items[2].role == .freeText)
    precondition(m1.items[3].role == .chat)
    precondition(m1.items[0].detail == "Keep one window; grow its frame and pin the top edge.")
    precondition(m1.highlighted == 1)
    precondition(!m1.items.contains { $0.label.hasPrefix("SYNTHETIC") || $0.label.hasPrefix("⏺") })
    let m2 = detectPromptCard(screen: fixture("phase6-multiq-2"))!
    precondition(m2.header == "Color")
    precondition(m2.progress == "2 of 2")
    precondition(m2.question == "Which accent colour?")
    precondition(m2.highlighted == 2)

    // edit / fetch
    let e = detectPromptCard(screen: fixture("phase6-edit"))!
    precondition(e.kind == .permission)
    precondition(e.title == "Edit file")
    precondition(e.title != "⏺ Update(src/foo.swift)")
    precondition(e.purpose == "src/foo.swift")
    precondition(e.body == nil)
    precondition(e.question == "Do you want to make this edit to foo.swift?")
    precondition(e.items[2].role == .deny)
    let f = detectPromptCard(screen: fixture("phase6-fetch"))!
    precondition(f.kind == .permission)
    precondition(f.title == "Fetch")
    precondition(f.purpose == "https://example.com/docs")
    precondition(f.body == nil)
    precondition(f.items[2].role == .deny)

    // nil / no rule / multi-select / deny fallback
    precondition(detectPromptCard(screen: fixture("inputbox")) == nil)
    let nr = detectPromptCard(screen: "Do you want to proceed?\n❯ 1. Yes\n  2. No\n Esc to cancel\n")!
    precondition(nr.title == nil)
    precondition(nr.question == "Do you want to proceed?")
    precondition(nr.items[1].role == .deny)
    let ms = fixture("question").replacingOccurrences(of: "Enter to select", with: "Space to toggle · Enter to select")
    precondition(detectPromptCard(screen: ms)!.kind == .permission)
    let sc = detectPromptCard(screen: "Review?\n❯ 1. Submit answers\n  2. Cancel\n Esc to cancel\n")!
    precondition(sc.items[1].role == .deny)

    // shortLabel
    precondition(shortLabel("Yes") == "Allow")
    precondition(shortLabel("No") == "Deny")
    precondition(shortLabel("No, and tell Claude what to do differently (esc)") == "Deny")
    precondition(shortLabel("Yes, and always allow access to /tmp/notch-fixture.WJuB from this project") == "Always in /tmp/notch-fixture.WJuB")
    precondition(shortLabel("Yes, and switch to auto mode · auto mode handles these prompts for you") == "Auto mode")
    precondition(shortLabel("Yes, allow all edits during this session (shift+tab)") == "All edits")
    precondition(shortLabel("Yes, and don't ask again for example.com") == "Always: example.com")
    precondition(shortLabel("Submit answers") == "Submit answers")
    let long = shortLabel(String(repeating: "x", count: 40))
    precondition(long.count == 22 && long.hasSuffix("…"))

    // moveHighlight
    let five = [1, 2, 3, 4, 5]
    precondition(moveHighlight(1, by: 1, in: five) == 2)
    precondition(moveHighlight(5, by: 1, in: five) == 5)
    precondition(moveHighlight(1, by: -1, in: five) == 1)
    precondition(moveHighlight(nil, by: 1, in: [1, 2]) == 1)
    precondition(moveHighlight(3, by: -1, in: [1, 2, 3]) == 2)
    precondition(moveHighlight(2, by: 1, in: []) == nil)

    // promptKey
    let n: Set<Int> = [1, 2, 3, 4]
    func k(_ code: UInt16, _ ch: String? = nil, cmd: Bool = false, edit: Bool = false, kind: PromptCard.Kind = .question) -> PromptKey {
        promptKey(keyCode: code, characters: ch, commandLike: cmd, editingText: edit, kind: kind, numbers: n)
    }
    precondition(k(19, "2") == .answer(2))
    precondition(k(0, "7") == .pass)
    precondition(k(18, "1", cmd: true) == .pass)
    precondition(k(18, "1", edit: true) == .pass)
    precondition(k(53, edit: true) == .pass)
    precondition(k(53) == .escape)
    precondition(k(126) == .up)
    precondition(k(125) == .down)
    precondition(k(36) == .select && k(76) == .select)
    precondition(k(126, kind: .permission) == .pass)
    precondition(k(36, kind: .permission) == .pass)
    precondition(k(0, "a") == .pass)

    // promptIdentity ignores highlighted
    do {
        var a = PromptCard(options: [], kind: .question); a.question = "Q"; a.items = [PromptCardOption(number: 1, label: "A")]
        var b = a; a.highlighted = 1; b.highlighted = 2
        precondition(promptIdentity(a) == promptIdentity(b))
        b.question = "Other"
        precondition(promptIdentity(a) != promptIdentity(b))
    }
}
