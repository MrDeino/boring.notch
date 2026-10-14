import SwiftUI

// Phase 4: stopped (07), offline (08), connecting (09).
struct OrchestratorStoppedView: View {
    @ObservedObject var manager = OrchestratorManager.shared

    var body: some View {
        let n = liveRunCount(manager.runs)
        VStack(spacing: 10) {
            Text("Orchestrator chat is stopped").font(OT.F.stateTitle).foregroundStyle(OT.C.text)
            Button {
                Task { await manager.startChat() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill").font(.system(size: 10))
                    Text("Start chat")
                }
                .font(OT.F.uiMedium).foregroundStyle(.black)
                .padding(.horizontal, 16).frame(height: 30)
                .background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            .disabled(manager.sending)
            if n > 0 {
                // "1 run" vs "N runs" pluralisation is a choice made here.
                Text(verbatim: "\(n) \(n == 1 ? "run" : "runs") still active · see Runs")
                    .font(OT.F.meta).foregroundStyle(OT.C.text6)
                    .contentShape(Rectangle())
                    .onTapGesture { manager.showRunsBoard = true }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OrchestratorOfflineView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Can't reach the orchestrator").font(OT.F.stateTitle).foregroundStyle(OT.C.text)
            Text(verbatim: "node orch.js serve · 127.0.0.1:4777")
                .font(OT.F.monoPath).foregroundStyle(OT.C.text2)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(OT.C.raised))
            Text("Retrying every 10s").font(OT.F.meta).foregroundStyle(OT.C.text6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct OrchestratorConnectingView: View {
    private let fractions: [CGFloat] = [0.48, 0.30, 0.62, 0.40]

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            GeometryReader { g in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(fractions.enumerated()), id: \.offset) { _, f in
                        RoundedRectangle(cornerRadius: 5).fill(OT.C.raised)
                            .frame(width: g.size.width * f, height: 9)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            HStack {
                Text("Message orchestrator").font(OT.F.ui).foregroundStyle(OT.C.text6)
                    .padding(.leading, 14)
                Spacer(minLength: 0)
                Circle().fill(OT.C.selected2).frame(width: 20, height: 20)
                    .overlay(Image(systemName: "arrow.up").font(.system(size: 10)).foregroundStyle(OT.C.text5))
                    .padding(.trailing, 6)
            }
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: OT.R.pill30).fill(OT.C.raised))
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
