import Foundation
import AppKit

/// GET /api/chat. All fields optional so server omissions never break decoding.
struct ChatResponse: Decodable {
    let running: Bool?
    let screen: String?
    var live: Bool? = nil
    var input: ChatInput? = nil
    var context: ChatContext? = nil
    /// True when serve sent the `input` key at all (null = no box on screen; absent = old serve, use the heuristic).
    var hasInputKey = false
    // Phase 9
    var approval: OrchestratorApproval? = nil
    /// True when serve sent the `approval` key (null = none pending; absent = old serve, leave the current value alone).
    var hasApproval = false
    /// Claude Code update state; nil on old serve.
    var claude: ClaudeInfo? = nil
}

/// serve's `claude`: running/installed are version strings (running nil while unknown).
struct ClaudeInfo: Decodable, Equatable {
    let running: String?
    let installed: String?
    let updateReady: Bool?
    private enum CodingKeys: String, CodingKey { case running, installed, updateReady }
    init(running: String?, installed: String?, updateReady: Bool?) { self.running = running; self.installed = installed; self.updateReady = updateReady }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = try? c.decodeIfPresent(String.self, forKey: .running)
        installed = try? c.decodeIfPresent(String.self, forKey: .installed)
        updateReady = try? c.decodeIfPresent(Bool.self, forKey: .updateReady)
    }
}

/// The "Claude update ready · Restart" flow.
enum ClaudeRestart: Equatable { case idle, confirming, busy, restarting }

/// serve's running version comes from the transcript, which stays on the old version until the new session
/// writes to it, so the badge also hides once we restarted onto the installed version it reports.
func claudeUpdateBadge(_ c: ClaudeInfo?, restartedOnto: String?) -> Bool {
    c?.updateReady == true && (restartedOnto == nil || c?.installed != restartedOnto)
}

/// After POST /api/chat/restart: 200 restarting (until the chat runs again), 409 busy (mid-turn), else idle.
func claudeRestartPhase(afterPost code: Int?) -> ClaudeRestart {
    code == 200 ? .restarting : code == 409 ? .busy : .idle
}

/// A chat payload that says running ends .restarting, unless it raced the restart POST itself.
func claudeRestartOnChat(_ p: ClaudeRestart, running: Bool, posting: Bool) -> ClaudeRestart {
    p == .restarting && running && !posting ? .idle : p
}

/// Pending tool approval from serve (hook-driven, never screen-inferred). `at` stays the raw ISO string.
struct OrchestratorApproval: Decodable, Equatable {
    let id: String
    let tool: String?
    let command: String?
    let description: String?
    let at: String?
    private enum CodingKeys: String, CodingKey { case id, tool, command, description, at }
    init(id: String, tool: String?, command: String?, description: String?, at: String?) {
        self.id = id; self.tool = tool; self.command = command; self.description = description; self.at = at
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tool = try? c.decodeIfPresent(String.self, forKey: .tool)
        command = try? c.decodeIfPresent(String.self, forKey: .command)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        at = try? c.decodeIfPresent(String.self, forKey: .at)
    }
}

/// Serve's exact input-box state (Phase 8).
struct ChatInput: Decodable, Equatable {
    let text: String?
    let suggested: Bool?
    private enum CodingKeys: String, CodingKey { case text, suggested }
    init(text: String?, suggested: Bool?) { self.text = text; self.suggested = suggested }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        suggested = try? c.decodeIfPresent(Bool.self, forKey: .suggested)
    }
}

struct ChatContext: Decodable, Equatable {
    let tokens: Int?
    let window: Int?
    let percent: Int?
    private enum CodingKeys: String, CodingKey { case tokens, window, percent }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tokens = try? c.decodeIfPresent(Int.self, forKey: .tokens)
        window = try? c.decodeIfPresent(Int.self, forKey: .window)
        percent = try? c.decodeIfPresent(Int.self, forKey: .percent)
    }
}

extension ChatResponse {
    private enum CodingKeys: String, CodingKey { case running, screen, live, input, context, approval, claude }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = try c.decodeIfPresent(Bool.self, forKey: .running)
        screen = try c.decodeIfPresent(String.self, forKey: .screen)
        // lossy: a wrong-typed field must not fail the chat decode
        live = try? c.decodeIfPresent(Bool.self, forKey: .live)
        input = try? c.decodeIfPresent(ChatInput.self, forKey: .input)
        context = try? c.decodeIfPresent(ChatContext.self, forKey: .context)
        hasInputKey = c.contains(.input)
        hasApproval = c.contains(.approval)
        approval = (try? c.decodeIfPresent(OrchestratorApproval.self, forKey: .approval)) ?? nil // malformed -> nil, never fails the chat decode
        claude = (try? c.decodeIfPresent(ClaudeInfo.self, forKey: .claude)) ?? nil
    }
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

    private enum CodingKeys: String, CodingKey { case id, project, ws, agent, prompt, state, startedAt, lastOutput, result, denials, latest, activity }

    /// Lenient (WR-05): a field of the wrong type becomes nil and null denials are dropped,
    /// so one odd run never fails StateResponse and takes the tab offline.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: k) }
        id = str(.id); project = str(.project); ws = str(.ws); agent = str(.agent); prompt = str(.prompt)
        state = str(.state); startedAt = str(.startedAt); lastOutput = str(.lastOutput); result = str(.result); latest = str(.latest)
        denials = (try? c.decodeIfPresent([String?].self, forKey: .denials))?.compactMap { $0 }
        activity = try? c.decodeIfPresent(RunActivity.self, forKey: .activity)
    }

    /// ForEach id that survives a nil id.
    var stableID: String { id ?? "\(project ?? "")|\(prompt ?? "")" }

    var shortPrompt: String {
        (prompt ?? "").split(separator: "\n").lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}

struct RunActivity: Decodable, Equatable { let step: String?; let agents: [RunAgent]?; let doing: String? }
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
    /// POST /api/chat/restart; force restarts mid-turn (otherwise 409).
    case restart(force: Bool)
    /// POST /api/notes: raw full text (not JSON).
    case notes(String)
    /// POST /api/chat/image: raw PNG body.
    case image(Data)

    static let allowedKeys: Set<String> = ["Enter", "Escape", "Up", "Down", "Left", "Right", "Tab", "BTab", "C-u", "1", "2", "3", "4", "5", "6", "7", "8", "9"]

    /// nil when the input would be rejected by the server (empty text, unknown key).
    func request(base: URL) -> URLRequest? {
        let path: String, body: [String: String]
        var force = false
        if case .notes(let s) = self {
            let data = Data(s.utf8)
            guard data.count <= 1_000_000 else { return nil } // serve destroys larger bodies
            var r = URLRequest(url: base.appendingPathComponent("api/notes"))
            r.httpMethod = "POST"
            r.setValue("1", forHTTPHeaderField: "x-orch")
            r.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = data
            return r
        }
        if case .image(let data) = self {
            guard !data.isEmpty, data.count <= 10 * 1024 * 1024 else { return nil } // serve's IMAGE_MAX
            var r = URLRequest(url: base.appendingPathComponent("api/chat/image"))
            r.httpMethod = "POST"
            r.setValue("1", forHTTPHeaderField: "x-orch")
            r.setValue("image/png", forHTTPHeaderField: "Content-Type")
            r.httpBody = data
            return r
        }
        switch self {
        case .text(let s):
            guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            path = "api/chat"; body = ["text": s]
        case .key(let k):
            guard Self.allowedKeys.contains(k) else { return nil }
            path = "api/chat"; body = ["key": k]
        case .start: path = "api/chat/start"; body = [:]
        case .stop: path = "api/chat/stop"; body = [:]
        case .restart(let f): path = "api/chat/restart"; body = [:]; force = f
        case .notes, .image: return nil
        }
        var r = URLRequest(url: base.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.setValue("1", forHTTPHeaderField: "x-orch")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = force ? Data(#"{"force":true}"#.utf8) : try? JSONEncoder().encode(body)
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

/// GET /api/notes (text/plain). Throws unless HTTP 200 so a failed load is never mistaken for empty notes.
func fetchOrchestratorNotes(base: URL, session: URLSession) async throws -> String {
    let (data, resp) = try await session.data(for: URLRequest(url: base.appendingPathComponent("api/notes")))
    guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
    return String(decoding: data, as: UTF8.self)
}

private struct ImagePathResponse: Decodable { let path: String? }

func decodeImagePath(_ data: Data) -> String? {
    guard let p = (try? JSONDecoder().decode(ImagePathResponse.self, from: data))?.path, !p.isEmpty else { return nil }
    return p
}

/// Server path of the uploaded image; nil on any failure (non-200, network, bad body).
func uploadOrchestratorImage(_ png: Data, base: URL, session: URLSession) async -> String? {
    guard let req = OrchestratorPost.image(png).request(base: base),
          let (data, resp) = try? await session.data(for: req),
          (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
    return decodeImagePath(data)
}

/// PNG of the image, longest pixel side capped at maxSide (never upscaled); 2000px keeps retina screenshots far below serve's 10 MB cap.
func orchestratorPNG(from image: NSImage, maxSide: CGFloat = 2000) -> Data? {
    var w = CGFloat(0), h = CGFloat(0)
    for r in image.representations { w = max(w, CGFloat(r.pixelsWide)); h = max(h, CGFloat(r.pixelsHigh)) }
    if w <= 0 || h <= 0 { w = image.size.width; h = image.size.height }
    guard w > 0, h > 0 else { return nil }
    let k = min(1, maxSide / max(w, h))
    let pw = max(1, Int((w * k).rounded())), ph = max(1, Int((h * k).rounded()))
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pw, pixelsHigh: ph, bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    rep.size = NSSize(width: pw, height: ph)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    image.draw(in: NSRect(x: 0, y: 0, width: pw, height: ph), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}
