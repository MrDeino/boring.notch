import Foundation

/// serve's "unknown" deploy state (in progress > 20 min): decoded with its note, kept apart from building,
/// shown in the wing and rows with the note; any other unrecognised state drops only that entry.
func runQuickUnknownDeployTests() {
    let t0 = parseRunDate("2026-11-18T03:00:00.000Z")!
    func iso(_ s: TimeInterval) -> String { ISO8601DateFormatter().string(from: t0.addingTimeInterval(s)) }
    func dep(_ project: String, _ state: String, note: String? = nil, start: TimeInterval = 0, sha: String = "abc1234") -> String {
        #"{"project":"\#(project)","state":"\#(state)","sha":"\#(sha)","pr":{"number":7,"title":"t"},"startedAt":"\#(iso(start))","finishedAt":null\#(note.map { #","note":"\#($0)""# } ?? "")}"#
    }
    func list(_ entries: [String]) -> [Deploy] {
        try! JSONDecoder().decode(StateResponse.self, from: Data(#"{"deploys":[\#(entries.joined(separator: ","))]}"#.utf8)).deploys!
    }

    // Decode: unknown kept with its note; a new unrecognised state drops only its own entry (state and SSE list).
    let l = list([dep("app", "unknown", note: "unknown, check Railway"), dep("web", "paused"), dep("api", "building")])
    precondition(l.map(\.state) == ["unknown", "building"] && l[0].note == "unknown, check Railway" && l[1].note == nil)
    var p = SSELineParser()
    _ = p.feed("event: deploy")
    if case .deploys(let s)? = p.feed("data: [" + dep("app", "unknown", note: "n") + "," + dep("web", "paused") + "]") {
        precondition(s.count == 1 && s[0].state == "unknown")
    } else { preconditionFailure("one odd state must not drop the SSE list") }

    // Row text and ordering: unknown shows the note (fallback when blank), is listed like an open deploy and timed to now.
    precondition(deployStateText(l[0]) == "unknown, check Railway")
    precondition(deployStateText(list([dep("app", "unknown", note: "  ")])[0]) == "unknown, check Railway")
    precondition(deployStateText(list([dep("app", "unknown")])[0]) == "unknown, check Railway")
    precondition(deployStateText(l[1]) == "deploying…")
    precondition(deployRows(l, now: t0.addingTimeInterval(1500)).count == 2)
    precondition(deployElapsed(l[0], now: t0.addingTimeInterval(1500)) == 1500)

    // Wing: building -> unknown is not a live flash and not "deploying"; it shows the note; building still wins; live after it flashes.
    var w = DeployWings()
    _ = w.ingest(list([dep("app", "building")]), offline: false, loaded: true)
    precondition(w.kind == .deploying("app · #7"))
    precondition(!w.ingest(list([dep("app", "unknown", note: "unknown, check Railway")]), offline: false, loaded: true))
    precondition(w.kind == .deployUnknown("app · #7", note: "unknown, check Railway") && w.buildingStart == nil)
    _ = w.ingest(list([dep("app", "unknown", note: "n"), dep("api", "building", start: 60, sha: "def")]), offline: false, loaded: true)
    precondition(w.kind == .deploying("api · #7"))
    precondition(w.ingest(list([dep("app", "live")]), offline: false, loaded: true) && w.kind == .deployed("app · #7", failed: false))
    // Offline clears it like the others.
    _ = w.ingest(list([dep("app", "unknown")]), offline: true, loaded: true)
    precondition(w.kind == nil)
}
