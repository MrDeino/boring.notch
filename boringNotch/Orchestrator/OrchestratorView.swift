import SwiftUI

struct OrchestratorView: View {
    @ObservedObject var manager = OrchestratorManager.shared

    var body: some View {
        Group {
            if !manager.hasLoaded {
                Text("connecting…").font(.system(size: 11)).foregroundStyle(.gray)
            } else if manager.offline {
                VStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.circle").font(.system(size: 22)).foregroundStyle(.gray)
                    Text("orchestrator offline").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    Text("start `node orch.js serve` · 127.0.0.1:4777").font(.system(size: 11)).foregroundStyle(.gray)
                }
            } else {
                chat
                    .overlay(alignment: .topTrailing) {
                        if manager.showRuns {
                            runsStrip
                                .frame(width: 200, alignment: .topLeading)
                                .padding(8)
                                .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15)))
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
        .overlay { OrchestratorExpandOverlay() }
    }

    @ViewBuilder private var chat: some View {
        if !manager.chatRunning {
            Text("chat not running").font(.system(size: 11)).foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(chatTail(screen: manager.screen, maxLines: 10).enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    private var runsStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            let runs = stripRuns(manager.runs, limit: 6)
            if runs.isEmpty {
                Text("no runs").font(.system(size: 10)).foregroundStyle(.gray)
            }
            ForEach(runs, id: \.stableID) { r in
                HStack(spacing: 5) {
                    Circle().fill(color(r.state)).frame(width: 6, height: 6)
                    Text(verbatim: r.project ?? "?").foregroundStyle(.white)
                    Text(verbatim: r.shortPrompt).foregroundStyle(.gray)
                        .lineLimit(1).truncationMode(.tail)
                }
                .font(.system(size: 10))
                .lineLimit(1)
            }
        }
    }

    private func color(_ state: String?) -> Color {
        switch state {
        case "running": return .green
        case "waiting": return .orange
        case "failed", "stuck": return .red
        default: return .gray
        }
    }
}

/// Header button that shows/hides the runs panel; from another tab it jumps to Orchestrator first.
struct OrchestratorRunsButton: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        Button {
            if coordinator.currentView != .orchestrator {
                coordinator.currentView = .orchestrator
                manager.showRuns = true
            } else {
                manager.showRuns.toggle()
            }
        } label: {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(manager.showRuns ? .white : .gray)
                        .imageScale(.medium)
                }
        }
        .buttonStyle(PlainButtonStyle())
        .help("Runs")
    }
}

/// Tiny 5h/7d usage in the open-notch header; hover swaps in reset times.
struct OrchestratorUsageBadge: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var hovering = false

    var body: some View {
        if let u = manager.usage {
            VStack(alignment: .trailing, spacing: 0) {
                row("5h", u.fiveHour) { $0.formatted(date: .omitted, time: .shortened) }
                row("7d", u.sevenDay) { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .monospacedDigit()
            .padding(.trailing, 4)
            .onHover { hovering = $0 }
        }
    }

    private func row(_ title: String, _ w: UsageWindow?, reset: (Date) -> String) -> some View {
        let pct = w?.usedPercentage
        let text = hovering
            ? (w?.resetsDate.map(reset) ?? "—")
            : (pct.map { "\(Int($0.rounded()))%" } ?? "—")
        return HStack(spacing: 3) {
            Text(verbatim: title).foregroundStyle(.gray)
            Text(verbatim: text).foregroundStyle((pct ?? 0) >= 80 ? Color.orange : Color.white)
        }
    }
}
