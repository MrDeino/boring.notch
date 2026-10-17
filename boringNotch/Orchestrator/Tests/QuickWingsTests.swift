import Foundation

/// Synthetic runs going running -> done: the working count clears and each finished wing shows exactly once.
func runQuickWingsTests() {
    func run(_ id: String, _ state: String, _ project: String) -> OrchestratorRun {
        try! JSONDecoder().decode(OrchestratorRun.self, from: Data(#"{"id":"\#(id)","project":"\#(project)","state":"\#(state)"}"#.utf8))
    }
    func working(_ runs: [OrchestratorRun]) -> Int { workingCount(chatWorking: false, runs: runs) }
    func kind(_ w: FinishedWings, _ runs: [OrchestratorRun]) -> WingKind? {
        wingKind(needsYou: false, needsLabel: "", finished: w.current, workingCount: working(runs))
    }

    var w = FinishedWings()
    var runs = [run("a", "running", "alpha")]
    precondition(!w.ingest(runs, offline: false, loaded: true))
    precondition(kind(w, runs) == .working(1))

    // One run finishes: its wing starts, then the wing clears.
    runs = [run("a", "done", "alpha")]
    precondition(w.ingest(runs, offline: false, loaded: true))
    precondition(kind(w, runs) == .finished("alpha", failed: false))
    precondition(!w.ingest(runs, offline: false, loaded: true)) // a repeat poll shows nothing new
    precondition(!w.expire() && kind(w, runs) == nil)

    // Three finish together (one failed) while a fourth keeps running: one wing each, in turn, then only the fourth.
    runs = [run("a", "done", "alpha"), run("b", "running", "beta"), run("c", "running", "gamma"), run("d", "running", "delta"), run("e", "running", "eps")]
    precondition(!w.ingest(runs, offline: false, loaded: true) && kind(w, runs) == .working(4))
    runs = [run("a", "done", "alpha"), run("b", "done", "beta"), run("c", "failed", "gamma"), run("d", "done", "delta"), run("e", "running", "eps")]
    precondition(w.ingest(runs, offline: false, loaded: true))
    var shown: [WingKind?] = [kind(w, runs)]
    while w.expire() { shown.append(kind(w, runs)) }
    precondition(shown.count == 3 && Set(shown.map { "\($0 as Any)" }).count == 3)
    precondition(kind(w, runs) == .working(1))
    precondition(!w.ingest(runs, offline: false, loaded: true) && kind(w, runs) == .working(1))
}
