import Foundation
import AppKit
import UniformTypeIdentifiers

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

/// A POST that died before any HTTP response: serve restarted under a kept-alive connection, or isn't listening yet.
/// Timeouts are left out (serve may have acted on the request).
func isOrchestratorConnectionDrop(_ error: Error) -> Bool {
    [.networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet].contains((error as? URLError)?.code)
}

/// session.data(for:) retried once, on a fresh session (no pooled connection), when the connection dropped before
/// any response. Never after a response of any status, so a message can't be sent twice.
func orchestratorPostData(for req: URLRequest, session: URLSession) async throws -> (Data, URLResponse) {
    do { return try await session.data(for: req) } catch where isOrchestratorConnectionDrop(error) {
        try? await Task.sleep(for: .milliseconds(250))
        let fresh = URLSession(configuration: session.configuration)
        defer { fresh.finishTasksAndInvalidate() }
        return try await fresh.data(for: req)
    }
}

/// HTTP status of the POST, nil when nothing was sent (invalid input). Network errors throw.
func sendOrchestratorPost(_ post: OrchestratorPost, base: URL, session: URLSession) async throws -> Int? {
    guard let req = post.request(base: base) else { return nil }
    let (_, resp) = try await orchestratorPostData(for: req, session: session)
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
          let (data, resp) = try? await orchestratorPostData(for: req, session: session),
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

// MARK: - Files (POST /api/chat/file)

/// serve's file cap.
let orchestratorFileMax: Int64 = 200 * 1024 * 1024

/// x-filename header: plain when printable ASCII (and no '%'), else percent-encoded so a header never carries raw bytes.
func orchestratorFilenameHeader(_ rawName: String) -> String {
    let name = rawName.precomposedStringWithCanonicalMapping // APFS hands back decomposed accents
    let plain = !name.isEmpty && !name.contains("%") && name.utf8.allSatisfy { $0 >= 0x20 && $0 < 0x7f }
    return plain ? name : (name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? "file")
}

func orchestratorFileRequest(name: String, base: URL) -> URLRequest {
    var r = URLRequest(url: base.appendingPathComponent("api/chat/file"))
    r.httpMethod = "POST"
    r.setValue("1", forHTTPHeaderField: "x-orch")
    r.setValue(orchestratorFilenameHeader(name), forHTTPHeaderField: "x-filename")
    r.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
    return r
}

struct FileUploadError: Error, Equatable { let message: String }

private final class UploadProgress: NSObject, URLSessionTaskDelegate {
    let onProgress: @Sendable (Double) -> Void
    init(_ f: @escaping @Sendable (Double) -> Void) { onProgress = f }
    func urlSession(_ s: URLSession, task: URLSessionTask, didSendBodyData b: Int64, totalBytesSent t: Int64, totalBytesExpectedToSend e: Int64) {
        if e > 0 { onProgress(min(1, Double(t) / Double(e))) }
    }
}

/// Streams the file from disk (never into memory). The server path on success.
func uploadOrchestratorFile(_ url: URL, name: String, base: URL, session: URLSession,
                            progress: @escaping @Sendable (Double) -> Void) async -> Result<String, FileUploadError> {
    let scoped = url.startAccessingSecurityScopedResource() // drag/paste URLs; false (harmless) for plain ones
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    // URLSession would send an empty body for a vanished file and serve would store an empty one.
    guard FileManager.default.isReadableFile(atPath: url.path) else { return .failure(.init(message: "File gone")) }
    do {
        let (data, resp) = try await session.upload(for: orchestratorFileRequest(name: name, base: base), fromFile: url, delegate: UploadProgress(progress))
        guard let http = resp as? HTTPURLResponse else { return .failure(.init(message: "Upload failed")) }
        if http.statusCode == 413 { return .failure(.init(message: "Too big")) }
        guard http.statusCode == 200, let path = decodeImagePath(data) else { return .failure(.init(message: "Upload failed")) }
        return .success(path)
    } catch {
        return .failure(.init(message: (error as? URLError)?.code == .fileDoesNotExist ? "File gone" : "Upload failed"))
    }
}

struct FileChip: Identifiable, Equatable {
    enum State: Equatable { case queued, uploading(Double), done(String), failed(String) }
    let id: Int
    let url: URL
    let name: String
    let size: Int64
    var temp = false // a file-promise copy we made: deleted once uploaded or removed
    var state: State
    var path: String? { if case .done(let p) = state { return p }; return nil }
    var isFailed: Bool { if case .failed = state { return true }; return false }
    var isActive: Bool { switch state { case .queued, .uploading: return true; default: return false } }
}

func orchestratorSizeLabel(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

enum OrchestratorDropKind { case image, file }

/// Real images keep going to /api/chat/image (re-encoded, capped); everything else is uploaded as the file itself.
func orchestratorDropKind(_ url: URL) -> OrchestratorDropKind {
    UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true ? .image : .file
}

/// The Orchestrator tab owns file drops/pastes while it is the current tab; every other tab leaves them to the shelf.
func orchestratorOwnsDrops(orchestratorIsCurrentTab: Bool) -> Bool { orchestratorIsCurrentTab }

/// Dropped/pasted file URLs: images to `image`, the rest to the upload queue.
@MainActor func orchestratorHandleURLs(_ urls: [URL], files: OrchestratorFileQueue, image: (URL) -> Void) {
    var other: [URL] = []
    for u in urls { if orchestratorDropKind(u) == .image { image(u) } else { other.append(u) } }
    if !other.isEmpty { files.add(other) }
}

/// Composer file chips, uploaded one at a time as they arrive. `base`/`session` are read per upload.
@MainActor final class OrchestratorFileQueue: ObservableObject {
    @Published private(set) var chips: [FileChip] = []
    private let base: () -> URL
    private let session: () -> URLSession
    private var nextID = 0
    private var worker: Task<Void, Never>?

    init(base: @escaping () -> URL, session: @escaping () -> URLSession) { self.base = base; self.session = session }

    /// A chip still waiting on or in an upload, or a failed one: sending must wait for the user to resolve it.
    var blocksSend: Bool { chips.contains { $0.isActive || $0.isFailed } }
    var isEmpty: Bool { chips.isEmpty }

    func add(_ urls: [URL], temp: Bool = false) {
        for u in urls {
            nextID += 1
            let size = Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let over = size > orchestratorFileMax
            chips.append(FileChip(id: nextID, url: u, name: u.lastPathComponent, size: size, temp: temp, state: over ? .failed("Over 200 MB") : .queued))
        }
        start()
    }

    /// Chips of a message sent back for editing (already uploaded).
    func restore(_ done: [FileChip]) { chips.insert(contentsOf: done, at: 0) }

    func remove(_ id: Int) {
        guard let i = chips.firstIndex(where: { $0.id == id }) else { return }
        let c = chips.remove(at: i)
        if c.temp { try? FileManager.default.removeItem(at: c.url) }
    }

    func retry(_ id: Int) {
        guard let i = chips.firstIndex(where: { $0.id == id }), chips[i].isFailed, chips[i].size <= orchestratorFileMax else { return }
        chips[i].state = .queued
        start()
    }

    /// Done chips for the message being sent; the row is cleared.
    func take() -> [FileChip] { defer { chips = [] }; return chips.filter { $0.path != nil } }

    func waitIdle() async { await worker?.value }

    #if ORCH_SNAPSHOT
    func snapshotSet(_ c: [FileChip]) { chips = c }
    #endif

    private func set(_ id: Int, _ s: FileChip.State) {
        if let i = chips.firstIndex(where: { $0.id == id }) { chips[i].state = s }
    }

    private func start() {
        guard worker == nil else { return }
        worker = Task { @MainActor in
            while let c = chips.first(where: { $0.state == .queued }) {
                set(c.id, .uploading(0))
                let r = await uploadOrchestratorFile(c.url, name: c.name, base: base(), session: session()) { p in
                    Task { @MainActor in if case .uploading = self.chips.first(where: { $0.id == c.id })?.state { self.set(c.id, .uploading(p)) } }
                }
                switch r {
                case .success(let path): set(c.id, .done(path)); if c.temp { try? FileManager.default.removeItem(at: c.url) }
                case .failure(let e): set(c.id, .failed(e.message))
                }
            }
            worker = nil
        }
    }
}
