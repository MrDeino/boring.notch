import AppKit
import SwiftUI

/// Real AppKit (offscreen panel): a long draft grows the composer up to maxHeight, then scrolls. The caret stays
/// visible while typing at the end, and moving it to the start scrolls the first line back into view.
@MainActor func runQuickGrowTest() {
    struct Host: View {
        @State var text = ""
        @FocusState var focused: Bool
        var body: some View { OrchestratorComposerField(text: $text, focused: $focused).frame(width: 220).fixedSize(horizontal: false, vertical: true) }
    }
    final class Panel: NSPanel { override var canBecomeKey: Bool { true } }
    func run(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    func field(_ v: NSView) -> NSTextField? { (v as? NSTextField) ?? v.subviews.lazy.compactMap(field).first }
    func clip(_ v: NSView?) -> NSClipView? { v.flatMap { ($0 as? NSClipView) ?? clip($0.superview) } }

    let p = Panel(contentRect: NSRect(x: -6000, y: -6000, width: 240, height: 400), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    let host = NSHostingView(rootView: Host())
    host.frame = p.contentView!.bounds
    p.contentView!.addSubview(host)
    p.orderFrontRegardless()
    p.makeKey()
    run(0.3)
    guard let tf = field(host) else { preconditionFailure("composer field not mounted") }
    let oneLine = tf.frame.height
    p.makeFirstResponder(tf)
    run(0.1)
    guard let tv = p.firstResponder as? NSTextView else { preconditionFailure("no field editor") }
    // Typed one line at a time, like a long paste or a long message.
    for i in 1...20 { tv.insertText("line \(i) of a long synthetic message" + (i < 20 ? "\n" : ""), replacementRange: tv.selectedRange()); run(0.02) }
    run(0.3)
    guard let c = clip(tf) else { preconditionFailure("field is not inside a scroll view") }
    precondition(tf.frame.height > OrchestratorComposerField.maxHeight, "field holds every line: \(tf.frame.height)")
    precondition(c.bounds.height <= OrchestratorComposerField.maxHeight + 1 && c.bounds.height > oneLine * 4, "box capped: \(c.bounds.height)")
    func caretVisible() -> Bool {
        guard let r = caretLineRect(tv) else { return false }
        let inClip = c.convert(r, from: tv)
        return inClip.minY >= c.bounds.minY - 1 && inClip.maxY <= c.bounds.maxY + 1
    }
    precondition(caretVisible(), "caret at the end is visible after typing")
    tv.setSelectedRange(NSRange(location: 0, length: 0))
    run(0.2)
    precondition(caretVisible(), "caret at the start scrolls into view")
    p.close()
}
