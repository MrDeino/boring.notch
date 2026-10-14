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
            .contentShape(shape)
            .onTapGesture { OrchestratorRunLog.shared.open(run) }
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

// MARK: - Run log overlay (GET /api/log/<id> only)

/// The open run log: lines of the one run being read, re-fetched every 2s while the run is live.
@MainActor final class OrchestratorRunLog: ObservableObject {
    static let shared = OrchestratorRunLog()
    @Published private(set) var runID: String?
    @Published private(set) var lines: [String] = []
    @Published private(set) var loaded = false
    @Published private(set) var failed = false
    private var task: Task<Void, Never>?

    func open(_ run: OrchestratorRun) {
        guard let id = run.id, isRunID(id) else { return }
        task?.cancel()
        runID = id; lines = []; loaded = false; failed = false
        #if ORCH_SNAPSHOT
        return
        #else
        task = Task { await poll(id) }
        #endif
    }

    func close() { task?.cancel(); task = nil; runID = nil }

    private func poll(_ id: String) async {
        let url = OrchestratorManager.baseURL.appendingPathComponent("api/log/" + id)
        while !Task.isCancelled {
            let got = try? await OrchestratorManager.shared.session.data(from: url)
            guard !Task.isCancelled, runID == id else { return }
            if let (data, resp) = got, (resp as? HTTPURLResponse)?.statusCode == 200,
               let l = try? JSONDecoder().decode([String].self, from: data) {
                if l != lines { lines = l }
                failed = false
            } else { failed = lines.isEmpty }
            loaded = true
            let state = OrchestratorManager.shared.runs.first { $0.id == id }?.state
            guard ["running", "waiting", "stuck"].contains(state ?? "") else { return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    #if ORCH_SNAPSHOT
    func snapshotSet(runID: String?, lines: [String], failed: Bool = false) {
        self.runID = runID; self.lines = lines; self.failed = failed; loaded = runID != nil
    }
    #endif
}

struct OrchestratorRunLogOverlay: View {
    @ObservedObject var log = OrchestratorRunLog.shared
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var stick = true
    @State private var contentHeight: CGFloat = 0

    private var run: OrchestratorRun? { manager.runs.first { $0.id == log.runID } }
    private let shape = RoundedRectangle(cornerRadius: OT.R.cardL)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let act = runActivityLine(run?.activity) {
                Text(verbatim: act).font(.system(size: 11)).foregroundStyle(OT.C.run).lineLimit(2).truncationMode(.tail)
            }
            bodyView
        }
        .padding(.top, 10).padding(.horizontal, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OT.C.raised, in: shape)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Circle().fill(runDotColor(run?.state)).frame(width: 6, height: 6)
            Text(verbatim: run?.project ?? "?").font(.system(size: 12, weight: .semibold)).foregroundStyle(OT.C.text).lineLimit(1)
            Text(verbatim: log.runID ?? "").font(OT.F.monoChip).foregroundStyle(OT.C.text5).lineLimit(1)
            Spacer(minLength: 4)
            if let run {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    Text(verbatim: runElapsed(run, now: ctx.date)).font(.system(size: 10)).foregroundStyle(OT.C.text5)
                }
            }
            Button { log.close() } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(OT.C.text).frame(width: 20, height: 20)
                    .background(OT.C.selected, in: Circle())
            }.buttonStyle(.plain).help("Close the log (esc)")
        }
    }

    @ViewBuilder private var bodyView: some View {
        if log.failed {
            note("Couldn't load the log")
        } else if !log.loaded {
            note("Loading…")
        } else if log.lines.isEmpty {
            note("No output yet.")
        } else {
            GeometryReader { g in
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(log.lines.enumerated()), id: \.offset) { _, l in row(l) }
                            Color.clear.frame(height: 0).id("bottom")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(GeometryReader { c in
                            Color.clear
                                .onAppear { geometry(c.frame(in: .named("orchRunLog")), viewport: g.size.height, proxy: proxy) }
                                .onChange(of: c.frame(in: .named("orchRunLog"))) { _, f in geometry(f, viewport: g.size.height, proxy: proxy) }
                        })
                    }
                    .defaultScrollAnchor(.bottom)
                }
            }
            .coordinateSpace(name: "orchRunLog")
        }
    }

    private func geometry(_ f: CGRect, viewport: CGFloat, proxy: ScrollViewProxy) {
        let r = chatScrollStep(stick: stick, oldHeight: contentHeight, newHeight: f.height, contentMinY: f.minY, viewport: viewport)
        contentHeight = f.height
        if r.stick != stick { stick = r.stick }
        if r.scrollToBottom {
            Task { @MainActor in
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private func note(_ s: String) -> some View {
        Text(s).font(.system(size: 11)).foregroundStyle(OT.C.text5).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private func row(_ l: String) -> some View {
        if let t = logToolLine(l) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: t.tool).font(OT.F.monoChip.weight(.medium)).foregroundStyle(OT.C.text3)
                    .padding(.vertical, 2).padding(.horizontal, 6)
                    .background(OT.C.selected, in: RoundedRectangle(cornerRadius: 5))
                if !t.summary.isEmpty {
                    Text(verbatim: t.summary).font(OT.F.monoPath).foregroundStyle(OT.C.text2)
                        .lineLimit(2).truncationMode(l.contains("/") && t.summary.hasPrefix("/") ? .middle : .tail)
                }
            }
        } else {
            Text(verbatim: l).font(OT.F.monoPath).foregroundStyle(OT.C.text2)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
