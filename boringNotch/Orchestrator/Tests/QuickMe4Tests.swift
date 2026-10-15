import AppKit
import SwiftUI

// Quick me4: type-to-focus, first-gesture selection in the composer, POST retry after a dropped connection.

@MainActor func runQuickMe4Tests() {
    // Type-to-focus: printable keys start the composer only on the open/expanded Orchestrator tab, with this app frontmost.
    let ok = ComposerKeyContext()
    let shift: UInt = 1 << 17, option: UInt = 1 << 19, control: UInt = 1 << 18, command: UInt = 1 << 20
    precondition(typeToFocusText(characters: "a", modifierFlags: 0, context: ok) == "a")
    precondition(typeToFocusText(characters: "A", modifierFlags: shift, context: ok) == "A")
    precondition(typeToFocusText(characters: " ", modifierFlags: 0, context: ok) == " ")
    precondition(typeToFocusText(characters: "ø", modifierFlags: option, context: ok) == "ø")
    precondition(typeToFocusText(characters: "1", modifierFlags: 0, context: ok) == "1") // no card: digits are text
    func ctx(_ f: (inout ComposerKeyContext) -> Void) -> ComposerKeyContext { var c = ok; f(&c); return c }
    for c in [ctx { $0.notchOpen = false }, ctx { $0.appActive = false }, ctx { $0.windowIsKey = false },
              ctx { $0.orchestratorTab = false }, ctx { $0.composerFocused = true }, ctx { $0.terminalFocused = true },
              ctx { $0.editingOtherText = true }] {
        precondition(typeToFocusText(characters: "a", modifierFlags: 0, context: c) == nil)
    }
    // A question card is showing: digits pick options, so they (and everything else) pass.
    precondition(typeToFocusText(characters: "1", modifierFlags: 0, context: ctx { $0.cardShowing = true }) == nil)
    // ⌘-shortcuts, ⌃U, Esc, Tab, Return, Delete, arrows, dead keys: unchanged.
    precondition(typeToFocusText(characters: "c", modifierFlags: command, context: ok) == nil)
    precondition(typeToFocusText(characters: "\\", modifierFlags: command, context: ok) == nil)
    precondition(typeToFocusText(characters: "\u{15}", modifierFlags: control, context: ok) == nil)
    precondition(typeToFocusText(characters: "u", modifierFlags: control, context: ok) == nil)
    for k in ["\u{1b}", "\t", "\r", "\u{7f}", "\u{F700}", "\u{F701}", "\u{F702}", "\u{F703}", "", nil] as [String?] {
        precondition(typeToFocusText(characters: k, modifierFlags: 0, context: ok) == nil)
    }
}

/// Real AppKit events (offscreen panel, no cursor movement): a non-key panel like the notch's, whose canBecomeKey is
/// gated. The first double-click selects a word and the first drag selects a range; focus opens the session and
/// keeps the selection. Runs last: once AppKit has spun the main run loop, an `await` in main.swift ends the process.
@MainActor func runQuickMe4SelectionTest() {
    var gate = false, focusCalls = 0
    final class Panel: NSPanel { var gate: () -> Bool = { false }; override var canBecomeKey: Bool { gate() } }
    struct Host: View {
        @State var text = "hello world foo"
        @FocusState var focused: Bool
        let onFocus: () -> Void
        var body: some View {
            ZStack { OrchestratorComposerField(text: $text, focused: $focused, onFocus: onFocus) }.frame(width: 220, height: 30)
        }
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    func run(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
    func field(_ v: NSView) -> NSTextField? { (v as? NSTextField) ?? v.subviews.lazy.compactMap(field).first }

    for gesture in ["double", "drag"] {
        focusCalls = 0; gate = false
        let p = Panel(contentRect: NSRect(x: -6000, y: -6000, width: 240, height: 40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.gate = { gate }
        let host = NSHostingView(rootView: Host(onFocus: { focusCalls += 1; gate = true; p.makeKey() }))
        host.frame = p.contentView!.bounds
        p.contentView!.addSubview(host)
        p.orderFrontRegardless()
        run(0.3)
        precondition(!p.isKeyWindow)
        guard let tf = field(host) else { preconditionFailure("composer field not mounted while idle") }
        let r = tf.convert(tf.bounds, to: nil)
        // x of the last word, "foo" (ends at the field's text end).
        let end = r.minX + (tf.attributedStringValue.size().width) - 3
        func ev(_ t: NSEvent.EventType, _ x: CGFloat, _ clicks: Int) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: NSPoint(x: x, y: r.midY), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: p.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
        }
        if gesture == "double" {
            for c in [1, 2] { app.postEvent(ev(.leftMouseUp, end, c), atStart: false); app.sendEvent(ev(.leftMouseDown, end, c)); run(0.05) }
        } else {
            app.postEvent(ev(.leftMouseDragged, r.minX + 40, 1), atStart: false)
            app.postEvent(ev(.leftMouseUp, r.minX + 40, 1), atStart: false)
            app.sendEvent(ev(.leftMouseDown, r.minX + 2, 1))
        }
        run(0.3)
        let sel = (p.firstResponder as? NSTextView)?.selectedRange()
        if gesture == "double" { precondition(sel == NSRange(location: 12, length: 3), "double-click: \(String(describing: sel))") }
        else { precondition((sel?.length ?? 0) > 0 && sel?.location == 0, "drag: \(String(describing: sel))") }
        precondition(focusCalls == 1 && p.isKeyWindow, "focus opens the session once")

        // Type-to-focus caret: focusing selects the whole field; the inserted key leaves the caret after it.
        if gesture == "drag" {
            (p.firstResponder as? NSTextView)?.selectAll(nil)
            moveCaretToEnd(in: p)
            precondition((p.firstResponder as? NSTextView)?.selectedRange() == NSRange(location: 15, length: 0))
        }
        p.close()
    }
}

/// Mock serve drops the first connection: the send succeeds on the retry. HTTP errors (500, 409) are never retried.
func runQuickMe4Mock() async {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    proc.arguments = ["-I", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("retry-mock.py").path]
    try! proc.run()
    defer { proc.terminate() }
    let root = URL(string: "http://127.0.0.1:47998")!
    let ses = URLSession(configuration: .ephemeral)
    func count(_ s: String) async -> Int {
        let (data, _) = try! await ses.data(from: root.appendingPathComponent("__count/\(s)"))
        return Int(String(decoding: data, as: UTF8.self))!
    }
    for _ in 0..<50 { if (try? await ses.data(from: root.appendingPathComponent("__count/x"))) != nil { break }; try! await Task.sleep(for: .milliseconds(100)) }

    let code = try? await sendOrchestratorPost(.text("hello"), base: root.appendingPathComponent("drop1"), session: ses)
    precondition(code == 200, "dropped first connection: \(String(describing: code))")
    let dropped = await count("drop1")
    precondition(dropped == 2)
    let path = await uploadOrchestratorImage(Data([1, 2, 3]), base: root.appendingPathComponent("drop2"), session: ses)
    let uploads = await count("drop2")
    precondition(path == "/tmp/x.png" && uploads == 2, "image upload retried")

    for s in ["s500", "s409"] {
        let c = try? await sendOrchestratorPost(.text("hello"), base: root.appendingPathComponent(s), session: ses)
        let n = await count(s)
        precondition(c == Int(s.dropFirst())! && n == 1, "\(s) must not be retried")
    }
    precondition(!isOrchestratorConnectionDrop(URLError(.timedOut)) && !isOrchestratorConnectionDrop(URLError(.badServerResponse)))
}
