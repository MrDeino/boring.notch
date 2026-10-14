import Foundation
import CoreGraphics

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
    precondition(expandedExtra(screenHeight: 1080, openHeight: 190) == 300)
    precondition(expandedExtra(screenHeight: 400, openHeight: 190) == 170)
    precondition(expandedExtra(screenHeight: 100, openHeight: 190) == 0)
    precondition(windowHeight(base: 210, notchHeight: 32, openHeight: 190) == 210)
    precondition(windowHeight(base: 210, notchHeight: 490, openHeight: 190) == 510)
    let pf = pinnedFrame(current: CGRect(x: 10, y: 800, width: 640, height: 210), newHeight: 510)
    precondition(pf.maxY == 1010 && pf.minX == 10 && pf.height == 510)
    precondition(pinnedFrame(current: pf, newHeight: 210).minY == 800)
    precondition(terminalState(pageText: nil) == .connecting && terminalState(pageText: "") == .connecting)
    precondition(terminalState(pageText: "Connection Closed") == .inUse)
    precondition(terminalState(pageText: "Press ⏎ to Reconnect") == .inUse)
    precondition(terminalState(pageText: "foo Reconnect bar") == .inUse)
    precondition(terminalState(pageText: "mitch@mac ~ %") == .connected)
    let wf = CGRect(x: 0, y: 500, width: 640, height: 510)
    func out(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 640) -> Bool { isOutsideNotch(point: CGPoint(x: x, y: y), windowFrame: wf, notchWidth: w, notchHeight: 490) }
    precondition(!out(320, 900) && !out(320, 1009))
    precondition(out(320, 515) && out(700, 900) && out(320, 300))
    precondition(out(5, 900, 600))
}
