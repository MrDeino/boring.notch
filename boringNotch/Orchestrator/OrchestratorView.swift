import SwiftUI

struct OrchestratorView: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var draft = ""
    @EnvironmentObject var vm: BoringViewModel
    @State private var keyWindow: NSWindow?
    @State private var anchor = NSView()
    @FocusState private var fieldFocused: Bool

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
        .background(WindowAnchor(view: anchor))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { n in
            if let w = keyWindow, (n.object as? NSWindow) === w { stopTyping() }
        }
        .onDisappear { stopTyping() }
        // Focus loss ends typing; clicking elsewhere resigns key (above). Pointer leaving keeps it (INT-06).
        .onChange(of: fieldFocused) { _, f in if !f { stopTyping() } }
        .onChange(of: manager.chatRunning) { _, running in if !running { stopTyping() } }
        .onChange(of: manager.offline) { _, off in if off { stopTyping() } }
        .onChange(of: manager.promptOptions) { _, o in if !o.isEmpty { stopTyping() } }
        .overlay { OrchestratorExpandOverlay() }
    }

    @ViewBuilder private var chat: some View {
        if !manager.chatRunning {
            Text("chat not running · start it from the header")
                .font(.system(size: 11)).foregroundStyle(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(chatTail(screen: manager.screen, maxLines: 7).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .contentShape(Rectangle())
                .onTapGesture { expandChat() }
                bottomBar
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if manager.promptOptions.isEmpty {
            ZStack {
                TextField("message orchestrator", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($fieldFocused)
                    .onSubmit { submit() }
                    .onExitCommand { stopTyping() }
                    .allowsHitTesting(manager.wantsKeyboard)
                if !manager.wantsKeyboard {
                    Color.clear.contentShape(Rectangle()).onTapGesture { startTyping() }
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
        } else {
            HStack(spacing: 6) {
                // Free-text answers aren't supported from the notch yet, so don't offer a dead-end button.
                ForEach(manager.promptOptions.filter { $0.label != "Type something." }, id: \.number) { o in
                    Button { manager.pressOption(o.number) } label: {
                        Text(verbatim: "\(o.number) \(o.label)").lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: 120)
                    }
                    .disabled(manager.optionsLocked || manager.sending)
                }
                Spacer(minLength: 0)
                Button("esc") { Task { await manager.pressEscape() } }
                    .disabled(manager.sending)
            }
            .font(.system(size: 10))
            .controlSize(.small)
        }
    }

    /// Clicking the conversation opens the terminal below; it takes the keyboard itself.
    private func expandChat() {
        stopTyping(handBack: false)
        OrchestratorExpand.shared.expand(vm: vm, window: anchor.window)
    }

    private func startTyping() {
        guard let w = anchor.window else { return }
        manager.beginTyping(in: w) // canBecomeKey reads it
        keyWindow = w
        OrchestratorKeyGate.activate()
        w.makeKey()
        DispatchQueue.main.async {
            guard manager.wantsKeyboard else { return }
            w.makeKey() // again, in case activation reassigned key
            fieldFocused = true
        }
        // Activation is asynchronous; give up (so typing can't latch on) only if the panel never became key.
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if keyWindow === w, !w.isKeyWindow { stopTyping() }
        }
    }

    /// handBack false: something else (the terminal) takes focus next, so don't reactivate the previous app.
    private func stopTyping(handBack: Bool = true) {
        fieldFocused = false
        guard let w = keyWindow else { return } // another display's view owns the session
        // No longer key = the user clicked into another app, which already took focus.
        let wasKey = w.isKeyWindow
        w.makeFirstResponder(nil)
        manager.endTyping()
        keyWindow = nil
        if handBack { OrchestratorKeyGate.restore(refocus: wasKey) }
    }

    private func submit() {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { stopTyping(); return }
        stopTyping()
        Task { if await manager.sendText(t) { draft = "" } }
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

/// Exposes the hosting NSWindow (read via `view.window` when needed).
private struct WindowAnchor: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
