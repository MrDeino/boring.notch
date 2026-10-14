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
    /// Runs panel toggled by the header button.
    @Published var showRuns = false

    /// Fed by notch open/close hooks; opening triggers an immediate refresh.
    var notchOpen = false {
        didSet {
            if notchOpen && !oldValue { Task { await refresh() } }
            if !notchOpen { endTyping() }
        }
    }

    @Published private(set) var wantsKeyboard = false
    @Published private(set) var sending = false
    @Published private(set) var optionsLocked = false
    private var typing = false
    private var lockGen = 0

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
        let code = (try? await sendOrchestratorPost(p, base: Self.baseURL, session: session)) ?? nil
        if code == 200 { await refresh(); return true }
        if code == 409 { await refresh() }
        return false
    }

    func sendText(_ s: String) async -> Bool { await post(.text(s)) }
    /// Debounced: Esc-Esc opens Claude Code's rewind picker.
    func pressEscape() async {
        guard Date().timeIntervalSince(lastEscape) > 1 else { return }
        lastEscape = Date()
        await post(.key("Escape"))
    }
    private var lastEscape = Date.distantPast
    func startChat() async { await post(.start) }
    func stopChat() async { await post(.stop) }

    func pressOption(_ n: Int) {
        guard !optionsLocked, (1...9).contains(n) else { return }
        optionsLocked = true
        lockGen += 1
        let gen = lockGen
        Task {
            await post(.key(String(n)))
            try? await Task.sleep(for: .seconds(3))
            if lockGen == gen { optionsLocked = false }
        }
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
                let secs = self.notchOpen ? 2 : 10
                try? await Task.sleep(for: .seconds(secs))
            }
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, resp) = try await session.data(from: Self.baseURL.appendingPathComponent(path))
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private var refreshing = false

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            async let chat: ChatResponse = get("api/chat")
            async let state: StateResponse = get("api/state")
            let (r, st) = try await (chat, state)
            if offline { offline = false }
            let running = r.running ?? false
            if chatRunning != running { chatRunning = running }
            let s = r.screen ?? ""
            if screen != s { screen = s }
            let rs = st.runs ?? []
            if runs != rs { runs = rs }
            if usage != st.usage { usage = st.usage }
            let po = running ? detectPrompt(screen: s) : []
            if promptOptions != po { promptOptions = po; optionsLocked = false }
        } catch {
            if !offline { offline = true }
            if !runs.isEmpty { runs = [] }
            if !promptOptions.isEmpty { promptOptions = [] }
        }
        if !hasLoaded { hasLoaded = true }
    }
}
