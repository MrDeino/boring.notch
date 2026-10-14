import Foundation

/// GET /api/chat. All fields optional so server omissions never break decoding.
struct ChatResponse: Decodable {
    let running: Bool?
    let screen: String?
}

/// Last `maxLines` non-blank conversation lines of a terminal screen, trailing spaces/NBSP trimmed.
/// Claude Code's input box (a rule, the `❯` line, a closing rule, status lines below) and every
/// `───` rule line are dropped; an unsent draft in the box goes with it.
func chatTail(screen: String, maxLines: Int) -> [String] {
    let junk = CharacterSet(charactersIn: " \u{a0}\t\r")
    var lines = screen.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
        var s = Substring(line)
        while let l = s.unicodeScalars.last, junk.contains(l) { s = s.dropLast() }
        return s.isEmpty ? nil : String(s)
    }
    let edge = CharacterSet(charactersIn: " \u{a0}")
    func isRule(_ s: String) -> Bool { s.trimmingCharacters(in: edge).hasPrefix("───") }
    // Requiring a closing rule keeps a live prompt's "❯ 1. Yes" (footer, no rule below) on screen.
    if let top = lines.indices.last(where: { i in
        isRule(lines[i]) && i + 1 < lines.count && lines[i + 1].trimmingCharacters(in: edge).hasPrefix("❯")
            && lines[(i + 2)...].contains(where: isRule)
    }) { lines.removeSubrange(top...) }
    return Array(lines.filter { !isRule($0) }.suffix(maxLines))
}

/// GET /api/state. Only runs and usage are decoded; everything else is ignored.
struct StateResponse: Decodable {
    let runs: [OrchestratorRun]?
    let usage: OrchestratorUsage?
}

struct OrchestratorRun: Decodable, Equatable {
    let id: String?
    let project: String?
    let ws: String?
    let agent: String?
    let prompt: String?
    let state: String?
    let startedAt: String?
    let lastOutput: String?
    let result: String?
    let denials: [String]?
    let latest: String?
    let activity: RunActivity?

    /// ForEach id that survives a nil id.
    var stableID: String { id ?? "\(project ?? "")|\(prompt ?? "")" }

    var shortPrompt: String {
        (prompt ?? "").split(separator: "\n").lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}

struct RunActivity: Decodable, Equatable { let step: String?; let agents: [RunAgent]? }
struct RunAgent: Decodable, Equatable { let type: String?; let desc: String? }

struct OrchestratorUsage: Decodable, Equatable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    enum CodingKeys: String, CodingKey { case fiveHour = "five_hour", sevenDay = "seven_day" }
}

struct UsageWindow: Decodable, Equatable {
    let usedPercentage: Double?
    let resetsAt: Double?
    enum CodingKeys: String, CodingKey { case usedPercentage = "used_percentage", resetsAt = "resets_at" }
    var resetsDate: Date? { resetsAt.map { Date(timeIntervalSince1970: $0) } }
}

/// Live runs first, original (newest-first) order kept within each group.
func stripRuns(_ runs: [OrchestratorRun], limit: Int) -> [OrchestratorRun] {
    let live: Set<String> = ["running", "waiting", "stuck"]
    let isLive = { (r: OrchestratorRun) in live.contains(r.state ?? "") }
    return Array((runs.filter(isLive) + runs.filter { !isLive($0) }).prefix(limit))
}

enum OrchestratorPost: Equatable {
    case text(String), key(String), start, stop

    static let allowedKeys: Set<String> = ["Enter", "Escape", "Up", "Down", "Tab", "C-u", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

    /// nil when the input would be rejected by the server (empty text, unknown key).
    func request(base: URL) -> URLRequest? {
        let path: String, body: [String: String]
        switch self {
        case .text(let s):
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            path = "api/chat"; body = ["text": s]
        case .key(let k):
            guard Self.allowedKeys.contains(k) else { return nil }
            path = "api/chat"; body = ["key": k]
        case .start: path = "api/chat/start"; body = [:]
        case .stop: path = "api/chat/stop"; body = [:]
        }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.setValue("1", forHTTPHeaderField: "x-orch")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONEncoder().encode(body)
        return r
    }
}

/// HTTP status of the POST, nil when nothing was sent (invalid input). Network errors throw.
func sendOrchestratorPost(_ post: OrchestratorPost, base: URL, session: URLSession) async throws -> Int? {
    guard let req = post.request(base: base) else { return nil }
    let (_, resp) = try await session.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    return http.statusCode
}
