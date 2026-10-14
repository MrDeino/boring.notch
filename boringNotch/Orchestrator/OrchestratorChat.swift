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
        // ponytail: full resync about every 15th open poll (~30 s) because /clear or a new transcript is
        // otherwise invisible to `since`; SSE in Phase 8 removes it.
        let full = needsFull || polls % 15 == 0
        polls += 1

        var comps = URLComponents(url: base.appendingPathComponent("api/chat/blocks"), resolvingAgainstBaseURL: false)
        let sinceSent = !full && !blocks.isEmpty
        if sinceSent { comps?.queryItems = [URLQueryItem(name: "since", value: blocks.last?.id)] }
        guard let url = comps?.url,
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = decodeChatBlocks(data) else {
            if !fallback { fallback = true }
            return
        }
        if decoded.running == false && decoded.blocks.isEmpty {
            if !blocks.isEmpty { blocks = [] }
            fallback = true
            needsFull = true
            return
        }
        let reset = full || blocksDiscontinuous(sinceSent: sinceSent, incoming: decoded.blocks, existing: blocks)
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
    }

    func postKey(_ key: String) async {
        guard let base, let session else { return }
        _ = try? await sendOrchestratorPost(.key(key), base: base, session: session)
    }

    func clearRealLineIfNeeded() async {
        if let l = inputLine, !l.isEmpty { await postKey("C-u") }
    }
}

struct OrchestratorChatView: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var draft = ""
    @EnvironmentObject var vm: BoringViewModel
    @State private var keyWindow: NSWindow?
    @State private var anchor = NSView()
    @FocusState private var fieldFocused: Bool
    private let showComposer: Bool

    init(showComposer: Bool = true) { self.showComposer = showComposer }

    var body: some View {
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
            if showComposer { composer }
        }
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
        // Phase 4
        .onChange(of: manager.statusMenuOpen) { _, open in if open { stopTyping() } }
    }

    private var composer: some View {
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
        stopTyping()
        Task { if await manager.sendText(t) { draft = "" } }
    }
}
