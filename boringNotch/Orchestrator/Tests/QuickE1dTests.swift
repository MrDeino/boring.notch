import Foundation

func runQuickE1dTests() {
    func frames(_ n: String) -> [String] { fixture(n).components(separatedBy: "<<<FRAME>>>\n") }
    func blocks(_ prose: String?) -> [ChatBlock] {
        var j = #"[{"id":"u","kind":"user","text":"explain the notch"}"#
        if let prose { j += ",{\"id\":\"p\",\"kind\":\"prose\",\"text\":\"" + prose + "\"}" }
        return decodeChatBlocks(Data((j + "]").utf8))!.blocks
    }
    let user = blocks(nil)

    // One block: spinner only -> nil, then a growing prefix; wraps re-joined, paragraph kept, no chrome.
    let one = frames("live-one")
    var prev: String? = nil
    var seen: [String] = []
    for f in one {
        prev = nextLiveReply(previous: prev, screen: f, blocks: user, working: true)
        if let p = prev { seen.append(p) }
    }
    precondition(seen.count == 3 && seen[0] == "The notch is a camera")
    precondition(seen[1].hasPrefix(seen[0]) && seen[2].hasPrefix("The notch is a camera cutout"))
    let last = seen[2]
    precondition(last.contains("dead space into a small control surface.\n\nSecond paragraph here."))
    precondition(!last.contains("\n") || last.components(separatedBy: "\n").count == 3)
    precondition(!last.contains("Working") && !last.contains("Tip") && !last.contains("esc to interrupt") && !last.contains("⏺"))
    // The swap: once the block holds the text (markdown and all) the live text is gone.
    let md = blocks("**The notch** is a `camera` cutout in the top of the screen that Apple added to the MacBook Pro so the display could reach.")
    precondition(nextLiveReply(previous: last, screen: one[3], blocks: md, working: true) == nil)

    // Several blocks: tool rows (inline and collapsed group) never show; held prose is dropped.
    let sev = frames("live-several")
    precondition(nextLiveReply(previous: nil, screen: sev[1], blocks: user, working: true) == "First answer.\n\nSecond answer is longer now.")
    precondition(nextLiveReply(previous: nil, screen: sev[0], blocks: user, working: true) == "First answer.\n\nSecond")
    precondition(nextLiveReply(previous: nil, screen: sev[1], blocks: blocks("First answer."), working: true) == "Second answer is longer now.")

    // End of turn: idle line, no spinner. Nothing live stays nothing; a live row is kept until its block arrives.
    let end = frames("live-end")
    precondition(nextLiveReply(previous: nil, screen: end[1], blocks: user, working: false) == nil)
    precondition(nextLiveReply(previous: "All done here.", screen: end[1], blocks: user, working: false) == "All done here.")
    precondition(nextLiveReply(previous: "All done here.", screen: end[1], blocks: blocks("All done here."), working: false) == nil)

    // Spinner rows (old and new format) alone are not a reply.
    precondition(screenLiveReply(screen: fixture("working-new"), blocks: user) == nil)
    precondition(screenLiveReply(screen: fixture("working"), blocks: user) == nil)

    // Question card: no input-box anchor while a dialog is up.
    precondition(screenLiveReply(screen: fixture("leadin-2q"), blocks: user) == nil)
    precondition(nextLiveReply(previous: nil, screen: fixture("leadin-2q"), blocks: user, working: false) == nil)

    // Long reply: 320 lines revealed 40 per frame through a 250-line capture; head accumulated across screens.
    let rule = String(repeating: "─", count: 190)
    let tail = ["", "✻ Working… (12s · ↑ 1.2k tokens · esc to interrupt)", "", rule, "❯ ", rule, "  footer"]
    func num(_ i: Int) -> String { String(format: "line %03d some words", i) }
    var acc: String? = nil
    var sawCut = false
    for shown in stride(from: 40, through: 320, by: 40) {
        var all = ["❯ write a lot", ""]
        for i in 1...shown { all.append((i == 1 ? "⏺ " : "  ") + num(i)) }
        all += tail
        let screen = all.suffix(250).joined(separator: "\n") + "\n"
        if let r = screenLiveReply(screen: screen, blocks: user), r.headCut { sawCut = true }
        acc = nextLiveReply(previous: acc, screen: screen, blocks: user, working: true)
    }
    precondition(sawCut)
    let got = acc!.components(separatedBy: "\n")
    precondition(got == (1...320).map(num), "long reply: \(got.count) lines, first \(got.first ?? "")")

    // mergeLiveReply
    precondition(mergeLiveReply(previous: "a\nb", current: "c", headCut: false) == "c")
    precondition(mergeLiveReply(previous: nil, current: "c", headCut: true) == "c")
    precondition(mergeLiveReply(previous: "one\ntwo\nthree", current: "two\nthree\nfour", headCut: true) == "one\ntwo\nthree\nfour")
    precondition(mergeLiveReply(previous: "one\ntwo", current: "zzz\nyyy", headCut: true) == "zzz\nyyy")

    // pollInterval: 0.5 s only for a live turn on the open notch.
    precondition(pollInterval(notchOpen: true, chatRunning: true, turnLive: true) == 0.5)
    precondition(pollInterval(notchOpen: false, chatRunning: true, turnLive: true) == 3)
    precondition(pollInterval(notchOpen: true, chatRunning: true, offline: true, turnLive: true) == 10)
    precondition(pollInterval(notchOpen: true, chatRunning: true) == 2)
}
