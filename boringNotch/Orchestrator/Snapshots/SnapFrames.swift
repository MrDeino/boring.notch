import SwiftUI
import QuartzCore

// run.sh --frames: display-link frame intervals through open (closed->open), expand (open->expanded),
// collapse (expanded->open) and close (open->closed), 3 runs each, on an app-like panel (on screen, alpha 0.01).
// No bitmap captures while measuring. Gate: no frame interval over 20 ms (FRAMES_REPORT=1 never fails).
// FRAMES_ONLY=open,close reports only those; FRAMES_LOOP=1 repeats the chain forever (for `sample <pid>`);
// FRAMES_MARK=1 marks each trigger for xctrace Time Profiler (framesMarker).
// Together gate: the notch shape's width and height progress must stay within 0.08 of each other on every layout
// sample of expand, collapse and close (and no frame where one moves while the other holds). FRAMES_TRACE=1 prints
// the per-sample shape / tab-body / window sizes. Even gate: no mid-spring jump over 0.12 of the travel (a stall that
// splits the motion). Content gate: the transcript frame is steady once it fades back in. Root-read gate: the root body
// reads the new notch size within 50 ms (a stale read inside @Published's willSet loses the spring). FRAMES_PIXELS=1:
// drawn-shape pass.

/// Mirror of ContentView.swift root chain (mainLayout + root modifiers, same order); keep in sync.
/// Only ContentView's open/closed branches that the Orchestrator tab uses (no sneak peek, gestures, music).
struct FramesRoot: View {
    @ObservedObject var vm: BoringViewModel
    @ObservedObject var wings = OrchestratorWingsModel.shared

    var body: some View {
        let _ = FramesProbe.bodies.append((CACurrentMediaTime(), vm.notchSize)) // stale-read gate
        let open = vm.notchState == .open
        let topR = open ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = VStack(alignment: .leading, spacing: open ? nil : 0) { // NotchLayout
                    VStack(alignment: .leading) {
                        if open { NotchReplica(vm: vm).header.frame(height: max(24, vm.effectiveClosedNotchHeight)) }
                        else { Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight) }
                    }
                    .zIndex(2)
                    if open || (FramesProbe.keepBuilt && OrchestratorExpand.shared.keepsTabBuilt(vm)) { // ContentView: the Orchestrator tab is kept built while closed
                        VStack { OrchestratorView() }
                            .background(SizeProbe(shape: false))
                            .transition(.opacity.animation(.smooth(duration: 0.35))) // ContentView: the Orchestrator tab fades only
                            .zIndex(1)
                            .allowsHitTesting(open)
                            .modifier(OrchestratorKeptBuilt(hidden: !open))
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
                    .background(SizeProbe(shape: true))

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
    weak var window: NSWindow?
    var windowSizes: [(CFTimeInterval, CGSize)] = []
    /// The transcript scroll view (biggest NSScrollView) per frame: frame from the window top, scroll offset, opacity.
    struct Box { var t: CFTimeInterval; var y, h, w, off: CGFloat; var alpha: Float }
    var boxes: [Box] = []
    private weak var scroll: NSScrollView?
    @objc func tick(_ link: CADisplayLink) {
        guard recording else { return }
        stamps.append(link.timestamp)
        guard let w = window else { return }
        windowSizes.append((CACurrentMediaTime(), w.frame.size))
        if scroll?.window == nil, let root = w.contentView {
            var best: NSScrollView?
            func walk(_ v: NSView) { if let s = v as? NSScrollView, s.frame.height > (best?.frame.height ?? 0) { best = s }; v.subviews.forEach(walk) }
            walk(root)
            scroll = best
        }
        guard let s = scroll else { return }
        let r = s.convert(s.bounds, to: nil)
        var a: Float = 1; var l: CALayer? = s.layer
        while let x = l { a *= x.presentation()?.opacity ?? x.opacity; l = x.superlayer }
        boxes.append(Box(t: CACurrentMediaTime(), y: w.frame.height - r.maxY, h: r.height, w: r.width, off: s.contentView.bounds.origin.y, alpha: a))
    }
}

/// Content gate: once the tab content is visible again after the level swap (it fades out, swaps while hidden, fades
/// in), its transcript frame must not change: laid out once at the final size, never growing after it shows.
/// Returns the first change after it showed (nil = steady), or "never hidden" when it never faded out.
func contentSteady(_ b: [FrameRecorder.Box]) -> String? {
    guard let hidden = b.firstIndex(where: { $0.alpha < 0.05 }) else { return b.isEmpty ? nil : "never hidden" }
    guard let shown = b[hidden...].firstIndex(where: { $0.alpha > 0.05 }) else { return nil }
    let f = b[shown]
    for x in b[shown...] where abs(x.y - f.y) > 0.5 || abs(x.h - f.h) > 0.5 || abs(x.w - f.w) > 0.5 || abs(x.off - f.off) > 0.5 {
        return String(format: "y%.0f h%.0f w%.0f off%.0f -> y%.0f h%.0f w%.0f off%.0f", f.y, f.h, f.w, f.off, x.y, x.h, x.w, x.off)
    }
    return nil
}

/// Layout-pass sizes of the notch shape (mainLayout) and the tab body wrapper, appended by FramesRoot.
enum FramesProbe {
    static var shape: [(CFTimeInterval, CGSize)] = []
    static var content: [(CFTimeInterval, CGSize)] = []
    /// Root body evaluations (time, the notchSize it read).
    static var bodies: [(CFTimeInterval, CGSize)] = []
    /// ContentView's currentView == .orchestrator while closed (FRAMES_REMOUNT=1: the old insert-on-open, for before/after).
    static var keepBuilt = ProcessInfo.processInfo.environment["FRAMES_REMOUNT"] == nil
}

/// An AppKit view in the shape's background: SwiftUI sets its frame on every animated frame (onGeometryChange and a
/// Layout's placeSubviews only see the final size), so its setFrameSize is the per-frame shape size.
struct SizeProbe: NSViewRepresentable {
    let shape: Bool
    final class V: NSView {
        var shape = true
        override func setFrameSize(_ s: NSSize) {
            super.setFrameSize(s)
            if shape { FramesProbe.shape.append((CACurrentMediaTime(), s)) } else { FramesProbe.content.append((CACurrentMediaTime(), s)) }
        }
        override func hitTest(_ p: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.shape = shape; return v }
    func updateNSView(_ v: V, context: Context) {}
}

struct TogetherResult { var maxGap = 0.0, at = 0.0, stuck = 0, samples = 0, worst = "", jump = 0.0, jumpAt = 0.0 }

/// Width and height progress of one transition, start `a` to the last sample. nil when either dimension moves <= 1 pt.
/// Samples within 2 ms of each other are one frame (the last one counts). Fails (see `ok`) when |pw - ph| > 0.08 on
/// any sample, or a consecutive pair mid-transition moves one dimension > 0.5 pt while the other moves < 0.05 pt.
/// `jump`: the biggest progress step between two drawn frames (a stall mid-spring splits the motion in two: the shape
/// moves, holds, then jumps on). Even when <= 0.12 (about two frames of travel at the spring's peak speed at 120 Hz).
func together(_ raw: [(t: Double, s: CGSize)], start a: CGSize) -> TogetherResult? {
    var s: [(t: Double, s: CGSize)] = []
    for x in raw { if let l = s.last, x.t - l.t < 0.002 { s[s.count - 1] = x } else { s.append(x) } }
    guard let b = s.last?.s, abs(b.width - a.width) > 1, abs(b.height - a.height) > 1 else { return nil }
    var r = TogetherResult(samples: s.count)
    var prev: (p: Double, s: CGSize)?
    for x in s {
        let pw = (x.s.width - a.width) / (b.width - a.width), ph = (x.s.height - a.height) / (b.height - a.height)
        let gap = Double(abs(pw - ph)), p = Double(pw + ph) / 2
        if gap > r.maxGap { r.maxGap = gap; r.at = x.t; r.worst = String(format: "w=%.1f h=%.1f pw=%.2f ph=%.2f", Double(x.s.width), Double(x.s.height), Double(pw), Double(ph)) }
        if let q = prev, abs(p - q.p) > r.jump { r.jump = abs(p - q.p); r.jumpAt = x.t }
        if let q = prev, q.p > 0.02, q.p < 0.98, p > 0.02, p < 0.98 {
            let dw = abs(x.s.width - q.s.width), dh = abs(x.s.height - q.s.height)
            if (dw > 0.5 && dh < 0.05) || (dh > 0.5 && dw < 0.05) { r.stuck += 1 }
        }
        prev = (p, x.s)
    }
    return r
}
extension TogetherResult {
    var ok: Bool { maxGap <= 0.08 && stuck == 0 }
    var even: Bool { jump <= 0.12 }
}

/// Self-check of `together`: one spring for both passes; width first, then height fails.
func togetherSelfCheck() {
    let a = CGSize(width: 640, height: 190), b = CGSize(width: 850, height: 540)
    func series(_ f: (Double) -> (Double, Double)) -> [(t: Double, s: CGSize)] {
        (0...40).map { i in let (pw, ph) = f(Double(i) / 40)
            return (Double(i) / 120, CGSize(width: a.width + pw * (b.width - a.width), height: a.height + ph * (b.height - a.height))) }
    }
    let same = together(series { t in let e = 1 - pow(1 - t, 3); return (e, e) }, start: a)
    let split = together(series { t in (min(1, 2 * t), max(0, 2 * t - 1)) }, start: a)
    // A 60 ms hold mid-spring (the shape stops, then catches up with the spring's clock) is uneven.
    let held = together(series { t in let e = 1 - pow(1 - (t > 0.25 && t < 0.4 ? 0.25 : t), 3); return (e, e) }, start: a)
    assert(same?.ok == true && same?.even == true && split?.ok == false && split!.stuck > 0 && held?.even == false, "together self-check")
    guard same?.ok == true, same?.even == true, split?.ok == false, held?.ok == true, held?.even == false else { print("FAIL: together self-check"); exit(1) }
    print("together self-check OK")
}

/// The drawn black shape: width from the row 4 pt below the top, height from the centre column (cacheDisplay).
@MainActor func drawnShape(_ host: NSView) -> CGSize? {
    let b = host.bounds
    func dark(_ c: NSColor?) -> Bool { (c?.brightnessComponent ?? 1) < 0.05 && (c?.alphaComponent ?? 0) > 0.5 }
    let row = NSRect(x: 0, y: host.isFlipped ? 4 : b.height - 6, width: b.width, height: 2), col = NSRect(x: b.midX - 1, y: 0, width: 2, height: b.height)
    guard let rr = host.bitmapImageRepForCachingDisplay(in: row), let cr = host.bitmapImageRepForCachingDisplay(in: col) else { return nil }
    host.cacheDisplay(in: row, to: rr); host.cacheDisplay(in: col, to: cr)
    let k = CGFloat(rr.pixelsWide) / b.width
    guard let l = (0..<rr.pixelsWide).first(where: { dark(rr.colorAt(x: $0, y: 0)) }),
          let r = (0..<rr.pixelsWide).last(where: { dark(rr.colorAt(x: $0, y: 0)) }),
          let bot = (0..<cr.pixelsHigh).last(where: { dark(cr.colorAt(x: 0, y: $0)) }) else { return nil }
    return CGSize(width: CGFloat(r - l + 1) / k, height: CGFloat(bot + 1) / k)
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
        togetherSelfCheck()
        let trace = env["FRAMES_TRACE"] != nil

        // Realistic content: long transcript, a running and a waiting run, usage.
        let state = (try? JSONDecoder().decode(StateResponse.self, from: Data(fixture("phase7-state.txt").utf8))) ?? StateResponse(runs: [], usage: nil)
        await OrchestratorManager.shared.snapshotApply(loaded: true, chat: ChatResponse(running: true, screen: ""), state: state)
        // FRAMES_BLOCKS=n: n prose+tool pairs instead of the 29-block fixture (a real transcript shows up to 60 rows).
        if let n = env["FRAMES_BLOCKS"].flatMap(Int.init) {
            let items = (1...n).map { i in #"{"id":"fp\#(i)","kind":"prose","text":"Step \#(i): the transcript keeps growing while Claude explains what it changed and why, long enough to wrap across several lines in the notch."},{"id":"ft\#(i)","kind":"tool","name":"Edit","target":"/Users/x/proj/File\#(i).swift","added":\#(i),"removed":1}"# }
            OrchestratorTranscriptStore.shared.snapshotSet(blocks: decodeChatBlocks(Data((#"{"running":true,"blocks":["# + items.joined(separator: ",") + "]}").utf8))?.blocks ?? longBlocks)
        } else { OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks) }

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
        rec.window = window
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
        var apart: Set<String> = []
        var lastShape: CGSize?
        var gaps: [String: [(gap: Double, stuck: Int, jump: Double)]] = [:]
        var uneven: Set<String> = [], moving: Set<String> = [], lost: Set<String> = []
        var round = 0
        repeat {
            round += 1
            for (step, (name, act)) in steps.enumerated() {
                if mark { framesMarker(step) }
                let a = FramesProbe.shape.last?.1 ?? lastShape
                lastShape = a
                FramesProbe.shape = []; FramesProbe.content = []; rec.windowSizes = []; rec.boxes = []; FramesProbe.bodies = []
                rec.stamps = []; rec.recording = true
                let before = vm.notchSize
                let t0 = CACurrentMediaTime()
                act()
                let target = vm.notchSize
                try? await Task.sleep(for: .milliseconds(900)) // covers the 650 ms deferred shrink + 200 ms
                rec.recording = false
                lastShape = FramesProbe.shape.last?.1 ?? lastShape
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
                    if let a, let r = together(FramesProbe.shape.map { ($0.0 - t0, $0.1) }, start: a) {
                        gaps[name, default: []].append((r.maxGap, r.stuck, r.jump))
                        let gated = ["expand", "collapse", "close"].contains(name)
                        if !r.ok && gated { apart.insert(name) }
                        if !r.even && gated { uneven.insert(name) }
                        print(String(format: "together %@ maxGap=%.3f at=%.0f stuck=%d jump=%.3f at=%.0f samples=%d %@ %@", name, r.maxGap, r.at * 1000, r.stuck, r.jump, r.jumpAt * 1000, r.samples, r.worst, r.ok ? (r.even ? "ok" : "UNEVEN") : "APART"))
                    }
                    // Stale read: SwiftUI can run the update synchronously inside @Published's willSet (before the new size is
                        // stored); the root then keeps the old size and the spring never starts until something else
                        // invalidates it. Gate: the root reads the new size within 50 ms of the trigger.
                    if before != target {
                        let stale = FramesProbe.bodies.filter { $0.0 >= t0 && $0.1 == before }.count
                        let fresh = FramesProbe.bodies.first { $0.0 >= t0 && $0.1 == target }.map { ($0.0 - t0) * 1000 }
                        let ok = (fresh ?? .infinity) <= 50
                        if !ok && ["expand", "collapse", "close"].contains(name) { lost.insert(name) }
                        print("rootread \(name) stale=\(stale) firstFresh=" + (fresh.map { String(format: "%.0fms", $0) } ?? "never") + (ok ? " ok" : " LOST"))
                    }
                    if name == "expand" || name == "collapse" {
                        let c = contentSteady(rec.boxes.map { var b = $0; b.t -= t0; return b })
                        if c != nil { moving.insert(name) }
                        print("content \(name) " + (c.map { "MOVES after it shows: " + $0 } ?? "steady once shown"))
                    }
                    if trace {
                        func row(_ l: String, _ xs: [(CFTimeInterval, CGSize)]) {
                            print("trace \(name) \(l) " + xs.map { String(format: "%.0f:%.0fx%.0f", ($0.0 - t0) * 1000, $0.1.width, $0.1.height) }.joined(separator: " "))
                        }
                        row("shape", FramesProbe.shape); row("body", FramesProbe.content)
                        var w: [(CFTimeInterval, CGSize)] = []
                        for x in rec.windowSizes where w.last?.1 != x.1 { w.append(x) }
                        row("window", w)
                        row("rootBody", FramesProbe.bodies)
                        print("trace \(name) scroll " + rec.boxes.map { String(format: "%.0f:y%.0f,h%.0f,w%.0f,off%.0f,a%.2f", ($0.t - t0) * 1000, $0.y, $0.h, $0.w, $0.off, $0.alpha) }.joined(separator: " "))
                    }
                }
                try? await Task.sleep(for: .milliseconds(1200))
            }
        } while loop || round < 3
        link.invalidate()
        // FRAMES_PIXELS=1: a separate pass after the timing runs (captures stall the main thread, so they never touch the
        // interval numbers): the drawn shape's width (header row) and height (centre column) every ~8 ms.
        if env["FRAMES_PIXELS"] != nil {
            for (name, act) in steps where name != "idle" {
                var px: [(t: Double, s: CGSize)] = []
                let a = drawnShape(host)
                let t0 = CACurrentMediaTime()
                act()
                while CACurrentMediaTime() - t0 < 0.7 {
                    try? await Task.sleep(for: .milliseconds(8))
                    if let s = drawnShape(host) { px.append((CACurrentMediaTime() - t0, s)) }
                }
                if let a, let r = together(px, start: a) {
                    print(String(format: "pixels %@ maxGap=%.3f at=%.0f stuck=%d samples=%d %@", name, r.maxGap, r.at * 1000, r.stuck, r.samples, r.worst))
                }
                print("pixels \(name) " + px.map { String(format: "%.0f:%.0fx%.0f", $0.t * 1000, $0.s.width, $0.s.height) }.joined(separator: " "))
                try? await Task.sleep(for: .milliseconds(1000))
            }
        }
        window.contentView = nil; window.orderOut(nil)
        let bad = results.filter { $0.key != "idle" && $0.value.contains { $0.over > 0 } }.keys.sorted()
        for (name, r) in results.sorted(by: { $0.key < $1.key }) {
            let g = gaps[name] ?? []
            print(String(format: "summary %@ max=%.1f p95(max)=%.1f over20(total)=%d togetherGap(max)=%.3f stuck(total)=%d jump(max)=%.3f", name, r.map(\.max).max() ?? 0, r.map(\.p95).max() ?? 0, r.map(\.over).reduce(0, +), g.map(\.gap).max() ?? 0, g.map(\.stuck).reduce(0, +), g.map(\.jump).max() ?? 0))
        }
        print(bad.isEmpty ? "OK: frames (no interval over 20 ms in open, expand, collapse, close)" : "\(report ? "REPORT" : "FAIL"): frames over 20 ms in " + bad.joined(separator: ", "))
        print(apart.isEmpty ? "OK: together (width and height move as one in expand, collapse, close)" : "\(report ? "REPORT" : "FAIL"): width/height apart in " + apart.sorted().joined(separator: ", "))
        print(uneven.isEmpty ? "OK: even (no mid-spring jump over 0.12 of the travel in expand, collapse, close)" : "\(report ? "REPORT" : "FAIL"): shape jumps mid-spring in " + uneven.sorted().joined(separator: ", "))
        print(moving.isEmpty ? "OK: content laid out once (steady once it shows) in expand, collapse" : "\(report ? "REPORT" : "FAIL"): content moves after it shows in " + moving.sorted().joined(separator: ", "))
        print(lost.isEmpty ? "OK: root reads the new notch size within 50 ms (expand, collapse, close)" : "\(report ? "REPORT" : "FAIL"): size change lost (stale root) in " + lost.sorted().joined(separator: ", "))
        if (!bad.isEmpty || !apart.isEmpty || !uneven.isEmpty || !moving.isEmpty || !lost.isEmpty) && !report { exit(1) }
    }
}
