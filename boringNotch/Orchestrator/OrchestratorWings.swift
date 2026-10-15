// Phase 7 owns: closed-notch wings.
import SwiftUI
import Combine

/// Decides which wing (if any) the closed notch shows. Publishes only `kind`.
@MainActor
final class OrchestratorWingsModel: ObservableObject {
    static let shared = OrchestratorWingsModel()
    @Published private(set) var kind: WingKind? = nil
    /// Offset that re-centres the closed shape when the wings differ in width; 0 while no wing is on screen.
    @Published private(set) var shiftX: CGFloat = 0
    private let manager = OrchestratorManager.shared
    private var baseline = RunsBaseline()
    private var queue: [(project: String, failed: Bool)] = []
    private var finished: (project: String, failed: Bool)?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        _ = OrchestratorRailState.shared // eager, so its waiting baseline exists before the first expand (WR-02)
        manager.$runs.combineLatest(manager.$offline, manager.$hasLoaded)
            .sink { [weak self] runs, offline, loaded in self?.runsChanged(runs, offline, loaded) }
            .store(in: &cancellables)
        manager.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
    }

    private func runsChanged(_ runs: [OrchestratorRun], _ offline: Bool, _ loaded: Bool) {
        for r in finishedTransitions(old: baseline.advance(runs, offline: offline, loaded: loaded), new: runs) {
            queue.append((r.project ?? "Run", r.state == "failed"))
        }
        if finished == nil { showNext() }
    }

    /// Each finished/failed run gets its own 4s wing, in turn.
    private func showNext() {
        guard !queue.isEmpty else { return }
        finished = queue.removeFirst()
        recompute()
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self else { return }
            self.finished = nil
            if self.queue.isEmpty { self.recompute() } else { self.showNext() }
        }
    }

    func setShift(_ x: CGFloat) {
        guard x != shiftX else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { shiftX = x }
    }

    private func recompute() {
        var k: WingKind? = nil
        if manager.hasLoaded && !manager.offline {
            let label = wingLabel(promptTitle: manager.prompt?.title,
                                  waitingDenials: manager.runs.first { $0.state == "waiting" }?.denials)
            k = wingKind(needsYou: manager.needsAttention, needsLabel: label, finished: finished,
                         workingCount: workingCount(chatWorking: manager.chatRunning && manager.liveStatus != nil, runs: manager.runs))
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
    @State private var anchor: (elapsed: TimeInterval, at: Date) = (0, .now)
    @State private var leftW: CGFloat = 0
    @State private var rightW: CGFloat = 0

    var body: some View {
        if let k = model.kind {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let elapsed = elapsedText(ctx.date)
                HStack(spacing: 0) {
                    left(k).padding(.trailing, 8).measured($leftW)
                    Rectangle().fill(.black).frame(width: vm.closedNotchSize.width)
                    right(k, elapsed: elapsed).padding(.leading, 8).measured($rightW)
                }
            }
            .frame(height: vm.effectiveClosedNotchHeight)
            .transition(.opacity)
            .onAppear { anchor = (manager.liveStatus?.elapsed ?? 0, .now) }
            .onChange(of: wingShift(left: leftW, right: rightW), initial: true) { _, x in model.setShift(x) }
            .onDisappear { model.setShift(0) }
            .onChange(of: manager.liveStatus?.elapsed) { _, e in anchor = (e ?? 0, .now) }
        }
    }

    private func elapsedText(_ now: Date) -> String {
        guard case .working = model.kind else { return "" }
        let chat = manager.liveStatus?.elapsed.map { _ in anchor.elapsed + now.timeIntervalSince(anchor.at) }
        return longestWorking(chatElapsed: chat, runs: manager.runs, now: now).map(formatElapsed) ?? ""
    }

    @ViewBuilder private func left(_ k: WingKind) -> some View {
        switch k {
        case .working:
            WingSpinner(size: 15)
        case .needsYou:
            WingGlowDot()
        case .finished(_, let failed):
            FinishedMark(failed: failed, size: 13)
        }
    }

    @ViewBuilder private func right(_ k: WingKind, elapsed: String) -> some View {
        switch k {
        case .working(let n):
            HStack(spacing: 4) {
                Text(verbatim: elapsed)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(OT.C.text4)
                if n > 1 {
                    Text(verbatim: "\(n)").font(.system(size: 9, weight: .semibold)).foregroundStyle(OT.C.text4)
                        .padding(.horizontal, 4).frame(minWidth: 14, minHeight: 14)
                        .background(OT.C.selected, in: Capsule())
                }
            }
            .lineLimit(1).fixedSize()
        case .needsYou(let label):
            Text(verbatim: label).font(.system(size: 11, weight: .medium)).foregroundStyle(OT.C.orangeText)
                .padding(.vertical, 2).padding(.horizontal, 8)
                .background(OT.C.orangeBg, in: RoundedRectangle(cornerRadius: 9))
                .lineLimit(1).fixedSize()
        case .finished(let project, _):
            Text(verbatim: project).font(.system(size: 11)).foregroundStyle(OT.C.text4).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 200, alignment: .leading).fixedSize(horizontal: true, vertical: false)
        }
    }
}

private extension View {
    /// Reports this view's width into `width`.
    func measured(_ width: Binding<CGFloat>) -> some View {
        background(GeometryReader { g in
            Color.clear.onAppear { width.wrappedValue = g.size.width }
                .onChange(of: g.size.width) { _, w in width.wrappedValue = w }
        })
    }
}

/// Repeating animations run as Core Animation, in the render server: a SwiftUI `repeatForever` / 30fps TimelineView
/// re-renders the whole notch root on the main thread every frame, which cost ~17% CPU on an idle closed notch.
struct OrchLayer: NSViewRepresentable {
    let size: CGSize
    let build: (CALayer) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: CGRect(origin: .zero, size: size))
        v.wantsLayer = true
        v.layer?.masksToBounds = false
        build(v.layer!)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? { size }
}

func orchAnimation(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval, autoreverses: Bool, linear: Bool = false) -> CABasicAnimation {
    let a = CABasicAnimation(keyPath: keyPath)
    a.fromValue = from; a.toValue = to; a.duration = duration; a.autoreverses = autoreverses; a.repeatCount = .infinity
    a.timingFunction = CAMediaTimingFunction(name: linear ? .linear : .easeInEaseOut)
    return a
}

// Own subviews so their state resets each time the wing kind re-inserts them (WR-03).
private struct WingSpinner: View {
    let size: CGFloat
    var body: some View {
        let text = NSAttributedString(string: "✻", attributes: [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor(OT.C.claude)])
        let box = text.size()
        OrchLayer(size: box) { root in
            let l = CALayer()
            l.frame = root.bounds
            l.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            l.contents = NSImage(size: box, flipped: false) { _ in text.draw(at: .zero); return true }
            l.add(orchAnimation("transform.rotation.z", from: 0, to: -2 * Double.pi, duration: 8, autoreverses: false, linear: true), forKey: "spin") // clockwise
            root.addSublayer(l)
        }
        .frame(width: box.width, height: box.height)
    }
}

private struct FinishedMark: View {
    let failed: Bool
    let size: CGFloat
    var body: some View {
        Image(systemName: failed ? "xmark" : "checkmark").font(.system(size: size, weight: .semibold))
            .foregroundStyle(failed ? OT.C.red : OT.C.green)
    }
}

private struct WingGlowDot: View {
    var body: some View {
        OrchLayer(size: CGSize(width: 8, height: 8)) { root in
            let c = NSColor(OT.C.orange).cgColor
            let l = CALayer()
            l.frame = root.bounds
            l.backgroundColor = c; l.cornerRadius = 4
            l.shadowColor = c; l.shadowOpacity = 1; l.shadowOffset = .zero; l.shadowRadius = 2
            l.shadowPath = CGPath(ellipseIn: l.bounds, transform: nil)
            l.add(orchAnimation("shadowRadius", from: 2, to: 8, duration: 1.2, autoreverses: true), forKey: "glow")
            root.addSublayer(l)
        }
        .frame(width: 8, height: 8)
    }
}

/// Just before the music visualizer while music plays (the wings stay hidden): 7px needs-you dot,
/// else a tiny ✻ while anything works, or a ✓/✕ for the 4s a finished run would show.
struct OrchestratorMusicIndicator: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var wings = OrchestratorWingsModel.shared
    var body: some View {
        Group {
            if manager.needsAttention && !manager.offline {
                Circle().fill(OT.C.orange).frame(width: 7, height: 7)
            } else if case .working = wings.kind {
                WingSpinner(size: 8)
            } else if case .finished(_, let failed) = wings.kind {
                FinishedMark(failed: failed, size: 7)
            }
        }
        .frame(width: 7, height: 7)
        .allowsHitTesting(false)
    }
}
