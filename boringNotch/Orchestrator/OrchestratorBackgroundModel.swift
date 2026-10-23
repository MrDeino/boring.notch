import Foundation

// Background work of the chat (GET /api/chat/agents, SSE `agents` / `agent`): Foundation only, harness-compiled.

struct BgStep: Equatable {
    let at: Date?
    let tool: String?
    let summary: String?
}

/// One background agent or monitor. Lenient like OrchestratorRun: any field of the wrong type becomes nil;
/// only an `id` is required. A missing `kind` is an agent.
struct BgTask: Decodable, Equatable, Identifiable {
    let id: String
    /// "agent" | "monitor"
    let kind: String
    let description: String?
    /// "running" | "done" | "failed" | "stopped" (anything else counts as finished)
    let status: String?
    let startedAt: Date?
    let endedAt: Date?
    let lastStep: String?
    let steps: [BgStep]
    let report: String?
    let tokens: Int?
    let toolUses: Int?

    var isMonitor: Bool { kind == "monitor" }
    var isRunning: Bool { status == "running" }

    private enum CodingKeys: String, CodingKey { case id, kind, description, status, startedAt, endedAt, lastStep, steps, report, tokens, toolUses }

    init?(lenient decoder: Decoder) {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return nil }
        let rawID = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? (try? c.decodeIfPresent(Int.self, forKey: .id)).flatMap { $0.map(String.init) }
        guard let rawID, !rawID.isEmpty else { return nil }
        id = rawID
        kind = ((try? c.decodeIfPresent(String.self, forKey: .kind)) ?? nil) == "monitor" ? "monitor" : "agent"
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? nil
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? nil
        startedAt = bgDate(c, .startedAt)
        endedAt = bgDate(c, .endedAt)
        lastStep = (try? c.decodeIfPresent(String.self, forKey: .lastStep)) ?? nil
        report = (try? c.decodeIfPresent(String.self, forKey: .report)) ?? nil
        tokens = (try? c.decodeIfPresent(Int.self, forKey: .tokens)) ?? nil
        toolUses = (try? c.decodeIfPresent(Int.self, forKey: .toolUses)) ?? nil
        steps = ((try? c.decodeIfPresent([LenientStep].self, forKey: .steps)) ?? nil)?.compactMap(\.step) ?? []
    }

    init(from decoder: Decoder) throws {
        guard let t = BgTask(lenient: decoder) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "bad background task")) }
        self = t
    }

    init(id: String, kind: String = "agent", description: String? = nil, status: String? = "running", startedAt: Date? = nil, endedAt: Date? = nil,
         lastStep: String? = nil, steps: [BgStep] = [], report: String? = nil, tokens: Int? = nil, toolUses: Int? = nil) {
        self.id = id; self.kind = kind; self.description = description; self.status = status; self.startedAt = startedAt; self.endedAt = endedAt
        self.lastStep = lastStep; self.steps = steps; self.report = report; self.tokens = tokens; self.toolUses = toolUses
    }
}

private func bgEpoch(_ v: Double) -> Date { Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v) }

/// ISO string, or epoch seconds / milliseconds.
private func bgDate<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ k: K) -> Date? {
    if let s = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil { return parseRunDate(s) }
    if let d = (try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil { return bgEpoch(d) }
    return nil
}

private struct LenientStep: Decodable {
    let step: BgStep?
    private enum Keys: String, CodingKey { case at, tool, summary }
    init(from decoder: Decoder) {
        guard let c = try? decoder.container(keyedBy: Keys.self) else { step = nil; return }
        step = BgStep(at: bgDate(c, .at), tool: (try? c.decodeIfPresent(String.self, forKey: .tool)) ?? nil,
                      summary: (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? nil)
    }
}

private struct LenientBg: Decodable {
    let task: BgTask?
    init(from decoder: Decoder) { task = BgTask(lenient: decoder) }
}

/// A bare array or `{"agents":[…]}`; nil when the payload is neither (the list stays as it was).
func decodeBgTasks(_ data: Data) -> [BgTask]? {
    let d = JSONDecoder()
    if let l = try? d.decode([LenientBg].self, from: data) { return l.compactMap(\.task) }
    struct Wrapped: Decodable { let agents: [LenientBg]? }
    return (try? d.decode(Wrapped.self, from: data))?.agents.map { $0.compactMap(\.task) }
}

/// One bare task object (SSE `agent`): an upsert by id.
func decodeBgTask(_ data: Data) -> BgTask? { try? JSONDecoder().decode(BgTask.self, from: data) }

func bgUpserting(_ list: [BgTask], _ t: BgTask) -> [BgTask] {
    var l = list
    if let i = l.firstIndex(where: { $0.id == t.id }) { l[i] = t } else { l.append(t) }
    return l
}

func bgRunningCount(_ l: [BgTask]) -> Int { l.filter(\.isRunning).count }

/// Running first, then the finished ones; serve's order otherwise.
func bgSorted(_ l: [BgTask]) -> [BgTask] { l.filter(\.isRunning) + l.filter { !$0.isRunning } }

func bgElapsed(_ t: BgTask, now: Date) -> TimeInterval? {
    guard let s = t.startedAt else { return nil }
    return max(0, (t.isRunning ? now : (t.endedAt ?? now)).timeIntervalSince(s))
}

/// The last few steps (events for a monitor); a task that only has `lastStep` shows that.
func bgRecentSteps(_ t: BgTask, limit: Int = 5) -> [BgStep] {
    if !t.steps.isEmpty { return Array(t.steps.suffix(limit)) }
    return t.lastStep.map { [BgStep(at: nil, tool: nil, summary: $0)] } ?? []
}

func bgTitle(_ t: BgTask) -> String {
    let d = (t.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return d.isEmpty ? (t.isMonitor ? "Monitor" : "Agent") : d
}
