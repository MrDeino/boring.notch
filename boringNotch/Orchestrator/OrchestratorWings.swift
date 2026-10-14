// Phase 7 owns: closed-notch wings.
import SwiftUI
import Combine

/// Decides which wing (if any) the closed notch shows. Publishes only `kind`.
@MainActor
final class OrchestratorWingsModel: ObservableObject {
    static let shared = OrchestratorWingsModel()
    @Published private(set) var kind: WingKind? = nil
    private let manager = OrchestratorManager.shared
    private var baseline = RunsBaseline()
    private var finished: (id: String, project: String)?
    private var generation = 0
    private var cancellables = Set<AnyCancellable>()

    private init() {
        manager.$runs.combineLatest(manager.$offline, manager.$hasLoaded)
            .sink { [weak self] runs, offline, loaded in self?.runsChanged(runs, offline, loaded) }
            .store(in: &cancellables)
        manager.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
    }

    private func runsChanged(_ runs: [OrchestratorRun], _ offline: Bool, _ loaded: Bool) {
        if let r = finishedTransition(old: baseline.advance(runs, offline: offline, loaded: loaded), new: runs) { showFinished(r) }
    }

    private func showFinished(_ r: OrchestratorRun) {
        finished = (r.id ?? "", r.project ?? "Run")
        generation += 1
        let g = generation
        recompute()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, g == self.generation else { return }
            self.finished = nil
            self.recompute()
        }
    }

    private func recompute() {
        var k: WingKind? = nil
        if manager.hasLoaded && !manager.offline {
            let label = wingLabel(promptTitle: manager.prompt?.title,
                                  waitingDenials: manager.runs.first { $0.state == "waiting" }?.denials)
            k = wingKind(needsYou: manager.needsAttention, needsLabel: label,
                         finishedProject: finished?.project,
                         working: manager.chatRunning && manager.liveStatus != nil)
        }
        if k != kind {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { kind = k }
        }
    }
}

struct OrchestratorWingsView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var model = OrchestratorWingsModel.shared
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var spin: Double = 0
    @State private var glow = false
    @State private var anchor: (elapsed: TimeInterval, at: Date) = (0, .now)

    var body: some View {
        if let k = model.kind {
            let side = wingSideWidth(k, notchWidth: vm.closedNotchSize.width)
            HStack(spacing: 0) {
                left(k).frame(width: side, alignment: .leading)
                Rectangle().fill(.black).frame(width: vm.closedNotchSize.width)
                right(k).frame(width: side, alignment: .trailing)
            }
            .frame(height: vm.effectiveClosedNotchHeight)
            .transition(.opacity)
        }
    }

    @ViewBuilder private func left(_ k: WingKind) -> some View {
        switch k {
        case .working:
            Text("✻").font(.system(size: 15)).foregroundStyle(OT.C.claude)
                .rotationEffect(.degrees(spin))
                .onAppear { withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spin = 360 } }
        case .needsYou:
            Circle().fill(OT.C.orange).frame(width: 8, height: 8)
                .shadow(color: OT.C.orange, radius: glow ? 8 : 2)
                .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { glow = true } }
        case .finished:
            Image(systemName: "checkmark").font(.system(size: 13)).foregroundStyle(OT.C.green)
        }
    }

    @ViewBuilder private func right(_ k: WingKind) -> some View {
        switch k {
        case .working:
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(manager.liveStatus?.elapsed == nil ? "" : formatElapsed(anchor.elapsed + ctx.date.timeIntervalSince(anchor.at)))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(OT.C.text4)
            }
            .onAppear { anchor = (manager.liveStatus?.elapsed ?? 0, .now) }
            .onChange(of: manager.liveStatus?.elapsed) { _, e in anchor = (e ?? 0, .now) }
        case .needsYou(let label):
            Text(verbatim: label).font(.system(size: 11, weight: .medium)).foregroundStyle(OT.C.orangeText)
                .padding(.vertical, 2).padding(.horizontal, 8)
                .background(OT.C.orangeBg, in: RoundedRectangle(cornerRadius: 9))
                .lineLimit(1).fixedSize()
        case .finished(let project):
            Text(verbatim: project).font(.system(size: 11)).foregroundStyle(OT.C.text4).lineLimit(1)
        }
    }
}

/// 7px dot overlaid just before the music visualizer when something needs the user.
struct OrchestratorMusicNeedsDot: View {
    @ObservedObject var manager = OrchestratorManager.shared
    var body: some View {
        if manager.needsAttention && !manager.offline {
            Circle().fill(OT.C.orange).frame(width: 7, height: 7).allowsHitTesting(false)
        }
    }
}
