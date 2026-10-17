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
}
