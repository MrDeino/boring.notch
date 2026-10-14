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
                HStack(alignment: .top, spacing: 12) {
                    chat
                    VStack(alignment: .leading, spacing: 10) {
                        usageBars
                        runsStrip
                    }
                    .frame(width: 200, alignment: .topLeading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    @ViewBuilder private var chat: some View {
        if !manager.chatRunning {
            Text("chat not running").font(.system(size: 11)).foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(chatTail(screen: manager.screen, maxLines: 8).enumerated()), id: \.offset) { _, line in
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

    private var usageBars: some View {
        VStack(alignment: .leading, spacing: 6) {
            usageRow("5h", manager.usage?.fiveHour) { $0.formatted(date: .omitted, time: .shortened) }
            usageRow("7d", manager.usage?.sevenDay) { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        }
    }

    private func usageRow(_ title: String, _ w: UsageWindow?, reset: (Date) -> String) -> some View {
        let pct = w?.usedPercentage
        let frac = min(max((pct ?? 0) / 100, 0), 1)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: title).foregroundStyle(.white)
                Text(verbatim: pct.map { "\(Int($0.rounded()))%" } ?? "—").foregroundStyle(.gray)
                Spacer()
                Text(verbatim: "resets " + (w?.resetsDate.map(reset) ?? "—")).foregroundStyle(.gray)
            }
            .font(.system(size: 10))
            Capsule().fill(Color(nsColor: .secondarySystemFill)).frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        Capsule().fill(frac >= 0.8 ? Color.orange : Color.white.opacity(0.8))
                            .frame(width: g.size.width * frac)
                    }
                }
        }
    }

    private var runsStrip: some View {
        VStack(alignment: .leading, spacing: 3) {
            let runs = stripRuns(manager.runs, limit: 3)
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
