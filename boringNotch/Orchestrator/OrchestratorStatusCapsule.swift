// Phase 4 (04-03): header segment, status capsule, usage ring, status menu.
import SwiftUI

/// "Chat | Runs N" segment after the tab buttons; only on the Orchestrator tab while online.
struct OrchestratorHeaderSegment: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        if coordinator.currentView == .orchestrator && !manager.offline {
            let n = liveRunCount(manager.runs)
            let waiting = manager.runs.contains { $0.state == "waiting" }
            HStack(spacing: 0) {
                seg(selected: !manager.showRunsBoard) { manager.showRunsBoard = false } label: {
                    Text("Chat")
                }
                seg(selected: manager.showRunsBoard) { manager.showRunsBoard = true } label: {
                    HStack(spacing: 0) {
                        Text("Runs")
                        if n > 0 {
                            Text(" \(n)").foregroundColor(waiting ? OT.C.orange : OT.C.text5)
                        }
                    }
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 12).fill(OT.C.raised))
            .font(OT.F.meta)
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 6)
        }
    }

    private func seg<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .foregroundColor(selected ? OT.C.text : OT.C.text5)
                .padding(.vertical, 2).padding(.horizontal, 9)
                .background(RoundedRectangle(cornerRadius: 10).fill(selected ? OT.C.selected2 : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Phase 7 adds the collapse button here.
struct OrchestratorHeaderTrailing: View {
    var body: some View { OrchestratorStatusCapsule() }
}

struct OrchestratorUsageRing: View {
    let fraction: Double
    let high: Bool
    var body: some View {
        ZStack {
            Circle().fill(OT.C.selected2)
            Circle().inset(by: 3)
                .trim(from: 0, to: fraction)
                .stroke(high ? OT.C.orange : OT.C.text, lineWidth: 6)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 12, height: 12)
    }
}

struct OrchestratorStatusCapsule: View {
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        let s = manager.capsuleStatus
        let (dot, label, fg, bg): (Color, String, Color, Color) = {
            switch s {
            case .running: return (OT.C.green, "Running", OT.C.text, OT.C.raised)
            case .idle: return (OT.C.green, "Idle", OT.C.text, OT.C.raised)
            case .needsYou: return (OT.C.orange, "Needs you", OT.C.orangeText, OT.C.orangeBg)
            case .stopped: return (OT.C.text5, "Stopped", OT.C.text4, OT.C.raised)
            case .offline: return (OT.C.red, "Offline", OT.C.text4, OT.C.raised)
            case .connecting: return (OT.C.text6, "Connecting", OT.C.text5, OT.C.raised)
            }
        }()
        let showRing = s == .running || s == .idle || s == .stopped
        Button {
            guard s != .connecting && s != .offline else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                if coordinator.currentView != .orchestrator {
                    coordinator.currentView = .orchestrator
                    manager.statusMenuOpen = true
                } else {
                    manager.statusMenuOpen.toggle()
                }
            }
        } label: {
            HStack(spacing: 7) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(label).id(s).transition(.opacity).foregroundColor(fg)
                if showRing, let f = fiveHourFraction(manager.usage) {
                    OrchestratorUsageRing(fraction: f, high: usageIsHigh(manager.usage?.fiveHour?.usedPercentage))
                }
            }
            .font(OT.F.meta)
            .lineLimit(1)
            .padding(.leading, 8).padding(.trailing, 10)
            .frame(height: 24)
            .background(Capsule().fill(bg))
            .animation(.easeInOut(duration: 0.18), value: s)
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct OrchestratorStatusMenu: View {
    let openTerminal: () -> Void
    @ObservedObject var manager = OrchestratorManager.shared
    @State private var confirmEnd = false

    private func close() { withAnimation(.easeOut(duration: 0.15)) { manager.statusMenuOpen = false } }

    var body: some View {
        let u = manager.usage
        VStack(spacing: 0) {
            usageRow("5-hour usage", u?.fiveHour) { $0.formatted(date: .omitted, time: .shortened).lowercased() }
            usageRow("7-day usage", u?.sevenDay) { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
            OT.C.divider2.frame(height: 1).padding(.vertical, 4)
            row("Open terminal", hint: Text("click transcript").foregroundColor(OT.C.text6)) {
                close(); openTerminal()
            }.disabled(!manager.chatRunning).opacity(manager.chatRunning ? 1 : 0.4)
            row("Interrupt", hint: Text("esc").font(OT.F.monoChip).foregroundColor(OT.C.text5)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: OT.R.keycap).fill(OT.C.selected))) {
                Task { await manager.pressEscape() }; close()
            }.disabled(!manager.chatRunning).opacity(manager.chatRunning ? 1 : 0.4)
            if manager.chatRunning {
                if confirmEnd {
                    HStack(spacing: 6) {
                        Text("End chat?").foregroundColor(OT.C.redText)
                        Spacer(minLength: 0)
                        pill("End", fg: .black, bg: OT.C.red) { confirmEnd = false; Task { await manager.stopChat() }; close() }
                        pill("Cancel", fg: OT.C.text, bg: OT.C.selected2) { confirmEnd = false }
                    }
                    .font(OT.F.ui)
                    .padding(.vertical, 3).padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: OT.R.cardS).fill(OT.C.redBg))
                } else {
                    row("End chat", color: OT.C.redText) { confirmEnd = true }
                }
            } else {
                row("Start chat") { Task { await manager.startChat() }; close() }
            }
        }
        .disabled(manager.sending)
        .task(id: confirmEnd) {
            guard confirmEnd else { return }
            try? await Task.sleep(for: .seconds(4))
            confirmEnd = false
        }
        .padding(5)
        .frame(width: 232)
        .background(RoundedRectangle(cornerRadius: OT.R.cardL).fill(OT.C.raised))
        .overlay(RoundedRectangle(cornerRadius: OT.R.cardL).stroke(OT.C.selected, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 15, y: 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pill(_ t: String, fg: Color, bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).foregroundColor(fg).padding(.horizontal, 10).frame(height: 20).background(Capsule().fill(bg))
        }.buttonStyle(PlainButtonStyle())
    }

    private func row<H: View>(_ title: String, color: Color = OT.C.text, hint: H, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundColor(color)
                Spacer(minLength: 0)
                hint.font(OT.F.hint)
            }
            .font(OT.F.ui)
            .padding(.vertical, 3).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }.buttonStyle(PlainButtonStyle())
    }

    private func row(_ title: String, color: Color = OT.C.text, action: @escaping () -> Void) -> some View {
        row(title, color: color, hint: EmptyView(), action: action)
    }

    private func usageRow(_ title: String, _ w: UsageWindow?, reset: (Date) -> String) -> some View {
        let pct = w?.usedPercentage
        let high = usageIsHigh(pct)
        let detail = pct.map { p in
            "\(Int(p.rounded()))%" + (w?.resetsDate.map { " · resets \(reset($0))" } ?? "")
        } ?? "—"
        return VStack(spacing: 3) {
            HStack {
                Text(title).foregroundColor(OT.C.text)
                Spacer(minLength: 0)
                Text(detail).foregroundColor(high ? OT.C.orange : OT.C.text5)
            }
            .font(OT.F.ui)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(OT.C.selected2)
                    Capsule().fill(high ? OT.C.orange : OT.C.text)
                        .frame(width: g.size.width * min(max((pct ?? 0) / 100, 0), 1))
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 3).padding(.horizontal, 8)
    }
}
