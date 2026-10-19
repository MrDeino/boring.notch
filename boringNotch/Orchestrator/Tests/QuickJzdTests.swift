import Foundation

func runQuickJzdTests() {
    // Real capture (Claude Code 2.1.299, 200 cols): two wrapped lines re-joined, the blank-line paragraph kept.
    let real = fixture("leadin-2q")
    let lead = screenLeadIn(screen: real)!
    precondition(lead.hasPrefix("Laptop notches exist because the webcam"))
    precondition(lead.contains("MacBook Pro introduced a notch") && lead.contains("menu bar and screen area"))
    precondition(lead.hasSuffix("work around it.\n\nLEADIN-END"))
    precondition(!lead.contains("Write a paragraph") && !lead.contains("Fruit"))

    let long = screenLeadIn(screen: fixture("leadin-long-2q"))!.components(separatedBy: "\n\n")
    precondition(long.count == 5 && long[0].hasSuffix("measurements already:") && !long[0].contains("\n") && long[4].hasPrefix("Done when:"))

    let rule = String(repeating: "─", count: 40)
    // The pending tool's own row is skipped; an earlier tool row or the user echo ends the lead-in.
    let s = "❯ hi\n\n⏺ Bash(ls)\n  ⎿  a\n\n⏺ First part.\n\n⏺ Second part\n  continues.\n\n⏺ Bash(rm x)\n\(rule)\n Bash command\n❯ 1. Yes\n  2. No\n"
    precondition(screenLeadIn(screen: s) == "First part.\n\nSecond part\ncontinues.")
    // No dialog under the prose, or no prose above the dialog: nothing.
    precondition(screenLeadIn(screen: "⏺ Done.\n") == nil)
    precondition(screenLeadIn(screen: "❯ hi\n\(rule)\n❯ 1. Yes\n") == nil)

    // Held: shown until its prose block reaches the transcript (markdown in the block does not matter).
    let user = decodeChatBlocks(Data(#"[{"id":"u","kind":"user","text":"hi"}]"#.utf8))!.blocks
    precondition(heldLeadIn(screen: real, blocks: user) == lead)
    let first = lead.components(separatedBy: "\n\n")[0].replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "webcam", with: "`webcam`")
    let partial = decodeChatBlocks(Data(("[{\"id\":\"u\",\"kind\":\"user\",\"text\":\"hi\"},{\"id\":\"p\",\"kind\":\"prose\",\"text\":\"**Laptop** notches exist because the `webcam` has to sit somewhere, and more.\"}]").utf8))!.blocks
    precondition(heldLeadIn(screen: real, blocks: partial) == lead) // a block holding only part of it does not hide the rest
    let arrived = decodeChatBlocks(Data(("[{\"id\":\"u\",\"kind\":\"user\",\"text\":\"hi\"},{\"id\":\"p\",\"kind\":\"prose\",\"text\":\"" + first + "\\n\\nLEADIN-END\"}]").utf8))!.blocks
    precondition(heldLeadIn(screen: real, blocks: arrived) == nil)
    let older = decodeChatBlocks(Data(#"[{"id":"u","kind":"user","text":"hi"},{"id":"p","kind":"prose","text":"Let me check the runs first."}]"#.utf8))!.blocks
    precondition(heldLeadIn(screen: real, blocks: older) == lead)
}
