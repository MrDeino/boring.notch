import Foundation

func runQuickHm7Tests() {
    func ap(_ tool: String?, _ cmd: String?, _ desc: String? = nil) -> OrchestratorApproval {
        OrchestratorApproval(id: "a", tool: tool, command: cmd, description: desc, at: nil)
    }
    precondition(approvalIsQuestion(ap("AskUserQuestion", "{}")))
    precondition(!approvalIsQuestion(ap("Bash", "ls")) && !approvalIsQuestion(ap(nil, nil)) && !approvalIsQuestion(nil))

    precondition(approvalSummary(ap("Bash", "git status  --short", "Show status")) == ApprovalSummary(caption: "Show status", lines: ["git status --short"], mono: true))
    precondition(approvalSummary(ap("Bash", "ls")) == ApprovalSummary(caption: nil, lines: ["ls"], mono: true))
    precondition(approvalSummary(ap("Bash", "", "d")) == ApprovalSummary(caption: nil, lines: ["d"], mono: true))

    for (t, v) in [("Read", "Read file"), ("Edit", "Edit file"), ("Write", "Write file"), ("MultiEdit", "Edit file"), ("NotebookEdit", "Edit notebook")] {
        precondition(approvalSummary(ap(t, "/a/b.swift")) == ApprovalSummary(caption: v, lines: ["/a/b.swift"], mono: true))
    }
    precondition(approvalSummary(ap("Edit", "/a/b.swift", "Fix it")).caption == "Fix it")

    let kv = approvalSummary(ap("mcp__x", #"{"query":"x","limit":5,"nested":{"a":1}}"#))
    precondition(kv.lines == ["limit: 5", #"nested: {"a":1}"#, "query: x"] && !kv.mono)
    let many = approvalSummary(ap("mcp__x", #"{"a":1,"b":2,"c":3,"d":4,"e":5,"f":6}"#))
    precondition(many.lines == ["a: 1", "b: 2", "c: 3", "d: 4", "+2 more"])

    let cut = approvalSummary(ap("WebFetch", #"{"url":"https://x.y","prompt":"summarise the pa"#))
    precondition(cut.lines == ["prompt: summarise the pa…", "url: https://x.y"] && !cut.mono)
    precondition(!cut.lines.contains { $0.hasPrefix("{") })

    precondition(approvalSummary(ap("Glob", "**/*.swift")) == ApprovalSummary(caption: nil, lines: ["**/*.swift"], mono: true))
    precondition(approvalSummary(ap("Bash", String(repeating: "x", count: 400))).lines[0].count == 200)
}
