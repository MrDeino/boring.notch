import Foundation

func runPhase4Tests() {
    func ls(_ s: String) -> LiveStatus? { parseLiveStatus(screen: s) }
    precondition(ls("✻ Working… (41s · ↑ 1.2k tokens · esc to interrupt)") == LiveStatus(text: "Working…", elapsed: 41, tokens: "↑ 1.2k tokens"))
    precondition(ls("✢ Pondering… (1m 52s · esc to interrupt)")?.elapsed == 112)
    precondition(ls("✶ Cogitating… (1h 2m · esc to interrupt)")?.elapsed == 3720)
    precondition(ls("✻ Thinking… (esc to interrupt)") == LiveStatus(text: "Thinking…", elapsed: nil))
    precondition(ls("✻ Sautéed for 22s · done 12:48 pm · 1 monitor still running") == nil)
    precondition(ls("> (esc to interrupt)") == nil)
    precondition(ls(fixture("working")) == LiveStatus(text: "Working…", elapsed: 12, tokens: "↑ 1.2k tokens"))
    precondition(ls(fixture("permission")) == nil && ls(fixture("inputbox")) == nil)

    precondition(formatElapsed(0) == "0:00" && formatElapsed(41) == "0:41")
    precondition(formatElapsed(112) == "1:52" && formatElapsed(3720) == "1:02:00")

    precondition(capsuleState(hasLoaded: false, offline: true, chatRunning: true, needsAttention: true, working: true) == .connecting)
    precondition(capsuleState(hasLoaded: true, offline: true, chatRunning: true, needsAttention: true, working: true) == .offline)
    precondition(capsuleState(hasLoaded: true, offline: false, chatRunning: false, needsAttention: true, working: true) == .stopped)
    precondition(capsuleState(hasLoaded: true, offline: false, chatRunning: true, needsAttention: true, working: true) == .needsYou)
    precondition(capsuleState(hasLoaded: true, offline: false, chatRunning: true, needsAttention: false, working: true) == .running)
    precondition(capsuleState(hasLoaded: true, offline: false, chatRunning: true, needsAttention: false, working: false) == .idle)

    let d = JSONDecoder()
    func run(_ s: String?) -> OrchestratorRun {
        try! d.decode(OrchestratorRun.self, from: Data((s.map { #"{"state":"\#($0)"}"# } ?? "{}").utf8))
    }
    precondition(liveRunCount([run("running"), run("waiting"), run("stuck"), run("done"), run("failed"), run(nil)]) == 3)

    func u(_ f: Double?) -> OrchestratorUsage {
        let w = f.map { #"{"used_percentage":\#($0)}"# } ?? "null"
        return try! d.decode(OrchestratorUsage.self, from: Data(#"{"five_hour":\#(w),"seven_day":{"used_percentage":90}}"#.utf8))
    }
    precondition(fiveHourFraction(nil) == nil && fiveHourFraction(u(nil)) == nil)
    precondition(fiveHourFraction(u(40)) == 0.4 && fiveHourFraction(u(130)) == 1.0 && fiveHourFraction(u(-5)) == 0.0)
    precondition(!usageIsHigh(79.9) && usageIsHigh(80) && !usageIsHigh(nil))

    precondition(pollInterval(notchOpen: true, chatRunning: false) == 2)
    precondition(pollInterval(notchOpen: false, chatRunning: false) == 10)
    precondition(pollInterval(notchOpen: true, chatRunning: false, offline: true) == 10)
    precondition(pollInterval(notchOpen: false, chatRunning: false, offline: true) == 10)

    let b = URL(string: "http://127.0.0.1:4799")!
    let cu = OrchestratorPost.key("C-u").request(base: b)!
    precondition((try! d.decode([String: String].self, from: cu.httpBody!)) == ["key": "C-u"])
    precondition(OrchestratorPost.key("C-x").request(base: b) == nil)

    let q = detectPromptCard(screen: fixture("question"))!
    precondition(q.kind == .question && q.options == detectPrompt(screen: fixture("question")))
    let p = detectPromptCard(screen: fixture("permission"))!
    precondition(p.kind == .permission && p.options == detectPrompt(screen: fixture("permission")))
    precondition(detectPromptCard(screen: fixture("inputbox")) == nil)
}
