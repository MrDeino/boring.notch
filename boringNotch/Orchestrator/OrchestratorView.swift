import SwiftUI

/// Exposes the hosting NSWindow (read via `view.window` when needed).
struct WindowAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct OrchestratorView: View {
    @ObservedObject var expand = OrchestratorExpand.shared
    let manager = OrchestratorManager.shared
    @StateObject private var slice = ModelSlice.view
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var runLog = OrchestratorRunLog.shared
    @ObservedObject var bgCard = OrchestratorBgCard.shared
    @State private var anchor = NSView()
    @State private var restoreLevel: ExpandLevel?
    @State private var escMonitor: Any?

    /// The log opens over the content: the open level grows to expanded first and returns on close.
    /// The run log or a background card is up over the content.
    private var overlayID: String? { runLog.runID ?? bgCard.selectedID }
    private func closeOverlay() { runLog.close(); bgCard.close() }

    private func logChanged(_ id: String?) {
        if id != nil {
            guard restoreLevel == nil else { return }
            restoreLevel = expand.level(for: vm)
            if restoreLevel == .open { expand.setLevel(.expanded, vm: vm, window: anchor.window) }
            if escMonitor == nil {
                escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    guard event.keyCode == 53, event.window === anchor.window else { return event }
                    closeOverlay()
                    return nil
                }
            }
        } else {
            if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
            if let r = restoreLevel, r != expand.level(for: vm) { expand.setLevel(r, vm: vm, window: anchor.window) }
            restoreLevel = nil
        }
    }

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
        .allowsHitTesting(!manager.statusMenuOpen && !manager.notesOpen && overlayID == nil)
        .overlay(alignment: .topTrailing) {
            if runLog.runID != nil {
                ZStack {
                    Color.clear.contentShape(Rectangle()).onTapGesture { runLog.close() }
                    OrchestratorRunLogOverlay().transition(.opacity)
                }
            } else if bgCard.selectedID != nil {
                ZStack {
                    Color.clear.contentShape(Rectangle()).onTapGesture { bgCard.close() }
                    OrchestratorBgCardView().transition(.opacity)
                }
            } else if manager.notesOpen {
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
        // The tab takes file drops anywhere (the composer's own onDrop wins over it); the shelf never sees them here.
        .onDrop(of: [.image, .fileURL, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            return orchestratorHandleDrop(providers) { _ in }
        }
        .onAppear { expand.tabOpened(vm: vm, anchor: anchor) }
        .onChange(of: overlayID) { _, id in logChanged(id) }
        // The log lives on the expanded level: leaving it (outside click, back) must not strand an overlay whose
        // content keeps the window from shrinking to the open size.
        .onChange(of: expand.level(for: vm)) { _, l in if l == .open && overlayID != nil { restoreLevel = nil; closeOverlay() } }
        .onDisappear {
            expand.tabClosed(vm: vm)
            OrchestratorNotesStore.shared.flush(); manager.statusMenuOpen = false; manager.notesOpen = false
            closeOverlay()
            if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
            restoreLevel = nil
        }
    }
}
