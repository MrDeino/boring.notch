import Foundation

/// Synthetic turn: a running tool line ("⏺ Calling Shopify…") around the answer. The live row holds only the answer, and when the
/// transcript block arrives it takes the row's place: same order, same position, nothing stale left behind.
func runQuickGlitchTests() {
    for l in ["⏺ Calling Shopify…", "⏺ Searching the web…", "Fetching 3 pages...", "⏺ Ran 2 shell commands (ctrl+o to expand)"] {
        precondition(isToolSummary(l), "tool line read as prose: \(l)")
    }
    for l in ["⏺ The receiver is wired and the test passed.", "⏺ Checking the receiver now: the pin idles high.", "⏺ Nothing…"] {
        precondition(!isToolSummary(l) || l == "⏺ Nothing…" , "prose read as a tool line: \(l)")
    }

    let answer = "The buzzer works now. The trigger test passed with clean presses."
    let rule = String(repeating: "─", count: 80)
    func screen(_ els: [String], working: Bool) -> String {
        els.joined(separator: "\n\n") + (working ? "\n\n✻ Working… (3s)" : "") + "\n\n" + rule + "\n❯ \n" + rule + "\n  ? for shortcuts\n"
    }
    func blocks(_ held: Bool) -> [ChatBlock] {
        let j = #"[{"id":"u","kind":"user","text":"go"},{"id":"t","kind":"tool","name":"Shopify","target":"x"}"# + (held ? #",{"id":"a","kind":"prose","text":""# + answer + #""}"# : "") + "]"
        return decodeChatBlocks(Data(j.utf8))!.blocks
    }
    func rows(_ b: [ChatBlock], _ live: String?) -> [String] {
        b.compactMap { $0.kind == .prose ? $0.text : nil } + (live.map { $0.components(separatedBy: "\n\n") } ?? [])
    }
    // Tool line before the answer, then after it; the answer is the same row either way.
    for els in [["⏺ Calling Shopify…", "⏺ " + answer], ["⏺ " + answer, "⏺ Calling Shopify…"]] {
        var live = nextLiveReply(previous: nil, screen: screen(els, working: true), blocks: blocks(false), working: true)
        precondition(live == answer, "live row is not just the answer: \(live ?? "nil")")
        let before = rows(blocks(false), live)
        // The block arrives (turn still on screen, grace not run): the live row empties and the block is in the same slot.
        live = nextLiveReply(previous: live, screen: screen(els, working: false), blocks: blocks(true), working: false)
        precondition(live == nil, "stale live row after the block: \(live ?? "")")
        let after = rows(blocks(true), live)
        precondition(before == after && after == [answer], "row order or position changed: \(before) -> \(after)")
        precondition(liveEndDue(working: false, hasRow: live != nil, cardUp: false, screen: screen(els, working: false)) == false)
    }
}
