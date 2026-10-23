import Foundation

struct PromptOption: Equatable {
    let number: Int
    let label: String
}

/// Numbered options of a Claude Code prompt on the screen, [] when none.
func detectPrompt(screen: String) -> [PromptOption] {
    scanPrompt(screen, window: 40)?.options ?? [] // same window as detectPromptCard, so they never disagree
}

/// Shared scan behind detectPrompt and detectPromptCard: trimmed non-blank lines plus where the winning
/// option run sits and which option carries the ❯ pointer.
// ponytail: bottom-window heuristic: the last option must be within the last 4 non-blank lines
// and be followed by the "Esc to cancel" footer; retune if Claude Code adds more footer lines.
private func scanPrompt(_ screen: String, window: Int) -> (lines: [String], options: [PromptOption], indices: [Int], marked: Int?, gaps: Set<Int>)? {
    let line = #/^[ \u{a0}]*(❯[ \u{a0}]*)?(\d+)\.[ \u{a0}]+(.+)$/#
    let trim = CharacterSet(charactersIn: " \u{a0}\t\r│")
    // gaps: indices of kept lines that follow a blank line (the question's paragraph breaks).
    var all: [String] = [], allGaps = Set<Int>(), gap = false
    for raw in screen.split(separator: "\n", omittingEmptySubsequences: false) {
        let t = raw.trimmingCharacters(in: trim)
        if t.isEmpty { gap = true; continue }
        if gap && !all.isEmpty { allGaps.insert(all.count) }
        gap = false
        all.append(t)
    }
    let skip = max(0, all.count - window)
    let lines = Array(all.dropFirst(skip))
    let gaps = Set(allGaps.compactMap { $0 >= skip ? $0 - skip : nil })
    var run: [PromptOption] = []
    var runIdx: [Int] = []
    var markedNo: Int?
    var best: [PromptOption] = []
    var bestIdx: [Int] = []
    var bestMarked: Int?
    var bestEnd = -1
    for (i, s) in lines.enumerated() {
        guard let m = try? line.wholeMatch(in: s), let n = Int(m.2), n <= 9 else {
            if let m = try? line.wholeMatch(in: s), let n = Int(m.2), n > 9 { run = []; runIdx = []; markedNo = nil }
            continue
        }
        if n == 1 { run = []; runIdx = []; markedNo = nil }
        guard n == run.count + 1 else { run = []; runIdx = []; markedNo = nil; continue }
        run.append(PromptOption(number: n, label: String(m.3).trimmingCharacters(in: trim)))
        runIdx.append(i)
        if m.1 != nil { markedNo = n }
        if run.count >= 2 && markedNo != nil { best = run; bestIdx = runIdx; bestMarked = markedNo; bestEnd = i }
    }
    // Live prompts end with an "Esc to cancel" footer; a numbered draft in the input box has none.
    // The question review step has no footer; its "Ready to submit" line stands in.
    // The footer wraps onto a second line when it grows (typing in a free-text option adds "ctrl+g to edit in Vim"): match the joined text.
    let footer = lines.dropFirst(bestEnd + 1).joined(separator: " ").localizedCaseInsensitiveContains("esc to cancel")
        || lines.contains { $0 == "Ready to submit your answers?" }
    guard bestEnd >= 0 && bestEnd >= lines.count - 4 && footer else { return nil }
    return (lines, best, bestIdx, bestMarked, gaps)
}

/// Observed in Claude Code 2.1.299: Shift-Tab (BTab) moves to the previous question chip, ticks kept,
/// and also leaves the review step. Left does the same; BTab chosen since it never moves a cursor.
let promptBackKey = "BTab"

/// Keys to move from chip `cur` to chip `k` (Tab forward, BTab back); nil when equal or forward from review.
func tabKeys(from cur: Int, to k: Int, review: Bool) -> [String]? {
    if k > cur { return review ? nil : Array(repeating: "Tab", count: k - cur) }
    return k < cur ? Array(repeating: promptBackKey, count: cur - k) : nil
}

struct PromptCardOption: Equatable {
    enum Role: Equatable { case normal, deny, freeText, chat }
    let number: Int
    var label: String
    var detail: String? = nil
    var role: Role = .normal
    /// Multi-select checkbox state; nil on rows without a checkbox.
    var checked: Bool? = nil
}

struct PromptTab: Equatable {
    let label: String
    let done: Bool
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
    var question: String? = nil
    /// `question` with its paragraphs, lists and labels kept (see briefBlocks).
    var questionBlocks: [BriefBlock] = []
    var items: [PromptCardOption] = []
    var highlighted: Int? = nil
    var multiSelect = false
    /// Question chips in order, the Submit chip last when the screen shows one.
    var tabs: [PromptTab] = []
    /// Index into `tabs` of the question on screen (the Submit chip on the review step).
    var currentTab: Int? = nil
    /// The "Review your answers" step.
    var review = false
}

/// Optimistic checkbox state: a pending toggle wins until the screen agrees, then it drops.
func mergeChecked(screen: [Int: Bool], pending: [Int: Bool]) -> (shown: [Int: Bool], pending: [Int: Bool]) {
    var shown = screen, left = pending
    for (n, v) in pending { if screen[n] == v { left[n] = nil } else { shown[n] = v } }
    return (shown, left)
}

/// What makes two cards "the same prompt" (excludes `highlighted`, which follows the TUI's cursor).
struct PromptIdentity: Equatable {
    let kind: PromptCard.Kind
    let text: [String?]
    let labels: [String]
}
func promptIdentity(_ c: PromptCard) -> PromptIdentity {
    PromptIdentity(kind: c.kind, text: [c.title, c.question, c.body], labels: c.items.map(\.label) + c.options.map(\.label))
}

private func isRule(_ s: String, _ ch: Character) -> Bool { s.count >= 10 && s.allSatisfy { $0 == ch } }

/// Screen chrome below a dialog that is never part of an option: any line opening with a box-drawing
/// character (─/━/╌ rules, titled rules like "─── Session title ──", box borders), the ❯ input line,
/// and Claude Code's footers.
private func isChrome(_ s: String) -> Bool {
    if let u = s.unicodeScalars.first, (0x2500...0x257F).contains(u.value) { return true }
    return s.hasPrefix("❯") || s.hasPrefix("⏵") || s.hasPrefix("? for shortcuts")
        || s.localizedCaseInsensitiveContains("esc to cancel") || s.localizedCaseInsensitiveContains("enter to select")
}

/// nil when no prompt is on screen.
func detectPromptCard(screen: String) -> PromptCard? {
    guard let sc = scanPrompt(screen, window: 40) else { return nil }
    let lines = sc.lines
    let first = sc.indices[0], last = sc.indices[sc.indices.count - 1]
    let full: (String) -> Bool = { isRule($0, "─") }
    let dashed: (String) -> Bool = { isRule($0, "╌") }
    let after = lines.dropFirst(last + 1)
    let ruleAbove = (0..<first).reversed().first { full(lines[$0]) }
    let chipIdx = ((ruleAbove.map { $0 + 1 } ?? 0)..<first).first { "←☐☒✔".contains(lines[$0].first!) }
    var kind = PromptCard.Kind.permission
    if chipIdx != nil || after.contains(where: { $0.localizedCaseInsensitiveContains("enter to select") }) { kind = .question }

    var items: [PromptCardOption] = []
    for (k, o) in sc.options.enumerated() {
        var it = PromptCardOption(number: o.number, label: o.label)
        if let m = o.label.wholeMatch(of: #/\[( |✔|x|X)\] (.*)/#) {
            it.label = String(m.2)
            if !it.label.hasPrefix("Type something") { it.checked = m.1 != " " }
        }
        if it.label.hasPrefix("Type something") { it.role = .freeText } else if it.label == "Chat about this" { it.role = .chat }
        if kind == .question && it.role == .normal {
            let end = k + 1 < sc.indices.count ? sc.indices[k + 1] : lines.count
            let d = lines[(sc.indices[k] + 1)..<end].prefix { !isChrome($0) }
            it.detail = d.isEmpty ? nil : d.joined(separator: " ")
        }
        items.append(it)
    }
    // Options carry no checkbox glyph either, so toggling never changes the card's identity.
    var card = PromptCard(options: zip(sc.options, items).map { PromptOption(number: $0.number, label: $1.label) },
                          kind: kind, items: items, highlighted: sc.marked)
    card.multiSelect = items.contains { $0.checked != nil }
    if card.multiSelect { card.kind = .question; kind = .question }
    if kind == .question {
        let from = chipIdx ?? ruleAbove ?? -1
        let q = lines[(from + 1)..<first].joined(separator: " ")
        card.question = q.isEmpty ? nil : q
        card.questionBlocks = briefBlocks(Array(lines[(from + 1)..<first]), gaps: Set(sc.gaps.map { $0 - from - 1 }), hardBreaks: false)
        if let c = chipIdx {
            var chips: [(done: Bool, label: String)] = []
            var cur: (done: Bool, label: String)?
            for ch in lines[c] {
                if "☐☒✔".contains(ch) { if let x = cur { chips.append(x) }; cur = (ch == "☒", "") }
                else if ch != "←" && ch != "→" { cur?.label.append(ch) }
            }
            if let x = cur { chips.append(x) }
            chips = chips.map { ($0.done, $0.label.trimmingCharacters(in: .whitespaces)) }
            card.tabs = chips.map { PromptTab(label: $0.label, done: $0.done) }
            let qs = chips.filter { $0.label != "Submit" }
            if !qs.isEmpty {
                // ponytail: plain text can't show which chip is highlighted. First unanswered chip, except a
                // multi-select with ticks is already counted ☒ while still showing: then the last answered one.
                var cur = qs.firstIndex { !$0.done } ?? qs.count - 1
                if card.multiSelect, items.contains(where: { $0.checked == true }), let l = qs.lastIndex(where: { $0.done }) { cur = l }
                card.currentTab = cur
                card.header = qs[cur].label
                card.progress = qs.count > 1 ? "\(cur + 1) of \(qs.count)" : nil
            }
        }
        if lines[(chipIdx ?? -1) + 1 ..< first].first == "Review your answers" {
            let l = Array(lines[((chipIdx ?? -1) + 2)..<first])
            card.review = true
            card.question = "Review your answers"
            card.body = l.dropLast().joined(separator: "\n") // last line is "Ready to submit your answers?"
            card.currentTab = card.tabs.count - 1
            card.header = nil; card.progress = nil
        }
    } else {
        // Only a label that means "cancel" is drawn as the red deny pill; anything else stays normal.
        let cancels: (String) -> Bool = { l in ["no", "cancel", "reject"].contains { l.lowercased().hasPrefix($0) } }
        if let d = card.items.lastIndex(where: { $0.role == .normal && cancels($0.label) }) { card.items[d].role = .deny }
        if first > 0 {
            card.question = lines[first - 1]
            if let r = (0..<(first - 1)).reversed().first(where: { full(lines[$0]) }) {
                let block = lines[(r + 1)..<(first - 1)].filter { !$0.hasPrefix("Tip:") }
                card.title = block.first
                let dashes = block.indices.filter { dashed(block[$0]) }
                let rest = block.dropFirst()
                card.purpose = rest.prefix { !dashed($0) }.first
                if dashes.count >= 2 {
                    let body = block[(dashes[0] + 1)..<dashes[1]]
                    // ponytail: a body whose lines all start with a line number is an Edit/Write diff and is dropped;
                    // confirm against real Edit/Write captures.
                    let numbered = body.allSatisfy { $0.wholeMatch(of: #/\d+\s.*/#) != nil }
                    card.body = body.isEmpty || numbered ? nil : body.joined(separator: "\n")
                }
            }
        }
    }
    return card
}

/// Pill text for a permission option; the full label stays the tooltip.
func shortLabel(_ label: String) -> String {
    var s = label
    if let r = s.range(of: " · ") { s = String(s[..<r.lowerBound]) }
    if let r = s.range(of: #"\s*\([^)]*\)$"#, options: .regularExpression) { s.removeSubrange(r) }
    if s == "Yes" { return "Allow" }
    if s.hasPrefix("No") { return "Deny" }
    if let m = s.wholeMatch(of: #/Yes, and always allow access to (.+?) from this project/#) { return "Always in \(m.1)" }
    if s.contains("switch to auto mode") { return "Auto mode" }
    if s.hasPrefix("Yes, allow all edits") { return "All edits" }
    if let m = s.wholeMatch(of: #/Yes, and don't ask again for (.+)/#) { return "Always: \(m.1)" }
    for p in ["Yes, and ", "Yes, "] where s.hasPrefix(p) {
        s = String(s.dropFirst(p.count))
        return s.prefix(1).uppercased() + s.dropFirst()
    }
    return s.count > 22 ? String(s.prefix(21)) + "…" : s
}

/// Move the ❯ highlight by delta within the option numbers, clamped.
func moveHighlight(_ current: Int?, by delta: Int, in numbers: [Int]) -> Int? {
    guard !numbers.isEmpty else { return nil }
    guard let c = current, let i = numbers.firstIndex(of: c) else { return numbers[0] }
    return numbers[max(0, min(numbers.count - 1, i + delta))]
}

enum PromptKey: Equatable { case answer(Int), escape, up, down, select, pass }

func promptKey(keyCode: UInt16, characters: String?, commandLike: Bool, editingText: Bool, kind: PromptCard.Kind, numbers: Set<Int>) -> PromptKey {
    if editingText || commandLike { return .pass }
    if keyCode == 53 { return .escape }
    if let c = characters, c.count == 1, let n = Int(c), (1...9).contains(n), numbers.contains(n) { return .answer(n) }
    if kind == .question {
        switch keyCode {
        case 126: return .up
        case 125: return .down
        case 36, 76: return .select
        default: break
        }
    }
    return .pass
}

/// False when answering with `keys` only moves to another step of the same prompt (next question, review), so the card stays up.
func hidesOnAnswer(_ c: PromptCard, keys: [String]) -> Bool {
    if keys.contains("Tab") || keys.contains(promptBackKey) { return false }
    return !(c.kind == .question && !c.review && c.tabs.filter { $0.label != "Submit" }.count > 1)
}

/// The free-text row is an inline input on the same screen (Claude Code 2.1.309): pressing its number
/// only moves the ❯ onto it (label stays "Type something.", prompt identity unchanged). Ready to type once the ❯ is there.
func freeTextFocused(_ c: PromptCard?, number: Int) -> Bool {
    guard let c, c.kind == .question else { return false }
    return c.highlighted == number && c.items.contains { $0.number == number && $0.role == .freeText }
}
