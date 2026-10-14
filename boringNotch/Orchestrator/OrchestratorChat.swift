import SwiftUI

// Phase 5 owns this file.
// The store property `boxIsDraft` shadows the global function inside the class.
private func globalBoxIsDraft(previous: String?, current: String?, wasDraft: Bool, editing: Bool) -> Bool {
    boxIsDraft(previous: previous, current: current, wasDraft: wasDraft, editing: editing)
}

@MainActor
final class OrchestratorTranscriptStore: ObservableObject {
    static let shared = OrchestratorTranscriptStore()

    @Published private(set) var blocks: [ChatBlock] = []
    /// True until a blocks fetch succeeds: the view then shows the chatTail lines.
    @Published private(set) var fallback = true
    @Published private(set) var inputLine: String? = nil
    @Published private(set) var boxIsDraft = false
    @Published private(set) var idleStatus: String? = nil

    private var base: URL?
    private var session: URLSession?
    private var needsFull = true
    private var polls = 0
    private var failures = 0

    func refresh(base: URL, session: URLSession, screen: String, chatRunning: Bool) async {
        self.base = base
        self.session = session
        let il = chatRunning ? parseInputLine(screen: screen) : nil
        let draft = globalBoxIsDraft(previous: inputLine, current: il, wasDraft: boxIsDraft, editing: OrchestratorManager.shared.wantsKeyboard)
        if draft != boxIsDraft { boxIsDraft = draft }
        if il != inputLine { inputLine = il }
        let idle = chatRunning ? parseIdleStatus(screen: screen) : nil
        if idle != idleStatus { idleStatus = idle }

        guard chatRunning else {
            if !blocks.isEmpty { blocks = [] }
            needsFull = true
            return
        }
        guard OrchestratorManager.shared.notchOpen else { return }
        // ponytail: full resync about every 15th open poll (~30 s) for what the overlap check can't see
        // (e.g. /clear with no new blocks yet); SSE in Phase 8 removes it.
        let full = needsFull || polls % 15 == 0
        polls += 1

        let sinceSent = !full && !blocks.isEmpty
        guard var decoded = await fetchBlocks(base: base, session: session, since: sinceSent ? blocks.last?.id : nil) else {
            fetchFailed()
            return
        }
        if decoded.running == false && decoded.blocks.isEmpty {
            if !blocks.isEmpty { blocks = [] }
            fallback = true
            needsFull = true
            return
        }
        var reset = full
        if blocksDiscontinuous(sinceSent: sinceSent, incoming: decoded.blocks, existing: blocks) {
            // Full fetch: still holding our last block = plain append, else the conversation changed (/clear): replace.
            guard let all = await fetchBlocks(base: base, session: session, since: nil) else {
                fetchFailed()
                return
            }
            decoded = all
            reset = !all.blocks.contains { $0.id == blocks.last?.id }
        }
        let m = mergeChatBlocks(blocks, decoded.blocks, reset: reset)
        if m.blocks != blocks {
            if m.appended && !reset {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { blocks = m.blocks }
            } else {
                blocks = m.blocks
            }
        }
        if fallback { fallback = false }
        needsFull = false
        failures = 0
    }

    /// D-03 fallback, but one transient failure keeps the rows we hold (no flicker to chatTail and back).
    private func fetchFailed() {
        failures += 1
        if (blocks.isEmpty || failures >= 3) && !fallback { fallback = true }
    }

    private func fetchBlocks(base: URL, session: URLSession, since: String?) async -> (running: Bool?, blocks: [ChatBlock])? {
        var comps = URLComponents(url: base.appendingPathComponent("api/chat/blocks"), resolvingAgainstBaseURL: false)
        if let since { comps?.queryItems = [URLQueryItem(name: "since", value: since)] }
        guard let url = comps?.url,
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return decodeChatBlocks(data)
    }

    func postKey(_ key: String) async {
        guard let base, let session else { return }
        _ = try? await sendOrchestratorPost(.key(key), base: base, session: session)
    }

    /// R-05: C-u the real box when it holds text, then confirm from a fresh screen that it is empty.
    /// C-u only kills to line start, so a multi-line box or a mid-line cursor leaves text: false = don't send.
    func clearRealLineIfNeeded() async -> Bool {
        guard let base, let session else { return false }
        for attempt in 0..<6 {
            guard let (d, _) = try? await session.data(from: base.appendingPathComponent("api/chat")),
                  let r = try? JSONDecoder().decode(ChatResponse.self, from: d) else { return false }
            guard let box = parseInputLine(screen: r.screen ?? ""), !box.isEmpty else { return true }
            if attempt == 0 { await postKey("C-u") }
            try? await Task.sleep(for: .milliseconds(150))
        }
        return false
    }

    /// Clear + send as one manager operation: no other POST can land between C-u and the text.
    func submit(_ text: String) async -> Bool {
        await OrchestratorManager.shared.sendText(text) { await self.clearRealLineIfNeeded() }
    }
}

struct OrchestratorChatView: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var draft = ""
    @EnvironmentObject var vm: BoringViewModel
    @State private var keyWindow: NSWindow?
    @State private var anchor = NSView()
    @FocusState private var fieldFocused: Bool
    @State private var fromTerminal = false
    @State private var keyMonitor: Any?
    @State private var clearedGen = 0
    @State private var showCleared = false
    @ObservedObject var store = OrchestratorTranscriptStore.shared
    private let showComposer: Bool
    private let proseLineLimit: Int?
    private let maxRows: Int
    private let scrolls: Bool

    /// scrolls: the expanded column (frame 12) shows full prose and scrolls, pinned to the newest row.
    init(showComposer: Bool = true, proseLineLimit: Int? = 4, maxRows: Int = 12, scrolls: Bool = false) {
        self.showComposer = showComposer
        self.proseLineLimit = proseLineLimit
        self.maxRows = maxRows
        self.scrolls = scrolls
    }

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if scrolls {
                    ScrollView(.vertical, showsIndicators: false) { rows }.defaultScrollAnchor(.bottom)
                } else {
                    rows
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 8)
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .contentShape(Rectangle())
            .onTapGesture { expandChat() }
            if showComposer { composer }
        }
        .background(WindowAnchor(view: anchor))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { n in
            if let w = keyWindow, (n.object as? NSWindow) === w { stopTyping() }
        }
        .onDisappear { stopTyping(); removeKeyMonitor() }
        // Focus loss ends typing; clicking elsewhere resigns key (above). Pointer leaving keeps it (INT-06).
        .onChange(of: fieldFocused) { _, f in if !f { stopTyping() } }
        .onChange(of: fieldFocused) { _, f in focusChanged(f) }
        .onChange(of: draft) { _, d in if d.isEmpty { fromTerminal = false } }
        .onChange(of: manager.chatRunning) { _, running in if !running { stopTyping() } }
        .onChange(of: manager.offline) { _, off in if off { stopTyping() } }
        .onChange(of: manager.promptOptions) { _, o in if !o.isEmpty { stopTyping() } }
        // Phase 4
        .onChange(of: manager.statusMenuOpen) { _, open in if open { stopTyping() } }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: OT.S.gapS) {
            if store.fallback {
                ForEach(Array(fallbackLines.enumerated()), id: \.offset) { _, line in
                    Text(verbatim: line)
                        .font(OT.F.prose)
                        .foregroundStyle(OT.C.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else {
                ForEach(store.blocks.suffix(maxRows)) { b in
                    ChatBlockRow(block: b, proseLineLimit: proseLineLimit)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            if let ls = manager.liveStatus {
                OrchestratorLiveStatusRow(status: ls)
            } else if !store.fallback, let idle = store.idleStatus {
                Text(verbatim: idle).font(OT.F.meta).foregroundStyle(OT.C.text6).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// chatTail lines minus spinner lines (the status row shows those).
    private var fallbackLines: [String] {
        chatTail(screen: manager.screen, maxLines: maxRows).filter {
            guard let c = $0.trimmingCharacters(in: .whitespaces).first else { return true }
            return !"✻✢✳✶✽✺✹".contains(c)
        }
    }

    /// Claude's box text offered as ghost text (only while the field is empty and it is not a terminal draft).
    private var suggestion: String? {
        guard draft.isEmpty, !store.boxIsDraft, let l = store.inputLine, !l.isEmpty else { return nil }
        return l
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    if fromTerminal && !draft.isEmpty {
                        Text(verbatim: "from terminal · ").font(OT.F.ui).foregroundStyle(OT.C.text5)
                    }
                    ZStack(alignment: .leading) {
                        ghostLayer
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .font(OT.F.ui)
                            .foregroundStyle(OT.C.text)
                            .focused($fieldFocused)
                            .onSubmit { submit() }
                            .onExitCommand { stopTyping() }
                            .allowsHitTesting(manager.wantsKeyboard)
                        if !manager.wantsKeyboard {
                            Color.clear.contentShape(Rectangle()).onTapGesture { startTyping() }
                        }
                    }
                }
                accessory
                sendButton
            }
            .padding(.leading, 14).padding(.trailing, 5)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: OT.R.pill30).fill(OT.C.raised))
            .overlay {
                if fieldFocused { RoundedRectangle(cornerRadius: OT.R.pill30).stroke(OT.C.claude, lineWidth: 1.5) }
            }
            if manager.wantsKeyboard {
                Text("⏎ send · ⌃U clear line · esc release")
                    .font(OT.F.hint).foregroundStyle(OT.C.text6)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 12)
            }
        }
    }

    @ViewBuilder private var ghostLayer: some View {
        if let g = suggestion {
            Text(verbatim: g).font(OT.F.ui).foregroundStyle(OT.C.text6).lineLimit(1).allowsHitTesting(false)
        } else if draft.isEmpty, store.boxIsDraft, let l = store.inputLine, !l.isEmpty {
            (Text(verbatim: "from terminal · ").foregroundStyle(OT.C.text5) + Text(verbatim: l).foregroundStyle(OT.C.text6))
                .font(OT.F.ui).lineLimit(1).allowsHitTesting(false)
        } else if draft.isEmpty {
            Text("Message orchestrator").font(OT.F.ui).foregroundStyle(OT.C.text6).allowsHitTesting(false)
        }
    }

    @ViewBuilder private var accessory: some View {
        if showCleared {
            Text("line cleared").font(OT.F.hint).foregroundStyle(OT.C.text5)
                .padding(.vertical, 2).padding(.horizontal, 7)
                .background(OT.C.selected, in: RoundedRectangle(cornerRadius: 8))
                .transition(.opacity)
        } else if suggestion != nil {
            HStack(spacing: 4) {
                Text("Tab").font(OT.F.monoChip.weight(.medium)).foregroundStyle(OT.C.text4)
                    .padding(.vertical, 1).padding(.horizontal, 5)
                    .background(OT.C.selected2, in: RoundedRectangle(cornerRadius: OT.R.keycap))
                Text("accept").font(OT.F.hint).foregroundStyle(OT.C.text6)
            }
        }
    }

    private var sendButton: some View {
        let blank = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button { submit() } label: {
            ZStack {
                Circle().fill(fieldFocused ? OT.C.claude : OT.C.selected2)
                Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(fieldFocused ? Color.black : OT.C.text5)
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(blank || manager.sending)
    }

    /// Terminal draft -> field on focus; key monitor lifecycle.
    private func focusChanged(_ f: Bool) {
        guard f else { removeKeyMonitor(); return }
        installKeyMonitor()
        if draft.isEmpty, store.boxIsDraft, let l = store.inputLine, !l.isEmpty {
            draft = l
            fromTerminal = true
        }
    }

    // ponytail: local-monitor key handling; swap to onKeyPress if it proves reliable for Tab in the panel.
    // Tab/→ accept and ⌃U are local only (user, 2026-10-14): every send clears Claude's box first.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard fieldFocused, event.window === keyWindow else { return event }
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if (event.keyCode == 48 || event.keyCode == 124), mods.isEmpty, let g = suggestion {
                draft = g
                fromTerminal = false
                return nil
            }
            if event.keyCode == 32, mods == .control {
                let tv = event.window?.firstResponder as? NSTextView
                draft = clearToCaret(draft, caretUTF16: tv?.selectedRange().location)
                DispatchQueue.main.async { tv?.setSelectedRange(NSRange(location: 0, length: 0)) }
                clearedGen += 1
                let gen = clearedGen
                withAnimation(.easeOut(duration: 0.15)) { showCleared = true }
                Task {
                    try? await Task.sleep(for: .milliseconds(1200))
                    if clearedGen == gen { withAnimation(.easeOut(duration: 0.15)) { showCleared = false } }
                }
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    /// Clicking the conversation opens the terminal below; it takes the keyboard itself.
    private func expandChat() {
        stopTyping(handBack: false)
        OrchestratorExpand.shared.transcriptTapped(vm: vm, window: anchor.window)
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
        guard !manager.sending else { return } // Enter is ignored like the disabled send button
        // A terminal draft not pulled in on focus would be C-u'd unseen: pull it in front and wait for a second Enter.
        if !fromTerminal, store.boxIsDraft, let l = store.inputLine, !l.isEmpty {
            draft = l + " " + draft
            fromTerminal = true
            return
        }
        stopTyping()
        Task { if await store.submit(t) { draft = ""; fromTerminal = false } }
    }
}

private struct ChatBlockRow: View {
    let block: ChatBlock
    let proseLineLimit: Int?

    var body: some View {
        switch block.kind {
        case .user:
            let first = (block.text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            Text(verbatim: "❯ " + first)
                .font(OT.F.ui).foregroundStyle(OT.C.text5)
                .lineLimit(1).truncationMode(.tail)
        case .tool:
            toolRow
        case .prose:
            // lineSpacing 2 on 13pt text ~ line-height 1.35 (13 * 1.35 = 17.5 vs ~15.5 natural).
            Text(proseAttributed(block.text ?? ""))
                .font(OT.F.prose).foregroundStyle(OT.C.text)
                .lineSpacing(2)
                .lineLimit(proseLineLimit).truncationMode(.tail)
        }
    }

    private var toolRow: some View {
        let target = toolTargetDisplay(name: block.name, target: block.target)
        let isPath = target.contains("/")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: block.name ?? "Tool")
                .font(OT.F.monoChip.weight(.medium)).foregroundStyle(OT.C.text3)
                .padding(.vertical, 2).padding(.horizontal, 6)
                .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 5))
            Text(verbatim: target)
                .font(OT.F.monoPath).foregroundStyle(OT.C.text2)
                .lineLimit(1).truncationMode(isPath ? .middle : .tail)
            if let add = block.added {
                Text(verbatim: "+\(add)").font(OT.F.monoChip).foregroundStyle(OT.C.green)
                Text(verbatim: "\u{2212}\(block.removed ?? 0)").font(OT.F.monoChip).foregroundStyle(OT.C.redText)
                Text(verbatim: "▸ diff").font(OT.F.meta).foregroundStyle(OT.C.text6)
            } else if let r = toolResultDisplay(name: block.name, result: block.result, added: block.added) {
                Text(verbatim: r).font(OT.F.meta)
                    .foregroundStyle(toolResultIsError(block.result) ? OT.C.redText : OT.C.text6)
                    .lineLimit(1)
            }
        }
    }
}

/// "✻ Working · m:ss  esc to interrupt". Elapsed ticks each second between polls; the accent text shimmers.
private struct OrchestratorLiveStatusRow: View {
    let status: LiveStatus
    @State private var anchor: (base: TimeInterval, at: Date) = (0, Date())
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            HStack(spacing: 6) {
                label(ctx.date)
                Text("esc to interrupt").font(OT.F.meta).foregroundStyle(OT.C.text6)
            }
        }
        .onAppear { reset() }
        .onChange(of: status.elapsed) { _, _ in reset() }
    }

    private func reset() { anchor = (status.elapsed ?? 0, Date()) }

    private func label(_ now: Date) -> some View {
        let t = status.elapsed == nil ? "✻ Working"
            : "✻ Working · " + formatElapsed(anchor.base + now.timeIntervalSince(anchor.at))
        let text = Text(verbatim: t).font(OT.F.meta).foregroundStyle(OT.C.claude)
        return text.overlay {
            if !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { c in
                    let p = c.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, .white.opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.5)
                            .offset(x: (p * 1.5 - 0.5) * g.size.width)
                    }
                }
                .mask(text)
            }
        }
    }
}
