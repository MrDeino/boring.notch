import SwiftUI

// Phase 7 owns; Plan 04-02 sets today's behaviour.
struct OrchestratorExpandedView: View {
    var body: some View { OrchestratorTabContent().overlay { OrchestratorExpandOverlay() } }
}
