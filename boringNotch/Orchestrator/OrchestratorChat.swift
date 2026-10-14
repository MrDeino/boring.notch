import SwiftUI
import UniformTypeIdentifiers

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
    @Published private(set) var pending: [PendingMessage] = []
    /// PNG attachments for the next message; in the store so the compact and expanded composers share them.
    @Published private(set) var attachments: [Data] = []
    private var knownUserIDs: Set<String> = []
    private var nextPendingID = 0
    private var draining = false

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
        reconcile()
    }

    private func reconcile() {
        guard !pending.isEmpty else { return }
        let r = reconcilePending(pending, blocks: blocks, known: knownUserIDs, now: Date())
        if r.known != knownUserIDs { knownUserIDs = r.known }
        if r.pending != pending {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pending = r.pending }
        }
    }

    func attach(_ png: Data) { withAnimation(.easeOut(duration: 0.15)) { attachments.append(png) } }
    func removeAttachment(at i: Int) {
        guard attachments.indices.contains(i) else { return }
        _ = withAnimation(.easeOut(duration: 0.15)) { attachments.remove(at: i) }
    }
    func takeAttachments() -> [Data] { defer { attachments = [] }; return attachments }

    func enqueue(_ text: String, images: [Data] = []) {
        // Older identical messages must not claim the new row.
        for b in blocks where b.kind == .user { knownUserIDs.insert(b.id) }
        nextPendingID += 1
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            pending.append(PendingMessage(id: nextPendingID, text: text, state: .queued, sentAt: nil, images: images))
        }
        drain()
    }

    private func setPending(_ id: Int, _ state: PendingMessage.State, sentAt: Date? = nil) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[i].state = state
        pending[i].sentAt = sentAt
    }

    // ponytail: a failed send marks only its own row and the queue moves on, so nothing sticks behind a dead row.
    private func drain() {
        guard !draining else { return }
        draining = true
        Task { @MainActor in
            let manager = OrchestratorManager.shared
            while let p = pending.first(where: { $0.state == .queued }) {
                setPending(p.id, .sending)
                // Upload first (paths kept on the row so Retry reuses them); a failed upload fails only this row.
                var uploaded = true
                for img in p.images.dropFirst(p.paths.count) {
                    guard let path = await uploadOrchestratorImage(img, base: OrchestratorManager.baseURL, session: manager.session) else { uploaded = false; break }
                    guard let i = pending.firstIndex(where: { $0.id == p.id }) else { uploaded = false; break }
                    pending[i].paths.append(path)
                }
                guard uploaded else { setPending(p.id, .failed); continue }
                // Never type queued text into a permission/question prompt.
                while manager.sending || !manager.promptOptions.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
                guard let row = pending.first(where: { $0.id == p.id && $0.state == .sending }) else { continue }
                let ok = await manager.sendText(row.wireText) { await self.clearRealLine() }
                setPending(p.id, ok ? .sent : .failed, sentAt: ok ? Date() : nil)
            }
            draining = false
        }
    }

    func retry(_ id: Int) {
        setPending(id, .queued)
        drain()
    }

    func restore(_ id: Int) -> (text: String, images: [Data])? {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return nil }
        let m = withAnimation { pending.remove(at: i) }
        attachments.insert(contentsOf: m.images, at: 0)
        return (m.text, m.images)
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

    /// R-05: always C-u Claude's box before typing; no wait-for-empty check. Claude's dim suggested
    /// prompt reads as plain box text in capture-pane and C-u can't clear it (fixtures/idle-suggestion.txt),
    /// but typing replaces it. false = the C-u POST failed, so don't type.
    func clearRealLine() async -> Bool {
        guard let base, let session else { return false }
        return (try? await sendOrchestratorPost(.key("C-u"), base: base, session: session)) == 200
    }
}

#if ORCH_SNAPSHOT
extension OrchestratorTranscriptStore {
    /// Snapshot harness only: fixture blocks instead of /api/chat/blocks.
    func snapshotSet(blocks: [ChatBlock], pending: [PendingMessage] = [], attachments: [Data] = []) {
        self.attachments = attachments
        self.blocks = blocks
        self.pending = pending
        fallback = blocks.isEmpty
    }
}
#endif

struct OrchestratorChatView: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var draft = ""
    @EnvironmentObject var vm: BoringViewModel
    @State private var keyWindow: NSWindow?
    @State private var anchor = NSView()
    @FocusState private var fieldFocused: Bool
    @State private var fromTerminal = false
    @State private var keyMonitor: Any?
    @State private var dropTargeted = false
    @State private var tagGen = 0
    @State private var tag: (text: String, error: Bool)?
    @ObservedObject var store = OrchestratorTranscriptStore.shared
    private let showComposer: Bool
    private let proseLineLimit: Int?
    private let maxRows: Int
    private let expanded: Bool

    init(showComposer: Bool = true, proseLineLimit: Int? = 4, maxRows: Int = 12, expanded: Bool = false) {
        self.expanded = expanded
        self.showComposer = showComposer
        self.proseLineLimit = proseLineLimit
        self.maxRows = maxRows
    }

    var body: some View {
        VStack(spacing: 4) {
            // The rows take only the height left under the header and above the composer and scroll,
            // pinned to the newest row; short transcripts sit at the bottom.
            GeometryReader { g in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            rows
                            Color.clear.frame(height: 0).id(Self.bottomID)
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 8)
                        .frame(minHeight: g.size.height, alignment: .bottomLeading)
                    }
                    .defaultScrollAnchor(.bottom)
                    .onChange(of: pinKey) { _, _ in proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
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
        .onChange(of: manager.notesOpen) { _, open in if open { stopTyping() } }
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
                    ChatBlockRow(block: b, proseLineLimit: proseLineLimit, expanded: expanded)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            ForEach(store.pending) { p in
                pendingRow(p)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let ls = manager.liveStatus {
                OrchestratorLiveStatusRow(status: ls)
            } else if !store.fallback, let idle = store.idleStatus {
                Text(verbatim: idle).font(OT.F.meta).foregroundStyle(OT.C.text6).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pendingRow(_ p: PendingMessage) -> some View {
        VStack(alignment: expanded ? .trailing : .leading, spacing: 2) {
            if !p.images.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(p.images.enumerated()), id: \.offset) { _, d in
                        if let img = NSImage(data: d) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                .padding(.leading, expanded ? 0 : 16) // the ❯ marker column (10 + 6 spacing)
                .opacity(0.5)
            }
            if !p.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ChatBlockRow(block: ChatBlock(pendingID: "pending-\(p.id)", text: p.text), proseLineLimit: proseLineLimit, expanded: expanded)
                    .opacity(0.5)
            }
            if p.state == .failed {
                HStack(spacing: 8) {
                    Text("Not sent").foregroundStyle(OT.C.redText)
                    Button("Retry") { store.retry(p.id) }.buttonStyle(.plain)
                    Button("Edit") {
                        if let r = store.restore(p.id) {
                            let t = r.text
                            draft = draft.isEmpty ? t : t + " " + draft
                            fromTerminal = false
                            if showComposer { startTyping() }
                        }
                    }.buttonStyle(.plain)
                }
                .font(OT.F.meta)
                .foregroundStyle(OT.C.text5)
                .padding(.leading, expanded ? 0 : 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: expanded ? .trailing : .leading)
    }

    private static let bottomID = "bottom"
    /// Changes whenever a row is added or the status row appears/disappears.
    private var pinKey: String {
        "\(store.fallback ? fallbackLines.count : store.blocks.count)|\(store.blocks.last?.id ?? "")|\(manager.liveStatus != nil)|\(store.pending.count)|\(store.idleStatus ?? "")"
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
        VStack(spacing: 4) {
            if !store.attachments.isEmpty { chipRow }
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    if fromTerminal && !draft.isEmpty {
                        Text(verbatim: "from terminal · ").font(OT.F.ui).foregroundStyle(OT.C.text5)
                    }
                    ZStack(alignment: .leading) {
                        ghostLayer
                        // The AppKit-backed TextField swallows clicks even under allowsHitTesting(false) and a
                        // tap overlay, so it only exists while typing; otherwise a Text shows the draft.
                        if manager.wantsKeyboard {
                            TextField("", text: $draft)
                                .textFieldStyle(.plain)
                                .font(OT.F.ui)
                                .foregroundStyle(OT.C.text)
                                .focused($fieldFocused)
                                .onSubmit { submit() }
                                .onExitCommand { stopTyping() }
                                .onAppear { DispatchQueue.main.async { if manager.wantsKeyboard { fieldFocused = true } } }
                        } else {
                            Text(verbatim: draft).font(OT.F.ui).foregroundStyle(OT.C.text)
                                .lineLimit(1).truncationMode(.head)
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
                if fieldFocused || dropTargeted { RoundedRectangle(cornerRadius: OT.R.pill30).stroke(OT.C.claude, lineWidth: 1.5) }
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
    }

    // ponytail: thumbnails decode from PNG per render; cache if chips ever get many.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(store.attachments.enumerated()), id: \.offset) { i, d in
                    Group {
                        if let img = NSImage(data: d) { Image(nsImage: img).resizable().aspectRatio(contentMode: .fill) } else { OT.C.raised }
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(alignment: .topTrailing) {
                        Button { store.removeAttachment(at: i) } label: {
                            ZStack {
                                Circle().fill(OT.C.selected2)
                                Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(OT.C.text)
                            }
                            .frame(width: 14, height: 14)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.leading, 14).padding(.trailing, 6).padding(.top, 4)
        }
        .frame(height: 38)
    }

    private func attachImage(_ image: NSImage) {
        guard let png = orchestratorPNG(from: image) else { flashTag("Couldn't paste image", error: true, ms: 1800); return }
        guard png.count <= 10 * 1024 * 1024 else { flashTag("Image too big", error: true, ms: 1800); return }
        store.attach(png)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var took = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                took = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
                          let img = NSImage(contentsOf: url) else { return }
                    DispatchQueue.main.async { attachImage(img) }
                }
            } else if p.canLoadObject(ofClass: NSImage.self) {
                took = true
                _ = p.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage else { return }
                    DispatchQueue.main.async { attachImage(img) }
                }
            }
        }
        return took
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
        if let tag {
            Text(tag.text).font(OT.F.hint).foregroundStyle(tag.error ? OT.C.redText : OT.C.text5)
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
        let blank = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachments.isEmpty
        return Button { submit() } label: {
            ZStack {
                Circle().fill(fieldFocused ? OT.C.claude : OT.C.selected2)
                Image(systemName: "arrow.up").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(fieldFocused ? Color.black : OT.C.text5)
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(blank)
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
                flashTag("line cleared", error: false, ms: 1200)
                return nil
            }
            // Cmd-V with an image on the pasteboard attaches it; text-only pastes fall through untouched.
            if event.keyCode == 9, mods == .command, NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil),
               let img = NSImage(pasteboard: .general) {
                attachImage(img)
                return nil
            }
            return event
        }
    }

    /// Brief inline tag in the composer pill ("line cleared", "Couldn't send").
    private func flashTag(_ text: String, error: Bool, ms: Int) {
        tagGen += 1
        let gen = tagGen
        withAnimation(.easeOut(duration: 0.15)) { tag = (text, error) }
        Task {
            try? await Task.sleep(for: .milliseconds(ms))
            if tagGen == gen { withAnimation(.easeOut(duration: 0.15)) { tag = nil } }
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
        guard !t.isEmpty || !store.attachments.isEmpty else { stopTyping(); return }
        // A terminal draft not pulled in on focus would be C-u'd unseen: pull it in front and wait for a second Enter.
        if !fromTerminal, store.boxIsDraft, let l = store.inputLine, !l.isEmpty {
            draft = l + " " + draft
            fromTerminal = true
            return
        }
        store.enqueue(t, images: store.takeAttachments())
        draft = ""
        fromTerminal = false
    }
}

private struct ChatBlockRow: View {
    let block: ChatBlock
    let proseLineLimit: Int?
    var expanded = false
    @State private var folded = false

    private var hasDiffCard: Bool {
        expanded && block.kind == .tool && ["Edit", "Write"].contains(block.name ?? "") && !(block.diff ?? []).isEmpty
    }

    /// Leading marker column like Claude Code's terminal (❯ user, ⏺ prose/tool); wrapped text hangs after it.
    /// Expanded view only: user messages are right-aligned bubbles and Edit rows fold out into a diff card.
    @ViewBuilder var body: some View {
        if expanded && block.kind == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(verbatim: block.text ?? "")
                    .font(.system(size: 12)).foregroundStyle(OT.C.text2)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(OT.C.raised, in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 4, topTrailingRadius: 12))
                    .containerRelativeFrame(.horizontal, alignment: .trailing) { w, _ in w * 0.8 }
            }
        } else if hasDiffCard {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                marker.frame(width: 10, alignment: .center)
                diffCard.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                marker.frame(width: 10, alignment: .center)
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func diffLine(_ r: DiffRow) -> some View {
        let sign: String = r.kind == .removed ? "-" : r.kind == .added ? "+" : " "
        let num: String = r.number.map { " \($0)" } ?? ""
        let fg: Color = r.kind == .removed ? Color(red: 1, green: 157 / 255, blue: 151 / 255) : r.kind == .added ? Color(red: 126 / 255, green: 230 / 255, blue: 154 / 255) : OT.C.text6
        let bg: Color = r.kind == .removed ? Color(red: 1, green: 105 / 255, blue: 97 / 255).opacity(0.12)
            : r.kind == .added ? Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255).opacity(0.12) : Color.clear
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: sign + num).frame(minWidth: 34, alignment: .leading)
            Text(verbatim: r.text).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(OT.F.monoChip)
        .foregroundStyle(fg)
        .padding(.horizontal, 10)
        .background(bg)
    }

    private var diffCard: some View {
        let rows = diffRows(block.diff ?? [])
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.15)) { folded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text(verbatim: folded ? "▸" : "▾").font(OT.F.meta).foregroundStyle(OT.C.text6)
                    Text(verbatim: block.name ?? "Edit").font(OT.F.monoChip.weight(.medium)).foregroundStyle(OT.C.text3)
                    Text(verbatim: toolTargetDisplay(name: block.name, target: block.target))
                        .font(OT.F.monoPath).foregroundStyle(OT.C.text2).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    if let a = block.added { Text(verbatim: "+\(a)").font(OT.F.monoChip).foregroundStyle(OT.C.green) }
                    if let r = block.removed { Text(verbatim: "\u{2212}\(r)").font(OT.F.monoChip).foregroundStyle(OT.C.redText) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !folded {
                VStack(alignment: .leading, spacing: 1.5) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in diffLine(r) }
                }
                .padding(.bottom, 6)
            }
        }
        .background(OT.C.diffCard, in: RoundedRectangle(cornerRadius: 9))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    @ViewBuilder private var marker: some View {
        switch block.kind {
        case .user: Text(verbatim: "❯").font(OT.F.ui).foregroundStyle(OT.C.text5)
        case .prose: dot(OT.C.text)
        case .tool:
            switch toolMarker(result: block.result) {
            case .running: dot(OT.C.text6)
            case .done: dot(OT.C.green)
            case .error: dot(OT.C.red)
            }
        }
    }

    /// U+FE0E keeps ⏺ a text glyph (not the emoji button).
    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 7, height: 7)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 0.5 }
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .user:
            let first = (block.text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            Text(verbatim: first)
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
