import SwiftUI

// Phase 5 owns this file.
@MainActor
final class OrchestratorTranscriptStore: ObservableObject {
    static let shared = OrchestratorTranscriptStore()

    /// Phase 5 fills the body; the call site in OrchestratorManager.refresh() is shared with Phase 6.
    func refresh(base: URL, session: URLSession, screen: String, chatRunning: Bool) async {}
}
