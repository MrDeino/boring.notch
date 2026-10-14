import SwiftUI
import Combine
import Defaults

extension Defaults.Keys {
    static let orchRunsRailCollapsed = Key<Bool>("orchRunsRailCollapsed", default: false)
}

private let railSpring = Animation.spring(response: 0.3, dampingFraction: 0.85)
// Level-change fade, tuned to OrchestratorExpand's notch spring (response 0.4): out, then in once the shape is near final.
private let fadeOut = 0.08, fadeInDelay = 0.28, fadeIn = 0.15

/// Rail collapse state. Persisted choice lives in Defaults; auto-open is a transient reveal.
/// Keeps its own waiting baseline (same idea as the wings model) so it does not depend on 07-03.
@MainActor
final class OrchestratorRailState: ObservableObject {
    static let shared = OrchestratorRailState()
    @Published private(set) var autoOpened = false
    private(set) var userCollapsedThisSession = false // "session" = this app launch
    private var baseline = RunsBaseline()
    private var bag = Set<AnyCancellable>()

    private init() {
        let m = OrchestratorManager.shared
        m.$runs.combineLatest(m.$offline, m.$hasLoaded).sink { [weak self] runs, offline, loaded in
            guard let self else { return }
            let old = self.baseline.advance(runs, offline: offline, loaded: loaded)
            if newlyWaiting(old: old, new: runs) && Defaults[.orchRunsRailCollapsed] && !self.userCollapsedThisSession {
                withAnimation(railSpring) { self.autoOpened = true }
            }
        }.store(in: &bag)
    }

    var collapsed: Bool { Defaults[.orchRunsRailCollapsed] && !autoOpened }

    func toggle() {
        objectWillChange.send()
        withAnimation(railSpring) {
            if collapsed {
                Defaults[.orchRunsRailCollapsed] = false; autoOpened = false
            } else {
                Defaults[.orchRunsRailCollapsed] = true; autoOpened = false; userCollapsedThisSession = true
            }
        }
    }
}

func runDotColor(_ state: String?) -> Color {
    switch state {
    case "running": return OT.C.green
    case "waiting": return OT.C.orange
    case "failed", "stuck": return OT.C.red
    default: return OT.C.text5
    }
}

private struct RailToggleButton: View {
    let symbol: String
    var body: some View {
        Button { OrchestratorRailState.shared.toggle() } label: {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(OT.C.text).frame(width: 20, height: 20)
                .background(OT.C.raised, in: Circle())
        }.buttonStyle(.plain).help("Toggle runs rail (⌘\\)")
    }
}

struct OrchestratorRunsRail: View {
    @ObservedObject var manager = OrchestratorManager.shared

    private func bar(_ label: String, _ w: UsageWindow?, reset: (Date) -> String) -> some View {
        let pct = w?.usedPercentage
        return VStack(spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text(verbatim: pct.map { "\(Int($0.rounded()))% · " + (w?.resetsDate.map(reset) ?? "—") } ?? "—")
            }.font(.system(size: 10)).foregroundStyle(OT.C.text5)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(OT.C.selected2)
                    Capsule().fill(usageIsHigh(pct) ? OT.C.orange : OT.C.text)
                        .frame(width: g.size.width * min(max((pct ?? 0) / 100, 0), 1))
                }
            }.frame(height: 3)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Runs · \(liveRunCount(manager.runs)) active").font(.system(size: 11)).foregroundStyle(OT.C.text5)
                Spacer()
                RailToggleButton(symbol: "chevron.right")
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(boardRuns(manager.runs, limit: 10), id: \.stableID) { OrchestratorRunCard(run: $0, compact: true) }
                }
            }
            Spacer(minLength: 0)
            bar("5h", manager.usage?.fiveHour) { $0.formatted(date: .omitted, time: .shortened).lowercased() }
            bar("7d", manager.usage?.sevenDay) { $0.formatted(.dateTime.weekday(.abbreviated)) }
        }
    }
}

struct OrchestratorRunsStrip: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var hovered: String?

    var body: some View {
        VStack(spacing: 8) {
            RailToggleButton(symbol: "chevron.left")
            ForEach(boardRuns(manager.runs, limit: 8), id: \.stableID) { run in
                ZStack {
                    Circle().fill(OT.C.raised).frame(width: 22, height: 22)
                    Circle().fill(runDotColor(run.state)).frame(width: 7, height: 7)
                }
                .overlay { if run.state == "waiting" { Circle().strokeBorder(OT.C.orange, lineWidth: 1) } }
                .contentShape(Circle())
                .onTapGesture { OrchestratorRunLog.shared.open(run) }
                .onHover { hovered = $0 ? run.stableID : (hovered == run.stableID ? nil : hovered) }
                .overlay(alignment: .topTrailing) {
                    if hovered == run.stableID {
                        OrchestratorRunCard(run: run, compact: true)
                            .frame(width: 178).offset(x: -(22 + 10))
                            .allowsHitTesting(false).transition(.opacity)
                    }
                }
                .zIndex(hovered == run.stableID ? 1 : 0)
            }
            Spacer(minLength: 0)
            OrchestratorUsageRing(fraction: fiveHourFraction(manager.usage) ?? 0,
                                  high: usageIsHigh(manager.usage?.fiveHour?.usedPercentage))
        }
    }
}

/// The Orchestrator tab body at every level: one view tree, so expanding and collapsing only reflows it
/// (the chat keeps its identity and scroll position); just the runs rail and the terminal panel come and go.
struct OrchestratorExpandedView: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var expand = OrchestratorExpand.shared
    @ObservedObject var rail = OrchestratorRailState.shared
    @ObservedObject var cards = PromptCardController.shared
    @ObservedObject var store = OrchestratorTranscriptStore.shared
    @Default(.orchRunsRailCollapsed) var persisted
    @EnvironmentObject var vm: BoringViewModel
    /// The level the content is laid out for: it lags the live level while the content is hidden, so nothing reflows on screen.
    @State private var shown: ExpandLevel?
    @State private var contentOpacity: Double = 1
    @State private var fadeGen = 0

    /// Fade out, lay out once at the new level while invisible, fade in near the end of the shape spring. Newest change wins.
    private func levelChanged() {
        fadeGen += 1
        let gen = fadeGen
        withAnimation(.easeOut(duration: fadeOut)) { contentOpacity = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(fadeOut))
            guard gen == fadeGen else { return }
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { shown = expand.level(for: vm) }
            try? await Task.sleep(for: .seconds(fadeInDelay - fadeOut))
            guard gen == fadeGen else { return }
            withAnimation(.easeOut(duration: fadeIn)) { contentOpacity = 1 }
        }
    }

    var body: some View {
        let level = shown ?? expand.level(for: vm)
        let collapsed = persisted && !rail.autoOpened
        let open = level == .open
        HStack(alignment: .top, spacing: open ? 0 : 12) {
            column(level).frame(maxWidth: .infinity, maxHeight: .infinity)
            if !open {
                // Pinned top/trailing by its own frame, so nothing in the column (a card leaving) can move it.
                VStack(spacing: 8) {
                    if collapsed { OrchestratorRunsStrip() } else { OrchestratorRunsRail() }
                    terminalPill(level, collapsed: collapsed)
                }
                .padding(.leading, collapsed ? 0 : 12)
                .overlay(alignment: .leading) { if !collapsed { Rectangle().fill(OT.C.divider).frame(width: 1) } }
                .frame(width: collapsed ? 30 : 178)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.identity) // nothing moves while the content is hidden
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, open ? 8 : 0)
        .padding(.top, open ? 0 : 6) // bottom comes only from ContentView's 12pt, same as at open
        .opacity(contentOpacity)
        .animation(railSpring, value: collapsed)
        .onAppear { shown = expand.level(for: vm) }
        .onChange(of: expand.level(for: vm)) { _, _ in levelChanged() }
        // The sticky Runs board must not hide a live prompt or outlive a disconnect.
        .onChange(of: manager.prompt != nil) { _, has in if has { manager.showRunsBoard = false } }
        .onChange(of: manager.offline) { _, off in if off { manager.showRunsBoard = false } }
        .onDisappear { expand.reset() }
    }

    /// The state switch. Runs board is checked before stopped so "see Runs" works while the chat is stopped.
    @ViewBuilder private func column(_ level: ExpandLevel) -> some View {
        let open = level == .open
        // An answered card is dismissed at once; the transcript shows meanwhile instead of an empty column.
        let promptVisible = manager.prompt.map { promptIdentity($0) != cards.dismissed } ?? false
        if !manager.hasLoaded { OrchestratorConnectingView() }
        else if manager.offline { OrchestratorOfflineView() }
        else if level == .terminal { OrchestratorTerminalPanel().transition(.opacity) }
        else if open && manager.showRunsBoard { OrchestratorRunsBoard() }
        else if !manager.chatRunning { OrchestratorStoppedView() }
        else {
            VStack(spacing: 6) {
                // Open: the card takes the whole column. Expanded: the transcript stays above it.
                if !(open && promptVisible) {
                    OrchestratorChatView(showComposer: !promptVisible, proseLineLimit: open ? 4 : nil, maxRows: 60, expanded: !open)
                        .frame(minHeight: promptVisible ? 72 : 0)
                }
                // Open: what Claude said before asking, a few lines, so the card is not out of context.
                if open && promptVisible, let ctx = latestAssistantProse(store.blocks) { PromptContextView(text: ctx) }
                if promptVisible { OrchestratorPromptCard() }
            }
        }
    }

    private func terminalPill(_ level: ExpandLevel, collapsed: Bool) -> some View {
        let on = level == .terminal
        return Button { expand.setLevel(on ? .expanded : .terminal, vm: vm, window: nil) } label: {
            if collapsed {
                Image(systemName: "terminal").font(.system(size: 12)).foregroundStyle(OT.C.text)
                    .frame(width: 30, height: 30)
                    .background(on ? OT.C.selected2 : OT.C.raised, in: Circle())
            } else {
                HStack(spacing: 6) {
                    Text("Terminal").font(.system(size: 12))
                    Text("⌘T").font(OT.F.monoChip).padding(.horizontal, 4)
                        .background(OT.C.selected2, in: RoundedRectangle(cornerRadius: OT.R.keycap))
                }
                .foregroundStyle(OT.C.text).frame(maxWidth: .infinity).frame(height: 32)
                .background(on ? OT.C.selected2 : OT.C.raised, in: Capsule())
            }
        }.buttonStyle(.plain)
    }
}

/// The latest assistant prose above a question/permission card at the open level: up to 3 lines, scrollable
/// (newest lines at the bottom); the notch grows by its height so the card keeps its room.
private struct PromptContextView: View {
    let text: String
    @EnvironmentObject var vm: BoringViewModel
    @State private var anchor = NSView()
    @State private var natural: CGFloat = 0

    private var height: CGFloat { min(natural, 54) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(proseAttributed(text)).font(OT.F.prose).foregroundStyle(OT.C.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { g in Color.clear.onAppear { natural = g.size.height }.onChange(of: g.size.height) { _, h in natural = h } })
        }
        .defaultScrollAnchor(.bottom)
        .frame(height: height)
        .padding(.horizontal, 6)
        .background(WindowAnchor(view: anchor))
        .onChange(of: height) { _, _ in fit() }
        .onAppear { fit() }
        .onDisappear { OrchestratorExpand.shared.setFit("prompt", extra: 0, vm: vm, window: anchor.window) }
    }

    private func fit() { OrchestratorExpand.shared.setFit("prompt", extra: height + 6, vm: vm, window: anchor.window) }
}
