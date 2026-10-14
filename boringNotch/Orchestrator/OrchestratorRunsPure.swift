// Phase 7 owns after Phase 4: run elapsed / sorting helpers.
import Foundation
import CoreGraphics

/// Poll cadence in seconds: 2 open, 3 closed while the chat runs, else 10.
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

private func parseLatest(_ latest: String?) -> String? {
    guard let l = latest, let line = firstLine(l) else { return nil }
    guard let r = line.range(of: "^\\[(\\w+)\\] ", options: .regularExpression) else { return line }
    let tool = String(line[r].dropFirst().dropLast(2))
    let rest = String(line[r.upperBound...])
    switch tool {
    case "Bash": return jsonField("command", in: rest).map { "$ " + $0 } ?? tool
    case "Edit", "Write", "Read", "MultiEdit", "NotebookEdit": return jsonField("file_path", in: rest).map { tool + " " + $0 } ?? tool
    case "Grep", "Glob": return jsonField("pattern", in: rest).map { tool + " " + $0 } ?? tool
    default: return tool
    }
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

func expandedHeight(screenHeight: CGFloat) -> CGFloat { max(300, min(440, 0.45 * screenHeight)) }

enum OrchShortcut: Equatable { case deeper, back, terminal, toggleRail }

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

func finishedTransition(old: [String: String]?, new: [OrchestratorRun]) -> OrchestratorRun? {
    guard let old else { return nil }
    let hits = new.filter { $0.state == "done" && ["running", "stuck"].contains(old[$0.id ?? ""] ?? "") }
    return hits.max { (parseRunDate($0.startedAt) ?? .distantPast) < (parseRunDate($1.startedAt) ?? .distantPast) }
}

enum WingKind: Equatable { case working, needsYou(String), finished(String) }

func wingKind(needsYou: Bool, needsLabel: String, finishedProject: String?, working: Bool) -> WingKind? {
    if needsYou { return .needsYou(needsLabel) }
    if let p = finishedProject { return .finished(p) }
    return working ? .working : nil
}

func wingLabel(promptTitle: String?, waitingDenials: [String]?) -> String {
    if let w = promptTitle?.split(separator: " ").first.map({ $0.trimmingCharacters(in: CharacterSet(charactersIn: "?")) }), !w.isEmpty { return w + "?" }
    if let d = waitingDenials?.first, !d.isEmpty { return d + "?" }
    return "Needs you"
}

// ponytail: character-count width estimate for 11pt text, upgrade = measure with NSFont if UAT shows clipping.
func wingSideWidth(_ kind: WingKind, notchWidth: CGFloat) -> CGFloat {
    let outer: CGFloat, est: CGFloat
    switch kind {
    case .working: outer = 285; est = 0
    case .needsYou(let l): outer = 305; est = CGFloat(l.count) * 6.5 + 8
    case .finished(let p): outer = 285; est = CGFloat(p.count) * 6.2
    }
    return max(((outer - 28 - notchWidth) / 2), est).rounded(.up)
}
