import Foundation

private func phase5Data(_ name: String) -> Data {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/\(name)")
    return try! Data(contentsOf: url)
}

private func p5Block(_ id: String, _ kind: String, result: String? = nil) -> ChatBlock {
    let r = result.map { "\"\($0)\"" } ?? "null"
    return try! JSONDecoder().decode(ChatBlock.self, from: Data(#"{"id":"\#(id)","kind":"\#(kind)","result":\#(r)}"#.utf8))
}

private func p5Box(_ line: String, extra: String = "") -> String {
    let rule = String(repeating: "─", count: 40)
    return "\(rule)\n\(line)\n\(extra)\(rule)\n  ? for shortcuts\n"
}

func runPhase5Tests() {
    // decode
    let d = decodeChatBlocks(phase5Data("phase5-blocks.json"))!
    precondition(d.running == true)
    precondition(d.blocks.map(\.kind) == [.user, .tool, .tool, .tool, .prose, .prose, .prose])
    precondition(d.blocks.map(\.id).contains("7"))
    precondition(!d.blocks.map(\.id).contains("th1"))
    precondition(d.blocks.count == 7)
    precondition(d.blocks.first { $0.id == "p-notext" }!.text == nil)
    let edit = d.blocks.first { $0.id == "toolu_02Edit" }!
    precondition(edit.name == "Edit")
    precondition(edit.target == "/Users/x/proj/OrchestratorView.swift")
    precondition(edit.added == 12 && edit.removed == 4)
    precondition(edit.diff?.count == 1 && edit.diff?[0].oldStart == 10)
    let pend = d.blocks.first { $0.id == "toolu_03Bash" }!
    precondition(pend.result == nil && pend.added == nil)
    let bare = decodeChatBlocks(phase5Data("phase5-blocks-bare.json"))!
    precondition(bare.running == nil && !bare.blocks.isEmpty)
    let empty = decodeChatBlocks(Data(#"{"running":false,"blocks":[]}"#.utf8))!
    precondition(empty.running == false && empty.blocks.isEmpty)
    precondition(decodeChatBlocks(Data("not json".utf8)) == nil)

    // merge
    let u1 = p5Block("u1", "user"), t1 = p5Block("t1", "tool"), t1r = p5Block("t1", "tool", result: "ok"), p1 = p5Block("p1", "prose")
    let m1 = mergeChatBlocks([u1, t1], [t1r, p1], reset: false)
    precondition(m1.blocks.map(\.id) == ["u1", "t1", "p1"] && m1.blocks[1].result == "ok" && m1.appended)
    let m2 = mergeChatBlocks([u1, t1], [t1r], reset: false)
    precondition(!m2.appended && m2.blocks[1].result == "ok")
    let m3 = mergeChatBlocks([u1], [p5Block("p9", "prose")], reset: true)
    precondition(m3.blocks.map(\.id) == ["p9"] && !m3.appended)
    let many = (1...250).map { p5Block("x\($0)", "prose") }
    let m4 = mergeChatBlocks([u1], many, reset: true)
    precondition(m4.blocks.count == 200 && m4.blocks.last!.id == "x250")

    // discontinuity
    let new80 = (1...80).map { p5Block("n\($0)", "prose") }
    precondition(blocksDiscontinuous(sinceSent: true, incoming: new80, existing: [u1]))
    precondition(!blocksDiscontinuous(sinceSent: true, incoming: [u1] + new80.dropFirst(), existing: [u1]))
    precondition(!blocksDiscontinuous(sinceSent: false, incoming: new80, existing: [u1]))
    precondition(!blocksDiscontinuous(sinceSent: true, incoming: Array(new80.prefix(79)), existing: [u1]))

    // input line
    precondition(parseInputLine(screen: fixture("inputbox")) == "make it my real app")
    precondition(parseInputLine(screen: p5Box("❯")) == "")
    precondition(parseInputLine(screen: fixture("permission")) == nil)
    precondition(parseInputLine(screen: fixture("question")) == nil)
    precondition(parseInputLine(screen: "") == nil)
    precondition(parseInputLine(screen: p5Box("❯\u{a0}hello there" + String(repeating: " ", count: 150))) == "hello there")
    precondition(parseInputLine(screen: p5Box("❯ first", extra: "  second\n")) == "first second")

    // draft heuristic
    precondition(!boxIsDraft(previous: nil, current: "run the phase 4 plan", wasDraft: false, editing: false))
    precondition(!boxIsDraft(previous: "", current: "run the phase 4 plan", wasDraft: false, editing: false))
    precondition(boxIsDraft(previous: "check the", current: "check the runs", wasDraft: false, editing: false))
    precondition(boxIsDraft(previous: "check the runs", current: "check the runs", wasDraft: true, editing: false))
    precondition(!boxIsDraft(previous: "a", current: "", wasDraft: true, editing: false))
    precondition(!boxIsDraft(previous: "a", current: nil, wasDraft: true, editing: false))
    precondition(!boxIsDraft(previous: "a", current: "ab", wasDraft: false, editing: true))

    // clear to caret
    precondition(clearToCaret("hello world", caretUTF16: 5) == " world")
    precondition(clearToCaret("hello world", caretUTF16: 0) == "hello world")
    precondition(clearToCaret("hello", caretUTF16: nil) == "")
    precondition(clearToCaret("hello", caretUTF16: 99) == "")
    precondition(clearToCaret("😀ab", caretUTF16: 2) == "ab")

    // idle status
    precondition(parseIdleStatus(screen: "⏺ Done, merged.\n\n✻ Brewed for 2m 4s · done 10:58 am\n\n" + fixture("inputbox")) == "✻ Brewed for 2m 4s")
    precondition(parseIdleStatus(screen: fixture("permission")) == nil)
    precondition(parseIdleStatus(screen: fixture("working")) == nil)
    precondition(parseIdleStatus(screen: "") == nil)
    precondition(parseIdleStatus(screen: "✻ Brewed for 2m 4s") == "✻ Brewed for 2m 4s")

    // tool display
    precondition(toolTargetDisplay(name: "Read", target: "/Users/x/proj/OrchestratorView.swift") == "OrchestratorView.swift")
    precondition(toolTargetDisplay(name: "Edit", target: "/Users/x/proj/OrchestratorView.swift") == "OrchestratorView.swift")
    precondition(toolTargetDisplay(name: "Bash", target: "git status") == "git status")
    precondition(toolTargetDisplay(name: "Grep", target: "/abs/dir") == "dir")
    precondition(toolTargetDisplay(name: "Bash", target: nil) == "")
    precondition(toolResultDisplay(name: "Read", result: "import SwiftUI (+286 lines)", added: nil) == "287 lines")
    precondition(toolResultDisplay(name: "Read", result: "only line", added: nil) == "1 line")
    precondition(toolResultDisplay(name: "Bash", result: "All three tweaks are in… (+14 lines)", added: nil) == "All three tweaks are in…")
    precondition(toolResultDisplay(name: "Edit", result: "updated", added: 12) == nil)
    precondition(toolResultDisplay(name: "Bash", result: nil, added: nil) == nil)
    precondition(toolResultDisplay(name: "Bash", result: "error: exit 1", added: nil) == "error: exit 1")
    precondition(toolResultIsError("error: exit 1") && !toolResultIsError("ok"))

    // prose
    let pa = proseAttributed("**bold** and [link](https://x.y)")
    precondition(String(pa.characters) == "bold and link")
    precondition(pa.runs.allSatisfy { $0.link == nil })
    precondition(String(proseAttributed(String(repeating: "a", count: 5000)).characters).count <= 2000)
}
