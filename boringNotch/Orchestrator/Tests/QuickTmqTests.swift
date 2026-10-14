import Foundation

func runQuickTmqTests() {
    func ls(_ s: String) -> LiveStatus? { parseLiveStatus(screen: s) }
    precondition(ls("· Waddling… (35s · ↓ 2.3k tokens)") == LiveStatus(text: "Waddling…", elapsed: 35, tokens: "↓ 2.3k tokens"))
    for g in ["·", "✢", "✳", "✶", "✻", "✽"] {
        precondition(ls("\(g) Waddling… (35s · ↓ 2.3k tokens)")?.elapsed == 35)
        precondition(ls(" \u{a0}\(g) Waddling… (35s · ↓ 2.3k tokens)")?.tokens == "↓ 2.3k tokens")
    }
    precondition(ls("✻ Working… (41s · ↑ 1.2k tokens · esc to interrupt)") == LiveStatus(text: "Working…", elapsed: 41, tokens: "↑ 1.2k tokens"))
    precondition(ls("✢ Pondering… (1m 52s · esc to interrupt)") == LiveStatus(text: "Pondering…", elapsed: 112, tokens: nil))
    precondition(ls("✻ Thinking… (esc to interrupt)") == LiveStatus(text: "Thinking…", elapsed: nil, tokens: nil))
    precondition(ls("✳ Brewing… (2m 5s · ↓ 12k tokens · thought for 3s)") == LiveStatus(text: "Brewing…", elapsed: 125, tokens: "↓ 12k tokens"))
    for bad in ["✻ Worked for 21s · done 9:19 pm · 1 monitor still running", "· Fixed the bug (see #12)", "· plain bullet… (note)", "> (esc to interrupt)"] {
        precondition(ls(bad) == nil)
    }
    for f in ["permission", "inputbox"] { precondition(ls(fixture(f)) == nil) }
    precondition(ls(fixture("working-new")) == LiveStatus(text: "Waddling…", elapsed: 35, tokens: "↓ 2.3k tokens"))
    precondition(ls(fixture("working")) != nil)

    let spin = "· Waddling… (35s · ↓ 2.3k tokens)"
    precondition(liveStatusFor(screen: spin, live: false) == nil)
    precondition(liveStatusFor(screen: "nothing", live: true) == LiveStatus(text: "Working…", elapsed: nil))
    precondition(liveStatusFor(screen: spin, live: true)?.text == "Waddling…")
    precondition(liveStatusFor(screen: spin, live: nil)?.elapsed == 35)
    precondition(liveStatusFor(screen: "nothing", live: nil) == nil)

    let d = JSONDecoder()
    func cr(_ j: String) -> ChatResponse { try! d.decode(ChatResponse.self, from: Data(j.utf8)) }
    precondition(cr(#"{"running":true}"#).live == nil)
    precondition(cr(#"{"running":true,"live":true}"#).live == true)
    let odd = cr(#"{"running":true,"live":"yes"}"#)
    precondition(odd.live == nil && odd.running == true)
    precondition(ChatResponse(running: true, screen: "x").live == nil)

    func st(_ stick: Bool, _ o: CGFloat, _ n: CGFloat, _ y: CGFloat) -> (Bool, Bool, Bool) {
        let r = chatScrollStep(stick: stick, oldHeight: o, newHeight: n, contentMinY: y, viewport: 200)
        return (r.stick, r.scrollToBottom, r.newContent)
    }
    precondition(st(true, 500, 560, -300) == (true, true, false))
    precondition(st(false, 500, 560, -100) == (false, false, true))
    precondition(st(false, 560, 500, -100) == (false, false, false))
    precondition(st(false, 500, 500, -285) == (true, false, false))  // 500-285-200 = 15
    precondition(st(true, 500, 500, -260) == (false, false, false))  // 40
}
