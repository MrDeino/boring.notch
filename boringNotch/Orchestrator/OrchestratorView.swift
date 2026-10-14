import SwiftUI

/// Exposes the hosting NSWindow (read via `view.window` when needed).
struct WindowAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The state switch. Runs board is checked before stopped so "see Runs" works while the chat is stopped.
struct OrchestratorTabContent: View {
    @ObservedObject var manager = OrchestratorManager.shared

    var body: some View {
        Group {
            if !manager.hasLoaded {
                OrchestratorConnectingView()
            } else if manager.offline {
                OrchestratorOfflineView()
            } else if manager.showRunsBoard {
                OrchestratorRunsBoard()
            } else if !manager.chatRunning {
                OrchestratorStoppedView()
            } else if manager.prompt != nil {
                OrchestratorPromptCard()
            } else {
                OrchestratorChatView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }
}

struct OrchestratorView: View {
    @ObservedObject var expand = OrchestratorExpand.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        Group {
            if expand.level(for: vm) != .open {
                OrchestratorExpandedView()
            } else {
                OrchestratorTabContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                manager.showRunsBoard = true
            } else {
                manager.showRunsBoard.toggle()
            }
        } label: {
            Capsule()
                .fill(.black)
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "list.bullet.rectangle")
                        .foregroundColor(manager.showRunsBoard ? .white : .gray)
                        .imageScale(.medium)
                }
        }
        .buttonStyle(PlainButtonStyle())
        .help("Runs")
    }
}

/// Header Start/End icon next to the runs button; End asks Yes/No first.
struct OrchestratorChatButton: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var confirmEnd = false

    var body: some View {
        if manager.hasLoaded && !manager.offline {
            if confirmEnd {
                HStack(spacing: 4) {
                    Text("End chat?").foregroundStyle(.orange)
                    Button("Yes") { confirmEnd = false; Task { await manager.stopChat() } }
                    Button("No") { confirmEnd = false }
                }
                .font(.system(size: 10))
                .controlSize(.small)
            } else {
                Button {
                    if manager.chatRunning {
                        confirmEnd = true
                        Task { try? await Task.sleep(for: .seconds(4)); confirmEnd = false }
                    } else {
                        Task { await manager.startChat() }
                    }
                } label: {
                    Capsule()
                        .fill(.black)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: manager.chatRunning ? "stop.circle" : "play.circle")
                                .foregroundColor(.gray)
                                .imageScale(.medium)
                        }
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(manager.sending)
                .help(manager.chatRunning ? "End chat" : "Start chat")
            }
        }
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
