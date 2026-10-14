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
    @ObservedObject var manager = OrchestratorManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @State private var anchor = NSView()

    private func close() { withAnimation(.easeOut(duration: 0.15)) { manager.statusMenuOpen = false } }

    var body: some View {
        Group {
            if expand.level(for: vm) != .open {
                OrchestratorExpandedView()
            } else {
                OrchestratorTabContent()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(manager.statusMenuOpen ? 0.35 : 1)
        .allowsHitTesting(!manager.statusMenuOpen)
        .overlay(alignment: .topTrailing) {
            if manager.statusMenuOpen {
                ZStack(alignment: .topTrailing) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                    OrchestratorStatusMenu(openTerminal: {
                        OrchestratorExpand.shared.setLevel(.terminal, vm: vm, window: anchor.window)
                    })
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            }
        }
        .background(WindowAnchor(view: anchor))
        .onDisappear { manager.statusMenuOpen = false }
    }
}
