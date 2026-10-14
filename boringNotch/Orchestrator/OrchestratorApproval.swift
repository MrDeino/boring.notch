// Phase 9 owns: closed-notch approval drop-down (frame 00).
import SwiftUI
import Combine

/// Publishes only the pending approval and a "show the card" request, so ContentView never observes the whole manager.
@MainActor
final class OrchestratorApprovalCenter: ObservableObject {
    static let shared = OrchestratorApprovalCenter()
    @Published private(set) var approval: OrchestratorApproval? = nil
    /// Bumped when an Allow resolves to "open the prompt card instead" (option 1 is not a plain Yes).
    @Published private(set) var cardRequest = 0
    private var cancellables = Set<AnyCancellable>()

    private init() {
        OrchestratorManager.shared.$approval.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] a in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self?.approval = a }
            }
            .store(in: &cancellables)
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
                Text(verbatim: approvalCommandLine(a))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(OT.C.text1)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .padding(.vertical, 7).padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 10) {
                    pill("Allow ⌥⏎", fg: .black, bg: .white, flex: true) { center.answer(allow: true) }
                    pill("Deny ⌥⎋", fg: OT.C.redText, bg: OT.C.raised, flex: true) { center.answer(allow: false) }
                    pill("More…", fg: .white, bg: OT.C.raised, flex: false) { onMore() }
                }
            }
            .padding(.top, 30).padding(.horizontal, 2).padding(.bottom, 14)
            .frame(width: 432)
            .onChange(of: center.cardRequest) { _, _ in onMore() }
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
