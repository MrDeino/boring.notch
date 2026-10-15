import SwiftUI
import os

/// Perf probes for the click->collapse path (Instruments > os_signpost; `log stream --predicate 'subsystem == "boringnotch.orch"'`).
let orchPerf = OSSignposter(subsystem: "boringnotch.orch", category: "perf")
private let orchLog = Logger(subsystem: "boringnotch.orch", category: "perf")

/// Per-screen expand-down state for the Orchestrator tab (Phase 3).
/// While expanded, one SharingStateManager interaction keeps the notch from auto-closing.
@MainActor
final class OrchestratorExpand: ObservableObject {
    static let shared = OrchestratorExpand()

    @Published private(set) var expanded: Set<ObjectIdentifier> = []
    /// Per-vm terminal flag, always a subset of `expanded`.
    @Published private(set) var terminal: Set<ObjectIdentifier> = []
    private var sizes: [ObjectIdentifier: CGSize] = [:]
    /// Extra open-level height asked for by content (composer lines, notes text, prompt context), per source.
    private var fits: [ObjectIdentifier: [String: CGFloat]] = [:]
    private var windows: [ObjectIdentifier: WeakWindow] = [:]
    private var shrinkTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var vms: [ObjectIdentifier: WeakVM] = [:]
    private final class WeakVM { weak var vm: BoringViewModel?; init(_ v: BoringViewModel) { vm = v } }
    private final class WeakWindow { weak var w: NSWindow?; init(_ w: NSWindow?) { self.w = w } }

    // Keyed by view model, not screenUUID: single-display mode reassigns the UUID on screen changes.
    private func key(_ vm: BoringViewModel) -> ObjectIdentifier { ObjectIdentifier(vm) }

    func isExpanded(_ vm: BoringViewModel) -> Bool { expanded.contains(key(vm)) }

    func openSize(for vm: BoringViewModel) -> CGSize {
        let k = key(vm)
        return sizes[k] ?? CGSize(width: openNotchSize.width, height: openNotchSize.height + fitHeight(k))
    }

    /// Current extra height of one source (so a view can exclude its own fit when measuring).
    func fit(_ source: String, vm: BoringViewModel) -> CGFloat { fits[key(vm)]?[source] ?? 0 }

    private func fitHeight(_ k: ObjectIdentifier) -> CGFloat {
        let screen = windows[k]?.w?.screen?.frame.size ?? CGSize(width: 1440, height: 900)
        let maxFit = expandedSize(screen: screen, openWidth: openNotchSize.width).height - openNotchSize.height
        return min(maxFit, fits[k]?.values.max() ?? 0)
    }

    /// Content at the open level asks for `extra` more height than openNotchSize (capped at the expanded height).
    /// The window grows first, the notch springs after; shrinking waits for the spring.
    func setFit(_ source: String, extra: CGFloat, vm: BoringViewModel, window: NSWindow?) {
        let k = key(vm)
        let e = max(0, extra.rounded())
        guard fits[k]?[source] ?? 0 != e else { return }
        fits[k, default: [:]][source] = e
        if let window { windows[k] = WeakWindow(window) }
        vms[k] = WeakVM(vm)
        guard level(for: vm) == .open, vm.notchState == .open else { return }
        let target = openSize(for: vm)
        guard target.height != vm.notchSize.height else { return }
        animate(vm, to: target)
    }

    /// The one notch-size change: model first, then the window (grow now so the spring has room; shrink is deferred in syncWindow).
    private func animate(_ vm: BoringViewModel, to target: CGSize) {
        // Window first (outside the animation): a window resize that lands in the spring's transaction makes SwiftUI
        // animate the root from the centre of the new window to the top (the "fills in from the middle" regression).
        syncWindow(vm: vm, size: target)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { vm.notchSize = target }
        syncWindow(vm: vm)
    }

    /// The only place the panel is resized: it follows vm.notchSize (never below windowSize), top edge and centre pinned.
    /// Growing is immediate; shrinking waits for the spring, then re-reads the current target.
    func syncWindow(vm: BoringViewModel, window: NSWindow? = nil, now: Bool = false, size: CGSize? = nil) {
        let k = key(vm)
        if let window { windows[k] = WeakWindow(window) }
        guard let w = window ?? windows[k]?.w ?? anchors[k]?.view.v?.window else { return }
        if windows[k]?.w == nil { windows[k] = WeakWindow(w) }
        func target() -> CGSize { panelSize(notch: vm.notchSize, base: windowSize, openHeight: openNotchSize.height) }
        let t = size.map { panelSize(notch: $0, base: windowSize, openHeight: openNotchSize.height) } ?? target(), f = w.frame.size
        if size != nil { // pre-spring call: only ever grows; the shrink is scheduled by the call after the model change
            if t.width > f.width || t.height > f.height { w.setFrame(pinnedFrame(current: w.frame, newSize: CGSize(width: max(t.width, f.width), height: max(t.height, f.height))), display: true) }
            return
        }
        shrinkTasks[k]?.cancel()
        if now { if t != f { w.setFrame(pinnedFrame(current: w.frame, newSize: t), display: true) }; return }
        if t.width > f.width || t.height > f.height {
            w.setFrame(pinnedFrame(current: w.frame, newSize: CGSize(width: max(t.width, f.width), height: max(t.height, f.height))), display: true)
        }
        guard t.width < f.width || t.height < f.height else { return }
        shrinkTasks[k] = Task { [weak w] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled, let w else { return }
            w.setFrame(pinnedFrame(current: w.frame, newSize: target()), display: true)
        }
    }

    func level(for vm: BoringViewModel) -> ExpandLevel {
        let k = key(vm)
        return terminal.contains(k) ? .terminal : expanded.contains(k) ? .expanded : .open
    }

    func setLevel(_ target: ExpandLevel, vm: BoringViewModel, window: NSWindow?) {
        let k = key(vm)
        let w = window ?? windows[k]?.w
        let cur = level(for: vm)
        guard target != cur else { return }
        switch target {
        case .open: collapse(vm: vm)
        case .expanded:
            if cur == .open { grow(vm, w) }
            if cur == .terminal { terminal.remove(k); releaseKey(w) }
        case .terminal:
            if cur == .open { grow(vm, w) }
            if expanded.contains(k) { terminal.insert(k) }
        }
    }

    func back(_ vm: BoringViewModel) { setLevel(nextLevel(level(for: vm), .back), vm: vm, window: nil) }

    /// Phase 7: tapping the transcript expands (the terminal is reached via Open terminal / ⌘T).
    func transcriptTapped(vm: BoringViewModel, window: NSWindow?) { setLevel(.expanded, vm: vm, window: window) }

    private final class WeakView { weak var v: NSView?; init(_ v: NSView) { self.v = v } }
    private var anchors: [ObjectIdentifier: (vm: WeakVM, view: WeakView)] = [:]
    private var keyMonitor: Any?

    /// Lets ⌘↓ find the notch window while still at level .open.
    func register(vm: BoringViewModel, anchor: NSView) { anchors[key(vm)] = (WeakVM(vm), WeakView(anchor)) }

    /// The notch is open on the Orchestrator tab: an outside click closes it at once, even while the composer holds a
    /// typing interaction (which makes the upstream hover-exit close refuse). Other tabs keep the upstream behaviour.
    private var openTabs: [ObjectIdentifier: WeakVM] = [:]
    func tabOpened(vm: BoringViewModel, anchor: NSView) {
        register(vm: vm, anchor: anchor)
        openTabs[key(vm)] = WeakVM(vm)
        installMonitors()
    }
    func tabClosed(vm: BoringViewModel) {
        openTabs[key(vm)] = nil
        if expanded.isEmpty && openTabs.isEmpty { removeMonitors() }
    }

    private init() {
        // ⌘↓/⌘↑/⌘T/⌘\ only while the notch panel is key (typing or terminal); a level change remounts the chat and ends typing (Phase 4 shell swap).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            let cmd = isCommandOnly(e.modifierFlags.rawValue)
            guard let sc = shortcut(keyCode: e.keyCode, chars: e.charactersIgnoringModifiers, commandOnly: cmd) else { return e }
            let handled = MainActor.assumeIsolated { self?.handle(sc, window: e.window) ?? false }
            return handled ? nil : e
        }
    }

    private func handle(_ sc: OrchShortcut, window: NSWindow?) -> Bool {
        guard let window, BoringViewCoordinator.shared.currentView == .orchestrator else { return false }
        let vm = anchors.values.first { $0.view.v?.window === window }?.vm.vm
            ?? vms.values.first { v in v.vm.flatMap { windows[key($0)]?.w } === window }?.vm
        guard let vm else { return false }
        let cur = level(for: vm)
        let next: ExpandLevel
        switch sc {
        case .deeper: next = nextLevel(cur, .deeper)
        case .back: next = nextLevel(cur, .back)
        case .terminal: next = .terminal
        case .toggleRail:
            guard cur != .open else { return false }
            OrchestratorRailState.shared.toggle()
            return true
        }
        // No-op shortcuts pass through (⌘↑ in the composer, ⌘↓/⌘T inside ttyd).
        guard next != cur else { return false }
        setLevel(next, vm: vm, window: window)
        return true
    }

    private func grow(_ vm: BoringViewModel, _ window: NSWindow?) {
        let k = key(vm)
        guard !expanded.contains(k), let window else { return }
        let size = expandedSize(screen: window.screen?.frame.size ?? CGSize(width: 1440, height: 900), openWidth: openNotchSize.width)
        sizes[k] = size
        windows[k] = WeakWindow(window)
        expanded.insert(k)
        vms[k] = WeakVM(vm)
        installMonitors()
        SharingStateManager.shared.beginInteraction()
        let sp = orchPerf.beginInterval("expand")
        animate(vm, to: openSize(for: vm))
        Task { try? await Task.sleep(for: .milliseconds(450)); orchPerf.endInterval("expand", sp) }
    }

    func collapse(vm: BoringViewModel, refocus: Bool = true) {
        let k = key(vm)
        guard expanded.contains(k) else { return }
        finish(k, refocus: refocus)
        if vm.notchState == .open { animate(vm, to: openSize(for: vm)) }
    }

    /// Notch closed or tab left: collapse everything now, no animation.
    func reset() {
        // Fits belong to the open notch; a closed notch starts from openNotchSize again.
        let fitted = fits.filter { $0.value.values.contains { $0 > 0 } }.keys
        fits = [:]
        for k in fitted where !expanded.contains(k) {
            if let vm = vms[k]?.vm {
                if vm.notchState == .open { vm.notchSize = openNotchSize }
                syncWindow(vm: vm, now: true)
            }
        }
        guard !expanded.isEmpty else { return }
        for k in Array(expanded) {
            let vm = vms[k]?.vm
            finish(k)
            if let vm {
                if vm.notchState == .open { vm.notchSize = openNotchSize }
                syncWindow(vm: vm, now: true)
            }
        }
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Both handlers run on the main thread: act in the same event turn, a Task hop would queue behind any SwiftUI render.
        // Global = click in another app, which takes focus itself; don't hand it back to previousApp.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] e in
            let p = e.locationInWindow, t = e.timestamp // window-less event: already screen coordinates
            MainActor.assumeIsolated { self?.collapseIfOutside(at: p, timestamp: t, refocus: false) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            let p = e.window.map { $0.convertPoint(toScreen: e.locationInWindow) } ?? NSEvent.mouseLocation, t = e.timestamp
            MainActor.assumeIsolated { self?.collapseIfOutside(at: p, timestamp: t, refocus: true) }
            return e
        }
    }

    /// Harness check: the click monitors must not outlive the open tab / expanded level.
    var monitorsActive: Bool { globalMonitor != nil }

    private func removeMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil; localMonitor = nil
    }

    /// Outside click: collapse, end typing, then close the notch (keep-open is released by collapse/endTyping).
    private func collapseIfOutside(at p: CGPoint, timestamp: TimeInterval, refocus: Bool) {
        func ms() -> Double { (ProcessInfo.processInfo.systemUptime - timestamp) * 1000 }
        orchLog.info("outsideClick handler \(ms(), format: .fixed(precision: 1)) ms after the event")
        orchPerf.emitEvent("outsideClick", "\(ms(), format: .fixed(precision: 1))ms")
        func outside(_ vm: BoringViewModel, _ k: ObjectIdentifier) -> Bool {
            guard let w = windows[k]?.w ?? anchors[k]?.view.v?.window else { return false }
            return isOutsideNotch(point: p, windowFrame: w.frame, notchWidth: vm.notchSize.width, notchHeight: vm.notchSize.height)
        }
        let hit = expanded.compactMap { k in vms[k]?.vm.flatMap { outside($0, k) ? $0 : nil } }
        let openHit = BoringViewCoordinator.shared.currentView == .orchestrator
            ? openTabs.compactMap { k, v in v.vm.flatMap { $0.notchState == .open && outside($0, k) ? $0 : nil } } : []
        let targets = hit + openHit.filter { o in !hit.contains { $0 === o } }
        guard !targets.isEmpty else { return }
        // Collapse and end typing first: close() is blocked while any keep-open session is still active.
        for vm in targets {
            orchPerf.emitEvent("collapseStart", "\(ms(), format: .fixed(precision: 1))ms")
            collapse(vm: vm, refocus: refocus)
            releaseKey(windows[key(vm)]?.w ?? anchors[key(vm)]?.view.v?.window, refocus: refocus)
        }
        OrchestratorManager.shared.endTyping()
        for vm in targets { orchPerf.emitEvent("closeStart", "\(ms(), format: .fixed(precision: 1))ms"); vm.close() }
    }

    /// Shared bookkeeping: exactly one endInteraction per expand.
    private func finish(_ k: ObjectIdentifier, refocus: Bool = true) {
        expanded.remove(k)
        terminal.remove(k)
        releaseKey(windows[k]?.w, refocus: refocus)
        sizes[k] = nil
        if expanded.isEmpty && openTabs.isEmpty { removeMonitors() }
        SharingStateManager.shared.endInteraction()
    }

    /// Give keyboard focus back: resignKey() is only a notification hook, so drop the
    /// first responder and reactivate the app that was frontmost before the terminal took focus.
    func releaseKey(_ w: NSWindow?, refocus: Bool = true) {
        OrchestratorKeyGate.terminalWantsKey = false
        guard let w, w.isKeyWindow else { return }
        w.makeFirstResponder(nil)
        OrchestratorKeyGate.restore(refocus: refocus)
    }
}

extension View {
    /// ContentView's root frame. The expanded window is resized at once (top pinned) while the notch
    /// height springs, so the root must fill the window top-aligned: a root shorter than the window is
    /// centred by NSHostingView, which slides the notch's top edge down mid-animation. When the window
    /// is windowSize tall (stock open/close) this is the same as the upstream frame. The width follows the
    /// animated notch width too (the expanded window is wider) and stays centred in the window.
    func notchRootFrame(notchSize: CGSize) -> some View {
        frame(maxWidth: max(windowSize.width, notchSize.width), maxHeight: windowSize.height + max(0, notchSize.height - openNotchSize.height), alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
