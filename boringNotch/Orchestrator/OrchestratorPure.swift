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
    var tokens: String? = nil
}

/// Spinner line of a working Claude Code: "✻ Working… (41s · ↑ 1.2k tokens · esc to interrupt)" (old)
/// or "· Waddling… (35s · ↓ 2.3k tokens)" (current).
// ponytail: both formats are assumed; serve's `live` flag (liveStatusFor) covers what the parser misses.
func parseLiveStatus(screen: String) -> LiveStatus? {
    let line = #/^[ \u{a0}]*[✻✢✳✶✽✺✹·*][ \u{a0}]+(.+?)[ \u{a0}]*\((.*)\)[ \u{a0}]*$/#
    let part = #/(\d+)\s*([hms])/#
    let tok = #/[↑↓]\s*[\d.,]+k?\s*tokens/#
    let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).suffix(30)
    for l in lines.reversed() {
        guard let m = try? line.wholeMatch(in: String(l)) else { continue }
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
        let tokens = m.2.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.first { (try? tok.wholeMatch(in: $0)) != nil }
        let verb = String(m.1)
        guard m.2.contains("esc to interrupt") || ((verb.hasSuffix("…") || verb.hasSuffix("...")) && (elapsed != nil || tokens != nil)) else { continue }
        return LiveStatus(text: verb, elapsed: elapsed, tokens: tokens)
    }
    return nil
}

/// Serve's `live` flag wins when present; without it, screen parsing only.
func liveStatusFor(screen: String, live: Bool?) -> LiveStatus? {
    switch live {
    case false: return nil
    case true: return parseLiveStatus(screen: screen) ?? LiveStatus(text: "Working…", elapsed: nil)
    default: return parseLiveStatus(screen: screen)
    }
}

/// Chat auto-scroll rule. Geometry alone can't tell growth from scrolling, but growth changes the content height and scrolling doesn't.
func chatScrollStep(stick: Bool, oldHeight: CGFloat, newHeight: CGFloat, contentMinY: CGFloat, viewport: CGFloat, threshold: CGFloat = 20) -> (stick: Bool, scrollToBottom: Bool, newContent: Bool) {
    if abs(newHeight - oldHeight) > 0.5 {
        return (stick, stick, !stick && newHeight > oldHeight)
    }
    return ((contentMinY + newHeight) - viewport <= threshold, false, false)
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

// MARK: - Approvals (Phase 9)

enum ApprovalAnswer: Equatable { case send(String), openCard, skip }

/// Allow/Deny gate: only act when the approval is still the pending one and a real prompt is on screen.
/// Allow sends "1" only when option 1 is a plain "Yes"; anything else goes to the card.
func approvalAnswer(allow: Bool, pendingId: String?, answeringId: String, options: [PromptOption]) -> ApprovalAnswer {
    guard pendingId == answeringId, !options.isEmpty else { return .skip }
    guard allow else { return .send("Escape") }
    let plain = options.first { $0.number == 1 }.map { $0.label.trimmingCharacters(in: .whitespaces).lowercased() == "yes" } ?? false
    return plain ? .send("1") : .openCard
}

/// KeyboardShortcuts rejects Option-only combos for sandboxed apps on macOS 15.0/15.1 only.
func approvalNeedsCtrlFallback(major: Int, minor: Int) -> Bool { major == 15 && minor <= 1 }

func approvalKeyLabels(ctrl: Bool) -> (allow: String, deny: String) {
    ctrl ? (allow: "⌃⌥⏎", deny: "⌃⌥⎋") : (allow: "⌥⏎", deny: "⌥⎋")
}

/// Hides the approval we just answered for the ignore window.
func visibleApproval(_ incoming: OrchestratorApproval?, ignoredId: String?, until: Date, now: Date) -> OrchestratorApproval? {
    guard let a = incoming else { return nil }
    return a.id == ignoredId && now < until ? nil : a
}

/// One display line: whitespace runs collapsed, 300 chars max; falls back to the description.
func approvalCommandLine(_ a: OrchestratorApproval) -> String {
    func clean(_ s: String?) -> String {
        String((s ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(300))
    }
    let c = clean(a.command)
    return c.isEmpty ? clean(a.description) : c
}
