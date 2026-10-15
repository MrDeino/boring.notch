import SwiftUI

// run.sh --closed: closed-notch wings and the music-playing indicator, driven through the real
// manager apply path and OrchestratorWingsModel. Writes /tmp/notch-snapshots/closed-*.png.

/// Closed notch: wings (or a stand-in music live activity with the indicator), black shape.
struct ClosedReplica: View {
    @ObservedObject var vm: BoringViewModel
    var music = false
    @ObservedObject var wings = OrchestratorWingsModel.shared
    @ObservedObject var approvals = OrchestratorApprovalCenter.shared

    var body: some View {
        Group {
            if approvals.approval != nil { // ContentView's branch order: the drop-down wins over music
                OrchestratorApprovalPanel(onMore: {})
            } else if music {
                let side = vm.effectiveClosedNotchHeight - 12
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.purple).frame(width: side, height: side)
                    Rectangle().fill(.black).frame(width: vm.closedNotchSize.width + 20)
                    HStack(spacing: 2) { ForEach([8, 14, 6, 11], id: \.self) { Capsule().fill(Color.green).frame(width: 2, height: CGFloat($0)) } }
                        .frame(width: side, height: side)
                        .overlay(alignment: .leading) { OrchestratorMusicIndicator().offset(x: -8) }
                }
                .frame(height: vm.effectiveClosedNotchHeight)
            } else {
                ZStack { // the bare notch when no wing shows
                    Color.clear.frame(width: vm.closedNotchSize.width, height: vm.effectiveClosedNotchHeight)
                    OrchestratorWingsView()
                }
            }
        }
        .padding(.horizontal, cornerRadiusInsets.closed.bottom)
        .background(.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: approvals.approval != nil ? OT.R.approvalPanel : 12, bottomTrailingRadius: approvals.approval != nil ? OT.R.approvalPanel : 12))
        .overlay { OrchestratorClosedIndicators() }
        .offset(x: music ? 0 : wings.shiftX)
        .frame(width: approvals.approval != nil ? 520 : 440, height: approvals.approval != nil ? 190 : 56, alignment: .top)
        .overlay(alignment: .top) { // where the hardware notch is
            Rectangle().stroke(Color.red, lineWidth: 1).frame(width: vm.closedNotchSize.width, height: vm.closedNotchSize.height)
        }
        .background(Color(white: 0.35))
        .environmentObject(vm)
    }
}

extension Snap {
    static func closed() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: "/tmp/notch-snapshots")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let m = OrchestratorManager.shared
        _ = OrchestratorWingsModel.shared
        let iso = ISO8601DateFormatter()
        func run(_ id: String, _ project: String, _ state: String, ago: TimeInterval) -> String {
            #"{"id":"\#(id)","project":"\#(project)","state":"\#(state)","startedAt":"\#(iso.string(from: Date().addingTimeInterval(-ago)))"}"#
        }
        func state(_ runs: [String]) -> StateResponse {
            try! JSONDecoder().decode(StateResponse.self, from: Data(#"{"runs":[\#(runs.joined(separator: ","))],"usage":{"five_hour":{"used_percentage":42,"resets_at":1791954000}}}"#.utf8))
        }
        let working = ChatResponse(running: true, screen: "✻ Working… (41s · ↑ 1.2k tokens · esc to interrupt)\n")
        let idle = ChatResponse(running: true, screen: "")
        func apply(_ c: ChatResponse, _ runs: [String]) async {
            await m.snapshotApply(loaded: true, chat: c, state: state(runs))
            try? await Task.sleep(for: .milliseconds(50)) // wings recompute on the next main-queue turn
        }
        func shot(_ name: String, music: Bool = false, height: CGFloat = 32, panel: Bool = false) async {
            let W: CGFloat = panel ? 520 : 440, H: CGFloat = panel ? 190 : 56
            let vm = BoringViewModel()
            vm.notchState = .closed
            vm.closedNotchSize = CGSize(width: 185, height: height)
            let host = NSHostingView(rootView: ClosedReplica(vm: vm, music: music))
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: W, height: H),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            host.frame = NSRect(x: 0, y: 0, width: W, height: H)
            window.contentView = host
            try? await Task.sleep(for: .milliseconds(500))
            host.layoutSubtreeIfNeeded()
            let rep0 = host.bitmapImageRepForCachingDisplay(in: host.bounds)
            if let rep = rep0 {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("closed-\(name).png"))
            }
            if !music, let rep = rep0 {
                func black(_ x: Int) -> Bool { (rep.colorAt(x: x, y: 2)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 1) < 0.05 }
                let xs = (0..<rep.pixelsWide).filter(black)
                let scale = CGFloat(rep.pixelsWide) / W
                if let a = xs.first, let b = xs.last {
                    let centre = (CGFloat(a) + CGFloat(b + 1)) / 2 / scale
                    let shift = OrchestratorWingsModel.shared.shiftX
                    print("wings \(name): shift=\(shift) centre=\(abs(centre - (W / 2 + shift)) <= 1 ? "ok" : "off") (\(centre))")
                }
            } else if music { print("wings \(name): shift=\(OrchestratorWingsModel.shared.shiftX)") }
            window.contentView = nil
            print("closed-\(name): \(String(describing: OrchestratorWingsModel.shared.kind))")
        }
        let r1 = run("r1", "notch", "running", ago: 4320), r2 = run("r2", "shop", "running", ago: 300)

        await apply(working, []); await shot("1-working-chat")
        await apply(working, [r1, r2]); await shot("2-working-three")
        await apply(idle, [r2]); await shot("3-working-run-only")
        await shot("4-music-working", music: true)
        await apply(idle, [run("r2", "shop", "done", ago: 300)]); await shot("5-finished")
        await shot("6-music-finished", music: true)
        try? await Task.sleep(for: .seconds(4))
        await shot("7-after-4s-nothing")
        await apply(idle, [r1, run("r3", "api", "running", ago: 60)])
        await apply(idle, [run("r1", "notch", "failed", ago: 4320), run("r3", "api", "done", ago: 60)])
        await shot("8-queued-first-failed")
        try? await Task.sleep(for: .seconds(4))
        await shot("9-queued-second-done")
        try? await Task.sleep(for: .seconds(4))
        await apply(idle, [run("w", "notch", "waiting", ago: 60)])
        await shot("10-needs-you")
        await shot("11-music-needs-you", music: true)
        await apply(working, []); await shot("15-wings-38", height: 38)
        await apply(idle, [run("w", "notch", "waiting", ago: 60)]); await shot("16-needs-you-38", height: 38)
        await apply(idle, [r1]); await apply(idle, [run("r1", "notch", "failed", ago: 4320)]); await shot("17-finished-failed-38", height: 38)
        try? await Task.sleep(for: .seconds(4))
        await apply(working, [r1, r2]); await shot("18-working-hour-count-38", height: 38)

        // Phase 9: approval drop-down. Over music, over wings (needs-you), over the bare notch; then back to music.
        let ap = ChatResponse.approvalFixture
        await shot("20-music-before", music: true)
        await apply(ap, []); await shot("21-approval-bare", panel: true)
        await shot("22-approval-over-music", music: true, panel: true)
        await apply(try! JSONDecoder().decode(ChatResponse.self, from: Data(#"{"running":true,"screen":"","approval":null}"#.utf8)), [r1]); await shot("23-approval-cleared-working")
        await shot("24-music-after", music: true)

        // quick hm7: readable summaries, and a question never shows the drop-down.
        func tool(_ t: String, _ cmd: String) -> ChatResponse {
            let o: [String: Any] = ["running": true, "screen": "", "approval": ["id": "t-\(t)", "tool": t, "command": cmd]]
            return try! JSONDecoder().decode(ChatResponse.self, from: JSONSerialization.data(withJSONObject: o))
        }
        await apply(ap, []); await shot("25-approval-bash-readable", panel: true)
        await apply(tool("mcp__claude_ai_Notion__notion-search", #"{"query":"roadmap notes","page_size":10,"filters":{"type":"page"}}"#), []); await shot("26-approval-other-kv", panel: true)
        await apply(tool("Edit", "/Users/mitch/x/boringNotch/ContentView.swift"), []); await shot("27-approval-edit-path", panel: true)
        let c0 = OrchestratorApprovalCenter.shared.cardRequest
        let qo: [String: Any] = ["running": true, "screen": fixture("question.txt"), "approval": ["id": "q1", "tool": "AskUserQuestion", "command": "{\"questions\":[…"]]
        await apply(try! JSONDecoder().decode(ChatResponse.self, from: JSONSerialization.data(withJSONObject: qo)), [])
        await shot("28-ask-over-music", music: true)
        print("ask: approval==nil \(OrchestratorApprovalCenter.shared.approval == nil) cardRequest+\(OrchestratorApprovalCenter.shared.cardRequest - c0)")
    }
}


extension ChatResponse {
    /// GET /api/chat body with a pending approval (shape from the 09-CONTEXT contract).
    static var approvalFixture: ChatResponse {
        try! JSONDecoder().decode(ChatResponse.self, from: Data(#"{"running":true,"screen":"","approval":{"id":"a1","tool":"Bash","command":"git -C /Users/mitch/Documents/Claude/orchestrator/worktrees/notch status --short && npm run build -- --verbose","description":"Show status","at":"2026-10-14T09:12:03.000Z"}}"#.utf8))
    }
}
