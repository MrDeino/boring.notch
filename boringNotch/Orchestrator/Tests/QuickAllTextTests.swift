import Foundation

/// The chat shows all the assistant text the terminal shows: before, during and after a question card.
func runQuickAllTextTests() {
    func blocks(_ prose: [String]) -> [ChatBlock] {
        let j = #"[{"id":"u","kind":"user","text":"go"}"# + prose.enumerated().map { ",{\"id\":\"p\($0.offset)\",\"kind\":\"prose\",\"text\":\"\($0.element)\"}" }.joined() + "]"
        return decodeChatBlocks(Data(j.utf8))!.blocks
    }
    // Recorded-style single and multi-question cards (leadin-1q synthetic, leadin-2q a real capture).
    for (name, head, tail) in [("leadin-1q", "The sample project has two parts", "SINGLE-LEADIN-END"), ("leadin-2q", "Laptop notches exist because", "LEADIN-END")] {
        let card = fixture(name)
        let user = blocks([])
        // Before: the reply was streaming (no card yet), the row shows it.
        var row = nextLiveReply(previous: nil, screen: "⏺ \(head) and more words.\n", blocks: user, working: true) ?? "\(head) streamed"
        // During: the card is up. The row holds the full text above it, the card's own text is not in it.
        row = nextLiveReply(previous: row, screen: card, blocks: user, working: false, cardUp: true)!
        precondition(row.hasPrefix(head) && row.hasSuffix(tail) && !row.contains("Fruit"))
        // The card repaints / the screen scrolls past the text: the row keeps it.
        row = nextLiveReply(previous: row, screen: "no prose here\n", blocks: user, working: false, cardUp: true)!
        precondition(row.hasSuffix(tail))
        // Answered or cancelled: the dialog is gone, the transcript has not caught up: still there, however the screen looks.
        precondition(nextLiveReply(previous: row, screen: "", blocks: user, working: true) == row)
        precondition(nextLiveReply(previous: row, screen: "", blocks: user, working: false) == row)
        // After: once the transcript block holds it, the block is the row (no duplicate).
        let block = blocks([row.replacingOccurrences(of: "\n\n", with: "\\n\\n").replacingOccurrences(of: "\n", with: " ")])
        precondition(nextLiveReply(previous: row, screen: "", blocks: block, working: false) == nil)
        precondition(heldLeadIn(screen: card, blocks: block) == nil)
    }

    // No card, nothing seen, nothing to show.
    precondition(nextLiveReply(previous: nil, screen: "", blocks: blocks([]), working: false, cardUp: true) == nil)

    // An earlier block of the same turn that opens the same way does not hide the new text.
    let opener = "Let me check the runs first and then compare them against the plan we made earlier today"
    let screen = "⏺ \(opener), which differs near the end: NEWTAIL-ONLY.\n\n" + String(repeating: "─", count: 40) + "\n Bash command\n❯ 1. Yes\n  2. No\n"
    precondition(heldLeadIn(screen: screen, blocks: blocks(["\(opener), which ends differently."])) != nil)
    precondition(heldLeadIn(screen: screen, blocks: blocks(["\(opener), which differs near the end: NEWTAIL-ONLY."])) == nil)
    // Several paragraphs: all of them held before the row goes; one missing keeps it.
    let two = "⏺ First paragraph of the brief goes here in full.\n\n  Second paragraph of the brief goes here too.\n" + String(repeating: "─", count: 40) + "\n Bash command\n❯ 1. Yes\n"
    precondition(heldLeadIn(screen: two, blocks: blocks(["First paragraph of the brief goes here in full."])) != nil)
    precondition(heldLeadIn(screen: two, blocks: blocks(["First paragraph of the brief goes here in full.", "Second paragraph of the brief goes here too."])) == nil)
}
