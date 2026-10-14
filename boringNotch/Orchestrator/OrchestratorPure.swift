// Phase 3 pure helpers; compiled by the swiftc test harness.
import Foundation
import CoreGraphics

/// Highest of the 5h/7d usage windows as 0...1, nil when unknown.
func usageFraction(_ u: OrchestratorUsage?) -> Double? {
    let p = [u?.fiveHour?.usedPercentage, u?.sevenDay?.usedPercentage].compactMap { $0 }
    guard let m = p.max() else { return nil }
    return min(max(m / 100, 0), 1)
}

/// Extra height the expanded notch adds below the normal open size.
func expandedExtra(screenHeight: CGFloat, openHeight: CGFloat) -> CGFloat {
    max(0, min(300, screenHeight - openHeight - 40))
}

func windowHeight(base: CGFloat, notchHeight: CGFloat, openHeight: CGFloat) -> CGFloat {
    base + max(0, notchHeight - openHeight)
}

/// Same x/width, new height, top edge (maxY) kept.
func pinnedFrame(current: CGRect, newHeight: CGFloat) -> CGRect {
    CGRect(x: current.minX, y: current.maxY - newHeight, width: current.width, height: newHeight)
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
