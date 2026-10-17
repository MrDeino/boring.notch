import SwiftUI

// run.sh --cardfit: a question or permission card at the open level grows the notch to its content, shrinks when it goes away,
// follows content changes between multi-question steps, and stops at the cap. Real tab in a real panel, synthetic fixtures.
extension Snap {
    static func cardFitPass() async -> Bool {
        let m = OrchestratorManager.shared, ex = OrchestratorExpand.shared
        func chat(_ f: String?) -> ChatResponse {
            guard let f else { return ChatResponse(running: true, screen: "") }
            var o: [String: Any] = ["running": true, "screen": fixture(f)]
            if f.hasPrefix("question") || f.hasPrefix("multi") { o["approval"] = ["id": "q1", "tool": "AskUserQuestion", "command": "{}"] }
            return try! JSONDecoder().decode(ChatResponse.self, from: JSONSerialization.data(withJSONObject: o))
        }
        let state = StateResponse(runs: [], usage: nil)
        await m.snapshotApply(loaded: true, chat: chat(nil), state: state)
        let vm = BoringViewModel()
        let window = KeyablePanel(contentRect: NSRect(x: -20000, y: -20000, width: windowSize.width, height: windowSize.height),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        let host = NSHostingView(rootView: NotchReplica(vm: vm).core.environmentObject(vm))
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(500))
        var fails: [String] = []
        func check(_ ok: Bool, _ what: String) { if !ok { fails.append(what) } }
        let screen = CGSize(width: 1440, height: 900) // the offscreen panel has no screen: the same default the cap uses
        let cap = promptCardMaxHeight(screen: screen)

        /// Shows `f`, waits for the fit, and checks the notch height is exactly what the card's need asks for.
        func show(_ f: String?, _ name: String) async -> CGFloat {
            await m.snapshotApply(loaded: true, chat: chat(f), state: state)
            try? await Task.sleep(for: .milliseconds(1100))
            let h = vm.notchSize.height, need = PromptFitProbe.last
            let want = f == nil ? openNotchSize.height : min(cap, openNotchSize.height + promptFitExtra(need: need))
            print("cardfit \(name): h=\(Int(h)) need=\(Int(need)) want=\(Int(want)) window=\(Int(window.frame.height))")
            if f != nil, f != "phase6-edit.txt" { check(need > 0, "\(name): card reported a need") }
            check(abs(h - want) <= 1, "\(name): notch \(Int(h)) != fitted \(Int(want))")
            check(ex.level(for: vm) == .open, "\(name): stays at the open level")
            return h
        }
        let open = openNotchSize.height
        let h0 = await show(nil, "no card")
        let h3 = await show("question.txt", "3 options")
        let h6 = await show("question6.txt", "6 options")
        check(h3 >= open && h6 > h3, "grows with the content (\(Int(h3)) -> \(Int(h6)))")
        let hl = await show("question-long.txt", "7 long options")
        check(hl > h6 && abs(hl - cap) <= 1, "very long question stops at the cap \(Int(cap)) (got \(Int(hl)))")
        let hDone = await show(nil, "dismissed")
        check(abs(hDone - open) <= 1 && h0 == open, "shrinks back to the open size")

        // Multi-question: each step's height follows its own content; the review step is its own size.
        var seen: [CGFloat] = []
        for f in ["multiq3-1.txt", "multiq3-2.txt", "multiq3-3.txt", "multiq3-review.txt", "multiselect-1.txt"] { seen.append(await show(f, f)) }
        check(Set(seen.map { Int($0) }).count > 1, "steps resize (\(seen.map { Int($0) }))")
        _ = await show("question6.txt", "6 options again")
        _ = await show("phase6-edit.txt", "permission, no command")
        let hp = await show("permission-longcmd.txt", "permission, long command")
        check(hp > open, "permission card grows to its command (\(Int(hp)))")
        let hEnd = await show(nil, "dismissed again")
        check(abs(hEnd - open) <= 1, "back to open after the last card")

        // Expanded keeps the expanded layout: the card never asks for a fit there.
        ex.setLevel(.expanded, vm: vm, window: window)
        try? await Task.sleep(for: .milliseconds(600))
        let hx = vm.notchSize.height
        await m.snapshotApply(loaded: true, chat: chat("question6.txt"), state: state)
        try? await Task.sleep(for: .milliseconds(1100))
        check(abs(vm.notchSize.height - hx) <= 1 && ex.level(for: vm) == .expanded, "expanded stays as it was (\(Int(hx)) -> \(Int(vm.notchSize.height)))")

        ex.reset()
        window.contentView = nil
        window.orderOut(nil)
        print(fails.isEmpty ? "OK: card fit (grow, cap, shrink, steps, expanded)" : "FAIL: card fit: " + fails.joined(separator: "; "))
        return fails.isEmpty
    }

    /// run.sh --cardclick (ORCH_BASE=http://127.0.0.1:47999, Tests/key-mock.py): at the open level with a card up, a click on an option answers
    /// (its key reaches serve, no expand); a click anywhere else on the card or its tab row expands, with the card still up and nothing sent.
    /// One fresh panel per probe, so a click never inherits state.
    static func cardClickPass() async -> Bool {
        let m = OrchestratorManager.shared, ex = OrchestratorExpand.shared, c = PromptCardController.shared
        let b = OrchestratorManager.baseURL
        precondition(b.port != 4777, "set ORCH_BASE to the key mock")
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-I", "boringNotch/Orchestrator/Tests/key-mock.py"]
        try! proc.run()
        defer { proc.terminate() }
        let ses = URLSession(configuration: .ephemeral)
        for _ in 0..<50 { if (try? await ses.data(from: b.appendingPathComponent("__log"))) != nil { break }; try? await Task.sleep(for: .milliseconds(100)) }
        func sent() async -> Int {
            let (data, _) = try! await ses.data(from: b.appendingPathComponent("__log"))
            return (try! JSONSerialization.jsonObject(with: data) as! [Any]).count
        }
        var reset = URLRequest(url: b.appendingPathComponent("__reset")); reset.httpMethod = "POST"; reset.httpBody = Data("{}".utf8)
        var fails: [String] = []
        var keep: [AnyObject] = [] // a freed view model's address could be reused by the next one, and the expand state is keyed by it
        // (name, x from the left, y below the top of the question's scroll area, option row?)
        let probes: [(String, CGFloat, CGFloat, Bool)] = [
            ("option row", 300, 44, true), ("option row, right end", 520, 44, true), ("option row, left end", 150, 44, true),
            ("question title", 300, 9, false), ("question title, right of text", 520, 9, false),
            ("tab row, empty space", 520, -16, false), ("tab row, beside the chips", 300, -16, false), ("gap above the question", 300, -12, false), ("chip Color", 107, -16, true), ("Next button", 386, 66, true),
        ]
        for (name, x, dy, option) in probes {
            _ = try? await ses.data(for: reset)
            await m.refresh(fresh: true)
            let vm = BoringViewModel()
            keep.append(vm)
            let window = KeyablePanel(contentRect: NSRect(x: -20000, y: -20000, width: windowSize.width, height: windowSize.height),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            // The app's root layout, root hover and tap included: without them SwiftUI-only regions get no clicks in a bare hosting view.
            let mainLayout = NotchReplica(vm: vm).core.environmentObject(vm).contentShape(Rectangle()).onHover { _ in }.onTapGesture { }
            let root = ZStack(alignment: .top) { VStack(spacing: 0) { mainLayout } }
                .padding(.bottom, 8).notchRootFrame(notchSize: vm.notchSize).compositingGroup()
            let host = NSHostingView(rootView: root)
            host.sizingOptions = []
            window.contentView = host
            window.setFrame(NSRect(x: -20000, y: -20000, width: windowSize.width, height: 520), display: true) // room for the notch to be clicked at its fitted height
            window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(2000))
            host.layoutSubtreeIfNeeded()
            c.snapshotSet()
            let H = host.bounds.height
            // The card's layout moves with the lead-in and the fit, so find the question's scroll area (an AppKit container) and measure from it.
            var top: CGFloat?
            for yy in stride(from: CGFloat(30), to: H, by: 2) where host.superview?.hitTest(NSPoint(x: 300, y: H - yy)).map({ String(describing: type(of: $0)).contains("PlatformGroupContainer") }) == true { top = yy; break }
            guard let scrollTop = top else { fails.append("\(name): card scroll area not found"); continue }
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: H - (scrollTop + dy)), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { window.sendEvent(e) }
                try? await Task.sleep(for: .milliseconds(30))
            }
            try? await Task.sleep(for: .milliseconds(400))
            let n = await sent(), expanded = ex.level(for: vm) != .open
            print("cardclick \(name): keys=\(n) expanded=\(expanded) card=\(m.prompt != nil)")
            if option { if n != 1 || expanded { fails.append("\(name): should answer without expanding") } }
            else if n != 0 || !expanded || m.prompt == nil { fails.append("\(name): should expand with the card still up") }
            for _ in 0..<60 where !c.pending.isEmpty { try? await Task.sleep(for: .milliseconds(100)) } // the answer's reconcile may still add a notice line, which moves the card
            c.snapshotSet()
            ex.reset()
            window.contentView = nil
            window.orderOut(nil)
        }
        print(fails.isEmpty ? "OK: card click (options answer, elsewhere expands)" : "FAIL: card click: " + fails.joined(separator: "; "))
        return fails.isEmpty
    }
}
