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
}
