import SwiftUI
import Defaults

// Renders the Orchestrator tab inside a replica of ContentView's open-notch layout (header row +
// tab body, same paddings, fixed notch height, window clip) with fixture data, to PNGs.
// Run: boringNotch/Orchestrator/Snapshots/run.sh  (writes /tmp/notch-snapshots/*.png)
//
// Captured from an offscreen NSHostingView (cacheDisplay), not ImageRenderer: ImageRenderer draws every
// AppKit-backed view (WindowAnchor, ScrollView, TextField) as a yellow "unsupported" placeholder, which
// covers the whole tab body, and runs no onAppear/.task (prompt card and expanded view fade in from those).
// `--image-renderer` renders with ImageRenderer instead, for comparison.

/// Mirrors ContentView.NotchLayout + mainLayout for the open notch (header, tab body, paddings, height).
struct NotchReplica: View {
    @ObservedObject var vm: BoringViewModel

    var body: some View {
        core
            .frame(width: max(openNotchSize.width, vm.notchSize.width), height: vm.notchSize.height + shadowPadding, alignment: .top)
            .background(Color(white: 0.35))
            .clipped()
            .environmentObject(vm)
    }

    /// The notch itself: ContentView's mainLayout (header + tab body, paddings, shape, fixed height).
    var core: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                header.frame(height: max(24, vm.effectiveClosedNotchHeight))
            }
            .zIndex(2)
            VStack { OrchestratorView() }.zIndex(1)
        }
        .frame(alignment: .top)
        .padding(.horizontal, cornerRadiusInsets.opened.top)
        .padding([.horizontal, .bottom], 12)
        .background(.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .frame(height: vm.notchSize.height)
    }

    /// BoringHeader with the tab icons drawn as placeholders.
    private var header: some View {
        HStack(spacing: 0) {
            HStack {
                HStack(spacing: 10) {
                    ForEach(["house.fill", "tray.fill", "sparkles"], id: \.self) {
                        Image(systemName: $0).foregroundStyle(.gray)
                    }
                }
                OrchestratorHeaderSegment()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.black).frame(width: vm.closedNotchSize.width)
            HStack(spacing: 4) { OrchestratorHeaderTrailing() }
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(.gray)
    }
}

private func fixture(_ name: String) -> String {
    let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/fixtures")
    return (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
}

private func blocks(_ json: String) -> [ChatBlock] { decodeChatBlocks(Data(json.utf8))?.blocks ?? [] }

private let longProse = (1...14).map { i -> String in
    let prose = "Step \(i): the transcript keeps growing while Claude explains what it changed and why, long enough to wrap across several lines in the notch so the chat area has to clip or scroll rather than push the header and the composer out of the notch."
    let tool = #"{"id":"t\#(i)","kind":"tool","name":"Edit","target":"/Users/x/proj/OrchestratorChat.swift","added":\#(i),"removed":1}"#
    return #"{"id":"p\#(i)","kind":"prose","text":"\#(prose)"},\#(tool)"#
}.joined(separator: ",")
private let longBlocks = blocks(#"{"running":true,"blocks":["# + longProse + #",{"id":"u-last","kind":"user","text":"Newest user message — must be fully visible above the composer"}]}"#)

private let longQuestion = """
⏺ Asking one question
────────────────────────────────────────────────────────────
How should the expanded view behave when the conversation is much longer than the notch can show, and the
user is in the middle of reading an older reply?

❯ 1. Keep the newest row pinned
     Scroll to the bottom on every new block, even while reading.
  2. Pin only when already at the bottom
     Leave the position alone if the user scrolled up.
  3. Show a "new messages" pill
     Stay put and offer a jump-to-latest control.
  4. Collapse older rows
     Fold everything but the last turn into a summary row.
  5. Grow the notch instead
     Use more of the screen height before scrolling.
  6. Let the terminal handle it
     Open the terminal level for long conversations.
  7. Type something.
────────────────────────────────────────────────────────────
  8. Chat about this

Enter to select · Tab/Arrow keys to navigate · Esc to cancel
"""

/// Every marker state: user ❯, wrapping prose ⏺, tool done (green), error (red), running (grey).
private let markerBlocks = blocks(#"""
{"running":true,"blocks":[
 {"id":"m1","kind":"user","text":"Why is the notch filling from the middle?"},
 {"id":"m2","kind":"tool","name":"Read","target":"/Users/x/proj/ContentView.swift","result":"import SwiftUI (+690 lines)"},
 {"id":"m3","kind":"tool","name":"Bash","target":"xcodebuild -scheme boringNotch build","result":"error: exit 65"},
 {"id":"m4","kind":"prose","text":"The root frame caps its height at the animating notch height, so NSHostingView resizes the window with its bottom edge fixed and the top edge slides down — wrapped lines should hang after the marker."},
 {"id":"m5","kind":"tool","name":"Edit","target":"/Users/x/proj/OrchestratorExpand.swift","result":"updated","added":11,"removed":1},
 {"id":"m6","kind":"tool","name":"Bash","target":"run.sh --transition","result":null}
]}
"""#)

/// Long user message, a Read, an Edit with two hunks (context, removed, added), then prose.
private let editBlocks = blocks(#"""
{"running":true,"blocks":[
 {"id":"e1","kind":"user","text":"Can you make the expanded view show my messages as bubbles and fold the Edit diffs out, the way the design frame shows them? Keep the open notch as it is."},
 {"id":"e2","kind":"tool","name":"Read","target":"/Users/x/proj/OrchestratorChat.swift","result":"import SwiftUI (+520 lines)"},
 {"id":"e3","kind":"tool","name":"Edit","target":"/Users/x/proj/OrchestratorChat.swift","result":"updated","added":3,"removed":2,"diff":[
   {"oldStart":58,"newStart":58,"lines":[" let a = 1","-let b = old","+let b = new","+let c = 3"," let d = 4"]},
   {"oldStart":120,"newStart":121,"lines":["-    return x","+    return y"]}]},
 {"id":"e4","kind":"prose","text":"Done: user messages now render as right-aligned bubbles in the expanded column, and Edit rows fold out into a diff card."}
]}
"""#)

private let shortNote = "Remember to ask about the Railway migration.\n\n- notch: back-nav for question chips\n- notes drop-down autosaves after 1s\n- check usage ring colour at 90%"
private let wordyDraft = "Please look at how the composer grows while I type a long message that wraps over several lines in the notch, and make sure the send button stays on the last line even when the text keeps going well past two full lines of the pill"
private let tenLineDraft = (1...10).map { "Line \($0) of a very long draft that keeps going and going" }.joined(separator: "\n")
private let longNote = (1...30).map { "Note line \($0): a longer scratch line that wraps when the panel is narrow enough to need it." }.joined(separator: "\n")

struct Scene {
    let name: String
    var loaded = true
    var chat: ChatResponse?
    var blocks: [ChatBlock] = []
    var runsBoard = false
    var expanded = false
    var railCollapsed = false
    var pressed: Int?
    var note: String?
    var pending: [Int: Bool] = [:]
    var sends: [PendingMessage] = []
    var notes: (String, NotesStatus)?
    var attachments: [Data] = []
    var dismissed = false
    var draft = ""
}

/// Two-colour test PNG through the real orchestratorPNG path.
private func testPNG(_ a: NSColor, _ b: NSColor) -> Data {
    let img = NSImage(size: NSSize(width: 400, height: 300), flipped: false) { r in
        a.setFill(); r.fill()
        b.setFill(); NSRect(x: 150, y: 80, width: 200, height: 140).fill()
        return true
    }
    return orchestratorPNG(from: img)!
}
private let pngA = testPNG(.systemTeal, .systemOrange), pngB = testPNG(.systemPurple, .systemYellow)

@MainActor
@main
struct Snap {
    static func main() async {
        if CommandLine.arguments.contains("--transition") { await transition(); return }
        if CommandLine.arguments.contains("--hittest") { await hitTest(); return }
        if CommandLine.arguments.contains("--closed") { await closed(); return }
        let useImageRenderer = CommandLine.arguments.contains("--image-renderer")
        let out = URL(fileURLWithPath: "/tmp/notch-snapshots")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let state = (try? JSONDecoder().decode(StateResponse.self, from: Data(fixture("phase7-state.txt").utf8)))
            ?? StateResponse(runs: [], usage: nil)
        func chat(_ screen: String, running: Bool = true) -> ChatResponse { ChatResponse(running: running, screen: screen) }
        let working = fixture("working.txt")
        let shortBlocks = blocks(fixture("phase5-blocks.json"))

        let scenes: [Scene] = [
            Scene(name: "01-chat-short", chat: chat(working), blocks: shortBlocks),
            Scene(name: "02-chat-long", chat: chat(""), blocks: longBlocks),
            Scene(name: "03-chat-fallback-tail", chat: chat(working)),
            Scene(name: "04-permission", chat: chat(fixture("phase6-edit.txt"))),
            Scene(name: "05-question-long", chat: chat(longQuestion)),
            Scene(name: "06-runs-board", chat: chat(""), runsBoard: true),
            Scene(name: "07-stopped", chat: chat("", running: false)),
            Scene(name: "08-offline", chat: nil),
            Scene(name: "09-connecting", loaded: false),
            Scene(name: "10-expanded-chat-long", chat: chat(""), blocks: longBlocks, expanded: true),
            Scene(name: "11-expanded-rail-collapsed", chat: chat(""), blocks: longBlocks, expanded: true, railCollapsed: true),
            Scene(name: "12-expanded-question-long", chat: chat(longQuestion), expanded: true),
            Scene(name: "13-expanded-permission", chat: chat(fixture("phase6-edit.txt")), expanded: true),
            Scene(name: "14-chat-idle-suggestion", chat: chat(fixture("idle-suggestion.txt")), blocks: shortBlocks),
            Scene(name: "15-chat-markers", chat: chat(""), blocks: markerBlocks),
            Scene(name: "16-expanded-markers", chat: chat(""), blocks: markerBlocks, expanded: true),
            Scene(name: "23-expanded-bubbles-edit", chat: chat(""), blocks: editBlocks, expanded: true),
            Scene(name: "24-chat-edit-compact", chat: chat(""), blocks: editBlocks),
            Scene(name: "25-chat-pending", chat: chat(""), blocks: markerBlocks, sends: [
                PendingMessage(id: 1, text: "Thanks — now fix the build error", state: .sent, sentAt: Date()),
                PendingMessage(id: 2, text: "and then run the tests", state: .queued, sentAt: nil)]),
            Scene(name: "26-chat-not-sent", chat: chat(""), blocks: markerBlocks, sends: [
                PendingMessage(id: 1, text: "Please also go through every remaining file in the Orchestrator folder and tidy the comments so they match the new naming, then summarise", state: .failed, sentAt: nil)]),
            Scene(name: "27-expanded-pending", chat: chat(""), blocks: editBlocks, expanded: true, sends: [
                PendingMessage(id: 1, text: "ok", state: .sending, sentAt: nil),
                PendingMessage(id: 2, text: "Please also go through every remaining file in the Orchestrator folder and tidy the comments so they match the new naming, then summarise", state: .failed, sentAt: nil)]),
            Scene(name: "31-composer-chips", chat: chat(""), blocks: markerBlocks, attachments: [pngA, pngB]),
            Scene(name: "32-chat-pending-images", chat: chat(""), blocks: markerBlocks, sends: [
                PendingMessage(id: 1, text: "what do you make of these", state: .queued, sentAt: nil, images: [pngA, pngB]),
                PendingMessage(id: 2, text: "", state: .failed, sentAt: nil, images: [pngB])]),
            Scene(name: "33-expanded-pending-images", chat: chat(""), blocks: editBlocks, expanded: true, sends: [
                PendingMessage(id: 1, text: "see this screenshot", state: .sending, sentAt: nil, images: [pngA]),
                PendingMessage(id: 2, text: "and compare with these two", state: .failed, sentAt: nil, images: [pngA, pngB])]),
            Scene(name: "28-notes-open", chat: chat(""), blocks: markerBlocks, notes: (shortNote, .saved)),
            Scene(name: "29-notes-couldnt-save", chat: chat(""), blocks: markerBlocks, notes: (shortNote, .failed)),
            Scene(name: "30-notes-expanded", chat: chat(""), blocks: markerBlocks, expanded: true, notes: (longNote, .idle)),
            Scene(name: "17-question-multiselect", chat: chat(fixture("multiselect-1.txt")), expanded: true),
            Scene(name: "18-question-multiselect-toggled", chat: chat(fixture("multiselect-1.txt")), expanded: true, pending: [1: true, 2: true]),
            Scene(name: "19-question-multiq-tabs", chat: chat(fixture("multiq-tab2.txt")), expanded: true),
            Scene(name: "20-question-review-submit", chat: chat(fixture("review-submit.txt")), expanded: true),
            Scene(name: "21-permission-pressed", chat: chat(fixture("phase6-edit.txt")), pressed: 1),
            Scene(name: "22-permission-retry-note", chat: chat(fixture("phase6-edit.txt")), note: "Didn't go through"),
            Scene(name: "34-expanded-question-transcript", chat: chat(longQuestion), blocks: longBlocks, expanded: true),
            Scene(name: "35-expanded-question-dismissed", chat: chat(longQuestion), blocks: longBlocks, expanded: true, dismissed: true),
            Scene(name: "37-composer-multiline", chat: chat(""), blocks: markerBlocks, draft: wordyDraft),
            Scene(name: "38-composer-five-lines", chat: chat(""), blocks: markerBlocks, draft: tenLineDraft),
            Scene(name: "39-expanded-composer-multiline", chat: chat(""), blocks: editBlocks, expanded: true, draft: wordyDraft),
            Scene(name: "36-permission-dismissed-open", chat: chat(fixture("phase6-edit.txt")), blocks: markerBlocks, dismissed: true),
        ]

        let savedRail = Defaults[.orchRunsRailCollapsed]
        defer { Defaults[.orchRunsRailCollapsed] = savedRail }
        for s in scenes {
            let vm = BoringViewModel()
            let m = OrchestratorManager.shared
            await m.snapshotApply(loaded: s.loaded, chat: s.chat, state: state, runsBoard: s.runsBoard)
            OrchestratorTranscriptStore.shared.snapshotSet(blocks: s.blocks, pending: s.sends, attachments: s.attachments, draft: s.draft)
            Defaults[.orchRunsRailCollapsed] = s.railCollapsed
            PromptCardController.shared.snapshotSet(pressed: s.pressed, note: s.note, pending: s.pending, dismissCurrent: s.dismissed)
            if let n = s.notes { OrchestratorNotesStore.shared.snapshotSet(text: n.0, status: n.1); m.notesOpen = true }

            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 640, height: 480),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            if s.expanded { OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: window) }
            let root = NotchReplica(vm: vm)
            let size = CGSize(width: max(openNotchSize.width, vm.notchSize.width), height: vm.notchSize.height + shadowPadding)
            let url = out.appendingPathComponent(s.name + ".png")
            var png: Data?
            if useImageRenderer {
                let r = ImageRenderer(content: root.frame(width: size.width, height: size.height))
                r.scale = 2
                png = r.nsImage.flatMap { NSBitmapImageRep(data: $0.tiffRepresentation ?? Data())?.representation(using: .png, properties: [:]) }
            } else {
                let host = NSHostingView(rootView: root)
                host.frame = NSRect(origin: .zero, size: size)
                window.setContentSize(size)
                window.contentView = host
                // Let onAppear/.task fade-ins and the scroll anchor settle.
                try? await Task.sleep(for: .milliseconds(700))
                host.layoutSubtreeIfNeeded()
                // Content-driven fits (composer, notes, prompt context) land after the first layout: re-size to the settled notch.
                let settled = CGSize(width: max(openNotchSize.width, vm.notchSize.width), height: vm.notchSize.height + shadowPadding)
                if settled != size {
                    host.frame = NSRect(origin: .zero, size: settled)
                    window.setContentSize(settled)
                    try? await Task.sleep(for: .milliseconds(300))
                    host.layoutSubtreeIfNeeded()
                }
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    print("\(s.name): notch h=\(Int(vm.notchSize.height))")
                    png = rep.representation(using: .png, properties: [:])
                    if s.expanded {
                        // Runs rail header: leftmost column / topmost row of lit pixels in the right 190pt below the header row.
                        let k = CGFloat(rep.pixelsWide) / host.bounds.width
                        var minX = Int.max, minY = Int.max
                        for y in Int(44 * k)..<rep.pixelsHigh { for x in Int((host.bounds.width - 190) * k)..<rep.pixelsWide
                            where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.3 { minX = min(minX, x); minY = min(minY, y) } }
                        print("rail \(s.name): x=\(Int(CGFloat(minX) / k)) y=\(Int(CGFloat(minY) / k))")
                    }
                }
                window.contentView = nil
            }
            OrchestratorExpand.shared.reset()
            m.notesOpen = false
            PromptCardController.shared.snapshotSet()
            if let png { try? png.write(to: url); print("wrote", url.path) } else { print("FAILED", s.name) }
        }
    }

    /// Height changes in a fixed window, like the app: the window is resized at once (top pinned) and
    /// vm.notchSize springs. Steps sample a 0.4/0.82 spring incl. overshoot. Prints the notch's top y
    /// (first black row at the centre column) and the window top for each step, old vs new root frame.
    static func transition() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let out = URL(fileURLWithPath: "/tmp/notch-snapshots")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        await OrchestratorManager.shared.snapshotApply(loaded: true, chat: ChatResponse(running: true, screen: ""), state: StateResponse(runs: [], usage: nil))
        OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks)
        let full = expandedSize(screen: CGSize(width: 1440, height: 900)).height
        let grow: [CGFloat] = [190, 250, 360, 470, 556, 528, full]
        let shrink: [CGFloat] = [full, 420, 300, 215, 183, 188, 190]
        let stock: [CGFloat] = [34, 90, 150, 185, 196, 190] // music open: closed -> open in the stock window
        let runs: [(String, [CGFloat], CGFloat)] = [
            ("grow", grow, full + shadowPadding), ("collapse", shrink, full + shadowPadding), ("stock-open", stock, windowSize.height),
        ]
        var moved = false
        for pinned in [false, true] {
            for (name, steps, winH) in runs {
                var tops: [String] = []
                for (i, h) in steps.enumerated() {
                    let vm = BoringViewModel()
                    vm.notchSize = CGSize(width: openNotchSize.width, height: h)
                    let core = NotchReplica(vm: vm).core.environmentObject(vm)
                    let root = Group {
                        if pinned { core.notchRootFrame(notchSize: CGSize(width: openNotchSize.width, height: h)) }
                        else { core.frame(maxWidth: windowSize.width, maxHeight: windowSize.height + max(0, h - openNotchSize.height), alignment: .top) }
                    }
                    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: openNotchSize.width, height: winH),
                                          styleMask: .borderless, backing: .buffered, defer: false)
                    window.backgroundColor = NSColor(white: 0.35, alpha: 1)
                    let topBefore = window.frame.maxY
                    let host = NSHostingView(rootView: root)
                    window.contentView = host
                    try? await Task.sleep(for: .milliseconds(80))
                    host.layoutSubtreeIfNeeded()
                    guard let rep = window.contentView?.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                    host.cacheDisplay(in: host.bounds, to: rep)
                    let x = rep.pixelsWide / 2
                    let top = (0..<rep.pixelsHigh).first { y in (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 1) < 0.05 }
                        .map { CGFloat($0) * host.bounds.height / CGFloat(rep.pixelsHigh) } ?? -1
                    let winMoved = abs(window.frame.maxY - topBefore) > 0.5
                    if top != 0 || winMoved { moved = moved || pinned }
                    tops.append("h=\(Int(h)):top=\(Int(top))\(winMoved ? "(window top moved)" : "")")
                    if [1, 3].contains(i) || name == "stock-open" && i == 2 {
                        try? rep.representation(using: .png, properties: [:])?
                            .write(to: out.appendingPathComponent("transition-\(pinned ? "new" : "old")-\(name)-\(i).png"))
                    }
                    window.contentView = nil
                }
                print("\(pinned ? "new" : "old") \(name): " + tops.joined(separator: "  "))
            }
        }
        print(moved ? "FAIL: top edge moved with the new root frame" : "OK: top edge pinned at y=0 in every step (new root frame)")
        await livePass(out)
    }

    private struct LiveRoot: View {
        @ObservedObject var vm: BoringViewModel
        var body: some View { NotchReplica(vm: vm).core.environmentObject(vm).notchRootFrame(notchSize: vm.notchSize) }
    }

    /// One hosted window, real setLevel animation: the transcript must be on screen in every frame of
    /// expand and collapse (it used to be hidden for ~120ms and faded back in).
    static func livePass(_ out: URL) async {
        let vm = BoringViewModel()
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: windowSize.width, height: windowSize.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = NSColor(white: 0.35, alpha: 1)
        let host = NSHostingView(rootView: LiveRoot(vm: vm))
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(700))
        func measure() -> (Int, NSBitmapImageRep?) {
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return (0, nil) }
            host.cacheDisplay(in: host.bounds, to: rep)
            let k = CGFloat(rep.pixelsWide) / host.bounds.width
            let x0 = Int(40 * k), x1 = min(rep.pixelsWide, Int(440 * k))
            let y0 = Int(44 * k), y1 = min(rep.pixelsHigh, Int((vm.notchSize.height - 12) * k))
            var n = 0
            if y1 > y0 { for y in y0..<y1 { for x in x0..<x1 where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.6 { n += 1 } } }
            // Newest row: the band just above the composer must hold lit pixels (bubble or compact row).
            var b = 0
            let by0 = Int(max(0, vm.notchSize.height - 100) * k), by1 = min(rep.pixelsHigh, Int((vm.notchSize.height - 45) * k))
            if by1 > by0 { for y in by0..<by1 { for x in Int(40 * k)..<min(rep.pixelsWide, Int(620 * k)) where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.3 { b += 1 } } }
            newest = b
            return (n, rep)
        }
        var newest = 0
        let baseline = measure().0
        let newestBase = newest
        print("live baseline open text=\(baseline) newest=\(newestBase)")
        var bad: [String] = []
        for (phase, level) in [("grow", ExpandLevel.expanded), ("collapse", .open)] {
            OrchestratorExpand.shared.setLevel(level, vm: vm, window: window)
            var prev = 0
            for t in [0, 30, 60, 120, 250, 400, 700, 1200] {
                try? await Task.sleep(for: .milliseconds(t - prev)); prev = t
                let (n, rep) = measure()
                print("live \(phase) t=\(t)ms text=\(n) newest=\(newest) h=\(Int(vm.notchSize.height)) lvl=\(OrchestratorExpand.shared.level(for: vm))")
                if n * 2 < baseline || (phase == "collapse" && newest * 4 < newestBase) { bad.append("\(phase) \(t)ms") }
                if [0, 30, 60, 120, 250, 700, 1200].contains(t) { try? rep?.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("transition-live-\(phase)-\(t).png")) }
                if t == 60 { try? rep?.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("transition-live-\(phase)-60.png")) }
            }
        }
        OrchestratorExpand.shared.reset()
        window.contentView = nil
        window.orderOut(nil)
        print(bad.isEmpty ? "OK: content present in every live frame" : "FAIL: content missing at " + bad.joined(separator: ", "))
    }

    /// Clicks into the real tab inside a copy of ContentView's root chain (mainLayout tap/hover, ZStack,
    /// bottom padding, notchRootFrame, compositingGroup, scaleEffect) in the app's panel class, open and
    /// expanded. Only actions that never POST: composer (starts typing, focuses the field), Chat|Runs
    /// segment, status capsule. Also reports what a click below the visible notch hits.
    static func hitTest() async {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory) // like the notch app (LSUIElement); windows stay offscreen
        let m = OrchestratorManager.shared
        await m.snapshotApply(loaded: true, chat: ChatResponse(running: true, screen: ""), state: StateResponse(runs: [], usage: nil))
        OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks)
        var ok = true
        for expanded in [false, true] {
            let vm = BoringViewModel()
            let mainLayout = NotchReplica(vm: vm).core.environmentObject(vm)
                .contentShape(Rectangle()).onHover { _ in }.onTapGesture { }
            let root = ZStack(alignment: .top) { VStack(spacing: 0) { mainLayout } }
                .padding(.bottom, 8)
                .notchRootFrame(notchSize: vm.notchSize)
                .compositingGroup()
                .scaleEffect(x: 1, y: 1, anchor: .top)
            let window = KeyablePanel(contentRect: NSRect(x: -20000, y: -20000, width: windowSize.width, height: windowSize.height),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            let host = NSHostingView(rootView: root)
            window.contentView = host
            window.orderFrontRegardless() // offscreen; events only reach ordered-in windows
            if expanded { OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: window) }
            try? await Task.sleep(for: .milliseconds(500))
            host.layoutSubtreeIfNeeded()
            let H = host.bounds.height
            func click(_ fromTop: CGFloat, x: CGFloat) async {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    if let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: H - fromTop), modifierFlags: [],
                                                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { window.sendEvent(e) }
                    try? await Task.sleep(for: .milliseconds(30))
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
            let label = expanded ? "expanded" : "open"
            var line: [String] = []

            // The regression: an AppKit platform view (the TextField) under the composer took the click.
            let hitName = window.contentView?.superview?.hitTest(NSPoint(x: expanded ? 200 : 320, y: H - (vm.notchSize.height - 27)))
                .map { String(describing: type(of: $0)) } ?? "nil"
            let reachesSwiftUI = hitName.hasPrefix("NSHostingView")
            ok = ok && reachesSwiftUI
            line.append("composer hit reaches SwiftUI: \(reachesSwiftUI)")
            // Composer: notch bottom padding 12, pill 30 -> centre 27 above the notch bottom. Clicked at the open
            // level only: while expanded, OrchestratorExpand's outside-click monitor reads the real cursor
            // (NSEvent.mouseLocation), which a synthetic click doesn't move, and collapses the notch.
            var typed: [Bool] = []
            let sub = m.$wantsKeyboard.sink { typed.append($0) }
            if !expanded {
                await click(vm.notchSize.height - 27, x: 320)
                let focused = window.firstResponder is NSTextView
                line.append("composer click starts typing: \(typed.contains(true)), field focused: \(focused)")
                ok = ok && typed.contains(true) && focused
                // The draft lives in the store: it must outlive a level change and a fresh view tree.
                (window.firstResponder as? NSTextView)?.insertText("keep this draft", replacementRange: NSRange(location: NSNotFound, length: 0))
                try? await Task.sleep(for: .milliseconds(100))
                let typedIn = OrchestratorTranscriptStore.shared.draft == "keep this draft"
                OrchestratorExpand.shared.releaseKey(window)
                m.endTyping()
                window.makeFirstResponder(nil)
                OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: window)
                try? await Task.sleep(for: .milliseconds(500))
                OrchestratorExpand.shared.setLevel(.open, vm: vm, window: window)
                OrchestratorExpand.shared.reset()
                window.contentView = NSHostingView(rootView: root)
                try? await Task.sleep(for: .milliseconds(500))
                let survives = typedIn && OrchestratorTranscriptStore.shared.draft == "keep this draft"
                line.append("draft survives level change and remount: \(survives)")
                ok = ok && survives
                OrchestratorTranscriptStore.shared.draft = ""
            }
            sub.cancel()
            OrchestratorExpand.shared.releaseKey(window)
            m.endTyping()
            window.makeFirstResponder(nil)
            try? await Task.sleep(for: .milliseconds(200))

            if !expanded {
                m.showRunsBoard = false
                await click(17, x: 190) // Runs half of the Chat|Runs segment
                line.append("segment: \(m.showRunsBoard)")
                ok = ok && m.showRunsBoard
                m.showRunsBoard = false
                m.statusMenuOpen = false
                await click(17, x: 560) // status capsule
                line.append("capsule opens menu: \(m.statusMenuOpen)")
                ok = ok && m.statusMenuOpen
                m.statusMenuOpen = false
                m.notesOpen = false
                await click(17, x: 590) // notes button, right of the capsule
                line.append("notes button opens panel: \(m.notesOpen)")
                ok = ok && m.notesOpen
                m.notesOpen = false
            }
            // Below the visible notch (only exists while the window is taller than the notch).
            if H > vm.notchSize.height + 30 {
                let below = window.contentView?.superview?.hitTest(NSPoint(x: 320, y: 10)).map { String(String(describing: type(of: $0)).prefix(20)) } ?? "nil"
                line.append("below notch hits: \(below)")
            }
            print("\(label) (\(Int(H))pt window): " + line.joined(separator: "; "))
            OrchestratorExpand.shared.reset()
            window.contentView = nil
            window.orderOut(nil)
        }
        print(ok ? "OK: composer, segment, capsule and notes button respond to clicks" : "FAIL: a click target did not respond")
    }
}

/// The app panel's key rule (BoringNotchSkyLightWindow.canBecomeKey).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { OrchestratorManager.shared.keyboardWindow === self || OrchestratorKeyGate.terminalWantsKey }
}
