import Foundation

/// Screen shapes seen in a real turn (synthetic text): Claude Code blinks the ⏺ of a running tool, so on "off" frames the tool's
/// header sits indented with no marker right under the prose above it; a question card whose footer wraps (typing in the
/// free-text option adds a hint) must not parse as "no card" and let the end-of-turn grace drop the lead-in.
func runQuickBlinkTests() {
    let rule = String(repeating: "─", count: 80)
    let one = "Alpha the first paragraph says what comes next, so run the check once. A-END"
    let two = "Beta the second paragraph reports the result and goes on to the next step. B-END"
    func frame(_ els: [String]) -> String { els.joined(separator: "\n") + "\n✻ Working… (3s)\n" + rule + "\n❯ \n" + rule + "\n  ? for shortcuts\n" }
    let user = decodeChatBlocks(Data(#"[{"id":"u","kind":"user","text":"go"}]"#.utf8))!.blocks
    // The same turn moment on three frames: marker on, marker off (header indented, with and without the ⎿ line), summary above.
    let frames = [
        frame(["⏺ " + one, "  Ran 2 shell commands", "⏺ " + two, "⏺ Running 1 shell command…", "  ⎿  $ sleep 3"]),
        frame(["⏺ " + one, "  Ran 2 shell commands", "⏺ " + two, "  Running 1 shell command…", "  ⎿  $ sleep 3"]),
        frame(["⏺ " + one, "  Ran 2 shell commands", "⏺ " + two, "  Running 1 shell command…"]),
        frame(["⏺ " + one, "  Ran 2 shell commands", "⏺ " + two, "  Ran 1 shell command"]),
        frame(["⏺ " + one, "  Ran 2 shell commands", "⏺ " + two, "⏺ Bash(sleep 3)", "  ⎿  Running…"]),
        frame(["⏺ " + one, "  Ran 2 shell commands", "⏺ " + two, "  Bash(sleep 3)", "  ⎿  Running…"]),
    ]
    var live: String?
    for (i, f) in frames.enumerated() {
        live = nextLiveReply(previous: live, screen: f, blocks: user, working: true)
        precondition(live == one + "\n\n" + two, "blink frame \(i): live row is \(live ?? "nil")")
    }
    // Marker-less tool header between two paragraphs on the first frame of a poll (no history): still two paragraphs, no summary text.
    let cold = nextLiveReply(previous: nil, screen: frames[1], blocks: user, working: true)
    precondition(cold == one + "\n\n" + two && !cold!.contains("Ran") && !cold!.contains("Running"))
    // Prose that merely wraps onto an indented line is untouched.
    let wrapped = frame(["⏺ " + one, "  and this indented line is still the same paragraph."])
    precondition(nextLiveReply(previous: nil, screen: wrapped, blocks: user, working: true) == one + " and this indented line is still the same paragraph.")

    // Question card, free-text option being typed into: footer wraps onto a second line.
    func card(_ footer: [String]) -> String {
        "⏺ " + one + "\n" + rule + "\n←  ☒ Base  ☐ Power  ✔ Submit  →\nWhich one?\n  1. First\n     First detail.\n  2. Second\n❯ 3. typed words\n" + rule + "\n  4. Chat about this\n" + footer.joined(separator: "\n") + "\n"
    }
    let wide = card(["Enter to select · Tab/Arrow keys to navigate · ctrl+g to edit in Vim · Esc", "to cancel"])
    precondition(detectPromptCard(screen: wide) != nil, "wrapped footer: card not detected")
    precondition(detectPromptCard(screen: card(["Enter to select · Tab/Arrow keys to navigate · Esc to cancel"])) != nil)
    precondition(detectPromptCard(screen: card(["Enter to select · Tab/Arrow keys to navigate"])) == nil) // no cancel hint: not a live dialog
    // Even when a dialog shape is not parsed (cardUp false), the grace must not run under it; it runs once the input box is back.
    precondition(!liveEndDue(working: false, hasRow: true, cardUp: false, screen: card(["unknown footer"])))
    precondition(!liveEndDue(working: false, hasRow: true, cardUp: true, screen: frames[0]))
    precondition(!liveEndDue(working: true, hasRow: true, cardUp: false, screen: frames[0]))
    precondition(!liveEndDue(working: false, hasRow: false, cardUp: false, screen: frames[0]))
    precondition(liveEndDue(working: false, hasRow: true, cardUp: false, screen: frames[0]))
    // And the row survives a dialog screen that the parser can't read.
    precondition(nextLiveReply(previous: one + "\n\n" + two, screen: card(["unknown footer"]), blocks: user, working: false) == one + "\n\n" + two)
}
