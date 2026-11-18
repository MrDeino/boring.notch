import SwiftUI

/// Where a keystroke landed, for type-to-focus.
struct ComposerKeyContext {
    var notchOpen = true          // open or expanded, never closed
    var orchestratorTab = true
    var appActive = true          // false = another app is frontmost
    var windowIsKey = true        // the event's window is this notch's key panel
    var composerFocused = false
    var terminalFocused = false   // ttyd owns the keys
    var editingOtherText = false  // notes or the question card's text field
    var cardShowing = false       // digits pick options; the composer is hidden
}

/// The text a keystroke should start the composer with, or nil to leave the key alone.
/// Printable keys only: ⌘/⌃ combos, Esc, Tab, Return, Delete and arrow/function keys pass.
func typeToFocusText(characters: String?, modifierFlags raw: UInt, context c: ComposerKeyContext) -> String? {
    let command: UInt = 1 << 20, control: UInt = 1 << 18
    guard c.notchOpen, c.orchestratorTab, c.appActive, c.windowIsKey, !c.composerFocused, !c.terminalFocused,
          !c.editingOtherText, !c.cardShowing, raw & (command | control) == 0,
          let s = characters, !s.isEmpty else { return nil }
    // Control characters (Esc, Tab, Return, Delete) and AppKit's function-key range (arrows, F-keys, Home/End).
    guard !s.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || (0xF700...0xF8FF).contains($0.value) }) else { return nil }
    return s
}

/// The composer's text field. Always mounted, so the first click, drag or double-click lands in AppKit's field and
/// selects there; onFocus then opens the typing session (key gate, activation) without touching the selection.
struct OrchestratorComposerField: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var onFocus: () -> Void = {}
    var onSubmit: () -> Void = {}
    var onExit: () -> Void = {}

    /// Tallest the box grows before it scrolls: 8 lines of OT.F.ui (16 pt each in the field).
    static let maxHeight: CGFloat = 8 * 16
    @State private var height: CGFloat = 15
    private final class Editor { weak var tv: NSTextView? }
    @State private var editor = Editor()

    // A vertical TextField with a capped lineLimit clips its top lines with no way to scroll to them, so the field is
    // uncapped inside a ScrollView that grows with it up to maxHeight. The field editor's scrollRangeToVisible stops
    // at the field, so every caret move (typing, arrows, click) scrolls the caret's line into the ScrollView.
    var body: some View {
        ScrollView(.vertical) {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .focused(focused)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onExit)
                .onChange(of: focused.wrappedValue) { _, f in if f { onFocus() } }
                .background(GeometryReader { g in
                    Color.clear.onAppear { height = g.size.height }.onChange(of: g.size.height) { _, h in
                        height = h
                        // The field grows a layout pass after the caret moved: follow it once the box has its new size.
                        if let tv = editor.tv { RunLoop.main.perform { MainActor.assumeIsolated { scrollCaretIntoView(tv) } } }
                    }
                })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { n in
            guard let tv = n.object as? NSTextView, tv.isFieldEditor, tv.window?.firstResponder === tv else { return }
            editor.tv = tv
            RunLoop.main.perform { MainActor.assumeIsolated { scrollCaretIntoView(tv) } }
        }
        .scrollIndicators(height > Self.maxHeight ? .automatic : .never)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(height, Self.maxHeight))
        // A ScrollView has no text baseline: keep the "from terminal ·" label on the first line's baseline.
        .alignmentGuide(.firstTextBaseline) { _ in NSFont.systemFont(ofSize: 12).ascender }
    }
}

/// The caret's line in the field editor's coordinates (after a trailing newline: the empty last line).
@MainActor func caretLineRect(_ tv: NSTextView) -> NSRect? {
    guard let lm = tv.layoutManager, let tc = tv.textContainer else { return nil }
    lm.ensureLayout(for: tc)
    let n = (tv.string as NSString).length, loc = NSMaxRange(tv.selectedRange())
    var r = loc >= n && !lm.extraLineFragmentRect.isEmpty ? lm.extraLineFragmentRect
        : n == 0 ? NSRect(x: 0, y: 0, width: 1, height: 15) : lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: min(loc, n - 1)), effectiveRange: nil)
    r.origin.y += tv.textContainerOrigin.y
    return r
}

/// Scrolls the enclosing ScrollView (the composer's) so the caret's line shows; the field editor's own scroll stops at its field.
@MainActor func scrollCaretIntoView(_ tv: NSTextView) {
    guard let tf = tv.delegate as? NSTextField, let r = caretLineRect(tv) else { return }
    var v: NSView? = tf.superview
    while let cur = v, !(cur is NSClipView) { v = cur.superview }
    guard let clip = v as? NSClipView else { return }
    let line = clip.convert(r, from: tv), b = clip.bounds
    let y = line.minY < b.minY ? line.minY : line.maxY > b.maxY ? line.maxY - b.height : b.minY
    guard y != b.minY else { return }
    clip.scroll(to: NSPoint(x: b.minX, y: y))
    clip.enclosingScrollView?.reflectScrolledClipView(clip)
}

/// Caret after the last character of the window's field editor (focusing a field selects all of it).
@MainActor func moveCaretToEnd(in window: NSWindow?) {
    guard let tv = window?.firstResponder as? NSTextView else { return }
    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
}
