import AppKit

@MainActor
final class OrchestratorManager: ObservableObject {
    static let shared = OrchestratorManager()
    #if ORCH_SNAPSHOT
    static let baseURL = URL(string: ProcessInfo.processInfo.environment["ORCH_BASE"] ?? "http://127.0.0.1:4777")! // mock-server tests only
    #else
    static let baseURL = URL(string: "http://127.0.0.1:4777")!
    #endif

    @Published private(set) var offline = false
    @Published private(set) var chatRunning = false
    @Published private(set) var screen = ""
    @Published private(set) var runs: [OrchestratorRun] = []
    @Published private(set) var usage: OrchestratorUsage?
    @Published private(set) var promptOptions: [PromptOption] = []
    /// A run is waiting or the chat shows a prompt. Deliberately independent of music/tab/notch state.
    var needsAttention: Bool { runs.contains { $0.state == "waiting" } || !promptOptions.isEmpty }
    /// False until the first response or error, so the view doesn't flash "offline".
    @Published private(set) var hasLoaded = false
    // Phase 4
    /// Chat | Runs segment state.
    @Published var showRunsBoard = false
    @Published var statusMenuOpen = false
    /// Notes drop-down; mutually exclusive with the status menu.
    @Published var notesOpen = false
    @Published private(set) var prompt: PromptCard? = nil
    @Published private(set) var liveStatus: LiveStatus? = nil
    @Published private(set) var chatLive: Bool? = nil
    // Phase 8
    /// serve's context.percent while the chat runs; nil on old serve.
    @Published private(set) var contextPercent: Int? = nil
    /// True while the SSE stream is healthy; polling and the notch-open refresh stand down.
    @Published private(set) var streaming = false
    private var streamTask: Task<Void, Never>?
    private var lastStreamLine = Date.distantPast
    private func makeStreamSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 45
        c.timeoutIntervalForResource = .greatestFiniteMagnitude
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }
    // Phase 9
    /// Pending tool approval from serve (hook-driven), minus the one we just answered. Never inferred from screen text.
    @Published private(set) var approval: OrchestratorApproval? = nil
    private var rawApproval: OrchestratorApproval?
    private var ignoredApprovalId: String?
    private var ignoredUntil = Date.distantPast

    func applyApproval(_ a: OrchestratorApproval?) {
        rawApproval = a
        recomputeApproval()
    }

    private func recomputeApproval() {
        let v = chatRunning ? visibleApproval(rawApproval, ignoredId: ignoredApprovalId, until: ignoredUntil, now: Date()) : nil
        if approval != v { approval = v }
    }

    /// Re-reads the screen, then answers only if the same approval is still pending (see approvalAnswer).
    /// Hides the panel before posting so the post's own refresh cannot flash it back.
    @discardableResult
    func answerApproval(allow: Bool) async -> ApprovalAnswer {
        guard let a = approval, !sending else { return .skip }
        await refresh(fresh: true)
        let ans = approvalAnswer(allow: allow, pendingId: approval?.id, answeringId: a.id, options: promptOptions)
        guard case .send(let k) = ans else { return ans }
        ignoredApprovalId = a.id
        ignoredUntil = Date() + 3
        approval = nil
        if !(await post(.key(k))) {
            ignoredApprovalId = nil
            await refresh()
        }
        return ans
    }

    var capsuleStatus: CapsuleState {
        capsuleState(hasLoaded: hasLoaded, offline: offline, chatRunning: chatRunning, needsAttention: needsAttention, working: liveStatus != nil)
    }

    /// Fed by notch open/close hooks; opening triggers an immediate refresh.
    var notchOpen = false {
        didSet {
            // Typing teardown is owned by OrchestratorView (close() is blocked while typing).
            if notchOpen && !oldValue && !streaming { Task { await refresh() } }
            if !notchOpen { OrchestratorExpand.shared.reset(); statusMenuOpen = false; notesOpen = false }
        }
    }

    @Published private(set) var wantsKeyboard = false
    @Published private(set) var sending = false
    private var typing = false

    /// The one notch panel allowed to become key (one panel per display).
    private(set) weak var keyboardWindow: NSWindow?

    /// Idempotent so begin/end can never unbalance the shared interaction count.
    func beginTyping(in window: NSWindow) {
        keyboardWindow = window
        guard !typing else { return }
        typing = true
        SharingStateManager.shared.beginInteraction()
        wantsKeyboard = true
    }

    func endTyping() {
        guard typing else { return }
        typing = false
        keyboardWindow = nil
        wantsKeyboard = false
        SharingStateManager.shared.endInteraction()
    }

    /// 200 -> refresh, true. 409 (chat not running) -> refresh, false. Anything else -> false.
    @discardableResult
    private func post(_ p: OrchestratorPost) async -> Bool {
        guard !sending else { return false }
        sending = true
        defer { sending = false }
        return await postNow(p)
    }

    private func postNow(_ p: OrchestratorPost) async -> Bool {
        let code = (try? await sendOrchestratorPost(p, base: Self.baseURL, session: session)) ?? nil
        if code == 200 { await refresh(fresh: true); return true }
        if code == 409 { await refresh(fresh: true) }
        return false
    }

    /// clearFirst runs inside the same `sending` window, so no other POST (a prompt answer) can land
    /// between clearing Claude's box and typing the text. Returning false from it cancels the send.
    func sendText(_ s: String, clearFirst: (() async -> Bool)? = nil) async -> Bool {
        guard !sending else { return false }
        sending = true
        defer { sending = false }
        if let clearFirst, !(await clearFirst()) { return false }
        return await postNow(.text(s))
    }
    /// Debounced: Esc-Esc opens Claude Code's rewind picker.
    func pressEscape() async {
        guard Date().timeIntervalSince(lastEscape) > 1 else { return }
        lastEscape = Date()
        await post(.key("Escape"))
    }
    private var lastEscape = Date.distantPast
    func startChat() async { await post(.start) }
    func stopChat() async { await post(.stop) }

    /// A key sequence in one `sending` window. Stops at the first non-200; true only if every key landed.
    func pressKeys(_ keys: [String]) async -> Bool {
        guard !sending else { return false }
        sending = true
        defer { sending = false }
        for k in keys {
            guard (try? await sendOrchestratorPost(.key(k), base: Self.baseURL, session: session)) == 200 else { await refresh(fresh: true); return false }
        }
        await refresh(fresh: true)
        return true
    }

    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        c.timeoutIntervalForResource = 5
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
    private var pollTask: Task<Void, Never>?

    private init() {}

    func start() {
        startStream()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.streaming { try? await Task.sleep(for: .seconds(2)); continue }
                await self.refresh()
                let secs = pollInterval(notchOpen: self.notchOpen, chatRunning: self.chatRunning || self.runs.contains { $0.state == "running" }, offline: self.offline)
                try? await Task.sleep(for: .seconds(secs))
            }
        }
    }

    // ponytail: fixed 30 s retry, no backoff.
    private func startStream() {
        guard streamTask == nil else { return }
        streamTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runStream()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Returns when the stream ends: 404 (old serve), error, or 20 s with no line. Polling resumes within ~2 s.
    private func runStream() async {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent("api/events"))
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let streamSession = makeStreamSession() // per stream: invalidateAndCancel() on watchdog trip guarantees the iterator ends
        defer { streamSession.finishTasksAndInvalidate() }
        guard let (bytes, resp) = try? await streamSession.bytes(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
        lastStreamLine = Date()
        streaming = true
        defer { streaming = false }
        let watchdogTripped = { [weak self] in self?.streaming = false; streamSession.invalidateAndCancel() }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                var parser = SSELineParser()
                var first = true
                do {
                    for try await line in bytes.lines {
                        guard let self else { return }
                        self.lastStreamLine = Date()
                        guard let ev = parser.feed(line) else { continue }
                        switch ev {
                        case .state(let st): self.applyState(st)
                        case .chat(let r):
                            await self.applyChat(r)
                            if r.running == false { OrchestratorTranscriptStore.shared.ingestBlocks(running: false, blocks: [], reset: true) }
                        case .blocks(let running, let blocks, let reset):
                            // First blocks event of a connection replaces; pending rows survive (store keeps them).
                            OrchestratorTranscriptStore.shared.ingestBlocks(running: running, blocks: blocks, reset: first || reset)
                            first = false
                        case .approval(let a): self.applySeq += 1; self.applyApproval(a) // joins the sequence so an older poll cannot overwrite it
                        }
                        if !self.hasLoaded { self.hasLoaded = true }
                    }
                } catch {}
            }
            group.addTask { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    guard let self, streamHealthy(lastLineAt: self.lastStreamLine, now: Date()) else { watchdogTripped(); return }
                }
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, resp) = try await session.data(from: Self.baseURL.appendingPathComponent(path))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private var inFlight: Task<Void, Never>?

    /// fresh: the caller needs a screen read after this call (e.g. before acting on a prompt), so wait
    /// out a poll already in flight and fetch again. Otherwise an in-flight poll makes this a no-op.
    func refresh(fresh: Bool = false) async {
        if let t = inFlight {
            guard fresh else { return }
            await t.value
            if let t2 = inFlight, t2 != t { await t2.value; return } // started after our call: fresh enough
        }
        let t = Task { await load() }
        inFlight = t
        await t.value
        if inFlight == t { inFlight = nil }
    }

    private func load() async {
        let started = applySeq
        do {
            async let chat: ChatResponse = get("api/chat")
            async let state: StateResponse = get("api/state")
            let (r, st) = try await (chat, state)
            applyState(st)
            await applyChat(r, polledAt: started)
        } catch {
            applyOffline()
        }
        if !hasLoaded { hasLoaded = true }
    }

    private func applyState(_ st: StateResponse) {
        if offline { offline = false }
        let rs = st.runs ?? []
        if runs != rs { runs = rs }
        if usage != st.usage { usage = st.usage }
    }

    /// Reused by the SSE stream (08-02): screen/input first, then blocks, then the prompt that needs them.
    private var applySeq = 0
    private func applyChat(_ r: ChatResponse, polledAt: Int? = nil) async {
        let approvalFresh = approvalApplyIsFresh(startedAt: polledAt, current: applySeq)
        applySeq += 1
        let mine = applySeq
        if offline { offline = false }
        let running = r.running ?? false
        if chatRunning != running { chatRunning = running }
        if !approvalFresh { recomputeApproval() } else if r.hasApproval { applyApproval(r.approval) } else if !running { applyApproval(nil) } else { recomputeApproval() }
        let s = r.screen ?? ""
        if screen != s { screen = s }
        let cp = running ? r.context?.percent.flatMap { $0 >= 0 ? $0 : nil } : nil
        if contextPercent != cp { contextPercent = cp }
        OrchestratorTranscriptStore.shared.applyScreen(r)
        let po = running ? detectPrompt(screen: s) : []
        let pc = running ? detectPromptCard(screen: s) : nil
        // Blocks first: a new card must appear with its context (Phase 8: ingest blocks before publishing a prompt).
        // While streaming, blocks arrive as events, except a chat event with a new prompt, which fetches them first.
        let newPrompt = pc != nil && pc != prompt || !po.isEmpty && po != promptOptions
        if shouldFetchBlocks(streaming: streaming, running: running, newPrompt: newPrompt) {
            await OrchestratorTranscriptStore.shared.refresh(base: Self.baseURL, session: session, chatRunning: running)
            guard mine == applySeq else { return } // a newer chat payload applied while we were suspended
        }
        if promptOptions != po { promptOptions = po }
        if prompt != pc { prompt = pc }
        let ls = running ? liveStatusFor(screen: s, live: r.live) : nil
        if liveStatus != ls { liveStatus = ls }
        let cl = running ? r.live : nil
        if chatLive != cl { chatLive = cl }
    }

    private func applyOffline() {
        if !offline { offline = true }
        if !runs.isEmpty { runs = [] }
        if rawApproval != nil || approval != nil { applyApproval(nil) }
        if !promptOptions.isEmpty { promptOptions = [] }
        if prompt != nil { prompt = nil }
        if liveStatus != nil { liveStatus = nil }
        if chatLive != nil { chatLive = nil }
        if contextPercent != nil { contextPercent = nil }
        statusMenuOpen = false
        notesOpen = false
    }
}

#if ORCH_SNAPSHOT
extension OrchestratorManager {
    /// Snapshot harness only (Orchestrator/Snapshots): fixture responses through the real apply path.
    /// loaded false = connecting; chat nil = offline.
    func snapshotApply(loaded: Bool, chat: ChatResponse?, state: StateResponse, runsBoard: Bool = false) async {
        if hasLoaded != loaded { hasLoaded = loaded } // like the real path: an unchanged value must not publish
        if showRunsBoard != runsBoard { showRunsBoard = runsBoard }
        guard loaded else { return }
        if let chat { applyState(state); await applyChat(chat) } else { applyOffline() }
    }
    /// Send-path harness: behave as if the SSE stream is up (blocks arrive as events, not fetched per poll).
    func snapshotSetStreaming(_ on: Bool) { streaming = on }
}
#endif
