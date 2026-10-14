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
        // The sticky Runs board must not hide a live prompt or outlive a disconnect.
        .onChange(of: manager.prompt != nil) { _, has in if has { manager.showRunsBoard = false } }
        .onChange(of: manager.offline) { _, off in if off { manager.showRunsBoard = false } }
    }
}

struct OrchestratorView: View {
    @ObservedObject var expand = OrchestratorExpand.shared
    @ObservedObject var manager = OrchestratorManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @State private var anchor = NSView()

    @State private var notesGrew = false
    @State private var bodyHeight: CGFloat = 999

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) {
            if manager.notesOpen { OrchestratorNotesStore.shared.flush() }
            manager.statusMenuOpen = false; manager.notesOpen = false
        }
    }

    var body: some View {
        Group {
            if expand.level(for: vm) != .open {
                OrchestratorExpandedView()
            } else {
                OrchestratorTabContent()
            }
        }
        // minHeight 0: take exactly the space under the header. A taller body would otherwise make the
        // notch's fixed-height frame centre it, pushing the header and the composer out of the notch.
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .background(GeometryReader { g in Color.clear.onAppear { bodyHeight = g.size.height }.onChange(of: g.size.height) { _, h in bodyHeight = h } })
        .opacity(manager.statusMenuOpen || manager.notesOpen ? 0.35 : 1)
        .allowsHitTesting(!manager.statusMenuOpen && !manager.notesOpen)
        .overlay(alignment: .topTrailing) {
            if manager.notesOpen {
                ZStack(alignment: .topTrailing) {
                    Color.clear.contentShape(Rectangle()).onTapGesture { close() }
                    OrchestratorNotesPanel(close: close)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                }
            } else if manager.statusMenuOpen {
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
        .onChange(of: manager.notesOpen) { _, open in
            // Grow only when the open level lacks room for a usable editor; undo only what we grew.
            if open, expand.level(for: vm) == .open, bodyHeight < 130 {
                expand.setLevel(.expanded, vm: vm, window: anchor.window); notesGrew = true
            } else if !open, notesGrew {
                notesGrew = false; expand.setLevel(.open, vm: vm, window: anchor.window)
            }
        }
        .onDisappear { OrchestratorNotesStore.shared.flush(); manager.statusMenuOpen = false; manager.notesOpen = false }
    }
}
