import Foundation

let d = JSONDecoder()
let a = try! d.decode(ChatResponse.self, from: Data(#"{"running":true,"screen":"a  \n\nb   \n"}"#.utf8))
precondition(a.running == true && a.screen != nil)
precondition(try! d.decode(ChatResponse.self, from: Data(#"{"running":false}"#.utf8)).screen == nil)
precondition(try! d.decode(ChatResponse.self, from: Data("{}".utf8)).running == nil)

precondition(chatTail(screen: a.screen!, maxLines: 10) == ["a", "b"])
precondition(chatTail(screen: "", maxLines: 5) == [])
precondition(chatTail(screen: "1\n2\n3\n4", maxLines: 2) == ["3", "4"])
precondition(chatTail(screen: "x\u{a0}\u{a0} \ny \u{a0}", maxLines: 5) == ["x", "y"])

let box = "─────────────────  \n❯\u{a0}merge 199" + String(repeating: " ", count: 150) + "\n─────────────────  \n  ? for shortcuts   \n"
let t = chatTail(screen: box, maxLines: 8)
precondition(t.count == 4)
precondition(t[1] == "❯\u{a0}merge 199")

let st = try! d.decode(StateResponse.self, from: Data(#"{"now":1,"sessions":[{"a":1}],"runs":[{"id":"x","project":"notch","prompt":"/gsd go\nmore","state":"running","pid":3,"denials":[]},{"id":"y","state":"done"}],"usage":{"five_hour":{"used_percentage":9,"resets_at":1791954000},"seven_day":{"used_percentage":14,"resets_at":1792116000}}}"#.utf8))
precondition(st.runs!.count == 2 && st.runs![0].state == "running")
precondition(st.usage!.fiveHour!.usedPercentage == 9 && st.usage!.fiveHour!.resetsAt == 1791954000)
precondition(st.usage!.sevenDay!.resetsDate == Date(timeIntervalSince1970: 1792116000))
precondition(try! d.decode(StateResponse.self, from: Data("{}".utf8)).runs == nil)
let e = try! d.decode(StateResponse.self, from: Data(#"{"runs":[{}],"usage":null}"#.utf8))
precondition(e.runs!.count == 1 && e.usage == nil && e.runs![0].shortPrompt == "")
precondition(st.runs![0].shortPrompt == "/gsd go")

func mk(_ id: String, _ s: String) -> OrchestratorRun {
    try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"\#(id)","state":"\#(s)"}"#.utf8))
}
let sr = stripRuns([mk("a","done"), mk("b","running"), mk("c","failed"), mk("d","waiting"), mk("e","stuck")], limit: 4)
precondition(sr.map { $0.id! } == ["b", "d", "e", "a"])

let opts = "Do you want to proceed?\n❯ 1. Yes\n  2. Yes, and don't ask again for …\n  3. No, and tell Claude what to do differently (esc)\n"
let want = [PromptOption(number: 1, label: "Yes"), PromptOption(number: 2, label: "Yes, and don't ask again for …"), PromptOption(number: 3, label: "No, and tell Claude what to do differently (esc)")]
precondition(detectPrompt(screen: box).isEmpty)
precondition(detectPrompt(screen: opts) == want)
precondition(detectPrompt(screen: opts.replacingOccurrences(of: "❯ 1", with: "❯\u{a0}1")) == want)
precondition(detectPrompt(screen: opts.split(separator: "\n").map { "│ \($0) │" }.joined(separator: "\n")) == want)
precondition(detectPrompt(screen: "1. foo\n2. bar\n").isEmpty)
precondition(detectPrompt(screen: "❯ 1. x\n").isEmpty)
precondition(detectPrompt(screen: opts + "1. foo\n") == want)
runPhase3Tests()
print("OK")
