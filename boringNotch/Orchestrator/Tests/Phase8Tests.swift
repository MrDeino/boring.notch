import Foundation

func runPhase8Tests() {
    func dec(_ j: String) -> ChatResponse { try! d.decode(ChatResponse.self, from: Data(j.utf8)) }
    let a = dec(#"{"running":true,"screen":"x"}"#)
    precondition(a.live == nil && a.input == nil && a.context == nil && !a.hasInputKey)
    let b = dec(#"{"running":true,"screen":"x","input":null}"#)
    precondition(b.hasInputKey && b.input == nil)
    let c = dec(#"{"input":{"text":"fix it","suggested":true},"live":true,"context":{"tokens":380000,"window":1000000,"percent":38}}"#)
    precondition(c.input?.text == "fix it" && c.input?.suggested == true && c.live == true && c.context?.percent == 38)
    let e = dec(#"{"live":"yes","context":{"percent":"x"},"input":5}"#)
    precondition(e.live == nil && e.context?.percent == nil && e.input == nil && e.hasInputKey)
    _ = ChatResponse(running: true, screen: "")

    let screen = "───\n❯ hello there\n───\n"
    let old = resolveInput(hasKey: false, input: nil, screen: screen, chatRunning: true, previous: nil, wasDraft: false, editing: false)
    precondition(old.line == parseInputLine(screen: screen))
    func r(_ i: ChatInput?, running: Bool = true) -> (line: String?, draft: Bool) {
        resolveInput(hasKey: true, input: i, screen: screen, chatRunning: running, previous: nil, wasDraft: false, editing: false)
    }
    precondition(r(ChatInput(text: "go on", suggested: true)) == ("go on", false))
    precondition(r(ChatInput(text: "go on", suggested: false)) == ("go on", true))
    precondition(r(ChatInput(text: "", suggested: true)) == (nil, false))
    precondition(r(nil) == (nil, false))
    precondition(r(ChatInput(text: "x", suggested: true), running: false) == (nil, false))
    precondition(resolveInput(hasKey: false, input: nil, screen: screen, chatRunning: false, previous: nil, wasDraft: false, editing: false) == (nil, false))

    var p = SSELineParser()
    precondition(p.feed("event: state") == nil)
    if case .state(let s)? = p.feed(#"data: {"runs":[],"usage":null}"#) { precondition(s.runs?.isEmpty == true) } else { preconditionFailure() }
    precondition(p.feed(#"data: {"runs":[]}"#) == nil)
    _ = p.feed("event: chat")
    if case .chat(let c)? = p.feed(#"data:{"running":true,"screen":"x","live":true,"input":null,"context":{"percent":12}}"#) {
        precondition(c.live == true && c.hasInputKey && c.context?.percent == 12)
    } else { preconditionFailure() }
    _ = p.feed("event: blocks")
    if case .blocks(let r, let b, let rs)? = p.feed(#"data: {"running":true,"reset":true,"blocks":[{"id":"1","kind":"prose","text":"hi"}]}"#) {
        precondition(r == true && b.count == 1 && rs)
    } else { preconditionFailure() }
    _ = p.feed("event: blocks")
    if case .blocks(_, _, let rs)? = p.feed(#"data: {"running":true,"blocks":[]}"#) { precondition(!rs) } else { preconditionFailure() }
    precondition(p.feed(": ping") == nil && p.feed("retry: 3000") == nil && p.feed("id: 7") == nil)
    _ = p.feed("event: foo")
    precondition(p.feed(#"data: {}"#) == nil)
    _ = p.feed("event: chat")
    precondition(p.feed("data: {nope") == nil)
    _ = p.feed("event: state")
    precondition(p.feed(#"data: {"runs":[]}"#) != nil)
    _ = p.feed("event: state")
    precondition(p.feed("data: " + String(repeating: "a", count: 2_000_001)) == nil)
    let t = Date()
    precondition(streamHealthy(lastLineAt: t, now: t + 19) && !streamHealthy(lastLineAt: t, now: t + 21))
    precondition(caretVisible(live: true, working: false, kind: .prose, id: "a", newestID: "a"))
    precondition(caretVisible(live: nil, working: true, kind: .prose, id: "a", newestID: "a"))
    precondition(!caretVisible(live: nil, working: false, kind: .prose, id: "a", newestID: "a"))
    precondition(!caretVisible(live: false, working: true, kind: .prose, id: "a", newestID: "a"))
    precondition(!caretVisible(live: true, working: true, kind: .tool, id: "a", newestID: "a"))
    precondition(!caretVisible(live: true, working: true, kind: .user, id: "a", newestID: "a"))
    precondition(!caretVisible(live: true, working: true, kind: .prose, id: "a", newestID: "b"))
    precondition(!caretVisible(live: true, working: true, kind: .prose, id: "a", newestID: nil))
    precondition(shouldFetchBlocks(streaming: false, running: true, newPrompt: false))
    precondition(!shouldFetchBlocks(streaming: true, running: true, newPrompt: false))
    precondition(shouldFetchBlocks(streaming: true, running: true, newPrompt: true))
    precondition(shouldFetchBlocks(streaming: true, running: false, newPrompt: false))
}
