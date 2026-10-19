import Foundation

/// One synthetic turn (text -> tool -> text -> tool -> text, collapsed "Ran N shell commands" lines, one question card, a transcript that lags
/// the screen): at every step each paragraph is shown exactly once (transcript rows, then the live row), in order, never gone once shown,
/// and no tool summary reads as prose. The per-step display is compared with fixtures/flicker-sequence.golden.txt (FLICKER_UPDATE=1 rewrites it).
func runQuickFlickerTests() {
    let p = ["P1 The buzzer works now and the next step is the trigger test, so press it a few times. P1-END",
             "P2 Sorry, a typo in my script meant that run did not count, so running it once more now. P2-END",
             "P3 Trigger test passed with clean presses and no doubles, so now checking the receiver. P3-END",
             "P4 Nothing came through, but the pin idling high confirms the setup is right. P4-END"]
    let rule = String(repeating: "─", count: 80)
    func screen(_ els: [String], card: Bool = false) -> String {
        els.joined(separator: "\n\n") + "\n\n✻ Working… (3s)\n\n" + rule + (card ? "\n Bash command\n❯ 1. Yes\n  2. No\n" : "\n❯ \n") + rule + "\n  ? for shortcuts\n"
    }
    func text(_ i: Int) -> String { "⏺ " + p[i] }
    let tool = "⏺ Bash(ssh gun2 'sleep 20')\n  ⎿  Running…"
    func ran(_ n: Int) -> String { "⏺ Ran \(n) shell command\(n == 1 ? "" : "s") (ctrl+o to expand)" }
    func blocks(_ held: [Int]) -> [ChatBlock] {
        let j = #"[{"id":"u","kind":"user","text":"go"}"# + held.map { ",{\"id\":\"p\($0)\",\"kind\":\"prose\",\"text\":\"\(p[$0])\"},{\"id\":\"t\($0)\",\"kind\":\"tool\",\"name\":\"Bash\",\"target\":\"x\"}" }.joined() + "]"
        return decodeChatBlocks(Data(j.utf8))!.blocks
    }
    // (screen, transcript holds, working, card up)
    let steps: [(String, [Int], Bool, Bool)] = [
        (screen(["⏺ P1 The buzzer works now and the next"]), [], true, false),
        (screen([text(0)]), [], true, false),
        (screen([text(0), tool]), [], true, false),
        (screen([text(0), ran(1), "⏺ P2 Sorry, a typo in my"]), [], true, false),
        (screen([text(0), ran(1), text(1)]), [0], true, false),
        (screen([text(0), ran(1), text(1), tool]), [0], true, false),
        (screen([ran(2), text(2), tool]), [0], true, false),               // P1, P2 scrolled off the capture
        (screen([ran(2), text(2)], card: true), [0, 1], false, true),     // question card up under P3
        (screen([ran(2), text(2), tool]), [0, 1], true, false),            // answered
        (screen([ran(2), text(2), ran(3), text(3)]), [0, 1, 2], false, false),
        (screen([text(3)]), [0, 1, 2], false, false),                      // turn over, P4 not in the transcript yet: kept
        ("", [0, 1, 2, 3], false, false),                                 // transcript caught up
    ]
    var live: String?, seen: [Int] = [], out = ""
    for (n, (scr, held, working, card)) in steps.enumerated() {
        let b = blocks(held)
        live = nextLiveReply(previous: live, screen: scr, blocks: b, working: working, cardUp: card)
        let rows = held.map { p[$0] } + (live.map { $0.components(separatedBy: "\n\n") } ?? [])
        for (k, r) in rows.enumerated() { out += "step \(n) row \(k): \(r)\n" }
        let shown = rows.joined(separator: "\n")
        precondition(!shown.contains("Ran "), "step \(n): tool summary in prose")
        let now = (0..<4).filter { shown.contains("P\($0 + 1) ") }
        for i in now { precondition(shown.components(separatedBy: "P\(i + 1) ").count == 2, "step \(n): P\(i + 1) shown twice") }
        precondition(now == now.sorted(), "step \(n): out of order")
        for i in seen { precondition(now.contains(i), "step \(n): P\(i + 1) disappeared") }
        seen = now
    }
    precondition(seen == [0, 1, 2, 3] && live == nil)
    let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/flicker-sequence.golden.txt")
    if ProcessInfo.processInfo.environment["FLICKER_UPDATE"] != nil { try! out.write(to: golden, atomically: true, encoding: .utf8) }
    precondition(out == (try! String(contentsOf: golden, encoding: .utf8)), "flicker-sequence golden differs")
}
