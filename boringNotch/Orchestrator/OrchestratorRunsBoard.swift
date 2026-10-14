import SwiftUI

/// Frame 05 runs board: run cards (horizontal scroll) plus the orchestrator status row.
struct OrchestratorRunsBoard: View {
    @ObservedObject var manager = OrchestratorManager.shared

    var body: some View {
        VStack(spacing: 8) {
            let runs = boardRuns(manager.runs, limit: 10)
            if runs.isEmpty {
                Text("No runs").font(.system(size: 11)).foregroundStyle(OT.C.text5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(runs, id: \.stableID) { OrchestratorRunCard(run: $0) }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            statusRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Text("✻").font(.system(size: 13)).foregroundStyle(OT.C.claude)
            Text(verbatim: boardStatusLine(runs: manager.runs, promptActive: manager.prompt != nil,
                                           liveText: manager.liveStatus?.text, chatRunning: manager.chatRunning))
                .font(OT.F.ui).foregroundStyle(OT.C.text5).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(OT.C.raised, in: RoundedRectangle(cornerRadius: OT.R.pill30))
    }
}

struct OrchestratorRunCard: View {
    let run: OrchestratorRun
    var compact = false

    private var state: String { run.state ?? "" }
    private var isWaiting: Bool { state == "waiting" }
    private var isFinished: Bool { state == "done" || state == "stopped" }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: compact ? OT.R.cardM : OT.R.cardL)
    }

    private var markColor: Color {
        switch state {
        case "running": return OT.C.green
        case "waiting": return OT.C.orange
        case "failed", "stuck": return OT.C.red
        default: return OT.C.text5
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let now = ctx.date
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if isFinished {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(OT.C.text5)
                    } else {
                        Circle().fill(markColor).frame(width: 6, height: 6)
                    }
                    Text(verbatim: run.project ?? "?")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(OT.C.text).lineLimit(1)
                    Spacer(minLength: 4)
                    if state == "stuck" || state == "failed" {
                        Text(verbatim: state).font(.system(size: 10)).foregroundStyle(OT.C.red)
                    } else {
                        Text(verbatim: runElapsed(run, now: now)).font(.system(size: 10)).foregroundStyle(OT.C.text5)
                    }
                }
                if let act = runActivityLine(run.activity) {
                    Text(verbatim: act).font(.system(size: 11)).foregroundStyle(OT.C.run)
                        .lineLimit(compact ? 1 : 2).truncationMode(.tail)
                }
                Text(verbatim: compact && state == "stuck" ? latestAction(run, now: now) : run.shortPrompt)
                    .font(.system(size: 11)).foregroundStyle(OT.C.text5).lineLimit(1)
                if isWaiting {
                    if !compact {
                        Text(verbatim: waitingQuestion(result: run.result, denials: run.denials ?? [], cap: 160))
                            .font(.system(size: 10)).foregroundStyle(OT.C.text2).lineLimit(2)
                        OrchestratorAskInChatButton(run: run)
                    }
                } else if !compact {
                    Text(verbatim: latestAction(run, now: now))
                        .font(OT.F.monoChip).foregroundStyle(OT.C.text2).lineLimit(2)
                }
            }
            .padding(.vertical, compact ? 8 : 9)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(width: compact ? nil : 196) // frame 05 card width: 196
            .frame(maxHeight: compact ? nil : .infinity, alignment: .top)
            .background(OT.C.raised, in: shape)
            .overlay { if isWaiting { shape.strokeBorder(OT.C.orange, lineWidth: 1) } }
            .opacity(isFinished ? 0.75 : 1)
        }
    }
}

/// Tap-only: sends one line naming the run and its question to the orchestrator chat.
struct OrchestratorAskInChatButton: View {
    let run: OrchestratorRun
    @ObservedObject private var manager = OrchestratorManager.shared
    @State private var sent = false

    private var disabled: Bool {
        !manager.chatRunning
            ? manager.sending
            : (manager.sending || manager.prompt != nil || !manager.promptOptions.isEmpty || sent)
    }

    var body: some View {
        Button {
            if !manager.chatRunning {
                Task { await manager.startChat() }
            } else {
                Task {
                    if await manager.sendText(askInChatMessage(run)) {
                        sent = true
                        try? await Task.sleep(for: .seconds(2))
                        sent = false
                    }
                }
            }
        } label: {
            Text(!manager.chatRunning ? "Start chat" : (sent ? "Sent" : "Ask in chat"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(disabled ? OT.C.text5 : Color.black)
                .frame(maxWidth: .infinity).frame(height: 22)
                .background(disabled ? OT.C.selected2 : Color.white, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help("Sends this run's question to the orchestrator chat")
    }
}
