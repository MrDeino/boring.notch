import Foundation

private let t0 = parseRunDate("2026-10-17T03:00:00.000Z")!
private func iso(_ s: TimeInterval) -> String { ISO8601DateFormatter().string(from: t0.addingTimeInterval(s)) }

private func dep(_ project: String, _ state: String, pr: Int? = 231, sha: String = "abc1234", start: TimeInterval = 0, end: TimeInterval? = nil) -> String {
    let prJSON = pr.map { #"{"number":\#($0),"title":"Tidy the widgets"}"# } ?? "null"
    return #"{"project":"\#(project)","state":"\#(state)","sha":"\#(sha)","pr":\#(prJSON),"startedAt":"\#(iso(start))","finishedAt":\#(end.map { "\"\(iso($0))\"" } ?? "null"),"url":"https://example.test/\#(project)"}"#
}
private func state(_ deploys: String?) -> StateResponse {
    try! JSONDecoder().decode(StateResponse.self, from: Data(#"{"runs":[]\#(deploys.map { ",\"deploys\":[\($0)]" } ?? "")}"#.utf8))
}
private func ds(_ s: StateResponse) -> [Deploy] { s.deploys ?? [] }

/// Deploys: decode (old serve, odd entries), building -> live -> wing, failed sticky, priority, rows.
func runQuickDeployTests() {
    // Decode: optional, lenient.
    precondition(state(nil).deploys == nil)
    let d = ds(state(dep("gg-app", "building") + "," + dep("odd", "weird") + #",{"project":7}"# + "," + dep("solo", "live", pr: nil, end: 5)))
    precondition(d.count == 2 && d[0].pr == Deploy.PR(number: 231, title: "Tidy the widgets") && d[1].pr == nil && d[0].finishedAt == nil)
    precondition(try! JSONDecoder().decode(StateResponse.self, from: Data(#"{"deploys":"nope"}"#.utf8)).deploys == nil)
    precondition(deployLabel(d[0]) == "gg-app · #231" && deployLabel(d[1]) == "solo")

    // SSE `deploy`: a list, a wrapped list, one deploy.
    var p = SSELineParser()
    func ev(_ json: String) -> OrchestratorStreamEvent? { _ = p.feed("event: deploy"); return p.feed("data: " + json) }
    if case .deploys(let l)? = ev("[" + dep("a", "live") + "]") { precondition(l.count == 1) } else { preconditionFailure() }
    if case .deploys(let l)? = ev(#"{"deploys":["# + dep("a", "live") + "," + dep("b", "failed") + "]}") { precondition(l.count == 2) } else { preconditionFailure() }
    if case .deploy(let x)? = ev(dep("a", "building")) { precondition(x.state == "building") } else { preconditionFailure() }

    func kind(_ w: DeployWings) -> WingKind? { w.kind }

    // Already live at the first load: nothing. Building: deploying wing; turns live: 6s flash, then nothing.
    var w = DeployWings()
    precondition(!w.ingest(ds(state(dep("gg-app", "live", sha: "old", end: -60))), offline: false, loaded: true) && kind(w) == nil)
    precondition(!w.ingest(ds(state(dep("gg-app", "building", start: 10))), offline: false, loaded: true))
    precondition(kind(w) == .deploying("gg-app · #231") && w.buildingStart == t0.addingTimeInterval(10))
    precondition(!w.ingest(ds(state(dep("gg-app", "building", start: 10))), offline: false, loaded: true)) // a repeat poll
    precondition(w.ingest(ds(state(dep("gg-app", "live", start: 10, end: 70))), offline: false, loaded: true))
    precondition(kind(w) == .deployed("gg-app · #231", failed: false) && w.buildingStart == nil)
    let gen = w.flashGen
    w.expire(gen: gen - 1); precondition(kind(w) == .deployed("gg-app · #231", failed: false)) // a stale timer does nothing
    w.expire(gen: gen); precondition(kind(w) == nil)

    // Failed is sticky: expiry and repeat polls leave it; the next deploy clears it; so does a click.
    precondition(!w.ingest(ds(state(dep("gg-app", "building", sha: "b2", start: 100))), offline: false, loaded: true))
    precondition(!w.ingest(ds(state(dep("gg-app", "failed", sha: "b2", start: 100, end: 130))), offline: false, loaded: true))
    precondition(kind(w) == .deployed("gg-app · #231", failed: true))
    w.expire(gen: w.flashGen); _ = w.ingest(ds(state(dep("gg-app", "failed", sha: "b2", start: 100, end: 130))), offline: false, loaded: true)
    precondition(kind(w) == .deployed("gg-app · #231", failed: true))
    precondition(!w.ingest(ds(state(dep("gg-app", "building", sha: "b3", start: 200) + "," + dep("gg-app", "failed", sha: "b2", start: 100, end: 130))), offline: false, loaded: true))
    precondition(kind(w) == .deploying("gg-app · #231"))
    precondition(!w.ingest(ds(state(dep("gg-app", "failed", sha: "b3", start: 200, end: 230))), offline: false, loaded: true)) // failed: no 6s timer
    precondition(kind(w) == .deployed("gg-app · #231", failed: true))
    w.dismissFailed(); precondition(kind(w) == nil) // a click / opening the notch
    precondition(w.ingest(ds(state(dep("gg-app", "live", sha: "b4", start: 300, end: 330))), offline: false, loaded: true))
    w.dismissFailed(); precondition(kind(w) == .deployed("gg-app · #231", failed: false)) // dismissal only touches a failure
    _ = w.ingest([], offline: true, loaded: true) // offline resets
    precondition(kind(w) == nil)

    // Old serve (no deploys): never anything.
    var old = DeployWings()
    precondition(!old.ingest(ds(state(nil)), offline: false, loaded: true) && kind(old) == nil)

    // Priority: needs-you > finished run > deploy > working.
    let dp = WingKind.deploying("gg-app · #231")
    precondition(wingKind(needsYou: true, needsLabel: "Bash?", finished: nil, workingCount: 2, deploy: dp) == .needsYou("Bash?"))
    precondition(wingKind(needsYou: false, needsLabel: "", finished: ("p", false), workingCount: 2, deploy: dp) == .finished("p", failed: false))
    precondition(wingKind(needsYou: false, needsLabel: "", finished: nil, workingCount: 2, deploy: dp) == dp)
    precondition(wingKind(needsYou: false, needsLabel: "", finished: nil, workingCount: 2) == .working(2))

    // Rows: building first (newest start), then the newest recent finished; stale finished dropped; elapsed.
    let all = ds(state([dep("a", "building", sha: "1", start: 0), dep("b", "building", sha: "2", start: 50), dep("c", "live", sha: "3", end: 900), dep("e", "live", sha: "4", end: -5000)].joined(separator: ",")))
    let now = t0.addingTimeInterval(1000)
    precondition(deployRows(all, now: now).map(\.project) == ["b", "a"])
    precondition(deployRows(all, now: now, limit: 3).map(\.project) == ["b", "a", "c"])
    precondition(deployElapsed(all[0], now: now) == 1000 && deployElapsed(all[2], now: now) == 900)
    precondition(deployURL(all[0])?.host == "example.test")
    precondition(deployURL(ds(state(#"{"project":"x","state":"live","url":"javascript:alert(1)"}"#))[0]) == nil)
}

/// A real HTTP round trip against Tests/deploy-mock.py: building -> live -> wing, failed sticky, then an old serve.
func runQuickDeployMock() async {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    proc.arguments = ["-I", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("deploy-mock.py").path]
    try! proc.run()
    defer { proc.terminate() }
    let b = URL(string: "http://127.0.0.1:47999")!
    let ses = URLSession(configuration: .ephemeral)
    for _ in 0..<50 { if (try? await ses.data(from: b.appendingPathComponent("api/state"))) != nil { break }; try! await Task.sleep(for: .milliseconds(100)) }
    func serve(_ deploys: String?) async -> StateResponse {
        var r = URLRequest(url: b.appendingPathComponent("__set")); r.httpMethod = "POST"
        r.httpBody = Data(#"{"runs":[]\#(deploys.map { ",\"deploys\":[\($0)]" } ?? "")}"#.utf8)
        _ = try! await ses.data(for: r)
        return try! JSONDecoder().decode(StateResponse.self, from: try! await ses.data(from: b.appendingPathComponent("api/state")).0)
    }
    var w = DeployWings()
    func feed(_ s: StateResponse) -> Bool { w.ingest(s.deploys ?? [], offline: false, loaded: true) }
    var started = false
    started = feed(await serve(nil)); precondition(!started && w.kind == nil)
    started = feed(await serve(dep("gg-app", "building", start: 0))); precondition(!started && w.kind == .deploying("gg-app · #231"))
    started = feed(await serve(dep("gg-app", "live", start: 0, end: 90))); precondition(started && w.kind == .deployed("gg-app · #231", failed: false))
    w.expire(gen: w.flashGen); precondition(w.kind == nil)
    started = feed(await serve(dep("gg-app", "building", sha: "z9", start: 200))); precondition(!started)
    started = feed(await serve(dep("gg-app", "failed", sha: "z9", start: 200, end: 240))); precondition(!started && w.kind == .deployed("gg-app · #231", failed: true))
    // An old serve answering (no `deploys`): decodes, the manager keeps its list, nothing new starts.
    let older = await serve(nil)
    precondition(older.deploys == nil && older.runs != nil)
}
