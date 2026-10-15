import SwiftUI

// run.sh --fulltext (quick kg6): a long multi-paragraph prose row, laid out like ChatBlockRow's prose branch, keeps its
// whole text and its last line inside the row frame at the open and expanded widths, also after the text grows
// (streaming) and after a line limit is lifted (open -> expanded). Guards proseAttributed's cap and the fit cache.

@MainActor private final class FullTextModel: ObservableObject {
    @Published var text = ""
    @Published var width: CGFloat = 560
    @Published var maxLines = 0
}

private struct FullTextRow: View {
    @ObservedObject var m: FullTextModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(.white).frame(width: 7, height: 7).frame(width: 10)
                OrchestratorSelectableText(orchestratorProseNS(proseAttributed(m.text), size: 13, color: .white, lineSpacing: 2),
                                           maxLines: m.maxLines, lineBreak: m.maxLines == 0 ? .byWordWrapping : .byTruncatingTail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .frame(width: m.width, height: 2000, alignment: .top)
    }
}

private func textViews(_ v: NSView) -> [OrchestratorSelectableTextView] {
    ((v as? OrchestratorSelectableTextView).map { [$0] } ?? []) + v.subviews.flatMap(textViews)
}

@MainActor func fullText() async {
    // The real failure: 2070 chars, cut at 2000 mid-word ("…merged into your f").
    let paras = (1...6).map { i in "Paragraph \(i): " + String(repeating: "the orchestrator explains what it dispatched and why, at length. ", count: 5) }
    var text = paras.joined(separator: "\n\n") + "\n\nOn the notch, the lead-in text fix is merged into your fork (#6). LAST-LINE-END"
    precondition(text.count > 2000)
    let m = FullTextModel()
    m.text = text
    let host = NSHostingView(rootView: FullTextRow(m: m))
    let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 1000, height: 2000), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = host
    var failures = 0

    func check(_ label: String, clamped: Bool = false) async {
        try? await Task.sleep(for: .milliseconds(120))
        host.layoutSubtreeIfNeeded()
        guard let tv = textViews(host).first, let lm = tv.layoutManager, let tc = tv.textContainer else { print("FAIL \(label): no text view"); failures += 1; return }
        lm.ensureLayout(for: tc)
        let glyphs = lm.glyphRange(for: tc)
        let used = lm.usedRect(for: tc)
        let whole = tv.string == text
        let allLaidOut = glyphs.upperBound == lm.numberOfGlyphs
        let fits = used.maxY <= tv.frame.height + 0.5 && used.width <= tv.frame.width + 0.5
        let ok = whole && allLaidOut != clamped && fits
        if !ok { failures += 1 }
        print("\(ok ? "ok  " : "FAIL") \(label): chars \(tv.string.count)/\(text.count) glyphs \(glyphs.upperBound)/\(lm.numberOfGlyphs) used \(Int(used.width))x\(String(format: "%.1f", used.maxY)) frame \(Int(tv.frame.width))x\(String(format: "%.1f", tv.frame.height))")
    }

    for w: CGFloat in [420, 560, 760, 900] {
        m.width = w
        await check("width \(Int(w))")
    }
    // Streaming: the same row's text grows twice; the cached fit must not keep the old height.
    m.width = 560
    text += " One more sentence streamed in after the first measure."
    m.text = text
    await check("grown once")
    text += "\n\nAnd a whole new closing paragraph that wraps across more than one line in the notch, ending with GROWN-END."
    m.text = text
    await check("grown twice")
    // Open level clamps to 4 lines (by design, tap to expand); lifting it must re-measure.
    m.maxLines = 4
    await check("4-line clamp", clamped: true)
    m.maxLines = 0
    await check("clamp lifted")
    print(failures == 0 ? "OK: fulltext" : "FAIL: fulltext (\(failures))")
    exit(failures == 0 ? 0 : 1)
}
