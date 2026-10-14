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
    private var raisedByCard = false
    private weak var vm: BoringViewModel?
    private weak var window: NSWindow?
    private var bag = Set<AnyCancellable>()

    private init() {
        OrchestratorManager.shared.$prompt.sink { [weak self] card in
            // $prompt emits before the property changes; hop to the main queue.
            DispatchQueue.main.async { self?.promptChanged(card) }
        }.store(in: &bag)
    }

    private func promptChanged(_ card: PromptCard?) {
        pressed = nil
        guard card?.kind != .question else { return }
        if raisedByCard, let vm, let window, OrchestratorExpand.shared.level(for: vm) == .expanded {
            OrchestratorExpand.shared.setLevel(.open, vm: vm, window: window)
        }
        raisedByCard = false
    }

    func sync(_ card: PromptCard?, vm: BoringViewModel, window: NSWindow?) {
        self.vm = vm
        self.window = window
        if card != shown {
            shown = card
            highlighted = card?.highlighted ?? card?.items.first?.number
            pressed = nil
        }
        if card?.kind == .question, OrchestratorExpand.shared.level(for: vm) == .open {
            OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: window)
            raisedByCard = true
        }
    }

    /// True when the live prompt is still the one the user clicked on.
    private func stillCurrent(_ displayed: PromptCard) async -> Bool {
        // ponytail: refresh() returns early if a poll is mid-flight, so the compare can use a <=2s-old
        // screen; upgrade = awaitable refresh in the manager.
        await OrchestratorManager.shared.refresh()
        let m = OrchestratorManager.shared
        guard let cur = m.prompt, promptIdentity(cur) == promptIdentity(displayed), !m.optionsLocked else {
            flash = true
            try? await Task.sleep(for: .milliseconds(250))
            flash = false
            return false
        }
        return true
    }

    func choose(_ n: Int, displayed: PromptCard) {
        Task {
            guard await stillCurrent(displayed) else { return }
            pressed = n
            OrchestratorManager.shared.pressOption(n)
        }
    }

    func escape(displayed: PromptCard) {
        Task {
            guard await stillCurrent(displayed) else { return }
            await OrchestratorManager.shared.pressEscape()
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
            if let card = manager.prompt {
                switch card.kind {
                case .permission: PermissionCard(card: card)
                case .question: QuestionCard(card: card)
                }
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
        .onAppear { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { shownIn = true } }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: manager.prompt)
    }
}

// MARK: - Shared pieces

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

/// Locked-state feedback shared by pills and rows.
@MainActor private func pressState(_ n: Int, _ m: OrchestratorManager, _ c: PromptCardController) -> (pressed: Bool, dim: Bool) {
    let on = m.optionsLocked && c.pressed != nil
    return (on && c.pressed == n, on && c.pressed != n)
}

// MARK: - Permission (frame 03)

private struct PermissionCard: View {
    let card: PromptCard
    @ObservedObject private var manager = OrchestratorManager.shared
    @ObservedObject private var ctl = PromptCardController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.title ?? card.question ?? "Permission").font(OT.F.title).foregroundStyle(OT.C.text)
                if let p = card.purpose {
                    Text(p).font(OT.F.ui).foregroundStyle(OT.C.text5).lineLimit(1)
                }
            }
            if let body = card.body {
                let first = body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? body
                HStack(spacing: 0) {
                    Text("$ ").foregroundStyle(OT.C.text6)
                    Text(first).foregroundStyle(OT.C.text1)
                }
                .font(OT.F.monoCommand).lineLimit(1).truncationMode(.tail)
                .padding(.vertical, 8).padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 8))
                .help(body)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach(card.items.filter { $0.role != .deny }, id: \.number) { pill($0) }
                Spacer(minLength: 0)
                ForEach(card.items.filter { $0.role == .deny }, id: \.number) { pill($0) }
            }
        }
    }

    private func pill(_ item: PromptCardOption) -> some View {
        let st = pressState(item.number, manager, ctl)
        let first = item.number == 1
        let deny = item.role == .deny
        let light = first || st.pressed
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
        .opacity(st.dim ? 0.4 : 1)
        .disabled(manager.optionsLocked || manager.sending)
        .help(item.label)
    }
}

// MARK: - Question (frame 04)

private struct QuestionCard: View {
    let card: PromptCard
    @ObservedObject private var manager = OrchestratorManager.shared
    @ObservedObject private var ctl = PromptCardController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if card.header != nil || card.progress != nil {
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
                        ForEach(card.items.filter { $0.role == .normal }, id: \.number) { row($0) }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: ctl.highlighted) { _, h in
                    if let h { withAnimation { proxy.scrollTo(h) } }
                }
            }
            footer
        }
    }

    private func row(_ item: PromptCardOption) -> some View {
        let st = pressState(item.number, manager, ctl)
        let hi = ctl.highlighted == item.number || st.pressed
        return Button { ctl.choose(item.number, displayed: card) } label: {
            HStack(alignment: .top) {
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
        .opacity(st.dim ? 0.4 : 1)
        .disabled(manager.optionsLocked || manager.sending)
        .id(item.number)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0) // 06-03 puts "Something else…" here
            if let chat = card.items.first(where: { $0.role == .chat }) {
                footPill("Chat about this", key: "\(chat.number)") { ctl.choose(chat.number, displayed: card) }
                    .disabled(manager.optionsLocked || manager.sending)
            }
            footPill(nil, key: "esc") { ctl.escape(displayed: card) }
                .disabled(manager.sending)
        }
    }

    private func footPill(_ title: String?, key: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let title { Text(title).font(OT.F.ui).foregroundStyle(OT.C.text) }
                PromptKeycap(text: key, light: false)
            }
            .padding(.leading, title == nil ? 7 : 14).padding(.trailing, 7)
            .frame(height: 28)
            .background(OT.C.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
