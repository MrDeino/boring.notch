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
        .frame(width: openNotchSize.width, height: vm.notchSize.height + shadowPadding, alignment: .top)
        .background(Color(white: 0.35))
        .clipped()
        .environmentObject(vm)
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

struct Scene {
    let name: String
    var loaded = true
    var chat: ChatResponse?
    var blocks: [ChatBlock] = []
    var runsBoard = false
    var expanded = false
    var railCollapsed = false
}

@MainActor
@main
struct Snap {
    static func main() async {
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
        ]

        let savedRail = Defaults[.orchRunsRailCollapsed]
        defer { Defaults[.orchRunsRailCollapsed] = savedRail }
        for s in scenes {
            let vm = BoringViewModel()
            let m = OrchestratorManager.shared
            await m.snapshotApply(loaded: s.loaded, chat: s.chat, state: state, runsBoard: s.runsBoard)
            OrchestratorTranscriptStore.shared.snapshotSet(blocks: s.blocks)
            Defaults[.orchRunsRailCollapsed] = s.railCollapsed

            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 640, height: 480),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            if s.expanded { OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: window) }
            let root = NotchReplica(vm: vm)
            let size = CGSize(width: openNotchSize.width, height: vm.notchSize.height + shadowPadding)
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
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    png = rep.representation(using: .png, properties: [:])
                }
                window.contentView = nil
            }
            OrchestratorExpand.shared.reset()
            if let png { try? png.write(to: url); print("wrote", url.path) } else { print("FAILED", s.name) }
        }
    }
}
