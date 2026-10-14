import AppKit

@MainActor
final class OrchestratorManager: ObservableObject {
    static let shared = OrchestratorManager()
    static let baseURL = URL(string: "http://127.0.0.1:4777")!

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
    @Published private(set) var prompt: PromptCard? = nil
    @Published private(set) var liveStatus: LiveStatus? = nil
    var capsuleStatus: CapsuleState {
        capsuleState(hasLoaded: hasLoaded, offline: offline, chatRunning: chatRunning, needsAttention: needsAttention, working: liveStatus != nil)
    }

    /// Fed by notch open/close hooks; opening triggers an immediate refresh.
    var notchOpen = false {
        didSet {
            // Typing teardown is owned by OrchestratorView (close() is blocked while typing).
            if notchOpen && !oldValue { Task { await refresh() } }
            if !notchOpen { OrchestratorExpand.shared.reset(); statusMenuOpen = false }
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
        if code == 200 { await refresh(); return true }
        if code == 409 { await refresh() }
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
            guard (try? await sendOrchestratorPost(.key(k), base: Self.baseURL, session: session)) == 200 else { await refresh(); return false }
        }
        await refresh()
        return true
    }

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 3
        c.timeoutIntervalForResource = 5
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()
    private var pollTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let secs = pollInterval(notchOpen: self.notchOpen, chatRunning: self.chatRunning, offline: self.offline)
                try? await Task.sleep(for: .seconds(secs))
            }
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
        do {
            async let chat: ChatResponse = get("api/chat")
            async let state: StateResponse = get("api/state")
            let (r, st) = try await (chat, state)
            await apply(r, st)
        } catch {
            applyOffline()
        }
        if !hasLoaded { hasLoaded = true }
    }

    private func apply(_ r: ChatResponse, _ st: StateResponse) async {
        if offline { offline = false }
        let running = r.running ?? false
        if chatRunning != running { chatRunning = running }
        let s = r.screen ?? ""
        if screen != s { screen = s }
        let rs = st.runs ?? []
        if runs != rs { runs = rs }
        if usage != st.usage { usage = st.usage }
        let po = running ? detectPrompt(screen: s) : []
        if promptOptions != po { promptOptions = po }
        let pc = running ? detectPromptCard(screen: s) : nil
        if prompt != pc { prompt = pc }
        let ls = running ? parseLiveStatus(screen: s) : nil
        if liveStatus != ls { liveStatus = ls }
        await OrchestratorTranscriptStore.shared.refresh(base: Self.baseURL, session: session, screen: s, chatRunning: running)
    }

    private func applyOffline() {
        if !offline { offline = true }
        if !runs.isEmpty { runs = [] }
        if !promptOptions.isEmpty { promptOptions = [] }
        if prompt != nil { prompt = nil }
        if liveStatus != nil { liveStatus = nil }
        statusMenuOpen = false
    }
}

#if ORCH_SNAPSHOT
extension OrchestratorManager {
    /// Snapshot harness only (Orchestrator/Snapshots): fixture responses through the real apply path.
    /// loaded false = connecting; chat nil = offline.
    func snapshotApply(loaded: Bool, chat: ChatResponse?, state: StateResponse, runsBoard: Bool = false) async {
        hasLoaded = loaded
        showRunsBoard = runsBoard
        guard loaded else { return }
        if let chat { await apply(chat, state) } else { applyOffline() }
    }
}
#endif
