import Foundation

struct PromptOption: Equatable {
    let number: Int
    let label: String
}

/// Numbered options of a Claude Code prompt on the screen, [] when none.
// ponytail: bottom-window heuristic: the last option must be within the last 4 non-blank lines
// and be followed by the "Esc to cancel" footer; retune if Claude Code adds more footer lines.
func detectPrompt(screen: String) -> [PromptOption] {
    let line = #/^[ \u{a0}]*(❯[ \u{a0}]*)?(\d+)\.[ \u{a0}]+(.+)$/#
    let trim = CharacterSet(charactersIn: " \u{a0}\t\r│")
    let lines = screen.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: trim) }.filter { !$0.isEmpty }.suffix(25)
    var run: [PromptOption] = []
    var marked = false
    var best: [PromptOption] = []
    var bestEnd = -1
    for (i, s) in lines.enumerated() {
        guard let m = try? line.wholeMatch(in: s), let n = Int(m.2), n <= 9 else {
            if let m = try? line.wholeMatch(in: s), let n = Int(m.2), n > 9 { run = []; marked = false }
            continue
        }
        if n == 1 { run = []; marked = false }
        guard n == run.count + 1 else { run = []; marked = false; continue }
        run.append(PromptOption(number: n, label: String(m.3).trimmingCharacters(in: trim)))
        if m.1 != nil { marked = true }
        if run.count >= 2 && marked { best = run; bestEnd = i }
    }
    // Live prompts end with an "Esc to cancel" footer; a numbered draft in the input box has none.
    let footer = lines.dropFirst(bestEnd + 1).contains { $0.localizedCaseInsensitiveContains("esc to cancel") }
    return bestEnd >= 0 && bestEnd >= lines.count - 4 && footer ? best : []
}

struct PromptCard: Equatable {
    enum Kind: Equatable { case permission, question }
    var title: String? = nil
    var purpose: String? = nil
    var body: String? = nil
    var options: [PromptOption]
    var kind: Kind
    var header: String? = nil
    var progress: String? = nil
}

/// nil when no prompt is on screen. Phase 6 fills title/purpose/body/header/progress.
func detectPromptCard(screen: String) -> PromptCard? {
    let o = detectPrompt(screen: screen)
    guard !o.isEmpty else { return nil }
    return PromptCard(options: o, kind: o.contains { $0.label == "Type something." } ? .question : .permission)
}
