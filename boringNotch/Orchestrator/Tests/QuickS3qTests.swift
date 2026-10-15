import Foundation

func runQuickS3qTests() {
    func b(_ items: String) -> [ChatBlock] { decodeChatBlocks(Data(#"{"running":true,"blocks":[\#(items)]}"#.utf8))?.blocks ?? [] }
    let u = #"{"id":"u","kind":"user","text":"hi"}"#, t = #"{"id":"t","kind":"tool","name":"Edit","target":"/x"}"#
    func p(_ id: String, _ text: String) -> String { #"{"id":"\#(id)","kind":"prose","text":"\#(text)"}"# }

    // latestAssistantProse: prose since the last user message
    precondition(latestAssistantProse(b([u, p("a", "a"), t, p("b", "b")].joined(separator: ","))) == "a\n\nb")
    precondition(latestAssistantProse(b([p("x", "x"), u, t].joined(separator: ","))) == nil)
    precondition(latestAssistantProse(b([p("x", "x"), u, p("y", "y")].joined(separator: ","))) == "y")
    precondition(latestAssistantProse(b(p("a", "a"))) == "a")
    precondition(latestAssistantProse([]) == nil)
    precondition(latestAssistantProse(b([u, p("s", "   ")].joined(separator: ","))) == nil)
    precondition(latestAssistantProse(b([u, p("s", "  trim me \\n")].joined(separator: ","))) == "trim me")
}
