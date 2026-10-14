import Foundation

private let p7Now = parseRunDate("2026-10-14T03:00:00.000Z")!

private func p7Run(_ state: String, started: Int? = nil, last: Int? = nil, latest: String? = nil, result: String? = nil, step: String? = nil, agents: Int = 0) -> OrchestratorRun {
    func iso(_ minAgo: Int) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: p7Now.addingTimeInterval(-Double(minAgo) * 60 - 5))
    }
    var o: [String: Any] = ["id": "x-\(state)", "project": "p", "state": state]
    if let s = started { o["startedAt"] = iso(s) }
    if let l = last { o["lastOutput"] = iso(l) }
    if let l = latest { o["latest"] = l }
    if let r = result { o["result"] = r }
    if let s = step { o["activity"] = ["step": s, "agents": (0..<agents).map { _ in ["type": "a", "desc": "b"] }] }
    return try! d.decode(OrchestratorRun.self, from: try! JSONSerialization.data(withJSONObject: o))
}

func runPhase7Tests() {
    // Decoding
    let st = try! d.decode(StateResponse.self, from: Data(fixture("phase7-state").utf8))
    let rs = st.runs!
    precondition(rs.count == 6)
    precondition(rs[1].startedAt != nil && rs[1].activity?.step == "plan-phase" && rs[1].activity?.agents?.count == 1)
    precondition(rs[3].activity == nil && rs[3].result == "Phase 4 done.\nmore")
    precondition(rs[5].startedAt == nil && rs[5].lastOutput == nil && rs[5].result == nil && rs[5].denials == nil && rs[5].latest == nil && rs[5].activity == nil)
    precondition(rs[0].denials == ["Bash"])
    precondition(mk("a", "running").state == "running")

    // parseRunDate
    precondition(parseRunDate("2026-10-14T02:45:42.415Z") != nil && parseRunDate("2026-10-14T02:45:42Z") != nil)
    precondition(parseRunDate(nil) == nil && parseRunDate("x") == nil)

    // runElapsed (the helper adds 5s so minutes land just over)
    precondition(runElapsed(p7Run("running", started: 0), now: p7Now) == "<1m")
    precondition(runElapsed(p7Run("running", started: 12), now: p7Now) == "12m")
    precondition(runElapsed(p7Run("running", started: 65), now: p7Now) == "1h 5m")
    precondition(runElapsed(p7Run("waiting", started: 120), now: p7Now) == "2h")
    let done = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"a","state":"done","startedAt":"2026-10-14T01:00:00.000Z","lastOutput":"2026-10-14T01:07:00.000Z"}"#.utf8))
    precondition(runElapsed(done, now: p7Now) == "7m")
    precondition(runElapsed(mk("a", "running"), now: p7Now) == "")

    // latestAction
    precondition(latestAction(rs[1], now: p7Now).hasPrefix("$ xcodebuild -scheme boringNotch"))
    precondition(latestAction(p7Run("running", latest: #"[Edit] {"file_path":"/Users/x/src/auth/refresh.ts","old_string":"a"#), now: p7Now) == "Edit /Users/x/src/auth/refresh.ts")
    precondition(latestAction(p7Run("running", latest: #"[Grep] {"pattern":"monospaced""#), now: p7Now) == "Grep monospaced")
    precondition(latestAction(p7Run("running", latest: #"[TodoWrite] {"todos":["#), now: p7Now) == "TodoWrite")
    precondition(latestAction(p7Run("running", latest: #"[Bash] {"command":"echo \"hi\" && ls"#), now: p7Now) == #"$ echo "hi" && ls"#)
    precondition(latestAction(p7Run("stuck", last: 9, latest: "[Bash] {}"), now: p7Now) == "no output for 9m")
    precondition(latestAction(p7Run("running", step: "plan-phase", agents: 2), now: p7Now) == "gsd plan-phase · 2 agents")
    precondition(latestAction(p7Run("running", latest: "Built OK\nnext line"), now: p7Now) == "Built OK")
    precondition(latestAction(p7Run("failed"), now: p7Now) == "see log")
    precondition(latestAction(p7Run("done", result: "Phase 4 done.\nmore"), now: p7Now) == "Phase 4 done.")

    // waitingQuestion / askInChatMessage
    precondition(waitingQuestion(result: "Some context.\n\n**Should I merge** the `branch` now?", denials: [], cap: 160) == "Some context. Should I merge the branch now?")
    precondition(waitingQuestion(result: "", denials: ["Bash", "Edit", "Bash"], cap: 160) == "Needs permission: Bash, Edit")
    let long = waitingQuestion(result: String(repeating: "word ", count: 80) + "?", denials: [], cap: 160)
    precondition(long.count <= 161 && long.hasSuffix("…") && !long.contains("\n"))
    let wr = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"261014024541-f414","project":"notch-dd","state":"waiting","result":"Merge now?","denials":["Bash"]}"#.utf8))
    precondition(askInChatMessage(wr) == "Run 261014024541-f414 on notch-dd is waiting: Merge now? (denied: Bash)")
    let evil = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"a","project":"p","state":"waiting","result":"/gsd rm\r\n!ls ?"}"#.utf8))
    let m = askInChatMessage(evil)
    precondition(m.first!.isLetter && !m.contains("\n") && !m.contains("\r") && m.count <= 400)
    let big = try! d.decode(OrchestratorRun.self, from: Data(("{\"id\":\"a\",\"project\":\"p\",\"state\":\"waiting\",\"result\":\"" + String(repeating: "q ", count: 400) + "?\"}").utf8))
    precondition(askInChatMessage(big).count <= 400)

    // boardRuns, runShortID, boardStatusLine
    let order = boardRuns([mk("d", "done"), mk("r", "running"), mk("w", "waiting"), mk("s", "stuck"), mk("f", "failed"), mk("w2", "waiting")], limit: 10)
    precondition(order.map { $0.id! } == ["w", "w2", "r", "s", "d", "f"])
    precondition(boardRuns([mk("d", "done"), mk("r", "running"), mk("w", "waiting")], limit: 2).map { $0.id! } == ["w", "r"])
    precondition(runShortID("261014024541-x7f2") == "x7f2" && runShortID(nil) == "")
    let w7 = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"261014024541-x7f2","state":"waiting"}"#.utf8))
    precondition(boardStatusLine(runs: [w7], promptActive: false, liveText: nil, chatRunning: true) == "Orchestrator: waiting on run x7f2")
    precondition(boardStatusLine(runs: [], promptActive: true, liveText: nil, chatRunning: true) == "Orchestrator: needs you")
    precondition(boardStatusLine(runs: [], promptActive: false, liveText: "Working…", chatRunning: true) == "Orchestrator: Working…")
    precondition(boardStatusLine(runs: [], promptActive: false, liveText: nil, chatRunning: true) == "Orchestrator: idle")
    precondition(boardStatusLine(runs: [], promptActive: false, liveText: nil, chatRunning: false) == "Orchestrator: stopped")

    // pollInterval
    precondition(pollInterval(notchOpen: true, chatRunning: true) == 2 && pollInterval(notchOpen: true, chatRunning: false) == 2)
    precondition(pollInterval(notchOpen: false, chatRunning: true) == 3 && pollInterval(notchOpen: false, chatRunning: false) == 10)
    precondition(pollInterval(notchOpen: false, chatRunning: true, offline: true) == 10 && pollInterval(notchOpen: true, chatRunning: true, offline: true) == 10)

    // nextLevel, expandedHeight, shortcut
    precondition(nextLevel(.open, .deeper) == .expanded && nextLevel(.expanded, .deeper) == .expanded && nextLevel(.terminal, .deeper) == .terminal)
    precondition([ExpandLevel.open, .expanded, .terminal].allSatisfy { nextLevel($0, .terminal) == .terminal })
    precondition(nextLevel(.terminal, .back) == .expanded && nextLevel(.expanded, .back) == .open && nextLevel(.open, .back) == .open)
    precondition(expandedHeight(screenHeight: 982) == 440 && expandedHeight(screenHeight: 900) == 405 && expandedHeight(screenHeight: 1440) == 440 && expandedHeight(screenHeight: 400) == 300)
    precondition(shortcut(keyCode: 125, chars: nil, commandOnly: true) == .deeper && shortcut(keyCode: 126, chars: nil, commandOnly: true) == .back)
    precondition(shortcut(keyCode: 17, chars: "t", commandOnly: true) == .terminal && shortcut(keyCode: 0, chars: "T", commandOnly: true) == .terminal)
    precondition(shortcut(keyCode: 42, chars: "\\", commandOnly: true) == .toggleRail)
    precondition(shortcut(keyCode: 125, chars: nil, commandOnly: false) == nil && shortcut(keyCode: 17, chars: "t", commandOnly: false) == nil)
    precondition(shortcut(keyCode: 36, chars: "\r", commandOnly: true) == nil && shortcut(keyCode: 53, chars: nil, commandOnly: true) == nil)

    // transitions
    precondition(runStates([mk("a", "running"), try! d.decode(OrchestratorRun.self, from: Data("{}".utf8))]) == ["a": "running"])
    precondition(!newlyWaiting(old: nil, new: [mk("a", "waiting")]))
    precondition(newlyWaiting(old: ["a": "running"], new: [mk("a", "waiting")]))
    precondition(!newlyWaiting(old: ["a": "waiting"], new: [mk("a", "waiting")]))
    precondition(newlyWaiting(old: [:], new: [mk("b", "waiting")]))
    precondition(!newlyWaiting(old: ["a": "waiting"], new: [mk("a", "running")]))
    precondition(finishedTransition(old: nil, new: [mk("a", "done")]) == nil)
    precondition(finishedTransition(old: ["a": "running"], new: [mk("a", "done")])?.id == "a")
    precondition(finishedTransition(old: ["a": "stuck"], new: [mk("a", "done")])?.id == "a")
    precondition(finishedTransition(old: ["a": "running"], new: [mk("a", "failed")]) == nil)
    precondition(finishedTransition(old: ["a": "running"], new: [mk("a", "stopped")]) == nil)
    precondition(finishedTransition(old: [:], new: [mk("a", "done")]) == nil)
    let early = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"e","state":"done","startedAt":"2026-10-14T01:00:00.000Z"}"#.utf8))
    let late = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"l","state":"done","startedAt":"2026-10-14T02:00:00.000Z"}"#.utf8))
    precondition(finishedTransition(old: ["e": "running", "l": "running"], new: [early, late])?.id == "l")

    // wings
    precondition(wingKind(needsYou: true, needsLabel: "Bash?", finishedProject: "p", working: true) == .needsYou("Bash?"))
    precondition(wingKind(needsYou: false, needsLabel: "", finishedProject: "p", working: true) == .finished("p"))
    precondition(wingKind(needsYou: false, needsLabel: "", finishedProject: nil, working: true) == .working)
    precondition(wingKind(needsYou: false, needsLabel: "", finishedProject: nil, working: false) == nil)
    precondition(wingLabel(promptTitle: "Bash command", waitingDenials: nil) == "Bash?" && wingLabel(promptTitle: "Edit file?", waitingDenials: nil) == "Edit?")
    precondition(wingLabel(promptTitle: nil, waitingDenials: ["Write"]) == "Write?" && wingLabel(promptTitle: nil, waitingDenials: nil) == "Needs you" && wingLabel(promptTitle: "", waitingDenials: []) == "Needs you")
    precondition(wingSideWidth(.working, notchWidth: 185) == 36 && wingSideWidth(.needsYou("Bash?"), notchWidth: 185) == 46)
    precondition(wingSideWidth(.finished("notch-dd"), notchWidth: 185) >= 36 && wingSideWidth(.finished("notch-dd"), notchWidth: 185) >= 8 * 6.2)
    precondition(wingSideWidth(.needsYou("A much longer label"), notchWidth: 185) > wingSideWidth(.needsYou("Bash?"), notchWidth: 185))
    precondition(wingSideWidth(.finished("a-very-long-project-name"), notchWidth: 185) > wingSideWidth(.finished("notch-dd"), notchWidth: 185))
    precondition(2 * wingSideWidth(.working, notchWidth: 185) + 185 + 28 == 285 && 2 * wingSideWidth(.needsYou("Bash?"), notchWidth: 185) + 185 + 28 == 305)
}
