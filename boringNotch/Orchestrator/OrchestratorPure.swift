// Phase 3 pure helpers; compiled by the swiftc test harness.
import Foundation

/// Highest of the 5h/7d usage windows as 0...1, nil when unknown.
func usageFraction(_ u: OrchestratorUsage?) -> Double? {
    let p = [u?.fiveHour?.usedPercentage, u?.sevenDay?.usedPercentage].compactMap { $0 }
    guard let m = p.max() else { return nil }
    return min(max(m / 100, 0), 1)
}
