// Phase 4 (04-03): header segment, status capsule, usage ring, status menu.
import SwiftUI

/// "Chat | Runs N" segment after the tab buttons; only on the Orchestrator tab while online.
struct OrchestratorHeaderSegment: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        if coordinator.currentView == .orchestrator && !manager.offline {
            let n = liveRunCount(manager.runs)
            let waiting = manager.runs.contains { $0.state == "waiting" }
            HStack(spacing: 0) {
                seg(selected: !manager.showRunsBoard) { manager.showRunsBoard = false } label: {
                    Text("Chat")
                }
                seg(selected: manager.showRunsBoard) { manager.showRunsBoard = true } label: {
                    HStack(spacing: 0) {
                        Text("Runs")
                        if n > 0 {
                            Text(" \(n)").foregroundColor(waiting ? OT.C.orange : OT.C.text5)
                        }
                    }
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 12).fill(OT.C.raised))
            .font(OT.F.meta)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 6)
        }
    }

    private func seg<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .foregroundColor(selected ? OT.C.text : OT.C.text5)
                .padding(.vertical, 2).padding(.horizontal, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(selected ? OT.C.selected2 : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Status capsule plus (Phase 7) the ⌃ back-one-level button above level .open.
struct OrchestratorHeaderTrailing: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var expand = OrchestratorExpand.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var anchor = NSView()

    var body: some View {
        HStack(spacing: 6) {
            OrchestratorStatusCapsule()
            if coordinator.currentView == .orchestrator && !manager.offline && manager.hasLoaded {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        if manager.notesOpen { manager.notesOpen = false; OrchestratorNotesStore.shared.flush() }
                        else { manager.statusMenuOpen = false; manager.notesOpen = true; OrchestratorNotesStore.shared.load() }
                    }
                } label: {
                    Image(systemName: "note.text").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OT.C.text).frame(width: 24, height: 24)
                        .background(manager.notesOpen ? OT.C.selected2 : OT.C.raised, in: Circle())
                }.buttonStyle(.plain).help("Notes")
            }
            if coordinator.currentView == .orchestrator && expand.level(for: vm) != .open {
                Button { expand.back(vm) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(OT.C.text).frame(width: 24, height: 24)
                        .background(OT.C.raised, in: Circle())
                }.buttonStyle(.plain).help("Back one level (⌘↑)")
            }
        }
        .background(WindowAnchor(view: anchor))
        .onAppear { expand.register(vm: vm, anchor: anchor) }
    }
}

struct OrchestratorUsageRing: View {
    let fraction: Double
    let high: Bool
    var body: some View {
        ZStack {
            Circle().fill(OT.C.selected2)
            Circle().inset(by: 3)
                .trim(from: 0, to: fraction)
                .stroke(high ? OT.C.orange : OT.C.text, lineWidth: 6)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
    }
}

struct OrchestratorStatusCapsule: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        let s = manager.capsuleStatus
        let (dot, label, fg, bg): (Color, String, Color, Color) = {
            switch s {
            case .running: return (OT.C.green, "Running", OT.C.text, OT.C.raised)
            case .idle: return (OT.C.green, "Idle", OT.C.text, OT.C.raised)
            case .needsYou: return (OT.C.orange, "Needs you", OT.C.orangeText, OT.C.orangeBg)
            case .stopped: return (OT.C.text5, "Stopped", OT.C.text4, OT.C.raised)
            case .offline: return (OT.C.red, "Offline", OT.C.text4, OT.C.raised)
            case .connecting: return (OT.C.text6, "Connecting", OT.C.text5, OT.C.raised)
            }
        }()
        let showRing = s == .running || s == .idle || s == .stopped
        Button {
            guard s != .connecting && s != .offline else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                if manager.notesOpen { manager.notesOpen = false; OrchestratorNotesStore.shared.flush() }
                if coordinator.currentView != .orchestrator {
                    coordinator.currentView = .orchestrator
                    manager.statusMenuOpen = true
                } else {
                    manager.statusMenuOpen.toggle()
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(label).id(s).transition(.opacity).foregroundColor(fg)
                if showRing, let f = fiveHourFraction(manager.usage) {
                    OrchestratorUsageRing(fraction: f, high: usageIsHigh(manager.usage?.fiveHour?.usedPercentage))
                }
            }
            .font(OT.F.meta)
            .lineLimit(1)
            .padding(.leading, 8).padding(.trailing, 10)
            .frame(height: 24)
            .background(Capsule().fill(bg))
            .animation(.easeInOut(duration: 0.18), value: s)
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct OrchestratorStatusMenu: View {
    let openTerminal: () -> Void
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var confirmEnd = false

    private func close() { withAnimation(.easeOut(duration: 0.15)) { manager.statusMenuOpen = false } }

    var body: some View {
        let u = manager.usage
        VStack(spacing: 0) {
            usageRow("5-hour usage", u?.fiveHour) { $0.formatted(date: .omitted, time: .shortened).lowercased() }
            usageRow("7-day usage", u?.sevenDay) { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
            OT.C.divider2.frame(height: 1).padding(.vertical, 4)
            row("Open terminal", hint: Text("click transcript").foregroundColor(OT.C.text6)) {
                close(); openTerminal()
            }.disabled(!manager.chatRunning).opacity(manager.chatRunning ? 1 : 0.4)
            row("Interrupt", hint: Text("esc").font(OT.F.monoChip).foregroundColor(OT.C.text5)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: OT.R.keycap).fill(OT.C.selected))) {
                Task { await manager.pressEscape() }; close()
            }.disabled(!manager.chatRunning).opacity(manager.chatRunning ? 1 : 0.4)
            if manager.chatRunning {
                if confirmEnd {
                    HStack(spacing: 6) {
                        Text("End chat?").foregroundColor(OT.C.redText)
                        Spacer(minLength: 0)
                        pill("End", fg: .black, bg: OT.C.red) { confirmEnd = false; Task { await manager.stopChat() }; close() }
                        pill("Cancel", fg: OT.C.text, bg: OT.C.selected2) { confirmEnd = false }
                    }
                    .font(OT.F.ui)
                    .padding(.vertical, 3).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: OT.R.cardS).fill(OT.C.redBg))
                } else {
                    row("End chat", color: OT.C.redText) { confirmEnd = true }
                }
            } else {
                row("Start chat") { Task { await manager.startChat() }; close() }
            }
        }
        .disabled(manager.sending)
        .task(id: confirmEnd) {
            guard confirmEnd else { return }
            try? await Task.sleep(for: .seconds(4))
            confirmEnd = false
        }
        .padding(5)
        .frame(width: 232)
        .background(RoundedRectangle(cornerRadius: OT.R.cardL).fill(OT.C.raised))
        .overlay(RoundedRectangle(cornerRadius: OT.R.cardL).stroke(OT.C.selected, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 15, y: 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ t: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).foregroundColor(fg).padding(.horizontal, 10).frame(height: 20).background(Capsule().fill(bg))
        }.buttonStyle(PlainButtonStyle())
    }

    private func row<H: View>(_ title: String, color: Color = OT.C.text, hint: H, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundColor(color)
                Spacer(minLength: 0)
                hint.font(OT.F.hint)
            }
            .font(OT.F.ui)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }.buttonStyle(PlainButtonStyle())
    }

    private func row(_ title: String, color: Color = OT.C.text, action: @escaping () -> Void) -> some View {
        row(title, color: color, hint: EmptyView(), action: action)
    }

    private func usageRow(_ title: String, _ w: UsageWindow?, reset: (Date) -> String) -> some View {
        let pct = w?.usedPercentage
        let high = usageIsHigh(pct)
        let detail = pct.map { p in
            "\(Int(p.rounded()))%" + (w?.resetsDate.map { " · resets \(reset($0))" } ?? "")
        } ?? "—"
        return VStack(spacing: 3) {
            HStack {
                Text(title).foregroundColor(OT.C.text)
                Spacer(minLength: 0)
                Text(detail).foregroundColor(high ? OT.C.orange : OT.C.text5)
            }
            .font(OT.F.ui)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(OT.C.selected2)
                    Capsule().fill(high ? OT.C.orange : OT.C.text)
                        .frame(width: g.size.width * min(max((pct ?? 0) / 100, 0), 1))
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 3).padding(.horizontal, 8)
    }
}

// Notepad drop-down: GET /api/notes on open, autosave (raw full text) ~1s after the last keystroke.
enum NotesStatus: Equatable { case loading, loadFailed, idle, saving, saved, failed }

@MainActor
final class OrchestratorNotesStore: ObservableObject {
    static let shared = OrchestratorNotesStore()
    @Published var text = ""
    @Published private(set) var status = NotesStatus.loading
    private var loaded = false, dirty = false
    private var synced = "" // what the server has; onChange from our own load is not an edit
    private var saveTask: Task<Void, Never>?

    func load() {
        guard !dirty else { return } // unsaved/failed edits win over a reload; they are retried by save
        status = .loading; loaded = false
        Task {
            do {
                let t = try await fetchOrchestratorNotes(base: OrchestratorManager.baseURL, session: OrchestratorManager.shared.session)
                guard !dirty else { return }
                text = t; synced = t; loaded = true; status = .idle
            } catch { status = .loadFailed }
        }
    }

    /// Editor onChange. Ignored until the last GET succeeded, so a failed load never overwrites the server's notes.
    func edited() {
        guard loaded, text != synced else { return }
        dirty = true
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { await save() } }
    }

    func save() async {
        saveTask?.cancel()
        guard loaded, dirty else { return }
        dirty = false; status = .saving
        let sent = text
        let code = (try? await sendOrchestratorPost(.notes(sent), base: OrchestratorManager.baseURL, session: OrchestratorManager.shared.session)) ?? nil
        if code == 200 { status = .saved; synced = sent; if text != sent { dirty = true } } else { status = .failed; dirty = true }
    }

    /// Close: don't lose the last second of typing.
    func flush() { if dirty { Task { await save() } } }

    #if ORCH_SNAPSHOT
    func snapshotSet(text t: String, status s: NotesStatus) { text = t; synced = t; status = s; loaded = true; dirty = false }
    #endif
}

struct OrchestratorNotesPanel: View {
    @ObservedObject var store = OrchestratorNotesStore.shared
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var keyWindow: NSWindow?
    @State private var anchor = NSView()
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool
    @EnvironmentObject var vm: BoringViewModel
    /// The AppKit text view only exists while editing: it takes the click before the key gate can open.
    @State private var editing = false
    @State private var textH: CGFloat = 0
    @State private var panelH: CGFloat = 0
    /// Panel height at openNotchSize, taken once when the panel first lays out (animated heights would feed back).
    @State private var baseH: CGFloat?
    let close: () -> Void

    private var canEdit: Bool { store.status != .loading && store.status != .loadFailed }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Notes").foregroundColor(OT.C.text5)
                Spacer(minLength: 0)
                switch store.status {
                case .loading: Text("Loading…").foregroundColor(OT.C.text5)
                case .saving: Text("Saving…").foregroundColor(OT.C.text5)
                case .saved: Text("Saved").foregroundColor(OT.C.text5)
                case .failed: Text("Couldn't save").foregroundColor(OT.C.redText)
                case .loadFailed:
                    Button { store.load() } label: { Text("Couldn't load · Retry").foregroundColor(OT.C.redText) }.buttonStyle(.plain)
                case .idle: EmptyView()
                }
            }
            .font(OT.F.meta).padding(.horizontal, 6)
            if editing {
                TextEditor(text: $store.text)
                    .focused($focused)
                    .font(OT.F.ui).foregroundColor(OT.C.text)
                    .scrollContentBackground(.hidden)
                    .onChange(of: store.text) { _, _ in store.edited() }
                    .onAppear { DispatchQueue.main.async { if editing { focused = true } } }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(verbatim: store.text.isEmpty ? "Write a note" : store.text)
                        .font(OT.F.ui).foregroundColor(store.text.isEmpty ? OT.C.text6 : OT.C.text)
                        .padding(.horizontal, 5).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .overlay { if canEdit { Color.clear.contentShape(Rectangle()).onTapGesture { startTyping() } } }
            }
        }
        .padding(5)
        .frame(width: 300)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: OT.R.cardL).fill(OT.C.raised))
        .overlay(RoundedRectangle(cornerRadius: OT.R.cardL).stroke(OT.C.selected, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 15, y: 10)
        .background(WindowAnchor(view: anchor))
        .background(GeometryReader { g in Color.clear.onAppear { panelH = g.size.height }.onChange(of: g.size.height) { _, h in panelH = h } })
        // Natural height of the text at the editor's width; drives the open notch's height.
        .background(
            Text(verbatim: store.text + "\n").font(OT.F.ui)
                .padding(.horizontal, 5).frame(width: 290, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .hidden()
                .background(GeometryReader { g in Color.clear.onAppear { textH = g.size.height }.onChange(of: g.size.height) { _, h in textH = h } }),
            alignment: .topLeading)
        .onChange(of: textH) { _, _ in fitNotch() }
        .onChange(of: panelH) { _, _ in fitNotch() }
        .onAppear { fitNotch() }
        .onChange(of: focused) { _, f in if !f { stopTyping() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { n in
            if let w = keyWindow, (n.object as? NSWindow) === w { stopTyping() }
        }
        .onDisappear { stopTyping(); OrchestratorExpand.shared.setFit("notes", extra: 0, vm: vm, window: anchor.window) }
    }

    /// Height the notch must gain at the open level for the whole text to show.
    private func fitNotch() {
        let expand = OrchestratorExpand.shared
        guard expand.level(for: vm) == .open else { return expand.setFit("notes", extra: 0, vm: vm, window: anchor.window) }
        guard panelH > 0 else { return }
        if baseH == nil { baseH = panelH - (vm.notchSize.height - openNotchSize.height) }
        let needed = textH + 42 // header row + spacing + paddings + editor inset
        expand.setFit("notes", extra: needed - (baseH ?? panelH), vm: vm, window: anchor.window)
    }

    // Same hand-over as OrchestratorChatView: take the key while editing, give it back after.
    private func startTyping() {
        guard let w = anchor.window, !OrchestratorKeyGate.terminalWantsKey else { return }
        manager.beginTyping(in: w)
        keyWindow = w
        editing = true
        OrchestratorKeyGate.activate()
        w.makeKey()
        DispatchQueue.main.async { if manager.wantsKeyboard { w.makeKey() } }
        installEsc()
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if keyWindow === w, !w.isKeyWindow { stopTyping() }
        }
    }

    private func stopTyping() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        focused = false
        editing = false
        guard let w = keyWindow else { return }
        let wasKey = w.isKeyWindow
        w.makeFirstResponder(nil)
        manager.endTyping()
        keyWindow = nil
        OrchestratorKeyGate.restore(refocus: wasKey)
    }

    private func installEsc() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, event.window === keyWindow else { return event }
            store.flush(); stopTyping(); close()
            return nil
        }
    }
}
