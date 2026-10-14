import SwiftUI

// Phase 7 owns this file; Phase 4 holds today's runs strip as full tab content.
struct OrchestratorRunsBoard: View {
    @ObservedObject var manager = OrchestratorManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 3) {
                let runs = stripRuns(manager.runs, limit: 6)
                if runs.isEmpty {
                    Text("no runs").font(.system(size: 10)).foregroundStyle(OT.C.text5)
                }
                ForEach(runs, id: \.stableID) { r in
                    HStack(spacing: 5) {
                        Circle().fill(color(r.state)).frame(width: 6, height: 6)
                        Text(verbatim: r.project ?? "?").foregroundStyle(OT.C.text)
                        Text(verbatim: r.shortPrompt).foregroundStyle(OT.C.text5)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .font(.system(size: 10))
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func color(_ state: String?) -> Color {
        switch state {
        case "running": return OT.C.green
        case "waiting": return OT.C.orange
        case "failed", "stuck": return OT.C.red
        default: return OT.C.text5
        }
    }
}
