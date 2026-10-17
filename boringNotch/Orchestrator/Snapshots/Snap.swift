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
    var header: some View {
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

/// A synthetic `deploys` entry started `ago` seconds ago (finished `done` seconds ago).
func snapDeploy(_ state: String, ago: TimeInterval, done: TimeInterval? = nil, sha: String = "abc1234") -> String {
    let iso = ISO8601DateFormatter()
    let end = done.map { "\"\(iso.string(from: Date().addingTimeInterval(-$0)))\"" } ?? "null"
    return #"{"project":"gg-app","state":"\#(state)","sha":"\#(sha)","pr":{"number":231,"title":"Tidy the widgets"},"startedAt":"\#(iso.string(from: Date().addingTimeInterval(-ago)))","finishedAt":\#(end),"url":"https://example.test/gg-app"}"#
}

func fixture(_ name: String) -> String {
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
let longBlocks = blocks(#"{"running":true,"blocks":["# + longProse + #",{"id":"u-last","kind":"user","text":"Newest user message — must be fully visible above the composer"}]}"#)

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

/// Described tool rows: ok, error, Edit with +/-, pending, then null / missing description (today's layout).
private let toolDescBlocks = blocks(#"""
{"running":true,"blocks":[
 {"id":"d1","kind":"user","text":"Check the result file and rebuild."},
 {"id":"d2","kind":"tool","name":"Read","target":"/Users/x/proj/11-fix-result.md","description":"Read 11-fix result, restart notch, start next step","result":"import SwiftUI (+120 lines)"},
 {"id":"d3","kind":"tool","name":"Bash","target":"xcodebuild -scheme boringNotch build","description":"Build the notch app","result":"error: exit 65"},
 {"id":"d4","kind":"tool","name":"Edit","target":"/Users/x/proj/OrchestratorChat.swift","description":"Add described tool row","result":"updated","added":3,"removed":1},
 {"id":"d5","kind":"tool","name":"Bash","target":"run.sh --transition","description":"Run the transition harness","result":null},
 {"id":"d6","kind":"tool","name":"Grep","target":"toolRow","description":null,"result":"4 matches"},
 {"id":"d7","kind":"tool","name":"Glob","target":"**/*.swift","result":"31 files"},
 {"id":"d8","kind":"prose","text":"Build failed with exit 65; looking at the errors now."}
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

/// Ends on a user message followed by several paragraphs of prose: the context above a question card.
/// What the store holds while a question is pending: Claude Code writes the turn's text only after the answer.
private let heldBlocks = blocks(#"""
{"running":true,"blocks":[
 {"id":"l0","kind":"prose","text":"The animation run (29b9) finished; the Release build is in /tmp/notch-rel."},
 {"id":"l1","kind":"user","text":"the animations are smoother, but still not 100% smooth, expand moves in two steps"}
]}
"""#)
private let questionBlocks = blocks(#"""
{"running":true,"blocks":[
 {"id":"q1","kind":"user","text":"How should the expanded view behave on long chats?"},
 {"id":"q2","kind":"prose","text":"I looked at the transcript and the scroll anchor. The newest row is pinned today, which is right for a live conversation but hides older replies while you read them."},
 {"id":"q3","kind":"tool","name":"Read","target":"/Users/x/proj/OrchestratorChat.swift","result":"import SwiftUI (+520 lines)"},
 {"id":"q4","kind":"prose","text":"There are three reasonable behaviours here and they trade off differently, so I would rather ask than pick one for you."},
 {"id":"q5","kind":"prose","text":"Pinning always keeps the last line visible but fights the user. Pinning only at the bottom respects scrolling but can miss a reply. A jump-to-latest pill needs a small new control in the column."}
]}
"""#)

/// Quick e1d: last recorded frame of a reply being written (spinner below it, text above the input box).
private let liveChat = ChatResponse(running: true, screen: fixture("live-one.txt").components(separatedBy: "<<<FRAME>>>\n").last ?? "", live: true)

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
    /// serve `deploys` entries (JSON objects) for the state.
    var deploys: [String] = []
    var pressed: Int?
    var note: String?
    var pending: [Int: Bool] = [:]
    var sends: [PendingMessage] = []
    var notes: (String, NotesStatus)?
    var attachments: [Data] = []
    var dismissed = false
    var draft = ""
    var diffOpen = false
    var calm = false // no runs: capsule shows Running (+ ctx)
    var logRun: String? // run log overlay over the content
    var logLines = true // false: empty log
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
        if CommandLine.arguments.contains("--hittest") {
            // A text view's mouseDown tracking loop stops the main run loop when it ends, which would end an async
            // main (exit 0). Drive the loop here instead; a stopped spin just returns early.
            var finished = false
            Task { await hitTest(); finished = true }
            while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            return
        }
        if CommandLine.arguments.contains("--qlevel") {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            exit(await questionLevelPass() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--cardfit") {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            exit(await cardFitPass() ? 0 : 1)
        }
        if CommandLine.arguments.contains("--closed") { await closed(); return }
        if CommandLine.arguments.contains("--askmock") { await askMock(); return }
        if CommandLine.arguments.contains("--sendmock") { await sendMock(); return }
        if CommandLine.arguments.contains("--idle") { await idle(); return }
        if CommandLine.arguments.contains("--frames") { await frames(); return }
        if CommandLine.arguments.contains("--paint") { await paint(); return }
        if CommandLine.arguments.contains("--fulltext") { await fullText(); return }
        let useImageRenderer = CommandLine.arguments.contains("--image-renderer")
        let out = URL(fileURLWithPath: "/tmp/notch-snapshots")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        let state = (try? JSONDecoder().decode(StateResponse.self, from: Data(fixture("phase7-state.txt").utf8)))
            ?? StateResponse(runs: [], usage: nil)
        func chat(_ screen: String, running: Bool = true) -> ChatResponse { ChatResponse(running: running, screen: screen) }
        func ctxChat(_ pct: Int) -> ChatResponse {
            try! JSONDecoder().decode(ChatResponse.self, from: Data(#"{"running":true,"screen":"","live":true,"context":{"percent":\#(pct)}}"#.utf8))
        }
        func askChat(_ f: String) -> ChatResponse {
            let o: [String: Any] = ["running": true, "screen": fixture(f), "approval": ["id": "q1", "tool": "AskUserQuestion", "command": "{\"questions\":[…"]]
            return try! JSONDecoder().decode(ChatResponse.self, from: JSONSerialization.data(withJSONObject: o))
        }
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
            Scene(name: "46-tools-described-open", chat: chat(""), blocks: toolDescBlocks),
            Scene(name: "47-expanded-tools-described", chat: chat(""), blocks: toolDescBlocks, expanded: true),
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
            Scene(name: "40-notes-long-open", chat: chat(""), blocks: markerBlocks, notes: (longNote, .idle)),
            Scene(name: "17-question-multiselect", chat: chat(fixture("multiselect-1.txt")), expanded: true),
            Scene(name: "18-question-multiselect-toggled", chat: chat(fixture("multiselect-1.txt")), expanded: true, pending: [1: true, 2: true]),
            Scene(name: "19-question-multiq-tabs", chat: chat(fixture("multiq-tab2.txt")), expanded: true),
            Scene(name: "20-question-review-submit", chat: chat(fixture("review-submit.txt")), expanded: true),
            Scene(name: "20b-question-review-chrome", chat: chat(fixture("review-chrome.txt")), expanded: true),
            Scene(name: "21-permission-pressed", chat: chat(fixture("phase6-edit.txt")), pressed: 1),
            Scene(name: "22-permission-retry-note", chat: chat(fixture("phase6-edit.txt")), note: "Didn't go through"),
            Scene(name: "34-expanded-question-transcript", chat: chat(longQuestion), blocks: longBlocks, expanded: true),
            Scene(name: "35-expanded-question-dismissed", chat: chat(longQuestion), blocks: longBlocks, expanded: true, dismissed: true),
            Scene(name: "37-composer-multiline", chat: chat(""), blocks: markerBlocks, draft: wordyDraft),
            Scene(name: "38-composer-five-lines", chat: chat(""), blocks: markerBlocks, draft: tenLineDraft),
            Scene(name: "39-expanded-composer-multiline", chat: chat(""), blocks: editBlocks, expanded: true, draft: wordyDraft),
            Scene(name: "41-permission-context-open", chat: chat(fixture("phase6-edit.txt")), blocks: editBlocks),
            Scene(name: "42-question-context-open", chat: chat(longQuestion), blocks: questionBlocks),
            Scene(name: "36-permission-dismissed-open", chat: chat(fixture("phase6-edit.txt")), blocks: markerBlocks, dismissed: true),
            Scene(name: "43-chat-live-new", chat: chat(fixture("working-new.txt")), blocks: shortBlocks),
            Scene(name: "44-expanded-live-new", chat: chat(fixture("working-new.txt")), blocks: markerBlocks, expanded: true),
            Scene(name: "45-chat-live-flag-only", chat: ChatResponse(running: true, screen: "", live: true), blocks: markerBlocks),
            Scene(name: "48-capsule-ctx", chat: ctxChat(38), blocks: markerBlocks, calm: true),
            Scene(name: "49-capsule-ctx-high", chat: ctxChat(86), blocks: markerBlocks, calm: true),
            Scene(name: "50-caret-live", chat: ChatResponse(running: true, screen: "", live: true), blocks: editBlocks),
            Scene(name: "51-open-diff-collapsed", chat: chat(""), blocks: editBlocks),
            Scene(name: "52-open-diff-expanded", chat: chat(""), blocks: editBlocks, diffOpen: true),
            Scene(name: "53-runlog-from-board", chat: chat(""), runsBoard: true, expanded: true, logRun: "261014024541-r002"),
            Scene(name: "54-runlog-expanded", chat: chat(""), blocks: longBlocks, expanded: true, logRun: "261014024541-r002"),
            Scene(name: "55-runlog-finished", chat: chat(""), blocks: longBlocks, expanded: true, logRun: "261014024541-d004"),
            Scene(name: "56-runlog-empty", chat: chat(""), blocks: longBlocks, expanded: true, logRun: "261014024541-s003", logLines: false),
            Scene(name: "50-ask-1q", chat: askChat("question.txt"), expanded: true),
            Scene(name: "51-ask-2q-multiselect", chat: askChat("multiselect-1.txt"), expanded: true),
            Scene(name: "62-ask-3opt-open", chat: askChat("question.txt")),
            Scene(name: "63-ask-6opt-open", chat: askChat("question6.txt")),
            Scene(name: "64-ask-12opt-capped", chat: askChat("question-long.txt")),
            Scene(name: "65-permission-longcmd-open", chat: chat(fixture("permission-longcmd.txt"))),
            Scene(name: "58-ask-leadin-long-2q", chat: askChat("leadin-long-2q.txt"), blocks: heldBlocks, expanded: true),
            Scene(name: "59-ask-leadin-real-2q", chat: askChat("leadin-2q.txt"), blocks: heldBlocks, expanded: true),
            Scene(name: "60-live-reply-open", chat: liveChat, blocks: heldBlocks),
            Scene(name: "61-live-reply-expanded", chat: liveChat, blocks: heldBlocks, expanded: true),
            Scene(name: "66-deploy-row-building-open", chat: chat(""), blocks: shortBlocks, deploys: [snapDeploy("building", ago: 41)]),
            Scene(name: "67-deploy-row-live-expanded", chat: chat(""), blocks: shortBlocks, expanded: true, deploys: [snapDeploy("building", ago: 300, sha: "e5"), snapDeploy("live", ago: 140, done: 30)]),
            Scene(name: "68-deploy-row-failed-open", chat: chat(""), blocks: shortBlocks, deploys: [snapDeploy("failed", ago: 75, done: 20)]),
            Scene(name: "57-runlog-open", chat: chat(""), blocks: longBlocks, logRun: "261014024541-r002"),
        ]

        var gapBad: [String] = [], gapOK = 0
        let savedRail = Defaults[.orchRunsRailCollapsed]
        defer { Defaults[.orchRunsRailCollapsed] = savedRail }
        for s in scenes {
            orchSnapDiffOpen = s.diffOpen
            let vm = BoringViewModel()
            let m = OrchestratorManager.shared
            await m.snapshotApply(loaded: s.loaded, chat: s.chat, state: s.calm ? StateResponse(runs: [], usage: nil) : StateResponse(runs: state.runs, usage: state.usage, deploys: s.deploys.isEmpty ? nil : try! JSONDecoder().decode([Deploy].self, from: Data("[\(s.deploys.joined(separator: ","))]".utf8))), runsBoard: s.runsBoard)
            OrchestratorTranscriptStore.shared.snapshotSet(blocks: s.blocks, pending: s.sends, attachments: s.attachments, draft: s.draft)
            Defaults[.orchRunsRailCollapsed] = s.railCollapsed
            PromptCardController.shared.snapshotSet(pressed: s.pressed, note: s.note, pending: s.pending, dismissCurrent: s.dismissed)
            if let n = s.notes { OrchestratorNotesStore.shared.snapshotSet(text: n.0, status: n.1); m.notesOpen = true }
            let logLines = (try? JSONDecoder().decode([String].self, from: Data(fixture("x18-log.json").utf8))) ?? []
            OrchestratorRunLog.shared.snapshotSet(runID: s.logRun, lines: s.logLines ? logLines : [])

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
                    if s.loaded, s.chat?.running == true, !s.runsBoard, s.notes == nil, m.prompt == nil {
                        let w = host.bounds.width
                        let c = bottomGap(rep, xPt: 200) ?? -1
                        let r = s.expanded ? (bottomGap(rep, xPt: w - 90) ?? -1) : 12
                        print("gap \(s.name): composer=\(c) rail=\(s.expanded ? "\(r)" : "-")")
                        if abs(c - 12) > 1 || abs(r - 12) > 1 { gapBad.append("\(s.name)=\(c)/\(r)"); } else { gapOK += 1 }
                    }
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
            OrchestratorRunLog.shared.snapshotSet(runID: nil, lines: [])
            m.notesOpen = false
            PromptCardController.shared.snapshotSet()
            if let png { try? png.write(to: url); print("wrote", url.path) } else { print("FAILED", s.name) }
        }
        print(gapBad.isEmpty ? "OK: composer bottom padding 12 in \(gapOK) scenes" : "FAIL: composer bottom padding \(gapBad.joined(separator: ", "))")
    }


    /// Rows (pt from the top) of the notch's black bottom edge and of the first non-black pixel above it
    /// (the composer / rail pill bottom) at column `xPt`. nil when no black bottom is found.
    static func edges(_ rep: NSBitmapImageRep, xPt: CGFloat) -> (bottom: CGFloat, pill: CGFloat)? {
        let k = CGFloat(rep.pixelsWide) / rep.size.width
        let x = Int(xPt * k)
        guard x >= 0, x < rep.pixelsWide else { return nil }
        func dark(_ y: Int) -> Bool { let c = rep.colorAt(x: x, y: y); return (c?.alphaComponent ?? 0) > 0.5 && (c?.brightnessComponent ?? 1) < 0.05 }
        guard let bottom = (0..<rep.pixelsHigh).reversed().first(where: dark),
              let pill = (0...bottom).reversed().first(where: { !dark($0) }) else { return nil }
        return (CGFloat(bottom) / k, CGFloat(pill) / k)
    }

    /// Distance in pt from the notch's bottom edge up to the pill bottom at column `xPt`.
    static func bottomGap(_ rep: NSBitmapImageRep, xPt: CGFloat) -> CGFloat? { edges(rep, xPt: xPt).map { $0.bottom - $0.pill } }

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
        print(moved ? "FAIL: root-frame-only check: top edge moved" : "OK: root-frame-only check (no panel, host-local): top edge at y=0 in every step")
        await livePass(out)
    }

    private struct LiveRoot: View {
        @ObservedObject var vm: BoringViewModel
        var body: some View {
            // ContentView's root chain, including the onChange hook that drives the real panel frame.
            ZStack(alignment: .top) { VStack(spacing: 0) { NotchReplica(vm: vm).core.environmentObject(vm).frame(height: vm.notchState == .open ? vm.notchSize.height : nil) } }
                .padding(.bottom, 8)
                .notchRootFrame(notchSize: vm.notchSize)
                .onChange(of: vm.notchSize) { _, _ in OrchestratorExpand.shared.syncWindow(vm: vm) }
                .compositingGroup()
                .scaleEffect(x: 1, y: 1, anchor: .top)
        }
    }

    /// Dense screen-space check on the app-like panel: window top, shape top and shape bottom every ~16ms through grow and collapse.
    static func topEdgePass(vm: BoringViewModel, window: NSWindow, host: NSView) async -> [String] {
        let screenTop = NSScreen.main?.frame.maxY ?? 900
        var bad: [String] = []
        print("dense start: screen \(NSScreen.main?.frame ?? .zero) window \(window.frame) host \(host.frame)")
        for (phase, level) in [("grow", ExpandLevel.expanded), ("collapse", .open)] {
            OrchestratorExpand.shared.setLevel(level, vm: vm, window: window)
            let t0 = ContinuousClock.now
            var lastBottom: CGFloat? = nil
            var first = true
            var settledFor = 0
            print("dense \(phase): t window(y,h) hostTopScreen hostH shapeTop shapeBottom notchH")
            while true {
                try? await Task.sleep(for: .milliseconds(8))
                let t = Int((ContinuousClock.now - t0) / .milliseconds(1))
                if t > 1000 { break }
                let hb = host.convert(host.bounds, to: nil)
                let hostTop = window.frame.minY + hb.maxY
                let col = NSRect(x: host.bounds.midX - 2, y: 0, width: 4, height: host.bounds.height)
                guard let rep = host.bitmapImageRepForCachingDisplay(in: col) else { continue }
                host.cacheDisplay(in: col, to: rep)
                let k = CGFloat(rep.pixelsHigh) / col.height
                func dark(_ y: Int) -> Bool { let c = rep.colorAt(x: 1, y: y); return (c?.brightnessComponent ?? 1) < 0.05 && (c?.alphaComponent ?? 0) > 0.5 }
                let topRow = (0..<rep.pixelsHigh).first(where: dark), botRow = (0..<rep.pixelsHigh).last(where: dark)
                let shapeTop = topRow.map { hostTop - CGFloat($0) / k } ?? -1
                let shapeBot = botRow.map { hostTop - CGFloat($0 + 1) / k } ?? -1
                print(String(format: "dense %@ %4d  win(%.1f,%.0f) hostTop=%.1f hostH=%.0f top=%.1f bottom=%.1f notchH=%.0f", phase, t, window.frame.minY, window.frame.height, hostTop, host.bounds.height, shapeTop, shapeBot, vm.notchSize.height))
                var why: [String] = []
                if abs(window.frame.maxY - screenTop) > 0.5 { why.append("window top \(window.frame.maxY)") }
                if abs(hostTop - screenTop) > 0.5 { why.append("host top \(hostTop)") }
                if topRow == nil || abs(shapeTop - screenTop) > 0.5 { why.append("shape top \(shapeTop)") }
                if let lb = lastBottom, topRow != nil {
                    let dy = shapeBot - lb // screen y up: growing moves the bottom down (negative)
                    // spring overshoot allowed: only judge until the notch height first reaches its target
                    if settledFor == 0, phase == "grow" ? dy > 0.5 : dy < -0.5 { why.append("bottom moved the wrong way (\(dy))") }
                }
                if vm.notchSize.height == OrchestratorExpand.shared.openSize(for: vm).height { settledFor += 1 }
                if topRow != nil { lastBottom = shapeBot }
                if !why.isEmpty, first { first = false; bad.append("\(phase) t=\(t)ms: " + why.joined(separator: ", ")) }
                if settledFor > 5 && t > 600 { break }
            }
            try? await Task.sleep(for: .milliseconds(700))
        }
        return bad
    }

    /// One hosted window, real setLevel animation. Content fades out, lays out once at the final size while hidden and
    /// fades in near the end of the spring: every frame must be blank, the old layout (first 60ms only) or the final
    /// layout, never an intermediate one, and the blank window must be short.
    static func livePass(_ out: URL) async {
        let vm = BoringViewModel()
        // Hosted like createBoringNotchWindow: panel style mask, clear, sizingOptions = [] (TRANSITION_DEFAULT_SIZING=1 keeps the default).
        let window = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
                                  styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.isFloatingPanel = true
        window.level = .mainMenu + 3; window.collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle] // like BoringNotchWindow: above the menu bar, so the frame is not pushed below it
        // Offscreen windows get no display link, so springs stall; a (nearly) transparent on-screen window keeps them ticking.
        window.alphaValue = 0.01; window.ignoresMouseEvents = true
        window.setFrameOrigin(NSPoint(x: ((NSScreen.main?.frame.midX ?? 720) - windowSize.width / 2), y: (NSScreen.main?.frame.maxY ?? 900) - windowSize.height))
        let host = NSHostingView(rootView: LiveRoot(vm: vm))
        if ProcessInfo.processInfo.environment["TRANSITION_DEFAULT_SIZING"] == nil { host.sizingOptions = [] }
        window.contentView = host
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(700))
        struct Frame { var lit = 0; var newest = 0; var minX: CGFloat = -1; var pillY: CGFloat = -1; var width: CGFloat = 0; var rep: NSBitmapImageRep? }
        func measure() -> Frame {
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return Frame() }
            host.cacheDisplay(in: host.bounds, to: rep)
            let k = CGFloat(rep.pixelsWide) / host.bounds.width
            let y0 = Int(44 * k), y1 = min(rep.pixelsHigh, Int((vm.notchSize.height - 12) * k))
            var f = Frame(rep: rep)
            var minX = Int.max
            // Every 4th pixel each way: a full scan blocks the main thread long enough to stall the animation under test.
            if y1 > y0 { for y in stride(from: y0, to: y1, by: 4) { for x in stride(from: 0, to: rep.pixelsWide, by: 4) where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.15 { f.lit += 1; minX = min(minX, x) } } }
            // Left edge of the black shape on the header row; content x is taken relative to it (the window widens at once).
            let left = (0..<rep.pixelsWide).first { x in let c = rep.colorAt(x: x, y: Int(20 * k)); return (c?.brightnessComponent ?? 1) < 0.05 && (c?.alphaComponent ?? 0) > 0.5 }.map { CGFloat($0) / k } ?? 0
            let right = (0..<rep.pixelsWide).reversed().first { x in let c = rep.colorAt(x: x, y: Int(20 * k)); return (c?.brightnessComponent ?? 1) < 0.05 && (c?.alphaComponent ?? 0) > 0.5 }.map { CGFloat($0) / k } ?? 0
            f.width = right - left
            f.minX = minX == .max ? -1 : CGFloat(minX) / k - left
            // Newest row: the band just above the composer must hold lit pixels (bubble or compact row).
            let by0 = Int(max(0, vm.notchSize.height - 100) * k), by1 = min(rep.pixelsHigh, Int((vm.notchSize.height - 45) * k))
            if by1 > by0 { for y in stride(from: by0, to: by1, by: 4) { for x in stride(from: Int(40 * k), to: min(rep.pixelsWide, Int(620 * k)), by: 4) where (rep.colorAt(x: x, y: y)?.brightnessComponent ?? 0) > 0.3 { f.newest += 1 } } }
            f.pillY = edges(rep, xPt: host.bounds.width / 2 - 140)?.pill ?? -1
            return f
        }
        // Height is excluded on purpose: the shape (and the content frame) springs in height while content may be fading in.
        func same(_ a: Frame, _ b: Frame) -> Bool { abs(a.minX - b.minX) <= 2 }
        var settled = measure()
        let newestBase = settled.newest
        print("live baseline open lit=\(settled.lit) minX=\(settled.minX) pillY=\(settled.pillY) newest=\(newestBase)")
        var bad: [String] = []
        var blankSpan: [Int] = [], spans: [String] = []
        let times = [0, 30, 60, 120, 200, 280, 350, 450, 700, 1200]
        for (phase, level) in [("grow", ExpandLevel.expanded), ("collapse", .open)] {
            let start = settled
            OrchestratorExpand.shared.setLevel(level, vm: vm, window: window)
            var frames: [(Int, Frame)] = []
            let t0 = ContinuousClock.now
            var actual: [Int] = []
            for t in times {
                // Wall clock: a capture takes tens of ms, so sleep only what is left of the nominal time.
                let el = Int((ContinuousClock.now - t0) / .milliseconds(1))
                // Always suspend: a capture runs on the main actor and would otherwise starve the view's own fade Task.
                try? await Task.sleep(for: .milliseconds(max(2, t - el)))
                actual.append(Int((ContinuousClock.now - t0) / .milliseconds(1)))
                frames.append((t, measure()))
            }
            let final = frames.last!.1
            // A capture takes ~100ms on the main thread and holds back the view's own fade work, so frames before the
            // first blank one are only "fading" (the old layout, still on screen because its fade-out was starved).
            // What the harness can assert: a blank window exists, every frame after it is blank or the final layout at
            // the final shape width (content never appears at an intermediate layout), and the blank span is short.
            var seenBlank = false
            for (i, (t, f)) in frames.enumerated() {
                let blank = f.lit * 10 < final.lit
                if blank { seenBlank = true; blankSpan.append(actual[i]) }
                let atFinal = same(f, final) && abs(f.width - final.width) <= 4
                let cls = blank ? "blank" : !seenBlank ? (same(f, start) ? "old" : "fading") : atFinal ? "final" : "intermediate"
                print("live \(phase) t=\(t)ms at=\(actual[i])ms w=\(Int(f.width)) lit=\(f.lit) minX=\(Int(f.minX)) pillY=\(Int(f.pillY)) newest=\(f.newest) h=\(Int(vm.notchSize.height)) lvl=\(OrchestratorExpand.shared.level(for: vm)) \(cls)")
                if cls == "intermediate" || (t >= 700 && cls != "final") { bad.append("\(phase) \(t)ms \(cls)") }
                if phase == "collapse" && t >= 700 && f.newest * 4 < newestBase { bad.append("\(phase) \(t)ms newest row missing") }
                if [0, 30, 60, 120, 200, 280, 350, 450, 700, 1200].contains(t) { try? f.rep?.representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("transition-live-\(phase)-\(t).png")) }
            }
            if !seenBlank { bad.append("\(phase) never blank") }
            if let lo = blankSpan.min(), let hi = blankSpan.max(), hi - lo > 350 { bad.append("\(phase) blank window \(lo)..\(hi)ms") }
            spans.append("\(phase) \(blankSpan.min() ?? 0)..\(blankSpan.max() ?? 0)")
            blankSpan.removeAll()
            settled = final
        }
        OrchestratorExpand.shared.reset()
        try? await Task.sleep(for: .milliseconds(900))
        let topBad = await topEdgePass(vm: vm, window: window, host: host)
        print(topBad.isEmpty ? "OK: screen-space top edge pinned through grow and collapse (panel-hosted)" : "FAIL: screen-space top edge: first offender " + topBad.joined(separator: " | "))
        OrchestratorExpand.shared.reset()
        window.contentView = nil
        window.orderOut(nil)
        print(bad.isEmpty ? "OK: no intermediate-layout frames; blank " + spans.joined(separator: ", ") + "ms" : "FAIL: " + bad.joined(separator: ", "))
    }

    /// Gap under the composer / rail Terminal pill in ContentView's full root chain, after states that used to
    /// leave a non-zero fit or extra height behind (composer growth, notes, a prompt at open, the terminal level).
    static func gapPass() async -> Bool {
        let m = OrchestratorManager.shared
        let store = OrchestratorTranscriptStore.shared
        var bad: [String] = []
        let cases: [(String, Bool, Bool, Bool, Bool)] = [ // name, draft, notes, prompt-then-cleared, terminal
            ("expanded", false, false, false, false), ("composer-grown", true, false, false, false),
            ("notes-open", false, true, false, false), ("prompt-then-cleared", false, false, true, false),
            ("terminal", false, false, false, true), ("all", true, true, true, false),
        ]
        for (name, draft, notes, prompt, term) in cases {
            await m.snapshotApply(loaded: true, chat: ChatResponse(running: true, screen: prompt ? fixture("phase6-edit.txt") : ""), state: StateResponse(runs: [], usage: nil))
            store.snapshotSet(blocks: editBlocks, draft: draft ? wordyDraft : "")
            PromptCardController.shared.snapshotSet()
            let vm = BoringViewModel()
            let window = KeyablePanel(contentRect: NSRect(x: -20000, y: -20000, width: windowSize.width, height: windowSize.height),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            // The offscreen spring stalls, so the level is set before the tree is mounted (as in the normal pass). What an
            // open-level state leaves behind is reproduced through the real fit sources and stores.
            if draft { OrchestratorExpand.shared.setFit("composer", extra: 40, vm: vm, window: window) }
            if prompt { OrchestratorExpand.shared.setFit("prompt", extra: 60, vm: vm, window: window) }
            if notes { OrchestratorNotesStore.shared.snapshotSet(text: shortNote, status: .saved); m.notesOpen = true }
            OrchestratorExpand.shared.setLevel(term ? .terminal : .expanded, vm: vm, window: window)
            // Built after the level change: `core` and the root frame read the notch size once (ContentView re-evaluates them).
            let mainLayout = NotchReplica(vm: vm).core.environmentObject(vm).contentShape(Rectangle()).onHover { _ in }.onTapGesture { }
            let root = ZStack(alignment: .top) { VStack(spacing: 0) { mainLayout } }
                .padding(.bottom, 8).notchRootFrame(notchSize: vm.notchSize).compositingGroup().scaleEffect(x: 1, y: 1, anchor: .top)
            let host = NSHostingView(rootView: root)
            window.contentView = host
            // window stays unordered: an ordered-in window runs the stalled spring from the model value
            
            try? await Task.sleep(for: .milliseconds(1200))
            host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                let mid = host.bounds.width / 2, half = vm.notchSize.width / 2
                let c = term ? nil : bottomGap(rep, xPt: mid - half + 200)
                let r = bottomGap(rep, xPt: mid + half - 90)
                print("hittest gap \(name): composer=\(c.map { "\($0)" } ?? "-") rail=\(r ?? -1) h=\(Int(vm.notchSize.height)) win=\(Int(host.bounds.height)) lvl=\(OrchestratorExpand.shared.level(for: vm))")
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/notch-snapshots/hittest-gap-\(name).png"))
                // notes dim the tab (35% opacity) and cover the composer: printed, not asserted
                if !notes, (c.map { abs($0 - 12) > 1 } ?? false) || abs((r ?? -1) - 12) > 1 { bad.append("\(name)=\(c ?? -1)/\(r ?? -1)") }
            } else { bad.append("\(name)=norep") }
            m.notesOpen = false
            OrchestratorExpand.shared.releaseKey(window)
            OrchestratorExpand.shared.reset()
            window.contentView = nil
            window.orderOut(nil)
        }
        print(bad.isEmpty ? "OK: hittest gap 12 in every state" : "FAIL: hittest gap " + bad.joined(separator: ", "))
        return bad.isEmpty
    }

    /// Clicks into the real tab inside a copy of ContentView's root chain (mainLayout tap/hover, ZStack,
    /// bottom padding, notchRootFrame, compositingGroup, scaleEffect) in the app's panel class, open and
    /// expanded. Only actions that never POST: composer (starts typing, focuses the field), Chat|Runs
    /// segment, status capsule. Also reports what a click below the visible notch hits.
    static func hitTest() async {
        setvbuf(stdout, nil, _IONBF, 0)
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
            if !expanded {
                // Smart auto-scroll: scrolled up keeps its position on new content (pill shown), the pill jumps
                // to the bottom, at the bottom a new row is followed.
                func scrollViews(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? [] + v.subviews.flatMap(scrollViews) }
                func extra(_ id: String) -> [ChatBlock] {
                    blocks(#"{"running":true,"blocks":[{"id":"\#(id)","kind":"prose","text":"A new message arrived while reading back."}]}"#)
                }
                try? await Task.sleep(for: .milliseconds(1000))
                if let sv = scrollViews(host).first(where: { $0.documentView != nil && $0.bounds.height > 40 && $0.bounds.height < host.bounds.height }) {
                    let clip = sv.contentView
                    func offY() -> CGFloat { clip.documentVisibleRect.origin.y }
                    func bottomY() -> CGFloat { (sv.documentView?.frame.height ?? 0) - clip.bounds.height }
                    func atBottom() -> Bool { abs(offY() - bottomY()) < 14 || (sv.documentView?.isFlipped == false && offY() < 4) }
                    let flipped = sv.documentView?.isFlipped ?? true
                    let start = offY()
                    var how = "scroll wheel"
                    if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 300, wheel2: 0, wheel3: 0),
                       let ev = NSEvent(cgEvent: cg) { window.sendEvent(ev) }
                    try? await Task.sleep(for: .milliseconds(300))
                    if abs(offY() - start) < 2 {
                        how = "clip scroll(to:)"
                        clip.scroll(to: NSPoint(x: 0, y: flipped ? max(0, start - 300) : start + 300))
                        sv.reflectScrolledClipView(clip)
                        try? await Task.sleep(for: .milliseconds(300))
                    }
                    let up = offY()
                    print("scroll view \(type(of: sv)), scrolled up via \(how): \(Int(start)) -> \(Int(up)), flipped \(flipped)")
                    OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks + extra("extra1"))
                    try? await Task.sleep(for: .milliseconds(500))
                    let kept = abs(offY() - up) < 2 && !atBottom()
                    try? window.contentView?.bitmapImageRepForCachingDisplay(in: host.bounds).flatMap { rep -> Data? in
                        host.cacheDisplay(in: host.bounds, to: rep); return rep.representation(using: .png, properties: [:])
                    }?.write(to: URL(fileURLWithPath: "/tmp/notch-snapshots/hittest-new-messages.png"))
                    print("scrolled-up position kept: \(kept)")
                    await click(vm.notchSize.height - 60, x: 320) // pill: just above the composer
                    try? await Task.sleep(for: .milliseconds(400))
                    let jumped = atBottom()
                    print("pill jumps to bottom: \(jumped) off \(offY()) bottom \(bottomY()) doc \(sv.documentView?.frame.height ?? 0) clip \(clip.bounds.height)")
                    OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks + extra("extra1") + extra("extra2"))
                    try? await Task.sleep(for: .milliseconds(500))
                    let follows = atBottom()
                    print("at bottom follows new row: \(follows)")
                    ok = ok && kept && jumped && follows
                } else {
                    print("FAIL: no NSScrollView found for the transcript")
                    ok = false
                }
                OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks)
                try? await Task.sleep(for: .milliseconds(300))
            }
            if !expanded {
                // Text selection: drag copies (private pasteboard) and never expands; a plain click expands.
                // An NSTextView's mouseDown tracks until mouse-up, so the drag/up events are queued first.
                OrchestratorSelectableText.pasteboard = NSPasteboard(name: .init("orch-snap-hittest"))
                OrchestratorTranscriptStore.shared.snapshotSet(blocks: markerBlocks)
                try? await Task.sleep(for: .milliseconds(1200))
                host.layoutSubtreeIfNeeded()
                func textViews(_ v: NSView) -> [NSTextView] { (v as? NSTextView).map { [$0] } ?? [] + v.subviews.flatMap(textViews) }
                func pbString() -> String { OrchestratorSelectableText.pasteboard.string(forType: .string) ?? "" }
                func ev(_ t: NSEvent.EventType, _ p: NSPoint) -> NSEvent? {
                    NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                }
                func shot(_ name: String) {
                    try? window.contentView?.bitmapImageRepForCachingDisplay(in: host.bounds).flatMap { rep -> Data? in
                        host.cacheDisplay(in: host.bounds, to: rep); return rep.representation(using: .png, properties: [:])
                    }?.write(to: URL(fileURLWithPath: "/tmp/notch-snapshots/\(name).png"))
                }
                /// Drag from +4 to +dx along the first line of `tv`; nil dx = plain click.
                func gesture(_ tv: NSTextView, dx: CGFloat?) async {
                    let r = tv.convert(tv.bounds, to: nil)
                    let y = r.maxY - 6, x0 = r.minX + 4
                    if let dx {
                        if let e = ev(.leftMouseDragged, NSPoint(x: x0 + 60, y: y)) { NSApp.postEvent(e, atStart: false) }
                        if let e = ev(.leftMouseUp, NSPoint(x: x0 + dx, y: y)) { NSApp.postEvent(e, atStart: false) }
                    } else if let e = ev(.leftMouseUp, NSPoint(x: x0, y: y)) { NSApp.postEvent(e, atStart: false) }
                    if let e = ev(.leftMouseDown, NSPoint(x: x0, y: y)) { window.sendEvent(e) }
                    try? await Task.sleep(for: .milliseconds(300))
                }
                if let tv = textViews(host).first(where: { $0.string.hasPrefix("The root frame") }) {
                    OrchestratorSelectableText.pasteboard.clearContents()
                    OrchestratorExpand.shared.reset()
                    await gesture(tv, dx: 140)
                    let got = pbString()
                    let copies = !got.isEmpty && tv.string.hasPrefix(got)
                    let noExpand = OrchestratorExpand.shared.level(for: vm) == .open
                    print("drag copies: \(copies) [\(got)]")
                    print("drag does not expand: \(noExpand)")
                    shot("hittest-selection")
                    await gesture(tv, dx: nil)
                    let plain = OrchestratorExpand.shared.level(for: vm) == .expanded
                    print("plain click expands: \(plain)")
                    ok = ok && copies && noExpand && plain
                    OrchestratorExpand.shared.setLevel(.open, vm: vm, window: window)
                    try? await Task.sleep(for: .milliseconds(600))
                    OrchestratorExpand.shared.reset()
                    // Tool target (m6 Bash ... run.sh --transition, visible at the bottom): drag copies a prefix of it.
                    if let tt = textViews(host).first(where: { $0.string.hasSuffix("--transition") }) {
                        OrchestratorSelectableText.pasteboard.clearContents()
                        await gesture(tt, dx: 100)
                        let g2 = pbString()
                        let tcopies = !g2.isEmpty && tt.string.contains(g2)
                        let tNoExpand = OrchestratorExpand.shared.level(for: vm) == .open
                        print("tool target drag copies: \(tcopies && tNoExpand) [\(g2)]")
                        ok = ok && tcopies && tNoExpand
                    } else {
                        print("tool target drag copies: false (text view not found)")
                        ok = false
                    }
                    // Scrolling over a text view: a wheel event sent into the window does not move any scroll view in this
                    // harness, so check the forwarding itself: the text view hands the wheel to its enclosing scroll view.
                    final class SpyScroll: NSScrollView {
                        var got = false
                        override func scrollWheel(with event: NSEvent) { got = true }
                    }
                    let spy = SpyScroll(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
                    let stv = OrchestratorSelectableTextView()
                    stv.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
                    spy.documentView = stv
                    if let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 80, wheel2: 0, wheel3: 0),
                       let e0 = NSEvent(cgEvent: cg) {
                        stv.scrollWheel(with: e0)
                        print("scroll over text works: \(spy.got)")
                        ok = ok && spy.got
                    }
                    OrchestratorTranscriptStore.shared.snapshotSet(blocks: markerBlocks)
                    try? await Task.sleep(for: .milliseconds(600))
                    OrchestratorExpand.shared.releaseKey(window)
                    window.makeFirstResponder(nil)
                    OrchestratorExpand.shared.setLevel(.open, vm: vm, window: window)
                    try? await Task.sleep(for: .milliseconds(600))
                    OrchestratorExpand.shared.reset()
                    window.contentView = NSHostingView(rootView: root) // fresh tree, like the remount check below
                    try? await Task.sleep(for: .milliseconds(600))
                } else {
                    print("prose text view: not found")
                    ok = false
                }
                OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks)
                try? await Task.sleep(for: .milliseconds(300))
            }
            var line: [String] = []

            // The regression: an AppKit platform view (the TextField) under the composer took the click.
            let hitName = window.contentView?.superview?.hitTest(NSPoint(x: expanded ? 200 : 320, y: H - (vm.notchSize.height - 27)))
                .map { String(describing: type(of: $0)) } ?? "nil"
            let reachesSwiftUI = hitName.hasPrefix("NSHostingView")
            ok = ok && reachesSwiftUI
            line.append("composer hit reaches SwiftUI: \(reachesSwiftUI)")
            // Composer: notch bottom padding 12, pill 30 -> centre 27 above the notch bottom. Clicked at the open
            // level only. (These clicks go through window.sendEvent, which the NSApp-level outside-click monitors never see;
            // the monitors take their point from the event, so SnapIdle's gates click outside without moving the cursor.)
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
                try? await Task.sleep(for: .milliseconds(1500))
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
                try? await Task.sleep(for: .milliseconds(1500)) // the button's own load() (GET) must settle before the fixture is set
                // Notes editor: clicking anywhere in it must start editing (the AppKit text view used to take the
                // click before the key gate opened). Never insert text: edits autosave via POST.
                OrchestratorNotesStore.shared.snapshotSet(text: "line one\nline two", status: .idle)
                m.notesOpen = true
                try? await Task.sleep(for: .milliseconds(1200))
                let ex = host.bounds.width / 2 + vm.notchSize.width / 2 - 31 - 150, ey = (max(24, vm.closedNotchSize.height) + vm.notchSize.height - 12) / 2
                let eHit = window.contentView?.superview?.hitTest(NSPoint(x: ex, y: H - ey)).map { String(describing: type(of: $0)) } ?? "nil"
                var typedN: [Bool] = []
                let subN = m.$wantsKeyboard.sink { typedN.append($0) }
                await click(ey, x: ex)
                let nFocused = window.firstResponder is NSTextView
                subN.cancel()
                line.append("notes editor hit \(eHit) at (\(Int(ex)), \(Int(ey)))")
                line.append("notes editor click starts typing: \(typedN.contains(true)), editor focused: \(nFocused)")
                ok = ok && typedN.contains(true) && nFocused
                OrchestratorExpand.shared.releaseKey(window)
                m.endTyping()
                window.makeFirstResponder(nil)
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
        ok = await gapPass() && ok
        ok = await runLogPass() && ok
        print(ok ? "OK: composer, segment, capsule and notes button respond to clicks" : "FAIL: a click target did not respond")
    }
}

extension Snap {
    /// Run log overlay: a rail card and a collapsed-strip dot open it, the X closes it and restores the level, Esc closes it.
    static func runLogPass() async -> Bool {
        let m = OrchestratorManager.shared
        let state = (try? JSONDecoder().decode(StateResponse.self, from: Data(fixture("phase7-state.txt").utf8)))
            ?? StateResponse(runs: [], usage: nil)
        await m.snapshotApply(loaded: true, chat: ChatResponse(running: true, screen: ""), state: state)
        OrchestratorTranscriptStore.shared.snapshotSet(blocks: longBlocks)
        let log = OrchestratorRunLog.shared
        let savedRail = Defaults[.orchRunsRailCollapsed]
        defer { Defaults[.orchRunsRailCollapsed] = savedRail }
        var ok = true
        for collapsed in [false, true] {
            Defaults[.orchRunsRailCollapsed] = collapsed
            for startOpen in [false, true] {
                // Collapsed strip only exists expanded; start-open is covered by the card pass.
                if collapsed && startOpen { continue }
                let vm = BoringViewModel()
                let window = KeyablePanel(contentRect: NSRect(x: -20000, y: -20000, width: windowSize.width, height: windowSize.height),
                                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.isOpaque = false; window.backgroundColor = .clear
                OrchestratorExpand.shared.setLevel(startOpen ? .open : .expanded, vm: vm, window: window)
                let mainLayout = NotchReplica(vm: vm).core.environmentObject(vm).contentShape(Rectangle()).onHover { _ in }.onTapGesture { }
                let root = ZStack(alignment: .top) { VStack(spacing: 0) { mainLayout } }
                    .padding(.bottom, 8).notchRootFrame(notchSize: vm.notchSize).compositingGroup()
                let host = NSHostingView(rootView: root)
                window.contentView = host
                window.orderFrontRegardless()
                m.showRunsBoard = startOpen
                try? await Task.sleep(for: .milliseconds(900))
                host.layoutSubtreeIfNeeded()
                func click(_ fromTop: CGFloat, x: CGFloat) async {
                    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                        if let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: host.bounds.height - fromTop), modifierFlags: [],
                                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                                      context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { window.sendEvent(e) }
                        try? await Task.sleep(for: .milliseconds(30))
                    }
                    try? await Task.sleep(for: .milliseconds(400))
                }
                var W: CGFloat { host.bounds.width }
                try? await Task.sleep(for: .milliseconds(300))
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) { host.cacheDisplay(in: host.bounds, to: rep); try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/notch-snapshots/hittest-runlog-pre-\(collapsed)-\(startOpen).png")) }
                print("run log host \(host.bounds.size)")
                let label = collapsed ? "strip dot" : startOpen ? "board card" : "rail card"
                // Board card: first (waiting) card; rail card: second row; strip dot: second dot.
                var right: CGFloat { W / 2 + vm.notchSize.width / 2 }
                let (x, y): (CGFloat, CGFloat) = collapsed ? (right - 46, 117)
                    : startOpen ? (right - 640 + 120, 90)
                    : (right - 114, 165)
                func esc() async {
                    if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                                isARepeat: false, keyCode: 53) { NSApp.sendEvent(e) }
                    try? await Task.sleep(for: .milliseconds(600))
                }
                let want: ExpandLevel = startOpen ? .open : .expanded
                for closer in ["x", "esc"] {
                    if startOpen && closer == "esc" { continue } // the host stays stale after the offscreen grow; Esc is covered expanded
                    await click(y, x: x)
                    let opened = log.runID != nil
                    let level = OrchestratorExpand.shared.level(for: vm)
                    print("run log \(label)/\(closer): opened \(opened), level \(level)")
                    if closer == "x", let png = host.bitmapImageRepForCachingDisplay(in: host.bounds).flatMap({ rep -> Data? in
                        host.cacheDisplay(in: host.bounds, to: rep); return rep.representation(using: .png, properties: [:]) }) {
                        try? png.write(to: URL(fileURLWithPath: "/tmp/notch-snapshots/hittest-runlog-\(label.replacingOccurrences(of: " ", with: "-")).png"))
                    }
                    ok = ok && opened && level == .expanded
                    guard opened else { continue }
                    switch closer {
                    // At the open level the offscreen spring never grows the host, so the X is not where it will be: close directly.
                    case "x" where startOpen: log.close()
                    case "x": await click(62, x: right - 53)
                    case "esc": await esc()
                    default: break
                    }
                    try? await Task.sleep(for: .milliseconds(600))
                    let closed = log.runID == nil, back = OrchestratorExpand.shared.level(for: vm)
                    print("run log \(label)/\(closer): closed \(closed), level \(back)")
                    ok = ok && closed && back == want
                    if !closed { log.close() }
                }
                OrchestratorExpand.shared.reset()
                window.contentView = nil
                window.orderOut(nil)
                log.snapshotSet(runID: nil, lines: [])
            }
        }
        print(ok ? "OK: run log opens from card and dot, close restores level" : "FAIL: run log open/close")
        return ok
    }
}

/// The app panel's key rule (BoringNotchSkyLightWindow.canBecomeKey).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { OrchestratorManager.shared.keyboardWindow === self || OrchestratorKeyGate.terminalWantsKey }
}

extension Snap {
    /// A question arriving leaves the level alone: open stays open, expanded stays expanded, closed opens to open.
    static func questionLevelPass() async -> Bool {
        let m = OrchestratorManager.shared
        let q = ChatResponse(running: true, screen: fixture("question.txt"))
        let idle = ChatResponse(running: true, screen: "")
        var ok = true
        for start in ["open", "expanded", "closed"] {
            await m.snapshotApply(loaded: true, chat: idle, state: StateResponse(runs: [], usage: nil))
            let vm = BoringViewModel()
            let window = KeyablePanel(contentRect: NSRect(x: -20000, y: -20000, width: windowSize.width, height: windowSize.height),
                                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            if start == "expanded" { OrchestratorExpand.shared.setLevel(.expanded, vm: vm, window: window) }
            if start == "closed" { vm.notchSize = vm.closedNotchSize; vm.notchState = .closed }
            let root = NotchReplica(vm: vm).core.environmentObject(vm)
            let host = NSHostingView(rootView: root)
            window.contentView = host
            window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(500))
            await m.snapshotApply(loaded: true, chat: q, state: StateResponse(runs: [], usage: nil))
            try? await Task.sleep(for: .milliseconds(900))
            if start == "closed" { vm.notchSize = OrchestratorExpand.shared.openSize(for: vm); vm.notchState = .open; try? await Task.sleep(for: .milliseconds(500)) }
            let level = OrchestratorExpand.shared.level(for: vm)
            let want: ExpandLevel = start == "expanded" ? .expanded : .open
            print("question level \(start): prompt \(m.prompt?.kind == .question), level \(level)")
            ok = ok && m.prompt?.kind == .question && level == want
            OrchestratorExpand.shared.reset()
            window.contentView = nil
            window.orderOut(nil)
        }
        print(ok ? "OK: question card keeps the level" : "FAIL: question card changed the level")
        return ok
    }
}
