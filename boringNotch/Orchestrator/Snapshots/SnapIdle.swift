import SwiftUI
import Darwin

// run.sh --idle: process CPU (limit 3% per scene) while idle (closed + open scenes, a running run, SSE-like repeated payloads),
// and the outside-click / close-gate checks. Windows are on screen at alpha 0.01 so springs and
// repeatForever animations really tick. Lines ending in //RUNLOG are dropped when the file is copied into
// bisect worktrees older than the run log overlay. Env: IDLE_REPORT=1 never fails, IDLE_SAMPLE=1 samples each scene, IDLE_GATES=1 runs only the close-gate checks.

private struct IdleRoot: View {
    @ObservedObject var vm: BoringViewModel
    var body: some View {
        NotchReplica(vm: vm).core.environmentObject(vm)
            .padding(.bottom, 8).notchRootFrame(notchSize: vm.notchSize).compositingGroup()
    }
}

/// The app's panel host (boringNotchApp.createBoringNotchWindow). IDLE_DEFAULT_SIZING=1 keeps AppKit's default sizingOptions to reproduce the stale min size.
@MainActor func panelHost<V: View>(_ v: V) -> NSHostingView<V> {
    let h = NSHostingView(rootView: v)
    if ProcessInfo.processInfo.environment["IDLE_DEFAULT_SIZING"] == nil { h.sizingOptions = [] }
    return h
}

private func cpuSeconds() -> Double {
    var u = rusage(); getrusage(RUSAGE_SELF, &u)
    func t(_ v: timeval) -> Double { Double(v.tv_sec) + Double(v.tv_usec) / 1e6 }
    return t(u.ru_utime) + t(u.ru_stime)
}

extension Snap {
    static func idle() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        setvbuf(stdout, nil, _IOLBF, 0)
        print("idle harness pid \(getpid())")
        let m = OrchestratorManager.shared
        _ = OrchestratorWingsModel.shared
        let report = ProcessInfo.processInfo.environment["IDLE_REPORT"] != nil
        let sampling = ProcessInfo.processInfo.environment["IDLE_SAMPLE"] != nil
        let iso = ISO8601DateFormatter()
        var failures: [String] = []
        let screenTop = NSScreen.main?.frame.maxY ?? 900

        let startedAt = iso.string(from: Date().addingTimeInterval(-300)) // fixed: a start time that moved every tick would be a real change
        func state(doing: String) -> StateResponse {
            let r = #"{"id":"r1","project":"notch","state":"running","startedAt":"\#(startedAt)","activity":{"step":"execute","doing":"\#(doing)"}}"#
            return try! JSONDecoder().decode(StateResponse.self, from: Data(#"{"runs":[\#(r)],"usage":{"five_hour":{"used_percentage":42,"resets_at":1791954000}}}"#.utf8))
        }
        func chat(_ secs: Int) -> ChatResponse { ChatResponse(running: true, screen: "✻ Working… (\(secs)s · ↑ 1.2k tokens · esc to interrupt)\n") }
        let none = try! JSONDecoder().decode(StateResponse.self, from: Data(#"{"runs":[]}"#.utf8))

        func makeWindow() -> KeyablePanel {
            let w = KeyablePanel(contentRect: NSRect(x: 0, y: screenTop - windowSize.height, width: windowSize.width, height: windowSize.height),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            w.isOpaque = false; w.backgroundColor = .clear; w.alphaValue = 0.01; w.ignoresMouseEvents = true
            return w
        }
        func teardown(_ w: NSWindow) {
            w.contentView = nil; w.orderOut(nil)
            OrchestratorExpand.shared.reset()
            OrchestratorRunLog.shared.snapshotSet(runID: nil, lines: []) //RUNLOG
        }

        // ---- CPU scenes ----
        var sceneVMs: [BoringViewModel] = [] // same reason as keepAlive below
        enum Feed { case same, doing, screen, tokens, none, rich, typing }
        let optimized = ProcessInfo.processInfo.environment["OPT"]?.contains("-O") == true
        // Transcript fixture for the rich feeds: a dozen blocks, one more per tick.
        func richBlocks(_ n: Int) -> [ChatBlock] {
            let items = (0..<n).map { i in
                i % 3 == 0 ? #"{"id":"u\#(i)","kind":"user","text":"Question number \#(i) about the notch"}"#
                : i % 3 == 1 ? #"{"id":"p\#(i)","kind":"prose","text":"Here is answer \#(i) with some **bold** words and `code`, long enough to wrap onto a second line in the expanded column."}"#
                : #"{"id":"t\#(i)","kind":"tool","name":"Edit","target":"boringNotch/File\#(i).swift","result":"ok","added":3,"removed":1}"#
            }
            return decodeChatBlocks(Data(#"{"running":true,"blocks":[\#(items.joined(separator: ","))]}"#.utf8))?.blocks ?? []
        }
        func scene(_ name: String, closed: Bool, level: ExpandLevel = .open, runs: Bool, feed: Feed, limit: Double = 3) async {
            let store = OrchestratorTranscriptStore.shared
            store.snapshotSet(blocks: feed == .rich || feed == .typing ? richBlocks(12) : [])
            defer { store.snapshotSet(blocks: []) }
            await m.snapshotApply(loaded: true, chat: runs ? chat(41) : ChatResponse(running: true, screen: ""), state: runs ? state(doing: "Reading files") : none)
            try? await Task.sleep(for: .milliseconds(100))
            let vm = BoringViewModel()
            let w = makeWindow()
            sceneVMs.append(vm)
            if closed {
                vm.notchState = .closed
                vm.closedNotchSize = CGSize(width: 185, height: 32)
                w.setFrame(NSRect(x: 0, y: screenTop - 64, width: 440, height: 64), display: false)
                w.contentView = panelHost(ClosedReplica(vm: vm).padding(.bottom, 8).compositingGroup())
            } else {
                vm.notchState = .open
                if level != .open { OrchestratorExpand.shared.setLevel(level, vm: vm, window: w) }
                w.contentView = panelHost(IdleRoot(vm: vm))
            }
            w.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(1))
            var n = 0
            let sameChat = runs ? chat(41) : ChatResponse(running: true, screen: ""), sameState = runs ? state(doing: "Reading files") : none // decoded once: only the apply path is measured
            let feeder = Task { @MainActor in
                while !Task.isCancelled {
                    n += 1
                    switch feed {
                    case .same: await m.snapshotApply(loaded: true, chat: sameChat, state: sameState)
                    case .tokens: await m.snapshotApply(loaded: true, chat: ChatResponse(running: true, screen: "✻ Working… (41s · ↑ \(n).2k tokens · esc to interrupt)\n"), state: sameState)
                    case .none: break
                    case .doing: await m.snapshotApply(loaded: true, chat: chat(41), state: state(doing: "Reading file \(n)"))
                    case .screen: await m.snapshotApply(loaded: true, chat: chat(41 + n), state: state(doing: "Reading file \(n)"))
                    case .rich, .typing:
                        store.snapshotSet(blocks: richBlocks(12 + n), draft: store.draft)
                        await m.snapshotApply(loaded: true, chat: chat(41 + n), state: state(doing: "Reading file \(n)"))
                    }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            let typist = Task { @MainActor in // one character per 100 ms, like a fast typist
                guard feed == .typing else { return }
                var k = 0
                while !Task.isCancelled { k += 1; store.draft = String(repeating: "x", count: k % 60); try? await Task.sleep(for: .milliseconds(100)) }
            }
            defer { typist.cancel() }
            if sampling {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
                p.arguments = ["\(getpid())", "3", "-file", "/tmp/notch-idle-\(name).sample"]
                try? p.run()
            }
            let c0 = cpuSeconds(), t0 = ContinuousClock.now
            try? await Task.sleep(for: .seconds(8))
            let wall = Double((ContinuousClock.now - t0) / .milliseconds(1)) / 1000
            let cpu = (cpuSeconds() - c0) / wall * 100
            feeder.cancel()
            print(String(format: "cpu %@: %.1f%%", name, cpu))
            if cpu >= limit { failures.append("cpu \(name) \(String(format: "%.1f", cpu))%") }
            teardown(w)
            try? await Task.sleep(for: .milliseconds(300))
        }
        let gatesOnly = ProcessInfo.processInfo.environment["IDLE_GATES"] != nil
        if !gatesOnly {
        await scene("a-closed-running-same", closed: true, runs: true, feed: .same)
        await scene("a2-closed-running-doing", closed: true, runs: true, feed: .doing)
        await scene("a3-closed-running-screen", closed: true, runs: true, feed: .screen)
        await scene("a4-closed-running-tokens", closed: true, runs: true, feed: .tokens)
        await scene("b-closed-nothing", closed: true, runs: false, feed: .same)
        await scene("c-open-running", closed: false, runs: true, feed: .same)
        await scene("c2-open-running-nofeed", closed: false, runs: true, feed: .none)
        await scene("d-expanded-running", closed: false, level: .expanded, runs: true, feed: .same)
        await scene("e-expanded-running-doing", closed: false, level: .expanded, runs: true, feed: .doing, limit: 9) // the board redraws its activity line every second: real data, unoptimized harness
        await scene("f-expanded-rich-tick", closed: false, level: .expanded, runs: true, feed: .rich, limit: 9) // doing + live status + one more block every second
        await scene("g-expanded-rich-typing", closed: false, level: .expanded, runs: true, feed: .typing, limit: 9) // plus a keystroke every 100 ms

        }
        // ---- outside-click / close-gate checks ----
        await m.snapshotApply(loaded: true, chat: chat(41), state: state(doing: "Reading files"))
        let share = SharingStateManager.shared
        var keepAlive: [BoringViewModel] = [] // OrchestratorExpand keys by ObjectIdentifier(vm): a freed vm's address would be reused by the next gate's vm
        func gate(_ name: String, _ body: (BoringViewModel, KeyablePanel, () async -> Void, (ExpandLevel) async -> Void) async -> (expectClose: Bool, extra: [String])) async {
            let vm = BoringViewModel(); vm.notchState = .open; keepAlive.append(vm)
            let w = makeWindow()
            w.contentView = panelHost(IdleRoot(vm: vm))
            w.orderFrontRegardless()
            OrchestratorExpand.shared.syncWindow(vm: vm, window: w, now: true)
            try? await Task.sleep(for: .milliseconds(700))
            let before = vm.closeCount
            // The window is "not visible" to AppKit, so SwiftUI's onChange handlers run late: wait for the state a user would see before acting.
            func waitLevel(_ l: ExpandLevel) async { for _ in 0..<50 where OrchestratorExpand.shared.level(for: vm) != l { w.contentView?.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(100)) }; try? await Task.sleep(for: .milliseconds(700)); w.contentView?.layoutSubtreeIfNeeded() }
            var clickAt: TimeInterval?, collapseAt: TimeInterval?
            let watch = OrchestratorExpand.shared.$expanded.sink { set in // fires synchronously when the collapse starts
                if clickAt != nil, collapseAt == nil, !set.contains(ObjectIdentifier(vm)) { collapseAt = ProcessInfo.processInfo.systemUptime }
            }
            func outsideClick() async {
                // A mouseDown 10pt under the notch, delivered in-process: the monitors take the point from the event, the real cursor never moves.
                let y = w.frame.height - vm.notchSize.height - 10
                let t = ProcessInfo.processInfo.systemUptime
                clickAt = t
                if let e = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: w.frame.width / 2, y: y), modifierFlags: [], timestamp: t,
                                              windowNumber: w.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) { NSApp.sendEvent(e) }
                try? await Task.sleep(for: .milliseconds(150))
            }
            let r = await body(vm, w, outsideClick, waitLevel)
            // The shrink waits for the notch spring, which this alpha-0.01 window sometimes advances slowly: allow up to 4s.
            let want = panelSize(notch: vm.notchSize, base: windowSize, openHeight: openNotchSize.height)
            for _ in 0..<40 where abs(w.frame.height - want.height) > 0.5 || abs(w.frame.width - want.width) > 0.5 { w.contentView?.layoutSubtreeIfNeeded(); try? await Task.sleep(for: .milliseconds(100)) }
            watch.cancel()
            var bad = r.extra
            let closed = vm.closeCount - before
            func lat(_ t: TimeInterval?) -> String { clickAt.flatMap { c in t.map { String(format: "%.1fms", ($0 - c) * 1000) } } ?? "-" }
            print("latency \(name): collapse=\(lat(collapseAt)) close=\(lat(vm.closedAt)) refused=\(vm.refused)")
            if r.expectClose && closed < 1 { bad.append("notch not closed by outside click") }
            if share.preventNotchClose { bad.append("interaction leaked (sessions=\(share.sessions))") }
            if OrchestratorExpand.shared.level(for: vm) != .open { bad.append("level \(OrchestratorExpand.shared.level(for: vm))") }
            let hv = w.contentView as? NSHostingView<IdleRoot>
            let diag = "min=\(w.minSize) cmin=\(w.contentMinSize) sizing=\(hv?.sizingOptions.rawValue ?? 99) fit=\(hv?.fittingSize ?? .zero)"
            var warn = " " + diag
            // Frame is owned by syncWindow: it must land on panelSize, and the window must not impose a larger min size.
            if abs(w.frame.height - want.height) > 0.5 || abs(w.frame.width - want.width) > 0.5 { bad.append("window \(w.frame.size) != \(want)") }
            if w.minSize.height > want.height + 0.5 || w.contentMinSize.height > want.height + 0.5 { bad.append("window min size \(w.minSize)/\(w.contentMinSize) above target") }
            print("gate \(name): visible=\(w.occlusionState.contains(.visible)) closes=\(closed) sessions=\(share.sessions) level=\(OrchestratorExpand.shared.level(for: vm)) win=\(w.frame.size) \(bad.isEmpty ? "ok" : "BAD " + bad.joined(separator: "; "))\(warn)")
            if !bad.isEmpty { failures.append("gate \(name): " + bad.joined(separator: "; ")) }
            teardown(w)
            m.endTyping()
            while share.preventNotchClose { share.endInteraction() } // do not let one failure poison the next gate
            try? await Task.sleep(for: .milliseconds(300))
            if OrchestratorExpand.shared.monitorsActive { failures.append("gate \(name): click monitors still installed after teardown") }
        }
        await gate("1-open-never-expanded") { _, _, _, _ in (false, []) }
        await gate("2-expanded-outside-click") { vm, w, click, wait in
            OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: w)
            await wait(.expanded)
            await click()
            return (true, [])
        }
        await gate("3-log-opened-closed-at-open") { vm, w, click, wait in //RUNLOG
            OrchestratorRunLog.shared.snapshotSet(runID: "r1", lines: ["a", "b"]) //RUNLOG
            await wait(.expanded) //RUNLOG
            OrchestratorRunLog.shared.snapshotSet(runID: nil, lines: []) //RUNLOG
            await wait(.open) //RUNLOG
            await click() //RUNLOG
            return (true, []) //RUNLOG
        } //RUNLOG
        await gate("4-log-then-notch-closes-then-reopen") { vm, w, click, wait in //RUNLOG
            OrchestratorRunLog.shared.snapshotSet(runID: "r1", lines: ["a", "b"]) //RUNLOG
            await wait(.expanded) //RUNLOG
            let host = w.contentView //RUNLOG
            m.notchOpen = false; w.contentView = nil //RUNLOG
            try? await Task.sleep(for: .milliseconds(300)) //RUNLOG
            w.contentView = host //RUNLOG
            m.notchOpen = true //RUNLOG
            OrchestratorExpand.shared.syncWindow(vm: vm, window: w, now: true) //RUNLOG
            try? await Task.sleep(for: .milliseconds(700)) //RUNLOG
            OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: w) //RUNLOG
            await wait(.expanded) //RUNLOG
            await click() //RUNLOG
            return (true, []) //RUNLOG
        } //RUNLOG
        await gate("5-log-open-then-outside-click") { vm, w, click, wait in //RUNLOG
            OrchestratorRunLog.shared.snapshotSet(runID: "r1", lines: ["a", "b"]) //RUNLOG
            await wait(.expanded) //RUNLOG
            await click() //RUNLOG
            return (true, []) //RUNLOG
        } //RUNLOG

        await gate("6-expanded-ticking-outside-click") { vm, w, click, wait in
            OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: w)
            await wait(.expanded)
            let store = OrchestratorTranscriptStore.shared
            store.snapshotSet(blocks: richBlocks(12))
            let feeder = Task { @MainActor in
                var n = 0
                while !Task.isCancelled { n += 1; store.snapshotSet(blocks: richBlocks(12 + n)); await m.snapshotApply(loaded: true, chat: chat(41 + n), state: state(doing: "Reading file \(n)")); try? await Task.sleep(for: .milliseconds(300)) }
            }
            try? await Task.sleep(for: .milliseconds(1500))
            await click()
            feeder.cancel(); store.snapshotSet(blocks: [])
            return (true, [])
        }
        await gate("7-open-typing-outside-click") { vm, w, click, wait in
            m.beginTyping(in: w) // the composer is focused: the hover-exit close is refused while typing
            try? await Task.sleep(for: .milliseconds(300))
            await click()
            return (true, [])
        }

        if failures.isEmpty { print("OK: idle"); return }
        print("FAIL: " + failures.joined(separator: ", "))
        if !report { exit(1) }
    }
}
