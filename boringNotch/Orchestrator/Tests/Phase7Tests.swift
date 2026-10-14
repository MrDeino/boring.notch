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
    let odd = try! d.decode(StateResponse.self, from: Data(#"{"runs":[{"id":"a","state":"waiting","denials":["Bash",null],"activity":{"agents":[1]},"startedAt":5},{"id":"b","state":"running"}]}"#.utf8))
    precondition(odd.runs!.count == 2 && odd.runs![0].denials == ["Bash"] && odd.runs![0].activity == nil && odd.runs![0].startedAt == nil && odd.runs![0].state == "waiting")

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

    // nextLevel, expandedSize, shortcut
    precondition(nextLevel(.open, .deeper) == .expanded && nextLevel(.expanded, .deeper) == .expanded && nextLevel(.terminal, .deeper) == .terminal)
    precondition([ExpandLevel.open, .expanded, .terminal].allSatisfy { nextLevel($0, .terminal) == .terminal })
    precondition(nextLevel(.terminal, .back) == .expanded && nextLevel(.expanded, .back) == .open && nextLevel(.open, .back) == .open)
    precondition(expandedSize(screen: CGSize(width: 1440, height: 900)) == CGSize(width: 850, height: 540))
    precondition(expandedSize(screen: CGSize(width: 1512, height: 982)) == CGSize(width: 850, height: 589))
    precondition(expandedSize(screen: CGSize(width: 1024, height: 600)) == CGSize(width: 850, height: 520))
    precondition(expandedSize(screen: CGSize(width: 800, height: 500)) == CGSize(width: 720, height: 460))
    precondition(expandedSize(screen: CGSize(width: 600, height: 500)).width == 640)
    precondition(shortcut(keyCode: 125, chars: nil, commandOnly: true) == .deeper && shortcut(keyCode: 126, chars: nil, commandOnly: true) == .back)
    precondition(shortcut(keyCode: 17, chars: "t", commandOnly: true) == .terminal && shortcut(keyCode: 0, chars: "T", commandOnly: true) == .terminal)
    precondition(shortcut(keyCode: 42, chars: "\\", commandOnly: true) == .toggleRail)
    precondition(shortcut(keyCode: 125, chars: nil, commandOnly: false) == nil && shortcut(keyCode: 17, chars: "t", commandOnly: false) == nil)
    precondition(shortcut(keyCode: 36, chars: "\r", commandOnly: true) == nil && shortcut(keyCode: 53, chars: nil, commandOnly: true) == nil)

    // isCommandOnly: ⌘↓ carries numericPad (1<<21) and function (1<<23); caps lock (1<<16) is ignored
    precondition(isCommandOnly(1 << 20 | 1 << 21 | 1 << 23) && isCommandOnly(1 << 20 | 1 << 16) && isCommandOnly(1 << 20))
    precondition(!isCommandOnly(1 << 20 | 1 << 17) && !isCommandOnly(1 << 20 | 1 << 19) && !isCommandOnly(1 << 18 | 1 << 20) && !isCommandOnly(1 << 21))

    // transitions
    precondition(runStates([mk("a", "running"), try! d.decode(OrchestratorRun.self, from: Data("{}".utf8))]) == ["a": "running"])
    precondition(!newlyWaiting(old: nil, new: [mk("a", "waiting")]))
    precondition(newlyWaiting(old: ["a": "running"], new: [mk("a", "waiting")]))
    precondition(!newlyWaiting(old: ["a": "waiting"], new: [mk("a", "waiting")]))
    precondition(newlyWaiting(old: [:], new: [mk("b", "waiting")]))
    precondition(!newlyWaiting(old: ["a": "waiting"], new: [mk("a", "running")]))
    precondition(finishedTransitions(old: nil, new: [mk("a", "done")]).isEmpty)
    precondition(finishedTransitions(old: ["a": "running"], new: [mk("a", "done")]).map(\.id) == ["a"])
    precondition(finishedTransitions(old: ["a": "stuck"], new: [mk("a", "done")]).map(\.id) == ["a"])
    precondition(finishedTransitions(old: ["a": "running"], new: [mk("a", "failed")]).map(\.state) == ["failed"])
    precondition(finishedTransitions(old: ["a": "running"], new: [mk("a", "stopped")]).isEmpty)
    precondition(finishedTransitions(old: ["a": "done"], new: [mk("a", "done")]).isEmpty)
    precondition(finishedTransitions(old: [:], new: [mk("a", "done")]).isEmpty)
    let early = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"e","state":"done","startedAt":"2026-10-14T01:00:00.000Z"}"#.utf8))
    let late = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"l","state":"done","startedAt":"2026-10-14T02:00:00.000Z"}"#.utf8))
    precondition(finishedTransitions(old: ["e": "running", "l": "running"], new: [late, early]).map(\.id) == ["e", "l"])

    // RunsBaseline (WR-01): launch, offline blip, reconnect with an already-waiting run
    var b = RunsBaseline()
    let wa = [mk("a", "waiting")]
    precondition(b.advance([], offline: false, loaded: false) == nil)
    precondition(b.advance(wa, offline: false, loaded: false) == nil)
    precondition(!newlyWaiting(old: b.advance(wa, offline: false, loaded: true), new: wa))
    precondition(b.advance([], offline: true, loaded: true) == nil)
    precondition(b.advance([], offline: false, loaded: true) == nil)
    precondition(!newlyWaiting(old: b.advance(wa, offline: false, loaded: true), new: wa))
    precondition(newlyWaiting(old: b.advance(wa + [mk("c", "waiting")], offline: false, loaded: true), new: wa + [mk("c", "waiting")]))
    precondition(b.advance([], offline: false, loaded: true) == ["a": "waiting", "c": "waiting"]) // emptied while online is a real baseline
    precondition(newlyWaiting(old: b.advance(wa, offline: false, loaded: true), new: wa))

    // wings
    precondition(wingKind(needsYou: true, needsLabel: "Bash?", finished: ("p", false), workingCount: 1) == .needsYou("Bash?"))
    precondition(wingKind(needsYou: false, needsLabel: "", finished: ("p", true), workingCount: 2) == .finished("p", failed: true))
    precondition(wingKind(needsYou: false, needsLabel: "", finished: nil, workingCount: 3) == .working(3))
    precondition(wingKind(needsYou: false, needsLabel: "", finished: nil, workingCount: 0) == nil)
    let now = parseRunDate("2026-10-14T03:00:00.000Z")!
    let r1 = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"r1","state":"running","startedAt":"2026-10-14T02:00:00.000Z"}"#.utf8))
    let r2 = try! d.decode(OrchestratorRun.self, from: Data(#"{"id":"r2","state":"running","startedAt":"2026-10-14T02:59:00.000Z"}"#.utf8))
    let notRunning = [mk("w", "waiting"), mk("s", "stuck"), early]
    precondition(workingCount(chatWorking: true, runs: [r1, r2] + notRunning) == 3 && workingCount(chatWorking: false, runs: notRunning) == 0)
    precondition(longestWorking(chatElapsed: 41, runs: [r1, r2] + notRunning, now: now) == 3600)
    precondition(longestWorking(chatElapsed: 7200, runs: [r2], now: now) == 7200 && longestWorking(chatElapsed: nil, runs: [r2], now: now) == 60)
    precondition(longestWorking(chatElapsed: nil, runs: notRunning, now: now) == nil)
    precondition(wingLabel(promptTitle: "Bash command", waitingDenials: nil) == "Bash?" && wingLabel(promptTitle: "Edit file?", waitingDenials: nil) == "Edit?")
    precondition(wingLabel(promptTitle: nil, waitingDenials: ["Write"]) == "Write?" && wingLabel(promptTitle: nil, waitingDenials: nil) == "Needs you" && wingLabel(promptTitle: "", waitingDenials: []) == "Needs you")
    precondition(wingShift(left: 23, right: 35) == 6 && wingShift(left: 16, right: 56) == 20 && wingShift(left: 30, right: 30) == 0)
    precondition(wingShift(left: 40, right: 20) == -10 && wingShift(left: 20, right: 25) == 3)
}
