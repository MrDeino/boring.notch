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

    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .lineLimit(1...5)
            .textFieldStyle(.plain)
            .focused(focused)
            .onSubmit(onSubmit)
            .onExitCommand(perform: onExit)
            .onChange(of: focused.wrappedValue) { _, f in if f { onFocus() } }
    }
}

/// Caret after the last character of the window's field editor (focusing a field selects all of it).
@MainActor func moveCaretToEnd(in window: NSWindow?) {
    guard let tv = window?.firstResponder as? NSTextView else { return }
    tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
}
