// Phase 7 owns after Phase 4: run elapsed / sorting helpers.
import Foundation
import CoreGraphics

/// Poll cadence in seconds: 2 open, 3 closed while the chat or a run is going, else 10.
func pollInterval(notchOpen: Bool, chatRunning: Bool, offline: Bool = false) -> TimeInterval {
    offline ? 10 : notchOpen ? 2 : chatRunning ? 3 : 10
}

// MARK: - Run card helpers (RUN-01)

private let isoFrac: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
private let isoPlain = ISO8601DateFormatter()

func parseRunDate(_ s: String?) -> Date? {
    guard let s else { return nil }
    return isoFrac.date(from: s) ?? isoPlain.date(from: s)
}

private let finishedStates: Set<String> = ["done", "failed", "stopped"]

private func minutesText(_ secs: TimeInterval) -> String {
    let m = max(0, Int(secs / 60))
    if m < 1 { return "<1m" }
    if m < 60 { return "\(m)m" }
    return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
}

func runElapsed(_ run: OrchestratorRun, now: Date) -> String {
    guard let start = parseRunDate(run.startedAt) else { return "" }
    if finishedStates.contains(run.state ?? "") {
        guard let end = parseRunDate(run.lastOutput) else { return "" }
        return minutesText(end.timeIntervalSince(start))
    }
    return minutesText(now.timeIntervalSince(start))
}

private func firstLine(_ s: String?) -> String? {
    s?.split(separator: "\n").lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
}

private func jsonField(_ key: String, in s: String) -> String? {
    guard let r = s.range(of: "\"\(key)\":\"((?:[^\"\\\\]|\\\\.)*)", options: .regularExpression) else { return nil }
    var v = String(s[r]).dropFirst(key.count + 4)
    v = v.replacingOccurrences(of: "\\n", with: " ").replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")[...]
    return String(v)
}

/// Tool name + its main input field out of a "[Tool] {json" string (JSON may be truncated).
private func toolField(_ tool: String, _ rest: String) -> String? {
    let key: String
    switch tool {
    case "Bash": key = "command"
    case "Edit", "Write", "Read", "MultiEdit", "NotebookEdit": key = "file_path"
    case "Grep", "Glob": key = "pattern"
    case "Task", "Agent": key = "description"
    case "WebFetch": key = "url"
    default: return nil
    }
    return jsonField(key, in: rest)
}

private func parseLatest(_ latest: String?) -> String? {
    guard let l = latest, let line = firstLine(l) else { return nil }
    guard let r = line.range(of: "^\\[(\\w+)\\] ", options: .regularExpression) else { return line }
    let tool = String(line[r].dropFirst().dropLast(2))
    guard ["Bash", "Edit", "Write", "Read", "MultiEdit", "NotebookEdit", "Grep", "Glob"].contains(tool),
          let v = toolField(tool, String(line[r.upperBound...])) else { return tool }
    return tool == "Bash" ? "$ " + v : tool + " " + v
}

/// "[Bash] {json" log line -> chip + summary; nil for prose / RESULT lines.
func logToolLine(_ line: String) -> (tool: String, summary: String)? {
    guard let first = line.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init),
          let r = first.range(of: "^\\[(\\w+)\\] ", options: .regularExpression) else { return nil }
    let tool = String(first[r].dropFirst().dropLast(2))
    return (tool, toolField(tool, String(first[r.upperBound...])) ?? "")
}

func isRunID(_ s: String) -> Bool { s.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil }

/// Dashboard activity line: "step → agent · desc — doing" (page.html).
func runActivityLine(_ a: RunActivity?) -> String? {
    guard let a else { return nil }
    let doing = a.doing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    var s = a.step ?? ""
    for ag in a.agents ?? [] { s += " → " + (ag.type ?? "") + ((ag.desc ?? "").isEmpty ? "" : " · " + ag.desc!) }
    if !doing.isEmpty { s += (s.isEmpty ? "" : " — ") + doing }
    s = s.trimmingCharacters(in: .whitespaces)
    return s.isEmpty ? nil : s
}

// ponytail: regex over serve's truncated "[Tool] {json" string; upgrade = serve sends parsed fields.
func latestAction(_ run: OrchestratorRun, now: Date) -> String {
    let state = run.state ?? ""
    if state == "stuck", let last = parseRunDate(run.lastOutput) { return "no output for \(minutesText(now.timeIntervalSince(last)))" }
    if finishedStates.contains(state) {
        if let r = firstLine(run.result) { return r }
        return parseLatest(run.latest) ?? (state == "failed" ? "see log" : "")
    }
    if let l = parseLatest(run.latest) { return l }
    if let step = run.activity?.step {
        let n = run.activity?.agents?.count ?? 0
        return "gsd " + step + (n > 0 ? " · \(n) agent\(n == 1 ? "" : "s")" : "")
    }
    return ""
}

func waitingQuestion(result: String?, denials: [String], cap: Int) -> String {
    let lines = (result ?? "").split(separator: "\n").compactMap { l -> String? in
        var s = l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("- ") || s.hasPrefix("> ") { s = String(s.dropFirst(2)) }
        return s.isEmpty ? nil : s
    }
    var q = lines.suffix(2).joined(separator: " ").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    if !denials.isEmpty && !q.contains("?") {
        var seen = Set<String>()
        q = "Needs permission: " + denials.filter { seen.insert($0).inserted }.joined(separator: ", ")
    }
    if q.count > cap {
        var cut = String(q.prefix(cap))
        if let sp = cut.lastIndex(of: " ") { cut = String(cut[..<sp]) }
        q = cut + "…"
    }
    return q
}

/// Always starts with "Run" so run text can never begin a slash/bash command in the chat (T-07-01).
func askInChatMessage(_ run: OrchestratorRun) -> String {
    let den = run.denials ?? []
    var m = "Run \(run.id ?? "?") on \(run.project ?? "?") is waiting: " + waitingQuestion(result: run.result, denials: den, cap: 300)
    if !den.isEmpty { m += " (denied: \(den.joined(separator: ", ")))" }
    m = String(m.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
    return String(m.prefix(400))
}

func boardRuns(_ runs: [OrchestratorRun], limit: Int) -> [OrchestratorRun] {
    let w = runs.filter { $0.state == "waiting" }
    let l = runs.filter { $0.state == "running" || $0.state == "stuck" }
    let rest = runs.filter { !["waiting", "running", "stuck"].contains($0.state ?? "") }
    return Array((w + l + rest).prefix(limit))
}

func runShortID(_ id: String?) -> String {
    guard let id else { return "" }
    return String((id.split(separator: "-").last.map(String.init) ?? id).suffix(4))
}

func boardStatusLine(runs: [OrchestratorRun], promptActive: Bool, liveText: String?, chatRunning: Bool) -> String {
    if let w = runs.first(where: { $0.state == "waiting" }) { return "Orchestrator: waiting on run \(runShortID(w.id))" }
    if promptActive { return "Orchestrator: needs you" }
    if let t = liveText { return "Orchestrator: \(t)" }
    return chatRunning ? "Orchestrator: idle" : "Orchestrator: stopped"
}

// MARK: - Levels, shortcuts, transitions, wings (RUN-02, RUN-04, RUN-05)

enum LevelEvent { case deeper, back, terminal }

func nextLevel(_ l: ExpandLevel, _ e: LevelEvent) -> ExpandLevel {
    switch e {
    case .terminal: return .terminal
    case .deeper: return l == .open ? .expanded : l
    case .back: return l == .terminal ? .expanded : .open
    }
}

/// Expanded notch size for a screen. 850 wide so the conversation column is ~600 with the rail open
/// (column = width - ~252: notch paddings ~72, rail 178, spacing 12); at least max(520, 60% of the height) tall.
/// Both clamped to the screen with a margin; never narrower than the open notch.
func expandedSize(screen: CGSize, openWidth: CGFloat = 640) -> CGSize {
    CGSize(width: max(openWidth, min(850, screen.width - 80)),
           height: min(max(520, (0.6 * screen.height).rounded()), screen.height - 40))
}

enum OrchShortcut: Equatable { case deeper, back, terminal, toggleRail }

/// Raw NSEvent.ModifierFlags: command alone, ignoring caps lock, numericPad and function (arrow keys carry the last two).
func isCommandOnly(_ raw: UInt) -> Bool {
    let command: UInt = 1 << 20, shift: UInt = 1 << 17, control: UInt = 1 << 18, option: UInt = 1 << 19
    return raw & (command | shift | control | option) == command
}

/// T and backslash match on characters (other layouts); esc is never handled (R-06).
func shortcut(keyCode: UInt16, chars: String?, commandOnly: Bool) -> OrchShortcut? {
    guard commandOnly else { return nil }
    if keyCode == 125 { return .deeper }
    if keyCode == 126 { return .back }
    if chars?.lowercased() == "t" { return .terminal }
    if chars == "\\" { return .toggleRail }
    return nil
}

func runStates(_ runs: [OrchestratorRun]) -> [String: String] {
    var m = [String: String]()
    for r in runs { if let id = r.id, let s = r.state { m[id] = s } }
    return m
}

func newlyWaiting(old: [String: String]?, new: [OrchestratorRun]) -> Bool {
    guard let old else { return false }
    return new.contains { $0.state == "waiting" && old[$0.id ?? ""] != "waiting" }
}

/// Waiting/finished baseline (WR-01): none until the manager has loaded, none while offline,
/// and none from the empty list offline leaves behind (reconnect clears `offline` before `runs` arrive).
struct RunsBaseline {
    private var states: [String: String]?
    private var stale = true
    /// Returns the baseline to diff `runs` against (nil = no baseline), then stores `runs` as the new one.
    mutating func advance(_ runs: [OrchestratorRun], offline: Bool, loaded: Bool) -> [String: String]? {
        if !loaded || offline { states = nil; stale = true; return nil }
        if stale && runs.isEmpty { return nil }
        stale = false
        defer { states = runStates(runs) }
        return states
    }
}

/// Every run that went running/stuck -> done/failed since the baseline, oldest start first, so each gets its own wing in turn.
func finishedTransitions(old: [String: String]?, new: [OrchestratorRun]) -> [OrchestratorRun] {
    guard let old else { return [] }
    return new.filter { ["done", "failed"].contains($0.state ?? "") && ["running", "stuck"].contains(old[$0.id ?? ""] ?? "") }
        .sorted { (parseRunDate($0.startedAt) ?? .distantPast) < (parseRunDate($1.startedAt) ?? .distantPast) }
}

/// working = agents at work (chat + running runs).
enum WingKind: Equatable { case working(Int), needsYou(String), finished(String, failed: Bool) }

func wingKind(needsYou: Bool, needsLabel: String, finished: (project: String, failed: Bool)?, workingCount: Int) -> WingKind? {
    if needsYou { return .needsYou(needsLabel) }
    if let f = finished { return .finished(f.project, failed: f.failed) }
    return workingCount > 0 ? .working(workingCount) : nil
}

func workingCount(chatWorking: Bool, runs: [OrchestratorRun]) -> Int {
    (chatWorking ? 1 : 0) + runs.filter { $0.state == "running" }.count
}

/// Elapsed of the longest-working agent: the chat's own timer or a running run's startedAt.
func longestWorking(chatElapsed: TimeInterval?, runs: [OrchestratorRun], now: Date) -> TimeInterval? {
    longestWorking(chatElapsed: chatElapsed, starts: runs.filter { $0.state == "running" }.compactMap { parseRunDate($0.startedAt) }, now: now)
}

/// `starts`: startedAt of the running runs.
func longestWorking(chatElapsed: TimeInterval?, starts: [Date], now: Date) -> TimeInterval? {
    (starts.map { now.timeIntervalSince($0) } + [chatElapsed].compactMap { $0 }).max()
}

func wingLabel(promptTitle: String?, waitingDenials: [String]?) -> String {
    if let w = promptTitle?.split(separator: " ").first.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "?")) }), !w.isEmpty { return w + "?" }
    if let d = waitingDenials?.first, !d.isEmpty { return d + "?" }
    return "Needs you"
}

/// Horizontal offset that keeps the middle notch rect centred over the hardware notch when the wings differ in width.
func wingShift(left: CGFloat, right: CGFloat) -> CGFloat { ((right - left) / 2).rounded() }
