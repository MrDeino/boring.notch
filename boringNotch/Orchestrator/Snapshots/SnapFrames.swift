import SwiftUI
import QuartzCore

// run.sh --frames: display-link frame intervals through open (closed->open), expand (open->expanded),
// collapse (expanded->open) and close (open->closed), 3 runs each, on an app-like panel (on screen, alpha 0.01).
// No bitmap captures while measuring. Gate: no frame interval over 20 ms (FRAMES_REPORT=1 never fails).
// FRAMES_ONLY=open,close reports only those; FRAMES_LOOP=1 repeats the chain forever (for `sample <pid>`);
// FRAMES_MARK=1 marks each trigger for xctrace Time Profiler (framesMarker).

/// Mirror of ContentView.swift root chain (mainLayout + root modifiers, same order); keep in sync.
/// Only ContentView's open/closed branches that the Orchestrator tab uses (no sneak peek, gestures, music).
struct FramesRoot: View {
    @ObservedObject var vm: BoringViewModel
    @ObservedObject var wings = OrchestratorWingsModel.shared

    var body: some View {
        let open = vm.notchState == .open
        let topR = open ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = VStack(alignment: .leading) { // NotchLayout
                    VStack(alignment: .leading) {
                        if open { NotchReplica(vm: vm).header.frame(height: max(24, vm.effectiveClosedNotchHeight)) }
                        else { Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight) }
                    }
                    .zIndex(2)
                    if open {
                        VStack { OrchestratorView() }
                            .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity).animation(.smooth(duration: 0.35)))
                            .zIndex(1)
                    }
                }
                .frame(alignment: .top)
                .padding(.horizontal, open ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.bottom)
                .padding([.horizontal, .bottom], open ? 12 : 0)
                .background(.black)
                .clipShape(NotchShape(topCornerRadius: topR, bottomCornerRadius: open
                    ? (vm.notchSize.height > openNotchSize.height + 1 ? OT.R.notchExpanded : cornerRadiusInsets.opened.bottom)
                    : cornerRadiusInsets.closed.bottom))
                .overlay(alignment: .top) { Rectangle().fill(.black).frame(height: 1).padding(.horizontal, topR) }
                .overlay { OrchestratorClosedIndicators() }
                .shadow(color: open ? .black.opacity(0.7) : .clear, radius: 6)

                mainLayout
                    .offset(x: open ? 0 : wings.shiftX)
                    .frame(height: open ? vm.notchSize.height : nil)
                    .animation(open ? .spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                               : .spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0), value: vm.notchState)
                    .contentShape(Rectangle())
            }
        }
        .padding(.bottom, 8)
        .notchRootFrame(notchSize: vm.notchSize)
        .onChange(of: vm.notchSize) { _, _ in OrchestratorExpand.shared.syncWindow(vm: vm) }
        .compositingGroup()
        .scaleEffect(x: 1, y: 1, anchor: .top)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
    }
}

final class FrameRecorder: NSObject {
    var stamps: [CFTimeInterval] = []
    var recording = false
    @objc func tick(_ link: CADisplayLink) { if recording { stamps.append(link.timestamp) } }
}

/// FRAMES_MARK=1: a busy spin before each trigger (5 ms per step index: idle 5, open 10 … close 25), so Time Profiler
/// samples show where each transition starts and which one it is.
@inline(never) func framesMarker(_ step: Int) {
    let end = CACurrentMediaTime() + 0.005 * Double(step + 1)
    while CACurrentMediaTime() < end {}
}

extension Snap {
    static func frames() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        setvbuf(stdout, nil, _IOLBF, 0)
        let env = ProcessInfo.processInfo.environment
        let report = env["FRAMES_REPORT"] != nil, loop = env["FRAMES_LOOP"] != nil, mark = env["FRAMES_MARK"] != nil
        let only = env["FRAMES_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        print("frames harness pid \(getpid())")

        // Realistic content: long transcript, a running and a waiting run, usage.
        let state = (try? JSONDecoder().decode(StateResponse.self, from: Data(fixture("phase7-state.txt").utf8))) ?? StateResponse(runs: [], usage: nil)
        await OrchestratorManager.shared.snapshotApply(loaded: true, chat: ChatResponse(running: true, screen: ""), state: state)
        OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks)

        let vm = BoringViewModel()
        vm.notchState = .closed
        vm.closedNotchSize = CGSize(width: 185, height: 32)
        vm.notchSize = vm.closedNotchSize
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = KeyablePanel(contentRect: NSRect(x: screen.midX - windowSize.width / 2, y: screen.maxY - windowSize.height, width: windowSize.width, height: windowSize.height),
                                  styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.isFloatingPanel = true
        window.level = .mainMenu + 3; window.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        window.alphaValue = 0.01; window.ignoresMouseEvents = true
        let host = NSHostingView(rootView: FramesRoot(vm: vm))
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()
        OrchestratorExpand.shared.syncWindow(vm: vm, window: window)

        let rec = FrameRecorder()
        let link = host.displayLink(target: rec, selector: #selector(FrameRecorder.tick(_:)))
        link.add(to: .main, forMode: .common)
        try? await Task.sleep(for: .milliseconds(1200))

        // Same calls the app makes (BoringViewModel.open/close, OrchestratorExpand.setLevel).
        let steps: [(String, () -> Void)] = [
            ("idle", {}), // reference only (not gated): the display link's own cadence with nothing changing
            ("open", { vm.notchSize = OrchestratorExpand.shared.openSize(for: vm); vm.notchState = .open }),
            ("expand", { OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: window) }),
            ("collapse", { OrchestratorExpand.shared.setLevel(.open, vm: vm, window: window) }),
            ("close", { vm.notchSize = vm.closedNotchSize; vm.notchState = .closed }),
        ]
        var results: [String: [(max: Double, p95: Double, over: Int)]] = [:]
        var round = 0
        repeat {
            round += 1
            for (step, (name, act)) in steps.enumerated() {
                if mark { framesMarker(step) }
                rec.stamps = []; rec.recording = true
                let t0 = CACurrentMediaTime()
                act()
                try? await Task.sleep(for: .milliseconds(900)) // covers the 650 ms deferred shrink + 200 ms
                rec.recording = false
                // Intervals from the trigger: the first one is trigger -> first frame after it.
                let ts = [t0] + rec.stamps.filter { $0 >= t0 - 0.0005 }
                let iv = zip(ts.dropFirst(), ts).map { ($0 - $1) * 1000 }
                let sorted = iv.sorted()
                let mx = sorted.last ?? 0, p95 = sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
                var stalls: [String] = []
                for (i, d) in iv.enumerated() where d > 20 {
                    let at = (ts[i] - t0) * 1000
                    stalls.append(String(format: "%.0f+%.0f", at, d))
                    orchPerf.emitEvent("frame-stall", "\(name) at \(Int(at))ms for \(Int(d))ms")
                }
                let worstAt = iv.firstIndex(of: mx).map { (ts[$0] - t0) * 1000 } ?? 0
                if only == nil || only!.contains(name) {
                    results[name, default: []].append((mx, p95, stalls.count))
                    print(String(format: "frames %@ n=%d max=%.1f p95=%.1f over20=%d worst@%.0f stalls[at+ms]=%@", name, iv.count, mx, p95, stalls.count, worstAt, stalls.joined(separator: " ")))
                }
                try? await Task.sleep(for: .milliseconds(1200))
            }
        } while loop || round < 3
        link.invalidate()
        window.contentView = nil; window.orderOut(nil)
        let bad = results.filter { $0.key != "idle" && $0.value.contains { $0.over > 0 } }.keys.sorted()
        for (name, r) in results.sorted(by: { $0.key < $1.key }) {
            print(String(format: "summary %@ max=%.1f p95(max)=%.1f over20(total)=%d", name, r.map(\.max).max() ?? 0, r.map(\.p95).max() ?? 0, r.map(\.over).reduce(0, +)))
        }
        print(bad.isEmpty ? "OK: frames (no interval over 20 ms in open, expand, collapse, close)" : "\(report ? "REPORT" : "FAIL"): frames over 20 ms in " + bad.joined(separator: ", "))
        if !bad.isEmpty && !report { exit(1) }
    }
}
