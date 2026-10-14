import SwiftUI

/// Per-screen expand-down state for the Orchestrator tab (Phase 3).
/// While expanded, one SharingStateManager interaction keeps the notch from auto-closing.
@MainActor
final class OrchestratorExpand: ObservableObject {
    static let shared = OrchestratorExpand()

    @Published private(set) var expanded: Set<ObjectIdentifier> = []
    private var extra: [ObjectIdentifier: CGFloat] = [:]
    private var windows: [ObjectIdentifier: WeakWindow] = [:]
    private var shrinkTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var vms: [ObjectIdentifier: WeakVM] = [:]
    private final class WeakVM { weak var vm: BoringViewModel?; init(_ v: BoringViewModel) { vm = v } }
    private final class WeakWindow { weak var w: NSWindow?; init(_ w: NSWindow?) { self.w = w } }

    // Keyed by view model, not screenUUID: single-display mode reassigns the UUID on screen changes.
    private func key(_ vm: BoringViewModel) -> ObjectIdentifier { ObjectIdentifier(vm) }

    func isExpanded(_ vm: BoringViewModel) -> Bool { expanded.contains(key(vm)) }

    func openSize(for vm: BoringViewModel) -> CGSize {
        CGSize(width: openNotchSize.width, height: openNotchSize.height + (extra[key(vm)] ?? 0))
    }

    func expand(vm: BoringViewModel, window: NSWindow?) {
        let k = key(vm)
        guard !expanded.contains(k), let window else { return }
        let e = expandedExtra(screenHeight: window.screen?.frame.height ?? 900, openHeight: openNotchSize.height)
        extra[k] = e
        windows[k] = WeakWindow(window)
        if let a = NSWorkspace.shared.frontmostApplication, a != NSRunningApplication.current { previousApp = a }
        shrinkTasks[k]?.cancel()
        window.setFrame(pinnedFrame(current: window.frame, newHeight: windowHeight(base: windowSize.height, notchHeight: openNotchSize.height + e, openHeight: openNotchSize.height)), display: true)
        expanded.insert(k)
        vms[k] = WeakVM(vm)
        installMonitors()
        SharingStateManager.shared.beginInteraction()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { vm.notchSize = openSize(for: vm) }
    }

    func collapse(vm: BoringViewModel, refocus: Bool = true) {
        let k = key(vm)
        guard expanded.contains(k) else { return }
        let win = windows[k]?.w
        finish(k, refocus: refocus)
        if vm.notchState == .open { withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { vm.notchSize = openNotchSize } }
        shrinkTasks[k]?.cancel()
        // Let the spring finish before the window stops covering the expanded area.
        shrinkTasks[k] = Task { [weak win] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let win else { return }
            win.setFrame(pinnedFrame(current: win.frame, newHeight: windowSize.height), display: true)
        }
    }

    /// Notch closed or tab left: collapse everything now, no animation.
    func reset() {
        guard !expanded.isEmpty else { return }
        for k in Array(expanded) {
            shrinkTasks[k]?.cancel()
            let win = windows[k]?.w
            let vm = vms[k]?.vm
            finish(k)
            if let vm, vm.notchState == .open { vm.notchSize = openNotchSize }
            win?.setFrame(pinnedFrame(current: win?.frame ?? .zero, newHeight: windowSize.height), display: true)
        }
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Global = click in another app, which takes focus itself; don't hand it back to previousApp.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.collapseIfOutside(refocus: false) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            Task { @MainActor in self?.collapseIfOutside(refocus: true) }
            return e
        }
    }

    private func removeMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil; localMonitor = nil
    }

    /// Outside click: collapse, then close the notch (keep-open is released by collapse).
    private func collapseIfOutside(refocus: Bool) {
        let p = NSEvent.mouseLocation
        let outside = expanded.compactMap { k -> BoringViewModel? in
            guard let vm = vms[k]?.vm, let w = windows[k]?.w,
                  isOutsideNotch(point: p, windowFrame: w.frame, notchWidth: vm.notchSize.width, notchHeight: vm.notchSize.height) else { return nil }
            return vm
        }
        // Collapse all first: close() is blocked while any keep-open session is still active.
        for vm in outside { collapse(vm: vm, refocus: refocus) }
        for vm in outside { vm.close() }
    }

    /// Shared bookkeeping: exactly one endInteraction per expand.
    private func finish(_ k: ObjectIdentifier, refocus: Bool = true) {
        expanded.remove(k)
        releaseKey(windows[k]?.w, refocus: refocus)
        extra[k] = nil
        if expanded.isEmpty { removeMonitors() }
        SharingStateManager.shared.endInteraction()
    }

    /// Give keyboard focus back: resignKey() is only a notification hook, so drop the
    /// first responder and reactivate the app that was frontmost when we expanded.
    func releaseKey(_ w: NSWindow?, refocus: Bool = true) {
        OrchestratorKeyGate.terminalWantsKey = false
        guard let w, w.isKeyWindow else { return }
        w.makeFirstResponder(nil)
        if refocus { previousApp?.activate() }
    }
}

struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onWindow(v.window) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) { DispatchQueue.main.async { onWindow(v.window) } }
}

struct OrchestratorExpandOverlay: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var expand = OrchestratorExpand.shared
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var window: NSWindow?
    @State private var termState: TerminalState = .connecting
    @State private var termID = UUID()

    var body: some View {
        let isExp = expand.isExpanded(vm)
        ZStack(alignment: .bottomTrailing) {
            if isExp {
                Color.black
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(chatTail(screen: manager.screen, maxLines: 28).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(8)
                if termState == .connecting || termState == .connected {
                    OrchestratorTerminalView(state: $termState).id(termID).background(Color.black)
                } else {
                    HStack(spacing: 8) {
                        Text(termState == .inUse ? "terminal in use" : "terminal unavailable")
                            .font(.system(size: 11)).foregroundStyle(.white)
                        Button("Retry") { termState = .connecting; termID = UUID() }
                    }
                    .padding(6).background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(8)
                }
            }
            if isExp || (manager.hasLoaded && !manager.offline) {
                Button {
                    isExp ? expand.collapse(vm: vm) : expand.expand(vm: vm, window: window)
                } label: {
                    Image(systemName: isExp ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12)).foregroundStyle(.gray).padding(6)
                }
                .buttonStyle(.plain)
            }
        }
        .background(WindowAccessor { window = $0 })
        // Pins the button bottom-trailing; the empty frame area has no hit shape, so chat clicks pass through.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .onChange(of: isExp) { _, on in if on { termState = .connecting; termID = UUID() } }
        .onDisappear { expand.reset() }
    }
}
