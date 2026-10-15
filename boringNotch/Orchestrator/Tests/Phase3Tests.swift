import Foundation
import CoreGraphics

func runPhase3Tests() {
    precondition(expandedExtra(screenHeight: 1080, openHeight: 190) == 300)
    precondition(expandedExtra(screenHeight: 400, openHeight: 190) == 170)
    precondition(expandedExtra(screenHeight: 100, openHeight: 190) == 0)
    precondition(windowHeight(base: 210, notchHeight: 32, openHeight: 190) == 210)
    precondition(windowHeight(base: 210, notchHeight: 490, openHeight: 190) == 510)
    let pf = pinnedFrame(current: CGRect(x: 10, y: 800, width: 640, height: 210), newSize: CGSize(width: 640, height: 510))
    precondition(pf.maxY == 1010 && pf.minX == 10 && pf.height == 510)
    precondition(pinnedFrame(current: pf, newSize: CGSize(width: 640, height: 210)).minY == 800)
    let wide = pinnedFrame(current: CGRect(x: 10, y: 800, width: 640, height: 210), newSize: CGSize(width: 850, height: 560))
    precondition(wide.maxY == 1010 && wide.midX == 330 && wide.minX == -95 && wide.minY == 450)
    precondition(terminalState(overlayText: nil) == .connecting && terminalState(overlayText: nil, previous: .connected) == .connecting)
    precondition(terminalState(overlayText: "") == .connected)
    precondition(terminalState(overlayText: "\n Connection Closed \n") == .inUse)
    precondition(terminalState(overlayText: "Press ⏎ to Reconnect") == .inUse)
    precondition(terminalState(overlayText: "Connection Closed", previous: .connected) == .unavailable)
    precondition(terminalState(overlayText: "foo Reconnect bar") == .connected)
    precondition(terminalState(overlayText: "the Connection Closed early") == .connected)
    precondition(terminalState(overlayText: "mitch@mac ~ %") == .connected)
    let wf = CGRect(x: 0, y: 500, width: 640, height: 510)
    func out(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 640) -> Bool { isOutsideNotch(point: CGPoint(x: x, y: y), windowFrame: wf, notchWidth: w, notchHeight: 490) }
    precondition(!out(320, 900) && !out(320, 1009))
    precondition(out(320, 515) && out(700, 900) && out(320, 300))
    precondition(out(5, 900, 600))
}
