// Phase 7 owns after Phase 4: run elapsed / sorting helpers.
import Foundation

/// Poll cadence in seconds. Phase 7 makes closed + chatRunning 3.
func pollInterval(notchOpen: Bool, chatRunning: Bool, offline: Bool = false) -> TimeInterval {
    offline ? 10 : (notchOpen ? 2 : 10)
}
