import Foundation

/// Synthetic fixture only (Tests/fixtures/bg-agents.json): running/done/failed agents, running/ended monitors.
func runQuickBgTests() {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/bg-agents.json")
    let data = try! Data(contentsOf: url)
    let l = decodeBgTasks(data)!
    let ids: [String] = l.map(\.id)
    let statuses: [String] = l.map { $0.status ?? "" }
    precondition(ids == ["a1", "a2", "a3", "m1", "m2"])
    precondition(statuses == ["running", "done", "failed", "running", "stopped"])
    precondition(l[3].isMonitor)
    precondition(!l[0].isMonitor)
    precondition(bgRunningCount(l) == 2)
    let sortedIDs: [String] = bgSorted(l).map(\.id)
    precondition(sortedIDs == ["a1", "m1", "a2", "a3", "m2"], "running first")
    precondition(l[1].report?.hasPrefix("**Release notes**") == true)
    precondition(l[1].tokens == 18400)
    precondition(l[1].toolUses == 7)

    // Elapsed: running counts to now, finished to endedAt.
    let now = parseRunDate("2026-10-22T04:01:00Z")!
    precondition(bgElapsed(l[0], now: now) == 60)
    precondition(bgElapsed(l[1], now: now) == 130)
    precondition(bgElapsed(BgTask(id: "x"), now: now) == nil)
    // Last steps: the tail; lastStep stands in when there are no steps; nothing otherwise.
    let many = BgTask(id: "s", steps: (1...9).map { BgStep(at: nil, tool: "T", summary: "\($0)") })
    let tail: [String] = bgRecentSteps(many).map { $0.summary ?? "" }
    precondition(tail == ["5", "6", "7", "8", "9"])
    let only: [String] = bgRecentSteps(BgTask(id: "s", lastStep: "only")).map { $0.summary ?? "" }
    precondition(only == ["only"])
    precondition(bgRecentSteps(l[4]).isEmpty)
    precondition(bgTitle(BgTask(id: "s", kind: "monitor")) == "Monitor")
    precondition(bgTitle(l[0]) == "Survey the widget modules")

    // Lenient: wrong types become nil, no id drops the entry, a wrapped list and epoch ms work, junk is nil (list untouched).
    let odd = decodeBgTasks(Data(#"{"agents":[{"id":7,"description":5,"status":"running","startedAt":1791950000000,"steps":[{"tool":1},"x",{"summary":"ok","at":1791950001}],"tokens":"many"},{"description":"no id"},{"id":"k","kind":"weird"}]}"#.utf8))!
    let oddIDs: [String] = odd.map(\.id)
    precondition(oddIDs == ["7", "k"])
    precondition(odd[0].description == nil)
    precondition(odd[0].tokens == nil)
    precondition(odd[0].kind == "agent")
    precondition(odd[0].startedAt == Date(timeIntervalSince1970: 1791950000))
    precondition(odd[0].steps.count == 2)
    precondition(odd[0].steps[1].at == Date(timeIntervalSince1970: 1791950001))
    precondition(decodeBgTasks(Data("[]".utf8))!.isEmpty)
    precondition(decodeBgTasks(Data(#"{"x":1}"#.utf8)) == nil)
    precondition(decodeBgTasks(Data("nope".utf8)) == nil)

    // SSE: `agents` replaces, `agent` upserts by id; a bad payload is dropped.
    var p = SSELineParser()
    precondition(p.feed("event: agents") == nil)
    guard case .background(let got)? = p.feed("data: " + String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\n", with: "")) else { preconditionFailure("agents event") }
    precondition(got == l)
    _ = p.feed("event: agent")
    guard case .backgroundOne(let one)? = p.feed(#"data: {"id":"a1","status":"done","endedAt":"2026-10-22T04:02:00Z"}"#) else { preconditionFailure("agent event") }
    let merged = bgUpserting(l, one)
    precondition(merged.count == 5)
    precondition(merged[0].status == "done")
    precondition(bgRunningCount(merged) == 1)
    _ = p.feed("event: agents")
    precondition(p.feed("data: 12") == nil)
}
