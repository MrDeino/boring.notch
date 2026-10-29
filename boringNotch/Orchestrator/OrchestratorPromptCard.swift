import SwiftUI
import Combine

// Phase 6: permission decision card (frame 03) and question list (frame 04).

/// Cross-mount state for the prompt card. The card remounts whenever the expand level changes,
/// so nothing that must survive that lives in @State. 06-03 extends this class (keys, free text).
@MainActor
final class PromptCardController: ObservableObject {
    static let shared = PromptCardController()

    @Published var pressed: Int?
    @Published var highlighted: Int?
    @Published var flash = false
    private var shown: PromptCard?
    private weak var hoverWindow: NSWindow?
    private var bag = Set<AnyCancellable>()
    private weak var keyWindow: NSWindow?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var dwell: Task<Void, Never>?
    private var hovering = false
    private var keyTakenAt = Date.distantPast
    private var mounted = 0
    /// Editing ending with the pointer outside re-runs the exit dwell, else the key-take outlives the hover.
    @Published var fieldEditing = false { didSet { if oldValue, !fieldEditing, !hovering { hover(false, window: nil) } } }
    @Published var focusField = false
    @Published var freeText = ""
    @Published private(set) var submitting = false
    /// Optimistic answer: the card with this identity is hidden at once; restored if the screen never moved on.
    @Published private(set) var dismissed: PromptIdentity?
    @Published private(set) var note: String?
    /// Optimistic checkbox state: taps show at once, and stay until the queue has drained and the screen has been compared with them.
    @Published private(set) var pending: [Int: Bool] = [:]
    /// Keys outside the `sending` window: the queue sends back-to-back while the rest of the UI stays live.
    private let queue = PromptKeyQueue { await OrchestratorManager.shared.postCode(.key($0)) == 200 }
    private var reconciling: Task<Void, Never>?
    private var busy = false
    private var lastId: PromptIdentity?
    private var noteGen = 0
    private let spring = Animation.spring(response: 0.3, dampingFraction: 0.85)

    private init() {
        OrchestratorManager.shared.$prompt.sink { [weak self] card in
            // $prompt emits before the property changes; hop to the main queue.
            DispatchQueue.main.async { self?.promptChanged(card) }
        }.store(in: &bag)
    }

    private func promptChanged(_ card: PromptCard?) {
        let id = card.map(promptIdentity)
        if id != lastId { lastId = id; pressed = nil; dismissed = nil; note = nil; pending = [:]; busy = false }
        if card == nil { release() } else if hovering, let w = hoverWindow { hover(true, window: w) }
    }

    func sync(_ card: PromptCard?, vm: BoringViewModel, window: NSWindow?) {
        if card != shown {
            shown = card
            highlighted = card?.highlighted ?? card?.items.first?.number
        }
    }

    /// True when the live prompt is still the one the user clicked on.
    private func stillCurrent(_ displayed: PromptCard) async -> Bool {
        await OrchestratorManager.shared.refresh(fresh: true)
        let m = OrchestratorManager.shared
        guard let cur = m.prompt, promptIdentity(cur) == promptIdentity(displayed) else {
            await flashStale()
            return false
        }
        return true
    }

    private func flashStale() async {
        flash = true
        try? await Task.sleep(for: .milliseconds(250))
        flash = false
    }

    /// Hide the card now, queue `keys` behind any ticks still in flight, and bring the card back with a note if ~2s later the same prompt is still up.
    /// Never re-sends by itself: the user taps again. If the screen disagrees with the ticks shown, nothing is submitted and the screen's state is shown.
    private func answer(_ keys: [String], pressed n: Int?, displayed: PromptCard) {
        guard !busy, dismissed == nil else { return }
        busy = true
        let id = promptIdentity(displayed)
        let t0 = Date()
        note = nil
        pressed = n
        let hides = hidesOnAnswer(displayed, keys: keys)
        Task {
            let m = OrchestratorManager.shared
            if hides {
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(spring) { dismissed = id }
            }
            reconciling?.cancel()
            guard await queue.settle() else { pending = [:]; restore(note: "Didn't go through"); return }
            guard await stillCurrent(displayed) else { restore(note: nil); return }
            if !pending.isEmpty, await screenShowsTicks(displayed) == false { pending = [:]; restore(note: Self.resync); return }
            pending = [:]
            queue.enqueue(keys)
            guard await queue.settle() else { restore(note: "Didn't go through"); return }
            try? await Task.sleep(for: .seconds(max(0, 2 - Date().timeIntervalSince(t0))))
            await m.refresh(fresh: true)
            if m.stale { restore(note: nil); return } // can't tell whether it moved on: show the card; the next good read decides
            if let cur = m.prompt, promptIdentity(cur) == id { restore(note: "Didn't go through"); return }
            // ponytail: identity-equal first redraw (chip flips before the question text) just shows this step a moment longer; a 2 s no-move still says "Didn't go through".
            if hides { release() } // else the next question is on screen: keep the card and its key focus
        }
    }

    private static let resync = "Re-synced: a tap didn't register"
    private static let waiting = "Waiting for the orchestrator…"

    private func restore(note text: String?) {
        withAnimation(spring) { dismissed = nil }
        pressed = nil
        busy = false
        show(note: text)
    }

    private func show(note text: String?) {
        note = text
        noteGen += 1
        let g = noteGen
        if text != nil { Task { try? await Task.sleep(for: .seconds(3)); if noteGen == g { note = nil } } }
    }

    func choose(_ n: Int, displayed: PromptCard) {
        guard let item = displayed.items.first(where: { $0.number == n }) else { return }
        if item.role == .freeText { focusField = true; return }
        if item.checked != nil { toggle(n, displayed: displayed); return }
        answer([String(n)], pressed: n, displayed: displayed)
    }

    func toggle(_ n: Int, displayed: PromptCard) {
        guard !busy, let item = displayed.items.first(where: { $0.number == n }), let was = item.checked else { return }
        pending[n] = !(pending[n] ?? was)
        queue.enqueue([String(n)])
        // ponytail: a key queued for a card that has since changed on the screen (answered at the terminal) is still sent; Esc and answers drop/flush the queue.
        reconciling?.cancel()
        reconciling = Task { await reconcile(displayed) }
    }

    /// After the queue drains: the screen must show the ticks. If it never does (a key was lost), show its state and say so.
    private func reconcile(_ displayed: PromptCard) async {
        guard await queue.settle() else { if !Task.isCancelled { pending = [:]; show(note: "Didn't go through") }; return }
        guard let ok = await screenShowsTicks(displayed) else { return }
        pending = [:]
        if !ok { show(note: Self.resync) }
    }

    /// True once the screen shows `pending` (or the card has moved on); re-reads a few times, the TUI may not have redrawn yet.
    /// nil: a newer tap owns the comparison.
    private func screenShowsTicks(_ displayed: PromptCard) async -> Bool? {
        let m = OrchestratorManager.shared
        for attempt in 0..<4 {
            await m.refresh(fresh: true)
            guard !Task.isCancelled, queue.isIdle else { return nil }
            guard let cur = m.prompt, promptIdentity(cur) == promptIdentity(displayed) else { return true }
            if promptMismatches(expected: pending, card: cur).isEmpty { return true }
            if attempt < 3 { try? await Task.sleep(for: .milliseconds(250)) }
        }
        return false
    }

    /// Multi-select has no Submit key: Tab is "done, next" (and from the last question lands on the review step).
    func next(displayed: PromptCard) { answer(["Tab"], pressed: -1, displayed: displayed) }

    /// d chips ahead = d x Tab, d chips back = d x BTab (see tabKeys).
    func goTab(_ k: Int, displayed: PromptCard) {
        guard let cur = displayed.currentTab, let keys = tabKeys(from: cur, to: k, review: displayed.review) else { return }
        answer(keys, pressed: nil, displayed: displayed)
    }

    func escape(displayed: PromptCard) {
        queue.cancel()
        reconciling?.cancel()
        pending = [:]
        Task {
            guard await stillCurrent(displayed) else { return }
            await OrchestratorManager.shared.pressEscape()
            release()
        }
    }

    // MARK: Hover key-take (PRM-04)

    func hover(_ inside: Bool, window w: NSWindow?) {
        hovering = inside
        if inside { hoverWindow = w }
        dwell?.cancel()
        if inside {
            dwell = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, hovering, let w else { return }
                takeKey(w)
            }
        } else {
            dwell = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, !hovering, !fieldEditing else { return }
                release()
            }
        }
    }

    func takeKey(_ w: NSWindow) {
        // ponytail: hover-dwell focus take steals keystrokes from the frontmost app while the pointer rests
        // on the notch; upgrade path is Phase 9's global option-return / option-escape.
        let m = OrchestratorManager.shared
        guard keyWindow == nil, m.prompt != nil, !m.wantsKeyboard, !OrchestratorKeyGate.terminalWantsKey else { return }
        m.beginTyping(in: w)
        keyWindow = w
        keyTakenAt = Date()
        OrchestratorKeyGate.activate()
        w.makeKey()
        DispatchQueue.main.async { if self.keyWindow === w { w.makeKey() } }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e) ?? e
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.release(refocus: false) }
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            if keyWindow === w, !w.isKeyWindow { release() }
        }
    }

    func release(refocus: Bool = true) {
        guard let w = keyWindow else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        fieldEditing = false
        let wasKey = w.isKeyWindow
        OrchestratorManager.shared.endTyping()
        keyWindow = nil
        // The terminal took the panel over: leave its focus and activation alone.
        guard !OrchestratorKeyGate.terminalWantsKey else { return }
        w.makeFirstResponder(nil)
        OrchestratorKeyGate.restore(refocus: refocus && wasKey)
    }

    private func handle(_ e: NSEvent) -> NSEvent? {
        // Keys for other windows, or the ttyd terminal once it is up, are never prompt answers.
        guard let card = shown, e.window === keyWindow, !OrchestratorKeyGate.terminalWantsKey else { return e }
        let combo = !e.modifierFlags.intersection([.command, .control, .option]).isEmpty
        let k = promptKey(keyCode: e.keyCode, characters: e.charactersIgnoringModifiers, commandLike: combo,
                          editingText: fieldEditing || NSApp.keyWindow?.firstResponder is NSText,
                          kind: card.kind, numbers: Set(card.items.map(\.number)))
        let nums = card.items.filter { $0.role == .normal }.map(\.number) // only rows that draw a highlight
        // Keys still being typed for the app the hover just took focus from are swallowed, not answers.
        // ponytail: 300 ms grace only; a click-to-arm for permission cards is Phase 9's call.
        if k != .pass, Date().timeIntervalSince(keyTakenAt) < 0.3 { return nil }
        switch k {
        case .pass: return e
        case .answer(let n): choose(n, displayed: card)
        case .escape: escape(displayed: card)
        case .up: highlighted = moveHighlight(highlighted, by: -1, in: nums)
        case .down: highlighted = moveHighlight(highlighted, by: 1, in: nums)
        case .select: if let h = highlighted, nums.contains(h) { choose(h, displayed: card) }
        }
        return nil
    }

    func appeared() { mounted += 1 }
    func disappeared() {
        mounted -= 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.mounted == 0 { self.hovering = false; self.dwell?.cancel(); self.release() }
        }
    }

    // MARK: Free text (PRM-05)

    func requestField(window w: NSWindow?) {
        if keyWindow == nil, let w { takeKey(w) }
        focusField = true
    }

    func submitFreeText(displayed: PromptCard) {
        let t = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !submitting, let ft = displayed.items.first(where: { $0.role == .freeText }) else { return }
        guard !busy, dismissed == nil else { return }
        submitting = true
        busy = true
        let id = promptIdentity(displayed)
        // Typing an answer to one of several questions only moves to the next one: the card stays up then.
        let hides = hidesOnAnswer(displayed, keys: [])
        if hides { withAnimation(spring) { dismissed = id } }
        Task {
            defer { submitting = false }
            let m = OrchestratorManager.shared
            var current = await stillCurrent(displayed)
            // Serve not answering: nothing typed yet. Keep the card and the text up, and go once it is back (Enter stays blocked meanwhile).
            while m.stale {
                withAnimation(spring) { dismissed = nil }
                note = Self.waiting
                await m.untilReachable()
                note = nil
                if hides { withAnimation(spring) { dismissed = id } }
                current = await stillCurrent(displayed)
            }
            guard current else { restore(note: nil); return }
            // The row is an inline input: its number moves the ❯ onto it, the screen is otherwise the same. Pressing it while
            // the ❯ already sits there would type the digit into the field.
            if !freeTextFocused(m.prompt, number: ft.number) { _ = await m.pressKeys([String(ft.number)]) }
            try? await Task.sleep(for: .milliseconds(350))
            // Only type once the field has the cursor; if the press was dropped, digits and Enter would answer the list.
            var landed = false
            for _ in 0..<6 {
                var i = 0
                while m.sending && i < 40 { try? await Task.sleep(for: .milliseconds(50)); i += 1 }
                if !m.sending { await m.refresh(fresh: true) }
                // A failed GET keeps the last prompt: stale data never counts as landed.
                if !m.stale, freeTextFocused(m.prompt, number: ft.number) { landed = true; break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            // One POST only: a timeout may still have typed the text, and 409 means chat is gone.
            guard landed, !m.sending, await m.sendText(t) else { restore(note: "Didn't go through"); return }
            // Enter must move the screen on (next question, review, or the prompt gone); else keep the text and say so.
            var moved = false
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(250))
                await m.refresh(fresh: true)
                if !m.stale, m.prompt.map(promptIdentity) != id { moved = true; break }
            }
            guard moved else { restore(note: "Didn't go through"); return }
            freeText = ""
            busy = false
            if hides { release() }
        }
    }
}

struct OrchestratorPromptCard: View {
    @ObservedObject private var manager = OrchestratorManager.shared
    @ObservedObject private var ctl = PromptCardController.shared
    @EnvironmentObject private var vm: BoringViewModel
    @State private var anchor = NSView()
    @State private var shownIn = false

    var body: some View {
        Group {
            if let card = manager.prompt, promptIdentity(card) != ctl.dismissed {
                Group {
                    switch card.kind {
                    case .permission: PermissionCard(card: card)
                    case .question: QuestionCard(card: card)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .layoutPriority(1)
        .opacity(ctl.flash ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.12), value: ctl.flash)
        .background(WindowAnchor(view: anchor))
        .task(id: manager.prompt) {
            try? await Task.sleep(for: .milliseconds(50)) // let the anchor get a window
            ctl.sync(manager.prompt, vm: vm, window: anchor.window)
        }
        .offset(y: shownIn ? 0 : 12)
        .opacity(shownIn ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { shownIn = true }; ctl.appeared() }
        .onDisappear { ctl.disappeared() }
        .onHover { ctl.hover($0, window: anchor.window) }
        .environment(\.promptWindow, anchor)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: manager.prompt)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: ctl.dismissed)
    }
}

// MARK: - Shared pieces

private struct PromptWindowKey: EnvironmentKey { static let defaultValue = NSView() }
private extension EnvironmentValues {
    var promptWindow: NSView { get { self[PromptWindowKey.self] } set { self[PromptWindowKey.self] = newValue } }
}

extension View {
    fileprivate func measureHeight(_ h: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h.wrappedValue = $0 }
    }
    /// At the open level the notch grows to the card's natural height (see promptFitExtra); the scroll only takes over past the cap.
    fileprivate func promptFit(content: CGFloat, viewport: CGFloat, card: CGFloat) -> some View {
        modifier(PromptFit(need: content > 0 && viewport > 0 && card > 0 ? (content + card - viewport).rounded() : 0))
    }
}

/// Reports the card's need once per change (a short settle filters the mid-layout readings), asks 0 when it leaves.
private struct PromptFit: ViewModifier {
    let need: CGFloat
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var expand = OrchestratorExpand.shared
    @Environment(\.promptWindow) private var anchor

    func body(content: Content) -> some View {
        content
            .task(id: "\(need)\(expand.level(for: vm) == .open)") {
                try? await Task.sleep(for: .milliseconds(40))
                guard !Task.isCancelled else { return }
                #if ORCH_SNAPSHOT
                PromptFitProbe.last = need
                #endif
                let extra = need > 0 && expand.level(for: vm) == .open ? promptFitExtra(need: need) : 0
                expand.setFit("card", extra: extra, vm: vm, window: anchor.window)
            }
            .onDisappear { expand.setFit("card", extra: 0, vm: vm, window: anchor.window) }
    }
}

#if ORCH_SNAPSHOT
/// Snapshot harness only: the last settled need reported by a card (content + its fixed chrome).
@MainActor enum PromptFitProbe { static var last: CGFloat = 0 }
#endif

/// Tallest the question text grows before it scrolls inside the card (about 10 lines).
let briefMaxHeight: CGFloat = 150

/// Question text from `briefBlocks`: paragraphs and list items with inline markdown (bold, `code`); text is selectable-free like the rest of the card.
struct BriefText: View {
    let blocks: [BriefBlock]
    let font: Font
    var color: Color = OT.C.text
    var spacing: CGFloat = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                switch b.kind {
                case .para:
                    Text(proseAttributed(b.text)).font(font).foregroundStyle(color).lineSpacing(spacing)
                        .fixedSize(horizontal: false, vertical: true)
                case .item(let mark):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(verbatim: mark).font(font).foregroundStyle(OT.C.text5)
                        Text(proseAttributed(b.text)).font(font).foregroundStyle(color).lineSpacing(spacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 4)
                }
            }
        }
    }
}

private let darkDesc = Color(red: 0x48 / 255, green: 0x48 / 255, blue: 0x4A / 255) // #48484A, not an OT token

private struct PromptKeycap: View {
    let text: String
    let light: Bool
    var body: some View {
        Text(text)
            .font(OT.F.monoChip.weight(.medium))
            .foregroundStyle(light ? Color.black : OT.C.text4)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(light ? OT.C.text1 : OT.C.selected2, in: RoundedRectangle(cornerRadius: OT.R.keycap))
    }
}

private struct PromptNote: View {
    @ObservedObject private var ctl = PromptCardController.shared
    var body: some View {
        if let n = ctl.note { Text(n).font(OT.F.meta).foregroundStyle(OT.C.redText) }
    }
}

// MARK: - Permission (frame 03)

private struct PermissionCard: View {
    let card: PromptCard
    @ObservedObject private var manager = OrchestratorManager.shared
    @ObservedObject private var ctl = PromptCardController.shared
    @State private var contentH: CGFloat = 0
    @State private var viewportH: CGFloat = 0
    @State private var cardH: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PromptNote()
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.title ?? card.question ?? "Permission").font(OT.F.title).foregroundStyle(OT.C.text)
                if let p = card.purpose {
                    Text(p).font(OT.F.ui).foregroundStyle(OT.C.text5).lineLimit(1)
                }
            }
            if let body = card.body {
                ScrollView(.vertical, showsIndicators: false) {
                    (Text("$ ").foregroundColor(OT.C.text6) + Text(body).foregroundColor(OT.C.text1))
                        .font(OT.F.monoCommand)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 8))
                        .expandsOnTap()
                        .measureHeight($contentH)
                }
                .scrollBounceBehavior(.basedOnSize)
                .measureHeight($viewportH)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(card.items.filter { $0.role != .deny }, id: \.number) { pill($0) }
                Spacer(minLength: 0)
                ForEach(card.items.filter { $0.role == .deny }, id: \.number) { pill($0) }
            }
        }
        .expandsOnTap()
        .measureHeight($cardH)
        .promptFit(content: contentH, viewport: viewportH, card: cardH)
    }

    private func pill(_ item: PromptCardOption) -> some View {
        let first = item.number == 1
        let deny = item.role == .deny
        let light = first || ctl.pressed == item.number
        return Button { ctl.choose(item.number, displayed: card) } label: {
            HStack(spacing: 8) {
                Text(shortLabel(item.label)).lineLimit(1).truncationMode(.tail)
                PromptKeycap(text: deny ? "esc" : "\(item.number)", light: light)
            }
            .font(light ? OT.F.uiMedium : OT.F.ui)
            .foregroundStyle(light ? Color.black : deny ? OT.C.redText : OT.C.text)
            .padding(.leading, 14).padding(.trailing, 7)
            .frame(height: 30)
            .frame(maxWidth: 230)
            .background(light ? OT.C.text : OT.C.raised, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(manager.sending)
        .help(item.label)
    }
}

// MARK: - Question (frame 04)

private struct QuestionCard: View {
    let card: PromptCard
    @ObservedObject private var manager = OrchestratorManager.shared
    @ObservedObject private var ctl = PromptCardController.shared
    @Environment(\.promptWindow) private var anchor
    @EnvironmentObject private var vm: BoringViewModel
    @FocusState private var fieldFocused: Bool
    @State private var contentH: CGFloat = 0
    @State private var viewportH: CGFloat = 0
    @State private var cardH: CGFloat = 0
    @State private var questionH: CGFloat = 0
    @State private var questionBoxH: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PromptNote()
            if card.tabs.count > 1 {
                tabRow
            } else if card.header != nil || card.progress != nil {
                HStack(spacing: 8) {
                    if let h = card.header {
                        Text(h).font(OT.F.meta).foregroundStyle(OT.C.text5)
                            .padding(.horizontal, 8).padding(.vertical, 1)
                            .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 8))
                    }
                    if let p = card.progress { Text(p).font(OT.F.meta).foregroundStyle(OT.C.text6) }
                }
            }
            questionText
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        if card.review, let b = card.body {
                            Text(b).font(OT.F.meta).foregroundStyle(OT.C.text5).lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(card.items.filter { $0.role == .normal }, id: \.number) { row($0) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .expandsOnTap()
                    .measureHeight($contentH)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: contentH > 0 ? contentH : nil)
                .layoutPriority(1) // short on room, the question box gives way first and the options keep theirs
                .measureHeight($viewportH)
                .onChange(of: ctl.highlighted) { _, h in
                    if let h { withAnimation { proxy.scrollTo(h) } }
                }
            }
            footer
        }
        .expandsOnTap()
        .measureHeight($cardH)
        .promptFit(content: contentH + min(questionH, briefMaxHeight) - questionBoxH, viewport: viewportH, card: cardH) // the question box at its natural height, not the squeezed one
    }

    /// Paragraphs, lists and bold labels kept; a long brief scrolls in its own box so the options below stay in view.
    private var questionText: some View {
        let blocks = card.questionBlocks
        let shown = blocks.isEmpty ? [BriefBlock(kind: .para, text: card.question ?? "")] : blocks
        let brief = shown.count > 1 // a one-line question keeps the title look; a brief is regular weight so its bold labels stand out
        return ScrollView(.vertical, showsIndicators: false) {
            BriefText(blocks: shown, font: brief ? OT.F.ui : OT.F.title, spacing: brief ? 3 : 14 * 0.35)
                .frame(maxWidth: .infinity, alignment: .leading)
                .measureHeight($questionH)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minHeight: min(questionH, 44), maxHeight: questionH > 0 ? min(questionH, briefMaxHeight) : nil)
        .measureHeight($questionBoxH)
        .expandsOnTap()
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(Array(card.tabs.enumerated()), id: \.offset) { k, tab in
                let current = k == card.currentTab
                let reachable = k != card.currentTab && tabKeys(from: card.currentTab ?? k, to: k, review: card.review) != nil
                Button { ctl.goTab(k, displayed: card) } label: {
                    Text((tab.done ? "\u{2713} " : "") + tab.label).font(OT.F.meta)
                        .foregroundStyle(current ? OT.C.text : OT.C.text5)
                        .lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 1)
                        .background(current ? OT.C.selected2 : OT.C.raised, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .allowsHitTesting(reachable && !manager.sending) // not .disabled: that would dim the current chip
            }
            Spacer(minLength: 0)
        }
        .expandsOnTap()
    }

    private func row(_ item: PromptCardOption) -> some View {
        let hi = ctl.highlighted == item.number || ctl.pressed == item.number
        let box = item.checked.map { ctl.pending[item.number] ?? $0 }
        return Button { ctl.choose(item.number, displayed: card) } label: {
            HStack(alignment: .top, spacing: 8) {
                if let box {
                    Image(systemName: box ? "checkmark.square.fill" : "square").font(.system(size: 13))
                        .foregroundStyle(hi ? Color.black : box ? OT.C.text : OT.C.text5)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(hi ? Color.black : OT.C.text)
                        .lineSpacing(12 * 0.3).fixedSize(horizontal: false, vertical: true)
                    if let d = item.detail {
                        Text(d).font(OT.F.meta).foregroundStyle(hi ? darkDesc : OT.C.text5)
                            .lineSpacing(11 * 0.4).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                PromptKeycap(text: "\(item.number)", light: hi)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8).padding(.horizontal, 10)
            .background(hi ? OT.C.text : OT.C.raised, in: RoundedRectangle(cornerRadius: OT.R.cardM))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(manager.sending)
        .id(item.number)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let ft = card.items.first(where: { $0.role == .freeText }) { freeField(ft) } else { Spacer(minLength: 0) }
            if card.multiSelect {
                let last = (card.currentTab ?? 0) + 1 >= card.tabs.filter { $0.label != "Submit" }.count
                Button { ctl.next(displayed: card) } label: {
                    Text(last ? "Submit" : "Next").font(OT.F.uiMedium).foregroundStyle(Color.black)
                        .padding(.horizontal, 14).frame(height: 28)
                        .background(OT.C.text, in: Capsule())
                }
                .buttonStyle(.plain).disabled(manager.sending)
            }
            if let chat = card.items.first(where: { $0.role == .chat }) {
                footPill("Chat about this", key: "\(chat.number)") { ctl.choose(chat.number, displayed: card) }
                    .disabled(manager.sending)
            }
            footPill(nil, key: "esc") { ctl.escape(displayed: card) }
                .disabled(manager.sending)
        }
    }

    private func freeField(_ ft: PromptCardOption) -> some View {
        HStack(spacing: 8) {
            ZStack {
                TextField("Something else…", text: $ctl.freeText,
                          prompt: Text("Something else…").foregroundColor(OT.C.text6))
                    .textFieldStyle(.plain).font(OT.F.ui).foregroundStyle(.white)
                    .focused($fieldFocused)
                    .onSubmit { ctl.submitFreeText(displayed: card) }
                    .onExitCommand { fieldFocused = false }
                    .allowsHitTesting(ctl.fieldEditing)
                if !ctl.fieldEditing {
                    Color.clear.contentShape(Rectangle()).onTapGesture { ctl.requestField(window: anchor.window) }
                }
            }
            PromptKeycap(text: "\(ft.number)", light: false)
        }
        .padding(.leading, 12).padding(.trailing, 7)
        .frame(maxWidth: .infinity).frame(height: 28)
        .background(OT.C.raised, in: Capsule())
        .disabled(false)
        .onChange(of: ctl.focusField) { _, f in
            if f { DispatchQueue.main.async { fieldFocused = true }; ctl.focusField = false }
        }
        .onChange(of: fieldFocused) { _, f in ctl.fieldEditing = f }
    }

    private func footPill(_ title: String?, key: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let title { Text(title).font(OT.F.ui).foregroundStyle(OT.C.text) }
                PromptKeycap(text: key, light: false)
            }
            .padding(.leading, title == nil ? 7 : 14).padding(.trailing, 7)
            .fixedSize() // the free-text field gives way; title and keycap never squeeze
            .frame(height: 28)
            .background(OT.C.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

#if ORCH_SNAPSHOT
extension PromptCardController {
    /// Snapshot harness only: force the optimistic state a scene wants to show.
    func snapshotSet(pressed: Int? = nil, note: String? = nil, pending: [Int: Bool] = [:], dismissCurrent: Bool = false) {
        self.pressed = pressed; self.note = note; self.pending = pending; busy = false
        lastId = OrchestratorManager.shared.prompt.map(promptIdentity) // the async $prompt hop must not see a change and clear the state
        dismissed = dismissCurrent ? OrchestratorManager.shared.prompt.map(promptIdentity) : nil
    }
}
#endif
