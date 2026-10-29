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
