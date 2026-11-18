import Foundation

// Quick jlt: open/close predictability (multi-display close, back-from-expanded hold).

func runQuickJltTests() {
    // Closing one display's notch leaves the shared tab / Orchestrator state alone while another is open.
    precondition(closeKeepsSharedState(othersOpen: 1) && closeKeepsSharedState(othersOpen: 2))
    precondition(!closeKeepsSharedState(othersOpen: 0))

    // Back-from-expanded hold: active until its deadline, never without one.
    let t0: TimeInterval = 100
    precondition(holdsOpen(until: t0 + expandBackHoldSeconds, now: t0))
    precondition(holdsOpen(until: t0 + expandBackHoldSeconds, now: t0 + 0.7)) // hover-exit lands ~0.1-0.7 s into the shrink
    precondition(!holdsOpen(until: t0 + expandBackHoldSeconds, now: t0 + expandBackHoldSeconds))
    precondition(!holdsOpen(until: nil, now: t0))
    // Covers the spring (0.4 s) plus the deferred window shrink (650 ms) and the 100 ms hover-exit delay.
    precondition(expandBackHoldSeconds >= 0.4 + 0.65 + 0.1)

    // A rebuilt panel for a closed notch is the stock windowSize-sized panel (no expanded leftovers).
    let base = CGSize(width: 640, height: 210)
    precondition(panelSize(notch: CGSize(width: 185, height: 32), base: base, openHeight: 190) == base)
}
