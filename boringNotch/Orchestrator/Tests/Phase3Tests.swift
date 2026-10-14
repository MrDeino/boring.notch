import Foundation

func runPhase3Tests() {
    func u(_ f: Double?, _ s: Double?) -> OrchestratorUsage {
        func w(_ p: Double?) -> String { p.map { #"{"used_percentage":\#($0)}"# } ?? "null" }
        let j = #"{"five_hour":\#(w(f)),"seven_day":\#(w(s))}"#
        return try! JSONDecoder().decode(OrchestratorUsage.self, from: Data(j.utf8))
    }
    precondition(usageFraction(nil) == nil)
    precondition(usageFraction(u(nil, nil)) == nil)
    precondition(usageFraction(u(40, nil)) == 0.4)
    precondition(usageFraction(u(30, 85)) == 0.85)
    precondition(usageFraction(u(130, nil)) == 1.0)
    precondition(usageFraction(u(-5, nil)) == 0.0)
}
