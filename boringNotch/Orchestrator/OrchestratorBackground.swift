import SwiftUI

/// Which background task's card is open (over the tab, like the run log).
@MainActor final class OrchestratorBgCard: ObservableObject {
    static let shared = OrchestratorBgCard()
    @Published private(set) var selectedID: String?
    func open(_ id: String) { selectedID = id }
    func close() { selectedID = nil }
    #if ORCH_SNAPSHOT
    func snapshotSet(_ id: String?) { selectedID = id }
    #endif
}

private func bgIcon(_ t: BgTask) -> some View {
    Group {
        switch t.status {
        case "running":
            if t.isMonitor { Image(systemName: "eye").font(.system(size: 9, weight: .semibold)).foregroundStyle(OT.C.run) }
            else { ProgressView().controlSize(.mini).scaleEffect(0.75) }
        case "failed": Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(OT.C.red)
        case "stopped": Image(systemName: "stop.fill").font(.system(size: 7)).foregroundStyle(OT.C.text5)
        default:
            Image(systemName: t.isMonitor ? "eye.slash" : "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(OT.C.text5)
        }
    }.frame(width: 12, height: 12)
}

/// Open/expanded notch: "Background · N" and one chip per agent / monitor; finished ones dimmed. Hidden like the deploy rows.
struct OrchestratorBackgroundRow: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var expand = OrchestratorExpand.shared
    @EnvironmentObject var vm: BoringViewModel

    var body: some View {
        if manager.hasLoaded && !manager.offline && manager.prompt == nil && expand.level(for: vm) != .terminal && !manager.bgTasks.isEmpty {
            let running = bgRunningCount(manager.bgTasks)
            HStack(spacing: 6) {
                Text(verbatim: running > 0 ? "Background · \(running) running" : "Background · finished")
                    .font(.system(size: 11)).foregroundStyle(OT.C.text5).lineLimit(1).fixedSize()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { ForEach(bgSorted(manager.bgTasks)) { BgChip(task: $0) } }
                }
            }
            .frame(height: 20)
        }
    }
}

private struct BgChip: View {
    let task: BgTask
    var body: some View {
        HStack(spacing: 5) {
            bgIcon(task)
            Text(verbatim: bgTitle(task)).font(.system(size: 11)).foregroundStyle(OT.C.text2).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 7).frame(height: 20).frame(maxWidth: 190)
        .background(OT.C.raised, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .opacity(task.isRunning ? 1 : 0.55)
        .onTapGesture { OrchestratorBgCard.shared.open(task.id) }
    }
}

/// The open card: description, running time, the last steps (events for a monitor, live), and a finished agent's report.
struct OrchestratorBgCardView: View {
    @ObservedObject var card = OrchestratorBgCard.shared
    @ObservedObject var manager = OrchestratorManager.shared
    private let shape = RoundedRectangle(cornerRadius: OT.R.cardL)
    private var task: BgTask? { manager.bgTasks.first { $0.id == card.selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let t = task { content(t) } else {
                Text("No longer running in this session").font(.system(size: 11)).foregroundStyle(OT.C.text5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.top, 10).padding(.horizontal, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OT.C.raised, in: shape)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let t = task { bgIcon(t) }
            Text(verbatim: task.map(bgTitle) ?? "Background").font(.system(size: 12, weight: .semibold)).foregroundStyle(OT.C.text).lineLimit(2)
            Spacer(minLength: 4)
            if let t = task {
                TimelineView(.periodic(from: .now, by: t.isRunning ? 1 : 60)) { ctx in
                    Text(verbatim: (t.isRunning ? "" : (t.status ?? "done") + " · ") + (bgElapsed(t, now: ctx.date).map(formatElapsed) ?? ""))
                        .font(.system(size: 10)).foregroundStyle(t.status == "failed" ? OT.C.red : OT.C.text5)
                }
            }
            Button { card.close() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OT.C.text).frame(width: 20, height: 20)
                    .background(OT.C.selected, in: Circle())
            }.buttonStyle(.plain).help("Close (esc)")
        }
    }

    private func content(_ t: BgTask) -> some View {
        let steps = bgRecentSteps(t)
        let report = t.isMonitor || t.isRunning ? nil : t.report.flatMap { $0.isEmpty ? nil : $0 }
        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                if !steps.isEmpty {
                    Text(t.isMonitor ? "Latest events" : "Latest steps").font(.system(size: 10)).foregroundStyle(OT.C.text6)
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, s in stepRow(s) }
                } else if report == nil {
                    Text(t.isRunning ? "Nothing yet." : "No steps recorded.").font(.system(size: 11)).foregroundStyle(OT.C.text5)
                }
                if let report {
                    Text("Report").font(.system(size: 10)).foregroundStyle(OT.C.text6).padding(.top, 2)
                    Text(proseAttributed(report)).font(OT.F.prose).foregroundStyle(OT.C.text).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                let usage = [t.toolUses.map { "\($0) tool uses" }, t.tokens.map { "\($0) tokens" }].compactMap { $0 }.joined(separator: " · ")
                if !usage.isEmpty { Text(verbatim: usage).font(.system(size: 10)).foregroundStyle(OT.C.text6) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func stepRow(_ s: BgStep) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let tool = s.tool, !tool.isEmpty {
                Text(verbatim: tool).font(OT.F.monoChip.weight(.medium)).foregroundStyle(OT.C.text3)
                    .padding(.vertical, 2).padding(.horizontal, 6)
                    .background(OT.C.selected, in: RoundedRectangle(cornerRadius: 5))
            }
            Text(verbatim: s.summary ?? "").font(OT.F.monoPath).foregroundStyle(OT.C.text2).lineLimit(2).truncationMode(.tail)
        }
    }
}
