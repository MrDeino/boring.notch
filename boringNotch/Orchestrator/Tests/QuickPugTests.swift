import Foundation

// Key map observed in real Claude Code (v2.1.299, tmux capture-pane -p -J), keys the notch server allows only:
//  - Multi-select rows read "N. [ ] label" / "N. [✔] label". The digit N toggles row N (cursor stays put);
//    Enter toggles the highlighted row. "Type something" is a checkbox row too (digit focuses its text input).
//  - Tab moves to the NEXT question chip (selections kept) and, from the last question, to the review step.
//    Tab on the review step does nothing (no wrap). Shift-Tab (BTab) and Left both go to the
//    PREVIOUS chip with ticks kept (also from the review step; Right = Tab). The notch uses BTab:
//    d chips ahead = d x Tab, d chips back = d x BTab.
//  - There is no Submit key on a multi-select question: Tab is "done, next". A chip turns ☒ as soon as
//    one box is ticked, so ☒ does not mean "left this question".
//  - Review step: no "Esc to cancel" footer; "Review your answers", answer summary, "Ready to submit your
//    answers?", then "1. Submit answers" / "2. Cancel". Digit 1 submits (unanswered questions are recorded as
//    "no answer"). Single-select digits answer and advance as before.

func runQuickPugTests() {
    let a = detectPromptCard(screen: fixture("multiselect-1"))!
    precondition(a.kind == .question && a.multiSelect)
    precondition(a.items.map(\.label) == ["apple", "banana", "cherry", "Type something", "Chat about this"])
    precondition(a.items.map(\.checked) == [false, false, false, nil, nil])
    precondition(a.items.map(\.role) == [.normal, .normal, .normal, .freeText, .chat])
    precondition(a.header == "Fruit" && a.progress == "1 of 2" && a.question == "Which fruits do you want?")
    precondition(a.items[0].detail == "Apple")
    precondition(!a.options.contains { $0.label.contains("[") })

    let t = detectPromptCard(screen: fixture("multiselect-toggled"))!
    precondition(t.items.map(\.checked) == [true, false, true, nil, nil])
    precondition(promptIdentity(a) == promptIdentity(t))
    precondition(t.header == "Fruit") // ☒ Fruit while still on it

    let q2 = detectPromptCard(screen: fixture("multiq-tab2"))!
    precondition(!q2.multiSelect && q2.kind == .question && q2.checkedNone)
    precondition(q2.tabs == [PromptTab(label: "Fruit", done: true), PromptTab(label: "Color", done: false), PromptTab(label: "Submit", done: false)])
    precondition(q2.header == "Color" && q2.progress == "2 of 2" && q2.currentTab == 1)

    let r = detectPromptCard(screen: fixture("review-submit"))!
    precondition(r.review && r.kind == .question && r.currentTab == 2)
    precondition(r.items.map(\.label) == ["Submit answers", "Cancel"] && r.items.allSatisfy { $0.role == .normal })
    precondition(r.body!.contains("cherry, apple"))
    precondition(detectPrompt(screen: fixture("review-submit")).count == 2)

    let s = detectPromptCard(screen: fixture("multiselect-single"))!
    precondition(s.multiSelect && s.tabs.count == 2 && s.header == "Pet" && s.progress == nil)

    for f in ["question", "permission", "phase6-edit", "phase6-fetch"] {
        let c = detectPromptCard(screen: fixture(f))!
        precondition(!c.multiSelect && !c.review && c.items.allSatisfy { $0.checked == nil })
    }

    let h = ChatDiffHunk(oldStart: 10, newStart: 10, lines: [" ctx", "-old", "+new"])
    precondition(diffRows([h]) == [DiffRow(kind: .context, number: 10, text: "ctx"), DiffRow(kind: .removed, number: 11, text: "old"), DiffRow(kind: .added, number: 11, text: "new")])
    let h2 = ChatDiffHunk(oldStart: nil, newStart: nil, lines: ["-a", "\\ No newline", "+b"])
    precondition(diffRows([h2, h]).map(\.number) == [nil, nil, nil, 10, 11, 11])
    precondition(diffRows([h2])[1] == DiffRow(kind: .context, number: nil, text: "\\ No newline"))
    let h3 = ChatDiffHunk(oldStart: 5, newStart: 7, lines: ["+x", "+y", "-z", " c"])
    precondition(diffRows([h3]).map(\.number) == [7, 8, 5, 9])

    let m = mergeChecked(screen: [1: false, 2: true], pending: [1: true])
    precondition(m.shown == [1: true, 2: true] && m.pending == [1: true])
    let m2 = mergeChecked(screen: [1: true, 2: true], pending: [1: true])
    precondition(m2.shown == [1: true, 2: true] && m2.pending.isEmpty)
}

private extension PromptCard { var checkedNone: Bool { items.allSatisfy { $0.checked == nil } } }
