import SwiftUI
import Combine
import UniformTypeIdentifiers

// Phase 5 owns this file.

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
    /// Composer text and its "pulled in from the terminal" flag live here (like the chips) so they survive
    /// level changes, notch close/reopen and tab switches, which remount the chat view.
    @Published var draft = "" { didSet { if draft.isEmpty && draftFromTerminal { draftFromTerminal = false } } }
    @Published var draftFromTerminal = false
    private var knownUserIDs: Set<String> = []
    private var nextPendingID = 0
    private var draining = false

    private var needsFull = true
    private var polls = 0
    private var failures = 0

    /// Input box + idle status from a chat payload (polled or pushed). Phase 8: serve's `input` wins over the heuristic.
    func applyScreen(_ r: ChatResponse) {
        let running = r.running ?? false
        let res = resolveInput(hasKey: r.hasInputKey, input: r.input, screen: r.screen ?? "", chatRunning: running,
                               previous: inputLine, wasDraft: boxIsDraft, editing: OrchestratorManager.shared.wantsKeyboard)
        if res.draft != boxIsDraft { boxIsDraft = res.draft }
        if res.line != inputLine { inputLine = res.line }
        let idle = running ? parseIdleStatus(screen: r.screen ?? "") : nil
        if idle != idleStatus { idleStatus = idle }
    }

    func refresh(base: URL, session: URLSession, chatRunning: Bool) async {
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
        if decoded.running == false && decoded.blocks.isEmpty { ingestBlocks(running: false, blocks: [], reset: true); return }
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
        ingestBlocks(running: decoded.running, blocks: decoded.blocks, reset: reset)
    }

    /// The one place blocks enter the store (polled or pushed). `reset` replaces the rows; pending rows are kept and reconciled.
    func ingestBlocks(running: Bool?, blocks incoming: [ChatBlock], reset: Bool) {
        if running == false && incoming.isEmpty {
            if !blocks.isEmpty { blocks = [] }
            fallback = true
            needsFull = true
            return
        }
        let m = mergeChatBlocks(blocks, incoming, reset: reset)
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
    /// but typing replaces it. false = the C-u POST failed, so don't type. Same base/session as the text POST:
    /// while streaming, refresh(base:) may never have run.
    func clearRealLine() async -> Bool {
        (try? await sendOrchestratorPost(.key("C-u"), base: OrchestratorManager.baseURL, session: OrchestratorManager.shared.session)) == 200
    }
}

#if ORCH_SNAPSHOT
extension OrchestratorTranscriptStore {
    /// Snapshot harness only: fixture blocks instead of /api/chat/blocks.
    func snapshotSet(blocks: [ChatBlock], pending: [PendingMessage] = [], attachments: [Data] = [], draft: String = "") {
        self.draft = draft
        draftFromTerminal = false
        self.attachments = attachments
        self.blocks = blocks
        self.pending = pending
        fallback = blocks.isEmpty
    }
}
#endif

/// A narrower objectWillChange than the whole model's: fires only when one of the listed fields changes. Containers
/// observe this instead of the whole OrchestratorManager, so a runs/usage tick or a transcript or composer change
/// does not re-evaluate (and re-lay-out) views that do not draw it.
@MainActor
final class ModelSlice: ObservableObject {
    private var bag = Set<AnyCancellable>()
    init(_ fields: [AnyPublisher<Void, Never>]) {
        Publishers.MergeMany(fields).sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
    }
    /// A @Published projection as a change signal (the replayed first value dropped).
    static func changes<P: Publisher>(_ p: P) -> AnyPublisher<Void, Never> where P.Failure == Never {
        p.dropFirst().map { _ in () }.eraseToAnyPublisher()
    }

    private static var m: OrchestratorManager { .shared }
    private static var t: OrchestratorTranscriptStore { .shared }
    /// OrchestratorView: the two drop-downs.
    static var view: ModelSlice { .init([changes(m.$statusMenuOpen), changes(m.$notesOpen)]) }
    /// OrchestratorExpandedView: which state to show, and the prose above a prompt card.
    static var column: ModelSlice {
        .init([changes(m.$hasLoaded), changes(m.$offline), changes(m.$chatRunning), changes(m.$showRunsBoard), changes(m.$prompt),
               changes(t.$blocks.map { latestAssistantProse($0) }.removeDuplicates()),
               changes(m.$screen.combineLatest(m.$prompt).map { $1 == nil ? nil : screenLeadIn(screen: $0) }.removeDuplicates())])
    }
    /// The runs rail / strip.
    static var runs: ModelSlice { .init([changes(m.$runs), changes(m.$usage)]) }
    /// The chat view's manager fields (it observes the transcript store directly).
    static var chat: ModelSlice {
        .init([changes(m.$chatLive), changes(m.$chatRunning), changes(m.$liveStatus), changes(m.$notesOpen), changes(m.$offline),
               changes(m.$prompt), changes(m.$promptOptions), changes(m.$screen), changes(m.$statusMenuOpen), changes(m.$wantsKeyboard)])
    }
}

struct OrchestratorChatView: View {
    let manager = OrchestratorManager.shared
    @StateObject private var slice = ModelSlice.chat
    @EnvironmentObject var vm: BoringViewModel
    @State private var keyWindow: NSWindow?
    @State private var anchor = NSView()
    @FocusState private var fieldFocused: Bool
    @State private var keyMonitor: Any?
    @State private var typeMonitor: Any?
    @State private var caretToEnd = false
    @State private var dropTargeted = false
    @State private var composerH: CGFloat = 30
    @State private var tagGen = 0
    @State private var copiedToast = false
    @State private var copyGen = 0
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
                            // AppKit text views win hit tests over SwiftUI overlays: while the pill shows, rows are inert so
                            // the pill gets its click (selecting resumes once it is gone).
                            // AppKit text views win hit tests over SwiftUI overlays: while the pill shows, rows are inert so
                            // the pill gets its click (selecting resumes once it is gone).
                            rows.allowsHitTesting(!(unseen && !stick))
                            Color.clear.frame(height: 0).id(Self.bottomID)
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 8)
                        .frame(minHeight: g.size.height, alignment: .bottomLeading)
                        .background(GeometryReader { c in
                            Color.clear
                                .onAppear { chatGeometry(c.frame(in: .named("orchChatScroll")), viewport: g.size.height, proxy: proxy) }
                                .onChange(of: c.frame(in: .named("orchChatScroll"))) { _, f in chatGeometry(f, viewport: g.size.height, proxy: proxy) }
                        })
                    }
                    .defaultScrollAnchor(.bottom)
                    // Also catches a new row that leaves the height unchanged (the row window drops an old one).
                    .onChange(of: pinKey) { _, _ in if stick { proxy.scrollTo(Self.bottomID, anchor: .bottom) } else { unseen = true } }
                    .overlay(alignment: .bottom) {
                        if unseen && !stick {
                            Button {
                                stick = true; unseen = false
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                            } label: {
                                Text("↓ New messages").font(OT.F.meta).foregroundStyle(OT.C.text2)
                                    .padding(.vertical, 3).padding(.horizontal, 9)
                                    .background(Capsule().fill(OT.C.raised))
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 4)
                            .transition(.opacity)
                        }
                    }
                    // A level change reflows the rows (width and height); the ScrollView keeps its offset, which
                    // would scroll the newest row out of view when the content shrinks. Stay on the newest row.
                    .onChange(of: g.size) { _, _ in
                        // Next turn: the content has not been laid out at the new size yet when this fires.
                        guard stick else { return }
                        Task { @MainActor in
                            for ms in [0, 80] {
                                try? await Task.sleep(for: .milliseconds(ms))
                                var t = Transaction(); t.disablesAnimations = true
                                withTransaction(t) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "orchChatScroll")
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { expandChat() }
            .overlay(alignment: .top) {
                if copiedToast {
                    Text("Copied").font(OT.F.hint).foregroundStyle(OT.C.text5)
                        .padding(.vertical, 2).padding(.horizontal, 7)
                        .background(OT.C.selected, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 2)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            if showComposer { composer }
        }
        .background(WindowAnchor(view: anchor))
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { n in
            if let w = keyWindow, (n.object as? NSWindow) === w { stopTyping() }
        }
        .onAppear { if showComposer { installTypeMonitor() } }
        .onDisappear { stopTyping(); removeKeyMonitor(); removeTypeMonitor() }
        // Kept built while closed: close ends typing; reopen re-asserts the composer fit that reset() cleared.
        .onChange(of: vm.notchState == .open) { _, o in
            if o { if showComposer { fitComposer(composerH); installTypeMonitor() } } else { stopTyping(); removeKeyMonitor(); removeTypeMonitor() }
        }
        // Focus loss ends typing; clicking elsewhere resigns key (above). Pointer leaving keeps it (INT-06).
        .onChange(of: fieldFocused) { _, f in if !f { stopTyping() } }
        .onChange(of: fieldFocused) { _, f in focusChanged(f) }
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
                    ChatBlockRow(block: b, proseLineLimit: proseLineLimit, expanded: expanded, caret: caretVisible(live: manager.chatLive, working: manager.liveStatus != nil, kind: b.kind, id: b.id, newestID: store.blocks.last?.id) && store.pending.isEmpty, onClick: expandChat, onCopied: showCopied)
                        .equatable()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                // Claude Code writes the turn to the transcript only after the prompt is answered: show its screen text meanwhile.
                if manager.prompt != nil, let lead = heldLeadIn(screen: manager.screen, blocks: store.blocks) {
                    ChatBlockRow(block: ChatBlock(pendingID: "lead-in", text: lead, kind: .prose), proseLineLimit: proseLineLimit, expanded: expanded, onClick: expandChat, onCopied: showCopied)
                        .equatable()
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
            if !p.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ChatBlockRow(block: ChatBlock(pendingID: "pending-\(p.id)", text: p.text), proseLineLimit: proseLineLimit, expanded: expanded, onClick: expandChat, onCopied: showCopied)
                    .opacity(0.5)
            }
            if !p.images.isEmpty {
                let textBlank = p.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                HStack(spacing: 4) {
                    if !expanded && textBlank { // image-only: keep the ❯ marker column so it reads as a user row
                        Text(verbatim: "❯").font(OT.F.ui).foregroundStyle(OT.C.text5).frame(width: 10, alignment: .center).padding(.trailing, 2)
                    }
                    ForEach(Array(p.images.enumerated()), id: \.offset) { _, d in
                        if let img = NSImage(data: d) {
                            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                                .frame(width: 24, height: 24).clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                    }
                }
                .padding(.leading, expanded || textBlank ? 0 : 16) // text rows: past the marker column (10 + 6)
                .opacity(0.5)
            }
            if p.state == .failed {
                HStack(spacing: 8) {
                    Text("Not sent").foregroundStyle(OT.C.redText)
                    Button("Retry") { store.retry(p.id) }.buttonStyle(.plain)
                    Button("Edit") {
                        if let r = store.restore(p.id) {
                            let t = r.text
                            store.draft = store.draft.isEmpty ? t : t + " " + store.draft
                            store.draftFromTerminal = false
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

    @State private var stick = true
    @State private var unseen = false
    @State private var contentHeight: CGFloat = 0

    private func chatGeometry(_ f: CGRect, viewport: CGFloat, proxy: ScrollViewProxy) {
        let r = chatScrollStep(stick: stick, oldHeight: contentHeight, newHeight: f.height, contentMinY: f.minY, viewport: viewport)
        contentHeight = f.height
        if r.stick != stick { stick = r.stick }
        if r.stick && unseen { unseen = false }
        if r.newContent { unseen = true }
        if r.scrollToBottom {
            Task { @MainActor in
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
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
            return !"✻✢✳✶✽✺✹".contains(c) && parseLiveStatus(screen: $0) == nil
        }
    }

    /// Claude's box text offered as ghost text (only while the field is empty and it is not a terminal draft).
    private var suggestion: String? {
        guard store.draft.isEmpty, !store.boxIsDraft, let l = store.inputLine, !l.isEmpty else { return nil }
        return l
    }

    private var composer: some View {
        VStack(spacing: 4) {
            if !store.attachments.isEmpty { chipRow }
            HStack(alignment: .bottom, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    if store.draftFromTerminal && !store.draft.isEmpty {
                        Text(verbatim: "from terminal · ").font(OT.F.ui).foregroundStyle(OT.C.text5)
                    }
                    ZStack(alignment: .topLeading) {
                        ghostLayer
                        // Always mounted: a click focuses it in place, so a drag or double-click selects on the first gesture.
                        OrchestratorComposerField(text: $store.draft, focused: $fieldFocused,
                                                  onFocus: { if keyWindow == nil { startTyping() } },
                                                  onSubmit: submit, onExit: { stopTyping() })
                            .font(OT.F.ui)
                            .foregroundStyle(OT.C.text)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                    // Behind the field: a click in the pill's padding still starts typing.
                    .background { Color.clear.contentShape(Rectangle()).onTapGesture { if !fieldFocused { startTyping() } } }
                }
                accessory.frame(height: 30)
                sendButton.frame(height: 30)
            }
            .padding(.leading, 14).padding(.trailing, 5)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
            .background(RoundedRectangle(cornerRadius: OT.R.pill30).fill(OT.C.raised))
            .background(GeometryReader { g in
                Color.clear.onAppear { fitComposer(g.size.height) }.onChange(of: g.size.height) { _, h in fitComposer(h) }
            })
            .overlay {
                if fieldFocused || dropTargeted { RoundedRectangle(cornerRadius: OT.R.pill30).stroke(OT.C.claude, lineWidth: 1.5) }
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
        .onDisappear { OrchestratorExpand.shared.setFit("composer", extra: 0, vm: vm, window: anchor.window) }
    }

    /// The open notch grows with extra composer lines; at expanded/terminal the column absorbs them.
    private func fitComposer(_ h: CGFloat) {
        composerH = h
        OrchestratorExpand.shared.setFit("composer", extra: expanded ? 0 : h - 30, vm: vm, window: anchor.window)
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
        } else if store.draft.isEmpty, store.boxIsDraft, let l = store.inputLine, !l.isEmpty {
            (Text(verbatim: "from terminal · ").foregroundStyle(OT.C.text5) + Text(verbatim: l).foregroundStyle(OT.C.text6))
                .font(OT.F.ui).lineLimit(1).allowsHitTesting(false)
        } else if store.draft.isEmpty {
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
        let blank = store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && store.attachments.isEmpty
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

    /// Terminal store.draft -> field on focus; key monitor lifecycle.
    private func focusChanged(_ f: Bool) {
        guard f else { removeKeyMonitor(); return }
        installKeyMonitor()
        if caretToEnd {
            caretToEnd = false
            DispatchQueue.main.async { moveCaretToEnd(in: keyWindow) }
        }
        if store.draft.isEmpty, store.boxIsDraft, let l = store.inputLine, !l.isEmpty {
            store.draft = l
            store.draftFromTerminal = true
        }
    }

    // ponytail: local-monitor key handling; swap to onKeyPress if it proves reliable for Tab in the panel.
    // Tab/→ accept and ⌃U are local only (user, 2026-10-14): every send clears Claude's box first.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard fieldFocused, event.window === keyWindow else { return event }
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            // Plain Return sends (the vertical field would insert a line); Shift/Option-Return fall through.
            if (event.keyCode == 36 || event.keyCode == 76), mods.isEmpty,
               (event.window?.firstResponder as? NSTextView)?.hasMarkedText() != true {
                submit()
                return nil
            }
            if (event.keyCode == 48 || event.keyCode == 124), mods.isEmpty, let g = suggestion {
                store.draft = g
                store.draftFromTerminal = false
                return nil
            }
            if event.keyCode == 32, mods == .control {
                let tv = event.window?.firstResponder as? NSTextView
                store.draft = clearToCaret(store.draft, caretUTF16: tv?.selectedRange().location)
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

    /// Brief "Copied" toast over the transcript after a drag-select.
    private func showCopied() {
        copyGen += 1
        let gen = copyGen
        withAnimation(.easeOut(duration: 0.15)) { copiedToast = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            if copyGen == gen { withAnimation(.easeOut(duration: 0.15)) { copiedToast = false } }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }

    /// Type-to-focus: a printable key while this notch is open on the tab and key, with the composer unfocused, starts
    /// typing with that character. A local monitor only sees keys sent to this app, never another frontmost app's.
    private func installTypeMonitor() {
        guard typeMonitor == nil else { return }
        typeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let w = anchor.window, event.window === w else { return event }
            let ctx = ComposerKeyContext(
                notchOpen: vm.notchState == .open,
                orchestratorTab: BoringViewCoordinator.shared.currentView == .orchestrator,
                appActive: NSApp.isActive,
                windowIsKey: w.isKeyWindow,
                composerFocused: fieldFocused,
                terminalFocused: OrchestratorKeyGate.terminalWantsKey,
                editingOtherText: (w.firstResponder as? NSTextView)?.isEditable == true,
                cardShowing: manager.prompt.map { promptIdentity($0) != PromptCardController.shared.dismissed } ?? false)
            guard let s = typeToFocusText(characters: event.characters, modifierFlags: event.modifierFlags.rawValue, context: ctx) else { return event }
            store.draft += s
            caretToEnd = true
            startTyping()
            return nil
        }
    }

    private func removeTypeMonitor() {
        if let m = typeMonitor { NSEvent.removeMonitor(m) }
        typeMonitor = nil
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
        let t = store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty || !store.attachments.isEmpty else { stopTyping(); return }
        // A terminal draft not pulled in on focus would be C-u'd unseen: pull it in front and wait for a second Enter.
        if !store.draftFromTerminal, store.boxIsDraft, let l = store.inputLine, !l.isEmpty {
            store.draft = l + " " + store.draft
            store.draftFromTerminal = true
            return
        }
        stick = true; unseen = false
        store.enqueue(t, images: store.takeAttachments())
        store.draft = ""
        store.draftFromTerminal = false
    }
}

#if ORCH_SNAPSHOT
var orchSnapDiffOpen = false
#endif

/// Equatable on what it draws (closures excluded): `.equatable()` at the call site skips unchanged rows, so a keystroke
/// or a new block re-lays-out only the rows whose block changed.
private struct ChatBlockRow: View, Equatable {
    static func == (a: ChatBlockRow, b: ChatBlockRow) -> Bool {
        a.block == b.block && a.proseLineLimit == b.proseLineLimit && a.expanded == b.expanded && a.caret == b.caret
    }

    let block: ChatBlock
    let proseLineLimit: Int?
    var expanded = false
    var caret = false
    var onClick: () -> Void = {}
    var onCopied: () -> Void = {}
    @State private var folded = false
    #if ORCH_SNAPSHOT
    @State private var diffOpen = orchSnapDiffOpen // open chat: "▸ diff" shows the same card inline
    #else
    @State private var diffOpen = false
    #endif

    private var canDiff: Bool {
        block.kind == .tool && ["Edit", "Write", "MultiEdit"].contains(block.name ?? "") && !(block.diff ?? []).isEmpty
    }
    private var hasDiffCard: Bool { expanded && canDiff }
    /// Inline card: taps must not reach the transcript's expandChat().
    private var cardClick: () -> Void { expanded ? onClick : {} }

    @ViewBuilder private var diffToggle: some View {
        if canDiff && !expanded {
            Button { withAnimation(.easeOut(duration: 0.15)) { diffOpen.toggle() } } label: {
                Text(verbatim: diffOpen ? "▾ diff" : "▸ diff").font(OT.F.meta).foregroundStyle(OT.C.text6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(diffOpen ? "Hide diff" : "Show diff")
        } else if block.added != nil {
            Text(verbatim: "▸ diff").font(OT.F.meta).foregroundStyle(OT.C.text6)
        }
    }

    /// Leading marker column like Claude Code's terminal (❯ user, ⏺ prose/tool); wrapped text hangs after it.
    /// Expanded view only: user messages are right-aligned bubbles and Edit rows fold out into a diff card.
    @ViewBuilder var body: some View {
        if expanded && block.kind == .user {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OrchestratorSelectableText(block.text ?? "", font: NSFont.systemFont(ofSize: 12), color: NSColor(OT.C.text2),
                                           onClick: onClick, onCopied: onCopied)
                    .padding(.vertical, 6).padding(.horizontal, 10)
                    .background(OT.C.raised, in: UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 4, topTrailingRadius: 12))
                    .containerRelativeFrame(.horizontal, alignment: .trailing) { w, _ in w * 0.8 }
            }
            .transition(.identity) // a level change swaps this branch in place; no cross-fade
        } else if hasDiffCard {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                marker.frame(width: 10, alignment: .center)
                diffCard.frame(maxWidth: .infinity, alignment: .leading)
            }
            .transition(.identity)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                marker.frame(width: 10, alignment: .center)
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .transition(.identity)
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
            OrchestratorSelectableText(r.text, font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), color: NSColor(fg), maxLines: 1,
                                       lineBreak: .byTruncatingTail, onClick: cardClick, onCopied: onCopied)
                .baselineAligned()
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
            Button { withAnimation(.easeOut(duration: 0.15)) { if expanded { folded.toggle() } else { diffOpen = false } } } label: {
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
        .contentShape(Rectangle())
        .onTapGesture { cardClick() }
    }

    @ViewBuilder private var marker: some View {
        switch block.kind {
        case .user: Text(verbatim: "❯").font(OT.F.ui).foregroundStyle(OT.C.text5)
        case .prose: dot(OT.C.text)
        case .tool:
            switch toolMarker(result: block.result) {
            case .running: if toolDescription(block) != nil { OrchPulseDot(color: OT.C.text6) } else { dot(OT.C.text6) }
            case .done: dot(OT.C.green)
            case .error: dot(OT.C.red)
            }
        }
    }

    /// U+FE0E keeps ⏺ a text glyph (not the emoji button).
    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 7, height: 7)
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 0.5 }
            .animation(.easeOut(duration: 0.25), value: c)
    }

    @ViewBuilder private var content: some View {
        switch block.kind {
        case .user:
            let first = (block.text ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            OrchestratorSelectableText(first, font: NSFont.systemFont(ofSize: 12), color: NSColor(OT.C.text5), maxLines: 1,
                                       lineBreak: .byTruncatingTail, onClick: onClick, onCopied: onCopied)
                .baselineAligned()
        case .tool:
            toolRow
        case .prose:
            // lineSpacing 2 on 13pt text ~ line-height 1.35 (13 * 1.35 = 17.5 vs ~15.5 natural).
            OrchestratorSelectableText(orchestratorProseNS(proseAttributed(block.text ?? ""), size: 13, color: NSColor(OT.C.text), lineSpacing: 2),
                                       maxLines: proseLineLimit ?? 0, lineBreak: proseLineLimit == nil ? .byWordWrapping : .byTruncatingTail, onClick: onClick, onCopied: onCopied)
                .caret(caret)
                .baselineAligned()
        }
    }

    @ViewBuilder private var toolRow: some View {
        if let desc = toolDescription(block) { describedToolRow(desc) } else { plainToolRow }
    }

    private func describedToolRow(_ desc: String) -> some View {
        let target = toolTargetDisplay(name: block.name, target: block.target)
        let isPath = target.contains("/")
        let result = toolResultDisplay(name: block.name, result: block.result, added: block.added)
        return VStack(alignment: .leading, spacing: 2) {
            if block.result == nil {
                Text(verbatim: desc).font(OT.F.ui).foregroundStyle(OT.C.text2).lineLimit(2).truncationMode(.tail)
                    .orchShimmer()
            } else {
                OrchestratorSelectableText(desc, font: NSFont.systemFont(ofSize: 12), color: NSColor(OT.C.text2), maxLines: 2,
                                           lineBreak: .byTruncatingTail, onClick: onClick, onCopied: onCopied)
                    .baselineAligned()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: block.name ?? "Tool")
                    .font(OT.F.monoChip.weight(.medium)).foregroundStyle(OT.C.text4)
                    .padding(.vertical, 1).padding(.horizontal, 5)
                    .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 5))
                OrchestratorSelectableText(target, font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular), color: NSColor(OT.C.text6), maxLines: 1,
                                           lineBreak: isPath ? .byTruncatingMiddle : .byTruncatingTail, onClick: onClick, onCopied: onCopied)
                    .baselineAligned()
                if let add = block.added {
                    Text(verbatim: "+\(add)").font(OT.F.monoChip).foregroundStyle(OT.C.green)
                    Text(verbatim: "\u{2212}\(block.removed ?? 0)").font(OT.F.monoChip).foregroundStyle(OT.C.redText)
                    diffToggle
                }
            }
            if diffOpen && !expanded && canDiff { diffCard }
            if let r = result {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\u{23BF}").font(OT.F.meta).foregroundStyle(OT.C.text6)
                    OrchestratorSelectableText(r, font: NSFont.systemFont(ofSize: 11), color: NSColor(toolResultIsError(block.result) ? OT.C.redText : OT.C.text6),
                                               maxLines: 1, lineBreak: .byTruncatingTail, onClick: onClick, onCopied: onCopied)
                        .baselineAligned()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: toolMarker(result: block.result))
    }

    private var plainToolRow: some View {
        let target = toolTargetDisplay(name: block.name, target: block.target)
        let isPath = target.contains("/")
        return VStack(alignment: .leading, spacing: 4) { HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: block.name ?? "Tool")
                .font(OT.F.monoChip.weight(.medium)).foregroundStyle(OT.C.text3)
                .padding(.vertical, 2).padding(.horizontal, 6)
                .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 5))
            OrchestratorSelectableText(target, font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), color: NSColor(OT.C.text2), maxLines: 1,
                                       lineBreak: isPath ? .byTruncatingMiddle : .byTruncatingTail, onClick: onClick, onCopied: onCopied)
                .baselineAligned()
            if let add = block.added {
                Text(verbatim: "+\(add)").font(OT.F.monoChip).foregroundStyle(OT.C.green)
                Text(verbatim: "\u{2212}\(block.removed ?? 0)").font(OT.F.monoChip).foregroundStyle(OT.C.redText)
                diffToggle
            } else if let r = toolResultDisplay(name: block.name, result: block.result, added: block.added) {
                OrchestratorSelectableText(r, font: NSFont.systemFont(ofSize: 11), color: NSColor(toolResultIsError(block.result) ? OT.C.redText : OT.C.text6),
                                           maxLines: 1, lineBreak: .byTruncatingTail, onClick: onClick, onCopied: onCopied)
                    .baselineAligned()
            }
        }
            if diffOpen && !expanded && canDiff { diffCard }
        }
    }
}

/// "✻ Verb · m:ss · ↓ tokens  esc to interrupt". Elapsed ticks each second between polls; the accent text shimmers.
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
        var verb = status.text
        if verb.hasSuffix("…") { verb.removeLast() } else if verb.hasSuffix("...") { verb.removeLast(3) }
        var t = "✻ " + (verb.isEmpty ? "Working" : verb)
        if status.elapsed != nil { t += " · " + formatElapsed(anchor.base + now.timeIntervalSince(anchor.at)) }
        if let k = status.tokens { t += " · " + k }
        return Text(verbatim: t).font(OT.F.meta).foregroundStyle(OT.C.claude).lineLimit(1).orchShimmer()
    }
}

/// White highlight sweeping across the content every 1.6s, masked by the content; static with Reduce Motion.
/// The sweep is a Core Animation on a gradient layer (no per-frame SwiftUI work).
private final class ShimmerNSView: NSView {
    private let band = CAGradientLayer()
    private var animatedWidth: CGFloat = 0
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        band.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.45).cgColor, NSColor.clear.cgColor]
        band.startPoint = CGPoint(x: 0, y: 0.5); band.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(band)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.width != animatedWidth else { return }
        animatedWidth = bounds.width
        let w = bounds.width
        CATransaction.begin(); CATransaction.setDisableActions(true)
        band.bounds = CGRect(x: 0, y: 0, width: w * 0.5, height: bounds.height)
        band.position = CGPoint(x: -0.25 * w, y: bounds.midY)
        CATransaction.commit()
        band.add(orchAnimation("position.x", from: -0.25 * w, to: 1.25 * w, duration: 1.6, autoreverses: false, linear: true), forKey: "sweep")
    }
}

private struct ShimmerLayer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ShimmerNSView(frame: .zero) }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct OrchShimmer: ViewModifier {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion { ShimmerLayer().mask(content) }
        }
    }
}

private extension View {
    func orchShimmer(_ active: Bool = true) -> some View { modifier(OrchShimmer(active: active)) }
}

/// Grey running dot that pulses 1 <-> 0.35 (static with Reduce Motion); a Core Animation like the shimmer.
private struct OrchPulseDot: View {
    let color: Color
    var body: some View {
        OrchLayer(size: CGSize(width: 7, height: 7)) { root in
            let l = CALayer()
            l.frame = root.bounds
            l.backgroundColor = NSColor(color).cgColor; l.cornerRadius = 3.5
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                l.add(orchAnimation("opacity", from: 1, to: 0.35, duration: 0.9, autoreverses: true), forKey: "pulse")
            }
            root.addSublayer(l)
        }
        .frame(width: 7, height: 7)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 0.5 }
    }
}

// MARK: - Selectable transcript text

/// Non-editable, transparent NSTextView used as a SwiftUI text replacement that can be drag-selected.
/// `mouseDown` runs AppKit's tracking loop until mouse-up, so when `super` returns the selection is final:
/// non-empty -> copy + toast; empty (a plain click) -> `onClick`, because this view swallows the click the
/// transcript's tap-to-expand would have received.
final class OrchestratorSelectableTextView: NSTextView {
    private static weak var active: OrchestratorSelectableTextView?
    var onClick: () -> Void = {}
    var onCopied: () -> Void = {}
    var current: NSAttributedString? { didSet { fitCache = [:] } }
    /// SwiftUI asks for the size several times per layout pass (and again on every composer keystroke that reflows the column);
    /// laying the text out in a fresh stack each time dominated the typing cost. Keyed by width, line limit and break mode.
    private struct FitKey: Hashable { let width: CGFloat; let lines: Int; let mode: UInt }
    private var fitCache: [FitKey: CGSize] = [:]
    /// Streaming caret (08-03): 7x13 accent block after the last laid-out glyph; a CALayer, so blinking never
    /// touches the text storage (selection survives). Static with Reduce Motion.
    var caretOn = false { didSet { if caretOn != oldValue { needsLayout = true } } }
    private let caretLayer = CALayer()

    override func layout() {
        super.layout()
        guard caretOn, let lm = layoutManager, let tc = textContainer else { caretLayer.removeFromSuperlayer(); return }
        wantsLayer = true
        if caretLayer.superlayer == nil {
            caretLayer.backgroundColor = NSColor(OT.C.claude).cgColor
            caretLayer.cornerRadius = 1
            caretLayer.bounds = CGRect(x: 0, y: 0, width: 7, height: 13)
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1; a.toValue = 0.2; a.duration = 0.5; a.autoreverses = true; a.repeatCount = .infinity
                caretLayer.add(a, forKey: "blink")
            }
            layer?.addSublayer(caretLayer)
        }
        lm.ensureLayout(for: tc)
        let g = lm.glyphRange(for: tc)
        guard g.length > 0 else { caretLayer.removeFromSuperlayer(); return }
        let r = lm.lineFragmentUsedRect(forGlyphAt: g.upperBound - 1, effectiveRange: nil)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        caretLayer.position = CGPoint(x: min(r.maxX + 5.5, max(bounds.width - 3.5, 3.5)), y: r.midY)
        CATransaction.commit()
    }

    convenience init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager() // TextKit 1: line limits and truncation
        let container = NSTextContainer(size: NSSize(width: 100, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
        isEditable = false
        isSelectable = true
        isRichText = false
        drawsBackground = false
        textContainerInset = .zero
        isVerticallyResizable = false
        isHorizontallyResizable = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        selectedTextAttributes = [.backgroundColor: NSColor(OT.C.selected2)]
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// First responder only while a drag is tracked: an always-willing selectable text view in the panel makes
    /// AppKit swallow the click that follows on the composer and the header.
    private var tracking = false
    override var acceptsFirstResponder: Bool { tracking }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer?.size = NSSize(width: newSize.width, height: .greatestFiniteMagnitude)
    }

    override func mouseDown(with event: NSEvent) {
        if let a = Self.active, a !== self { a.setSelectedRange(NSRange(location: 0, length: 0)) }
        Self.active = self
        tracking = true
        super.mouseDown(with: event)
        tracking = false
        let r = selectedRange()
        if r.length > 0, r.location + r.length <= string.utf16.count {
            let pb = OrchestratorSelectableText.pasteboard
            pb.clearContents()
            pb.setString((string as NSString).substring(with: r), forType: .string)
            onCopied()
        } else {
            onClick()
        }
    }

    /// Used size at `width` (nil = unbounded) with the container's line limit and break mode. Measured in a fresh
    /// text stack: resizing the live container leaves usedRect stale.
    func fit(width: CGFloat?) -> CGSize {
        guard let live = textContainer, let text = current else { return .zero }
        let key = FitKey(width: width ?? -1, lines: live.maximumNumberOfLines, mode: live.lineBreakMode.rawValue)
        if let hit = fitCache[key] { return hit }
        if fitCache.count > 16 { fitCache = [:] }
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        let tc = NSTextContainer(size: NSSize(width: width ?? 100_000, height: .greatestFiniteMagnitude))
        tc.lineFragmentPadding = 0
        tc.maximumNumberOfLines = live.maximumNumberOfLines
        tc.lineBreakMode = live.lineBreakMode
        storage.addLayoutManager(layout)
        layout.addTextContainer(tc)
        layout.ensureLayout(for: tc)
        let u = layout.usedRect(for: tc)
        let size = CGSize(width: ceil(u.width), height: u.height)
        fitCache[key] = size
        return size
    }
}

struct OrchestratorSelectableText: NSViewRepresentable {
    /// The system pasteboard; the snapshot harness swaps in a private one.
    static var pasteboard: NSPasteboard = .general

    let text: NSAttributedString
    var maxLines = 0 // 0 = unlimited
    var lineBreak: NSLineBreakMode = .byWordWrapping
    var onClick: () -> Void = {}
    var onCopied: () -> Void = {}
    var caret = false

    func caret(_ on: Bool) -> Self { var c = self; c.caret = on; return c }

    init(_ text: NSAttributedString, maxLines: Int = 0, lineBreak: NSLineBreakMode = .byWordWrapping,
         onClick: @escaping () -> Void = {}, onCopied: @escaping () -> Void = {}) {
        self.text = text; self.maxLines = maxLines; self.lineBreak = lineBreak
        self.onClick = onClick; self.onCopied = onCopied
    }

    init(_ string: String, font: NSFont, color: NSColor, maxLines: Int = 0, lineBreak: NSLineBreakMode = .byWordWrapping,
         onClick: @escaping () -> Void = {}, onCopied: @escaping () -> Void = {}) {
        self.init(NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color]),
                  maxLines: maxLines, lineBreak: lineBreak, onClick: onClick, onCopied: onCopied)
    }

    /// First baseline from the top, like Text's.
    private var ascent: CGFloat {
        ((text.length > 0 ? text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil) ?? NSFont.systemFont(ofSize: 12)).ascender
    }

    func makeNSView(context: Context) -> OrchestratorSelectableTextView {
        let v = OrchestratorSelectableTextView()
        apply(to: v)
        return v
    }

    func updateNSView(_ v: OrchestratorSelectableTextView, context: Context) { apply(to: v) }

    private func apply(to v: OrchestratorSelectableTextView) {
        v.onClick = onClick
        v.onCopied = onCopied
        v.caretOn = caret
        v.textContainer?.maximumNumberOfLines = maxLines
        v.textContainer?.lineBreakMode = lineBreak
        if v.current?.isEqual(to: text) != true { // keep the selection across polls
            v.current = text
            v.textStorage?.setAttributedString(text)
            if v.caretOn { v.needsLayout = true }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView v: OrchestratorSelectableTextView, context: Context) -> CGSize? {
        let w = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        let s = v.fit(width: w)
        return CGSize(width: min(s.width, w ?? s.width), height: s.height)
    }
}

extension OrchestratorSelectableText {
    /// Baseline-aligned like Text inside an HStack(.firstTextBaseline).
    func baselineAligned() -> some View {
        let a = ascent
        return alignmentGuide(.firstTextBaseline) { _ in a }
    }
}

/// proseAttributed's emphasis (bold, italic, code) as an NSAttributedString at the prose size.
func orchestratorProseNS(_ a: AttributedString, size: CGFloat, color: NSColor, lineSpacing: CGFloat) -> NSAttributedString {
    let out = NSMutableAttributedString()
    let para = NSMutableParagraphStyle()
    para.lineSpacing = lineSpacing
    for run in a.runs {
        let intent = run.inlinePresentationIntent ?? []
        var font = intent.contains(.code) ? NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular) : NSFont.systemFont(ofSize: size)
        if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        out.append(NSAttributedString(string: String(a[run.range].characters),
                                      attributes: [.font: font, .foregroundColor: color, .paragraphStyle: para]))
    }
    return out
}
