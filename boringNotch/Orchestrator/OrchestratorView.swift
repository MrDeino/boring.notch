import SwiftUI

/// Exposes the hosting NSWindow (read via `view.window` when needed).
struct WindowAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct OrchestratorView: View {
    @ObservedObject var expand = OrchestratorExpand.shared
    @ObservedObject var manager = OrchestratorManager.shared
    @EnvironmentObject var vm: BoringViewModel
    @State private var anchor = NSView()

    private func close() {
        withAnimation(.easeOut(duration: 0.15)) {
            if manager.notesOpen { OrchestratorNotesStore.shared.flush() }
            manager.statusMenuOpen = false; manager.notesOpen = false
        }
    }

    var body: some View {
        OrchestratorExpandedView()
        // minHeight 0: take exactly the space under the header. A taller body would otherwise make the
        // notch's fixed-height frame centre it, pushing the header and the composer out of the notch.
        .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
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
        .onDisappear { OrchestratorNotesStore.shared.flush(); manager.statusMenuOpen = false; manager.notesOpen = false }
    }
}
