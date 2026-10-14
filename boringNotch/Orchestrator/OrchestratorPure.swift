// Phase 3 pure helpers; compiled by the swiftc test harness.
import Foundation
import CoreGraphics

/// Extra height the expanded notch adds below the normal open size.
func expandedExtra(screenHeight: CGFloat, openHeight: CGFloat) -> CGFloat {
    max(0, min(300, screenHeight - openHeight - 40))
}

func windowHeight(base: CGFloat, notchHeight: CGFloat, openHeight: CGFloat) -> CGFloat {
    base + max(0, notchHeight - openHeight)
}

/// New size with the top edge (maxY) and the horizontal centre (midX) kept.
func pinnedFrame(current: CGRect, newSize: CGSize) -> CGRect {
    CGRect(x: current.midX - newSize.width / 2, y: current.maxY - newSize.height, width: newSize.width, height: newSize.height)
}

enum TerminalState: Equatable { case connecting, connected, inUse, unavailable }

/// Maps ttyd's overlay text to a state. nil = terminal not on the page yet.
/// A socket close shows the "Connection Closed" overlay: a second client before ever connecting (in use),
/// or a dropped session after it was connected (unavailable). Whole-line match, so terminal output never counts.
func terminalState(overlayText: String?, previous: TerminalState = .connecting) -> TerminalState {
    guard let t = overlayText else { return .connecting }
    let closed = t.split(separator: "\n").contains { line in
        let l = line.trimmingCharacters(in: .whitespaces)
        return l == "Connection Closed" || l.hasSuffix("to Reconnect")
    }
    guard closed else { return .connected }
    return previous == .connected ? .unavailable : .inUse
}

/// True when a screen point is outside the notch rect (centred on the window, top-pinned).
func isOutsideNotch(point: CGPoint, windowFrame: CGRect, notchWidth: CGFloat, notchHeight: CGFloat) -> Bool {
    let r = CGRect(x: windowFrame.midX - notchWidth / 2, y: windowFrame.maxY - notchHeight, width: notchWidth, height: notchHeight)
    return !r.contains(point)
}

// Phase 4
enum ExpandLevel: Equatable { case open, expanded, terminal }

struct LiveStatus: Equatable {
    let text: String
    let elapsed: TimeInterval?
}

/// Spinner line of a working Claude Code, e.g. "✻ Working… (41s · ↑ 1.2k tokens · esc to interrupt)".
// ponytail: working-line format is assumed (RESEARCH A1); degrades to idle if Claude Code drops "esc to interrupt".
func parseLiveStatus(screen: String) -> LiveStatus? {
    let line = #/^[ \u{a0}]*[✻✢✳✶✽✺✹·*][ \u{a0}]+(.+?)[ \u{a0}]*\((.*)\)[ \u{a0}]*$/#
    let part = #/(\d+)\s*([hms])/#
    let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).suffix(30)
    for l in lines.reversed() {
        guard let m = try? line.wholeMatch(in: String(l)), m.2.contains("esc to interrupt") else { continue }
        var elapsed: TimeInterval?
        if let first = m.2.split(separator: "·").first {
            let toks = first.matches(of: part)
            let rest = first.replacing(part, with: "").trimmingCharacters(in: .whitespaces)
            if !toks.isEmpty && rest.isEmpty {
                elapsed = toks.reduce(0) { acc, t in
                    acc + Double(t.1)! * (t.2 == "h" ? 3600 : t.2 == "m" ? 60 : 1)
                }
            }
        }
        return LiveStatus(text: String(m.1), elapsed: elapsed)
    }
    return nil
}

func formatElapsed(_ seconds: TimeInterval) -> String {
    let t = max(0, Int(seconds))
    let h = t / 3600, m = t % 3600 / 60, s = t % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

enum CapsuleState: Equatable { case connecting, offline, stopped, needsYou, running, idle }

func capsuleState(hasLoaded: Bool, offline: Bool, chatRunning: Bool, needsAttention: Bool, working: Bool) -> CapsuleState {
    if !hasLoaded { return .connecting }
    if offline { return .offline }
    if !chatRunning { return .stopped }
    if needsAttention { return .needsYou }
    return working ? .running : .idle
}

func liveRunCount(_ runs: [OrchestratorRun]) -> Int {
    runs.filter { ["running", "waiting", "stuck"].contains($0.state ?? "") }.count
}

/// 5h window used as 0...1, nil when unknown.
func fiveHourFraction(_ u: OrchestratorUsage?) -> Double? {
    u?.fiveHour?.usedPercentage.map { min(max($0 / 100, 0), 1) }
}

func usageIsHigh(_ percent: Double?) -> Bool { (percent ?? 0) >= 80 }
