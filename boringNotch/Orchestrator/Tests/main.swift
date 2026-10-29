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
precondition(chatTail(screen: box, maxLines: 8).isEmpty)
precondition(chatTail(screen: "⏺ hi\n  ─────────────\nok\n" + box, maxLines: 8) == ["⏺ hi", "ok"])
// A live prompt (no closing rule under the ❯ line) stays visible.
precondition(chatTail(screen: "─────\n❯ 1. Yes\n  2. No\n Esc to cancel\n", maxLines: 8) == ["❯ 1. Yes", "  2. No", " Esc to cancel"])

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

let opts = "Do you want to proceed?\n❯ 1. Yes\n  2. Yes, and don't ask again for …\n  3. No, and tell Claude what to do differently (esc)\n Esc to cancel · Tab to amend\n"
let want = [PromptOption(number: 1, label: "Yes"), PromptOption(number: 2, label: "Yes, and don't ask again for …"), PromptOption(number: 3, label: "No, and tell Claude what to do differently (esc)")]
precondition(detectPrompt(screen: box).isEmpty)
precondition(detectPrompt(screen: opts) == want)
precondition(detectPrompt(screen: opts.replacingOccurrences(of: "❯ 1", with: "❯\u{a0}1")) == want)
precondition(detectPrompt(screen: opts.split(separator: "\n").map { "│ \($0) │" }.joined(separator: "\n")) == want)
precondition(detectPrompt(screen: "1. foo\n2. bar\n").isEmpty)
precondition(detectPrompt(screen: "❯ 1. x\n").isEmpty)
precondition(detectPrompt(screen: opts + "1. foo\n") == want)

func fixture(_ n: String) -> String {
    try! String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/\(n).txt"), encoding: .utf8)
}
func po(_ l: [(Int, String)]) -> [PromptOption] { l.map { PromptOption(number: $0.0, label: $0.1) } }
precondition(detectPrompt(screen: fixture("question")) == po([(1, "apple"), (2, "banana"), (3, "cherry"), (4, "Type something."), (5, "Chat about this")])) // question.txt
precondition(detectPrompt(screen: fixture("permission")) == po([(1, "Yes"), (2, "Yes, and always allow access to /tmp/notch-fixture.WJuB from this project"), (3, "Yes, and switch to auto mode · auto mode handles these prompts for you"), (4, "No")])) // permission.txt
precondition(chatTail(screen: fixture("inputbox"), maxLines: 8).isEmpty) // inputbox.txt: real screen tail from the notch
precondition(chatTail(screen: "⏺ Done, merged.\n\n" + fixture("inputbox"), maxLines: 8) == ["⏺ Done, merged."])
precondition(detectPrompt(screen: fixture("inputbox")).isEmpty)
precondition(detectPrompt(screen: opts + "a\nb\nc\nd\ne\n").isEmpty)
precondition(detectPrompt(screen: "1. a\n" + "────\n❯ 2. foo\n────\n  ? for shortcuts\n").isEmpty)
precondition(detectPrompt(screen: "────\n❯\u{a0}1. do X\n  2. do Y\n────\n").isEmpty)
precondition(detectPrompt(screen: "❯ 1. Yes\n  2. No\n").isEmpty) // no footer

let b = URL(string: "http://127.0.0.1:4799")!
for bad in [OrchestratorPost.text("   "), .text(""), .key("x"), .key("0"), .key("10")] { precondition(bad.request(base: b) == nil) }
let kr = OrchestratorPost.key("Escape").request(base: b)!
precondition(kr.httpMethod == "POST" && kr.value(forHTTPHeaderField: "x-orch") == "1" && kr.value(forHTTPHeaderField: "Content-Type") == "application/json")
precondition(kr.url!.path == "/api/chat" && (try! d.decode([String: String].self, from: kr.httpBody!)) == ["key": "Escape"])

if let logPath = ProcessInfo.processInfo.environment["ORCH_MOCK_LOG"] {
    let ses = URLSession(configuration: .ephemeral)
    for (p, want) in [(OrchestratorPost.text("hello"), 200), (.key("1"), 200), (.key("Escape"), 200), (.start, 200), (.stop, 200), (.text("busy-409"), 409)] {
        let got = try! await sendOrchestratorPost(p, base: b, session: ses)
        precondition(got == want)
    }
    for bad in [OrchestratorPost.text("  "), .key("x")] { let r = try! await sendOrchestratorPost(bad, base: b, session: ses); precondition(r == nil) }
    let log = try! String(contentsOfFile: logPath, encoding: .utf8).split(separator: "\n")
    precondition(log.count == 6)
    let ents = log.map { try! JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: String] }
    let paths = ["/api/chat", "/api/chat", "/api/chat", "/api/chat/start", "/api/chat/stop", "/api/chat"]
    let bodies = [#"{"text":"hello"}"#, #"{"key":"1"}"#, #"{"key":"Escape"}"#, "{}", "{}", #"{"text":"busy-409"}"#]
    for (i, e) in ents.enumerated() {
        precondition(e["method"] == "POST" && e["path"] == paths[i] && e["xorch"] == "1" && e["ctype"] == "application/json" && e["host"] == "127.0.0.1:4799" && e["body"] == bodies[i])
    }
}

runPhase3Tests()
runPhase4Tests()
runPhase5Tests()
runPhase6Tests()
runPhase7Tests()
runQuickPugTests()
runQuickQeiTests()
runQuickR8wTests()
runQuickRm9Tests()
runQuickS3qTests()
runQuickTmqTests()
runQuickX18Tests()
runQuickWingsTests()
runPhase8Tests()
runPhase9Tests()
runQuickHm7Tests()
runQuickJzdTests()
runQuickChromeTests()
runQuickDotTests()
runQuickCardFitTests()
runQuickClaudeTests()
runQuickMe4Tests()
runQuickE1dTests()
runQuickFilesTests()
runQuickDeployTests()
runQuickAllTextTests()
runQuickFlickerTests()
runQuickGlitchTests()
runQuickBgTests()
runQuickBlinkTests()
runQuickAskTests()
await runQuickKeyQueueTests()
runQuickFreetextTests()
runQuickCtxTests()
runQuickSlowTests()
if ProcessInfo.processInfo.environment["ORCH_APPROVAL_MOCK"] != nil { await runPhase9Mock() }
if ProcessInfo.processInfo.environment["ORCH_NOTES_MOCK"] != nil { await runQuickR8wMock() }
if ProcessInfo.processInfo.environment["ORCH_IMAGE_MOCK"] != nil { await runQuickRm9Mock() }
if ProcessInfo.processInfo.environment["ORCH_FILE_MOCK"] != nil { await runQuickFilesMock() }
if ProcessInfo.processInfo.environment["ORCH_RESTART_MOCK"] != nil { await runQuickClaudeMock() }
if ProcessInfo.processInfo.environment["ORCH_RETRY_MOCK"] != nil { await runQuickMe4Mock() }
if ProcessInfo.processInfo.environment["ORCH_DEPLOY_MOCK"] != nil { await runQuickDeployMock() }
runQuickMe4SelectionTest()
print("OK")
