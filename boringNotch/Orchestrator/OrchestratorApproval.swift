// Phase 9 owns: closed-notch approval drop-down (frame 00).
import SwiftUI
import Combine
#if !ORCH_SNAPSHOT
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let orchApprovalAllow = Self("orchApprovalAllow")
    static let orchApprovalDeny = Self("orchApprovalDeny")
}
#endif

/// Publishes only the pending approval and a "show the card" request, so ContentView never observes the whole manager.
@MainActor
final class OrchestratorApprovalCenter: ObservableObject {
    static let shared = OrchestratorApprovalCenter()
    @Published private(set) var approval: OrchestratorApproval? = nil
    /// Bumped when an Allow resolves to "open the prompt card instead" (option 1 is not a plain Yes).
    @Published private(set) var cardRequest = 0
    /// Pushed by ContentView: the closed drop-down or the Orchestrator tab is on screen (see approvalVisibleToUser).
    @Published var surfaceShown = false
    private var lastQuestionId: String?
    private var cancellables = Set<AnyCancellable>()

    let ctrlFallback: Bool = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return approvalNeedsCtrlFallback(major: v.majorVersion, minor: v.minorVersion)
    }()
    var keyLabels: (allow: String, deny: String) { approvalKeyLabels(ctrl: ctrlFallback) }

    private init() {
        #if !ORCH_SNAPSHOT
        // Re-set every launch so the stored combo always matches the labels. Handlers are installed once;
        // the keys are only registered (enable) while an approval is pending, so other apps get them otherwise.
        let mods: NSEvent.ModifierFlags = ctrlFallback ? [.control, .option] : [.option]
        KeyboardShortcuts.setShortcut(.init(.return, modifiers: mods), for: .orchApprovalAllow)
        KeyboardShortcuts.setShortcut(.init(.escape, modifiers: mods), for: .orchApprovalDeny)
        KeyboardShortcuts.onKeyDown(for: .orchApprovalAllow) { [weak self] in self?.answer(allow: true) }
        KeyboardShortcuts.onKeyDown(for: .orchApprovalDeny) { [weak self] in self?.answer(allow: false) }
        KeyboardShortcuts.disable(.orchApprovalAllow, .orchApprovalDeny)
        #endif
        OrchestratorManager.shared.$approval.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] a in
                guard let self else { return }
                // AskUserQuestion is answered on the Phase 6 question card, never by Allow/Deny: no drop-down, open the card once per id.
                let q = approvalIsQuestion(a)
                if q, a?.id != self.lastQuestionId { self.cardRequest += 1 }
                self.lastQuestionId = q ? a?.id : nil
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self.approval = q ? nil : a }
            }
            .store(in: &cancellables)
        #if !ORCH_SNAPSHOT
        $approval.combineLatest($surfaceShown)
            .map { $0 != nil && $1 }.removeDuplicates()
            .sink { on in
                if on { KeyboardShortcuts.enable(.orchApprovalAllow, .orchApprovalDeny) }
                else { KeyboardShortcuts.disable(.orchApprovalAllow, .orchApprovalDeny) }
            }
            .store(in: &cancellables)
        #endif
    }

    func answer(allow: Bool) {
        Task { if await OrchestratorManager.shared.answerApproval(allow: allow) == .openCard { cardRequest += 1 } }
    }
}

struct OrchestratorApprovalPanel: View {
    let onMore: () -> Void
    @ObservedObject var center = OrchestratorApprovalCenter.shared

    var body: some View {
        if let a = center.approval {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle().fill(OT.C.orange).frame(width: 7, height: 7)
                    Text("Orchestrator wants to run").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Text(verbatim: a.tool ?? "").font(.system(size: 11)).foregroundStyle(OT.C.text6).lineLimit(1)
                }
                let sm = approvalSummary(a)
                if let c = sm.caption {
                    Text(verbatim: c).font(.system(size: 12)).foregroundStyle(OT.C.text5).lineLimit(1).help(c)
                }
                let body = sm.lines.joined(separator: "\n")
                Text(verbatim: body)
                    .font(.system(size: 12, design: sm.mono ? .monospaced : .default))
                    .foregroundStyle(OT.C.text1)
                    .lineLimit(sm.caption == nil ? 4 : 3)
                    .truncationMode(.tail)
                    .help(body)
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 10) {
                    pill("Allow \(center.keyLabels.allow)", fg: .black, bg: .white, flex: true) { center.answer(allow: true) }
                    pill("Deny \(center.keyLabels.deny)", fg: OT.C.redText, bg: OT.C.raised, flex: true) { center.answer(allow: false) }
                    pill("More…", fg: .white, bg: OT.C.raised, flex: false) { onMore() }
                }
            }
            .padding(.top, 30).padding(.horizontal, 2).padding(.bottom, 14)
            .frame(width: 432)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func pill(_ title: String, fg: Color, bg: Color, flex: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(fg)
                .padding(.horizontal, flex ? 0 : 14)
                .frame(maxWidth: flex ? .infinity : nil)
                .frame(height: 30)
                .background(bg, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
