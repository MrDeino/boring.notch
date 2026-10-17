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
    /// In-flight checkbox toggles, shown before the next screen read confirms them.
    @Published private(set) var pending: [Int: Bool] = [:]
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

    /// Hide the card now, send `keys`, and bring the card back with a note if ~2s later the same prompt is still up.
    /// Never re-sends by itself: the user taps again.
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
            guard await stillCurrent(displayed) else { restore(note: nil); return }
            let ok = await m.pressKeys(keys)
            guard ok else { restore(note: "Didn't go through"); return }
            try? await Task.sleep(for: .seconds(max(0, 2 - Date().timeIntervalSince(t0))))
            await m.refresh(fresh: true)
            if !m.offline, let cur = m.prompt, promptIdentity(cur) == id { restore(note: "Didn't go through"); return }
            // ponytail: identity-equal first redraw (chip flips before the question text) just shows this step a moment longer; a 2 s no-move still says "Didn't go through".
            if hides { release() } // else the next question is on screen: keep the card and its key focus
        }
    }

    private func restore(note text: String?) {
        withAnimation(spring) { dismissed = nil }
        pressed = nil
        busy = false
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
        let to = !(pending[n] ?? was)
        pending[n] = to
        Task {
            if await stillCurrent(displayed) { _ = await OrchestratorManager.shared.pressKeys([String(n)]) }
            pending[n] = nil // the screen read inside pressKeys is the truth now
        }
    }

    /// Multi-select has no Submit key: Tab is "done, next" (and from the last question lands on the review step).
    func next(displayed: PromptCard) { answer(["Tab"], pressed: -1, displayed: displayed) }

    /// d chips ahead = d x Tab, d chips back = d x BTab (see tabKeys).
    func goTab(_ k: Int, displayed: PromptCard) {
        guard let cur = displayed.currentTab, let keys = tabKeys(from: cur, to: k, review: displayed.review) else { return }
        answer(keys, pressed: nil, displayed: displayed)
    }

    func escape(displayed: PromptCard) {
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
        withAnimation(spring) { dismissed = id }
        Task {
            defer { submitting = false }
            let m = OrchestratorManager.shared
            guard await stillCurrent(displayed) else { restore(note: nil); return }
            // ponytail: number-then-text acceptance is UAT A1.
            _ = await m.pressKeys([String(ft.number)])
            try? await Task.sleep(for: .milliseconds(350))
            // Only type once the select list has left the screen; if the press was dropped, digits and
            // Enter would answer the list, so re-check a few times.
            var landed = false
            for _ in 0..<6 {
                var i = 0
                while m.sending && i < 40 { try? await Task.sleep(for: .milliseconds(50)); i += 1 }
                if !m.sending { await m.refresh(fresh: true) }
                // A failed GET also nils the prompt, so offline never counts as landed.
                if !m.offline, m.prompt.map(promptIdentity) != promptIdentity(displayed) { landed = true; break }
                try? await Task.sleep(for: .milliseconds(200))
            }
            // One POST only: a timeout may still have typed the text, and 409 means chat is gone.
            guard landed, !m.sending, await m.sendText(t) else { restore(note: "Didn't go through"); return }
            freeText = ""
            release()
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
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(card.question ?? "").font(OT.F.title).foregroundStyle(OT.C.text)
                            .lineSpacing(14 * 0.35).fixedSize(horizontal: false, vertical: true)
                        if card.review, let b = card.body {
                            Text(b).font(OT.F.meta).foregroundStyle(OT.C.text5).lineLimit(6)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(card.items.filter { $0.role == .normal }, id: \.number) { row($0) }
                    }
                    .measureHeight($contentH)
                }
                .scrollBounceBehavior(.basedOnSize)
                .measureHeight($viewportH)
                .onChange(of: ctl.highlighted) { _, h in
                    if let h { withAnimation { proxy.scrollTo(h) } }
                }
            }
            footer
        }
        .measureHeight($cardH)
        .promptFit(content: contentH, viewport: viewportH, card: cardH)
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
