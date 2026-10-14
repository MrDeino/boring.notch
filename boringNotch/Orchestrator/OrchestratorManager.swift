import Foundation

@MainActor
final class OrchestratorManager: ObservableObject {
    static let shared = OrchestratorManager()
    static let baseURL = URL(string: "http://127.0.0.1:4777")!

    @Published private(set) var offline = false
    @Published private(set) var chatRunning = false
    @Published private(set) var screen = ""
    /// False until the first response or error, so the view doesn't flash "offline".
    @Published private(set) var hasLoaded = false

    /// Fed by BoringViewModel open()/close(); opening triggers an immediate refresh.
    var notchOpen = false {
        didSet { if notchOpen && !oldValue { Task { await refresh() } } }
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

    func refresh() async {
        do {
            let r: ChatResponse = try await get("api/chat")
            if offline { offline = false }
            let running = r.running ?? false
            if chatRunning != running { chatRunning = running }
            let s = r.screen ?? ""
            if screen != s { screen = s }
        } catch {
            if !offline { offline = true }
        }
        if !hasLoaded { hasLoaded = true }
    }
}
