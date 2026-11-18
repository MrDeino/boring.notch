import Foundation

/// A slow or briefly unreachable serve is not "offline": only before the first load, or 3+ failures over 30 s.
func runQuickSlowTests() {
    precondition(goesOffline(everLoaded: false, failures: 1, failingFor: 0)) // nothing on screen to keep
    precondition(!goesOffline(everLoaded: true, failures: 1, failingFor: 0))
    precondition(!goesOffline(everLoaded: true, failures: 10, failingFor: 29)) // quick refusals, not long enough
    precondition(!goesOffline(everLoaded: true, failures: 2, failingFor: 60)) // two slow timeouts, not enough tries
    precondition(goesOffline(everLoaded: true, failures: 3, failingFor: 30))
    precondition(capsuleState(hasLoaded: true, offline: false, chatRunning: true, needsAttention: true, working: true, reconnecting: true) == .reconnecting)
    precondition(capsuleState(hasLoaded: true, offline: true, chatRunning: true, needsAttention: false, working: false, reconnecting: true) == .offline)
    precondition(neverReachedServe(URLError(.cannotConnectToHost)))
    precondition(!neverReachedServe(URLError(.timedOut)) && !neverReachedServe(URLError(.networkConnectionLost)))
}

/// A usage window past its reset time is shown as unknown, not as the old percentage.
func runQuickStaleUsageTests() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let u = OrchestratorUsage(fiveHour: UsageWindow(usedPercentage: 90, resetsAt: 999_999),
                              sevenDay: UsageWindow(usedPercentage: 14, resetsAt: 1_000_500))
    let l = liveUsage(u, now: now)!
    precondition(l.fiveHour?.usedPercentage == nil && fiveHourFraction(l) == nil)
    precondition(l.sevenDay?.usedPercentage == 14)
    precondition(liveUsage(u, now: Date(timeIntervalSince1970: 1_000_000 - 10))!.fiveHour?.usedPercentage == 90)
    precondition(liveUsage(nil, now: now) == nil)
    precondition(liveUsage(OrchestratorUsage(fiveHour: UsageWindow(usedPercentage: 5, resetsAt: nil), sevenDay: nil), now: now)!.fiveHour?.usedPercentage == 5)
}
