import SwiftUI

// run.sh --paint: what the window server actually shows of the panel through open, expand, close from expanded
// (outside click and hover exit), collapse and close. FramesRoot on an app-like panel parked off screen at full alpha,
// captured as composited (CGWindowListCreateImage on our own window: no Screen Recording permission, AppKit-backed
// text included, unlike cacheDisplay) every ~8 ms. Gates, per transition and frame:
//   leak:  no light pixel (text, badge) outside the black notch shape
//   box:   the black shape is never taller or wider than the layout's notch shape within the last 50 ms (no black box
//          held after the content or the layout has moved on)
//   badge: no update-badge pixels on a frame where the tab content below the header is hidden
// PAINT_DIR=<dir> writes a strip of every captured frame per transition (default /tmp/notch-paint).

private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
/// CGWindowListCreateImage is unavailable in the macOS 15+ SDK but still exported; capturing our own window needs no permission.
private let createImage: CreateImage? = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: CreateImage.self) }

private struct Frame { var t: Double; var img: CGImage }
private struct Look { var shape: CGRect; var leak: Int; var content: Int; var badge: Int; var leakAt: CGPoint }

/// Pixels in points: shape = bounding box of opaque black; leak = light pixels outside it (1 pt slack);
/// content/badge = light/orange pixels inside it below the 40 pt header band.
private func look(_ img: CGImage, scale k: CGFloat) -> Look {
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h)) // row 0 = top
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4
        if px[i + 3] > 240 && max(px[i], px[i + 1], px[i + 2]) < 13 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
    } }
    let pad = Int(k), top = minY + Int(40 * k)
    var leak = 0, content = 0, badge = 0, leakAt = CGPoint.zero
    for y in 0..<h { for x in 0..<w {
        let i = (y * w + x) * 4, a = Int(px[i + 3])
        guard a > 76 else { continue }
        let r = Int(px[i]) * 255 / a, g = Int(px[i + 1]) * 255 / a, b = Int(px[i + 2]) * 255 / a
        guard max(r, g, b) > 90 else { continue }
        if maxX < 0 || x < minX - pad || x > maxX + pad || y < minY - pad || y > maxY + pad {
            if leak == 0 { leakAt = CGPoint(x: CGFloat(x) / k, y: CGFloat(y) / k) }
            leak += 1; continue
        }
        guard y > top else { continue }
        if r > 150 && r - b > 70 && g > 70 && g < r - 30 { badge += 1 } else { content += 1 }
    } }
    let shape = maxX < 0 ? .zero : CGRect(x: CGFloat(minX) / k, y: CGFloat(minY) / k, width: CGFloat(maxX - minX + 1) / k, height: CGFloat(maxY - minY + 1) / k)
    return Look(shape: shape, leak: Int((CGFloat(leak) / (k * k)).rounded(.up)), content: content, badge: badge, leakAt: leakAt)
}

/// All frames of one transition side by side (half size), for the before/after evidence.
private func writeStrip(_ frames: [Frame], to url: URL) {
    guard let f0 = frames.first?.img else { return }
    let cw = f0.width / 4, ch = f0.height / 4, cols = 8, rows = (frames.count + cols - 1) / cols
    guard let ctx = CGContext(data: nil, width: cw * cols, height: ch * rows, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    ctx.setFillColor(CGColor(red: 0.45, green: 0.55, blue: 0.65, alpha: 1)) // stand-in wallpaper, so black and text both show
    ctx.fill(CGRect(x: 0, y: 0, width: cw * cols, height: ch * rows))
    for (i, f) in frames.enumerated() {
        ctx.draw(f.img, in: CGRect(x: (i % cols) * cw, y: (rows - 1 - i / cols) * ch, width: cw, height: ch))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: (i % cols) * cw, y: (rows - 1 - i / cols) * ch, width: 1, height: ch))
    }
    guard let img = ctx.makeImage(), let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dst, img, nil); CGImageDestinationFinalize(dst)
}

extension Snap {
    static func paint() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        setvbuf(stdout, nil, _IOLBF, 0)
        let env = ProcessInfo.processInfo.environment
        let dir = URL(fileURLWithPath: env["PAINT_DIR"] ?? "/tmp/notch-paint")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let createImage else { print("FAIL: paint (no CGWindowListCreateImage)"); exit(1) }
        let state = (try? JSONDecoder().decode(StateResponse.self, from: Data(fixture("phase7-state.txt").utf8))) ?? StateResponse(runs: [], usage: nil)
        var chat = ChatResponse(running: true, screen: "")
        chat.claude = ClaudeInfo(running: "2.1.0", installed: "2.1.1", updateReady: true) // the update badge is up, as in the recording
        await OrchestratorManager.shared.snapshotApply(loaded: true, chat: chat, state: state)
        OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks)

        let vm = BoringViewModel()
        vm.notchState = .closed
        vm.closedNotchSize = CGSize(width: 185, height: 32)
        vm.notchSize = vm.closedNotchSize
        // Off screen (nothing shows on the user's display), full alpha so the capture is what the window server composites.
        let window = KeyablePanel(contentRect: NSRect(x: -6000, y: 300, width: windowSize.width, height: windowSize.height),
                                  styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.isFloatingPanel = true
        window.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]
        window.ignoresMouseEvents = true
        let host = NSHostingView(rootView: FramesRoot(vm: vm))
        host.sizingOptions = []
        window.contentView = host
        window.orderFrontRegardless()
        OrchestratorExpand.shared.syncWindow(vm: vm, window: window)
        try? await Task.sleep(for: .milliseconds(1200))

        let expand = OrchestratorExpand.shared
        // Same calls the app makes: BoringViewModel.open/close, OrchestratorExpand.setLevel, and the outside click
        // (collapseIfOutside: collapse, then close).
        // ContentView.doOpen: hover/tap open runs vm.open() inside its interactive spring.
        let open = { withAnimation(.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)) { vm.notchSize = expand.openSize(for: vm); vm.notchState = .open } }
        let close = { vm.notchSize = vm.closedNotchSize; vm.notchState = .closed }
        let toExpanded = { expand.setLevel(.expanded, vm: vm, window: window) }
        let steps: [(String, () -> Void)] = [
            ("open", open), ("expand", toExpanded), ("closeExpanded", { expand.collapse(vm: vm); close() }),
            ("open2", open), ("expand2", toExpanded), ("closeExpandedHover", close), // hover exit: no collapse first
            ("open3", open), ("expand3", toExpanded), ("collapse", { expand.setLevel(.open, vm: vm, window: window) }), ("close", close),
        ]
        var fails: [String] = []
        for (name, act) in steps {
            FramesProbe.shape = []
            var frames: [Frame] = []
            let t0 = CACurrentMediaTime()
            act()
            while CACurrentMediaTime() - t0 < 0.9 {
                try? await Task.sleep(for: .milliseconds(8))
                if let img = createImage(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() { frames.append(Frame(t: (CACurrentMediaTime() - t0) * 1000, img: img)) }
            }
            let layout = FramesProbe.shape.map { (t: ($0.0 - t0) * 1000, s: $0.1) }
            let k = window.backingScaleFactor
            let looks = frames.map { look($0.img, scale: k) }
            var bad: [String] = []
            if let i = looks.indices.first(where: { looks[$0].leak > 2 }) {
                let n = looks.filter { $0.leak > 2 }.count
                bad.append(String(format: "%d pt² drawn outside the shape at %.0fms (first at %.0f,%.0f; %d frames)", looks[i].leak, frames[i].t, looks[i].leakAt.x, looks[i].leakAt.y, n))
            }
            // Layout shape over the last 50 ms (the window server shows a frame or two after layout).
            let start = layout.first?.s ?? .zero
            for (f, l) in zip(frames, looks) where l.shape.height > 0 {
                let recent = layout.filter { $0.t <= f.t && $0.t >= f.t - 50 }.map(\.s) + [layout.last { $0.t <= f.t }?.s ?? start]
                let mw = recent.map(\.width).max() ?? 0, mh = recent.map(\.height).max() ?? 0
                if l.shape.height > mh + 8 || l.shape.width > mw + 8 {
                    bad.append(String(format: "black %.0fx%.0f at %.0fms, layout shape %.0fx%.0f", l.shape.width, l.shape.height, f.t, mw, mh)); break
                }
            }
            let cMax = max(1, looks.map(\.content).max() ?? 1)
            if let i = looks.indices.first(where: { looks[$0].content * 50 <= cMax && looks[$0].badge > 40 && looks[$0].shape.height > 120 }) {
                bad.append(String(format: "badge shown with the content hidden at %.0fms", frames[i].t))
            }
            writeStrip(frames, to: dir.appendingPathComponent("\(name).png"))
            if env["PAINT_FRAMES"] != nil {
                for (i, f) in frames.enumerated() where looks[i].leak > 2 {
                    if let d = CGImageDestinationCreateWithURL(dir.appendingPathComponent(String(format: "%@-%03.0f.png", name, f.t)) as CFURL, "public.png" as CFString, 1, nil) { CGImageDestinationAddImage(d, f.img, nil); CGImageDestinationFinalize(d) }
                }
            }
            let sizes = stride(from: 0, to: looks.count, by: max(1, looks.count / 8)).map { String(format: "%.0f:%.0fx%.0f", frames[$0].t, looks[$0].shape.width, looks[$0].shape.height) }
            let gaps = zip(frames.dropFirst(), frames).map { $0.t - $1.t }, gap = gaps.max() ?? 0
            let gapAt = frames[(gaps.firstIndex(of: gap) ?? 0) + (gaps.isEmpty ? 0 : 1)].t
            print(String(format: "paint %@ longest main-thread gap %.0fms at %.0fms (first capture %.0fms)", name, gap, gapAt, frames.first?.t ?? 0))
            print("paint \(name) frames=\(frames.count) black " + sizes.joined(separator: " ") + " " + (bad.isEmpty ? "ok" : bad.joined(separator: "; ")))
            if !bad.isEmpty { fails.append(name) }
            try? await Task.sleep(for: .milliseconds(600))
        }
        window.contentView = nil; window.orderOut(nil)
        print("paint strips in \(dir.path)")
        print(fails.isEmpty ? "OK: paint (nothing drawn outside the notch shape, no black box past the layout, badge fades with the content)" : "FAIL: paint in " + fails.joined(separator: ", "))
        if !fails.isEmpty { exit(1) }
    }
}
