// Finished AskUserQuestion rows: serve's optional `questions` / `answers` on the tool block -> a row model.
import Foundation

struct AskOption: Decodable, Equatable {
    let label: String?
    let description: String?
    private enum CodingKeys: String, CodingKey { case label, description }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try? c.decodeIfPresent(String.self, forKey: .label)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
    }
}

struct AskQuestion: Decodable, Equatable {
    let header: String?
    let question: String?
    let multiSelect: Bool?
    let options: [AskOption]?
    private enum CodingKeys: String, CodingKey { case header, question, multiSelect, options }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        header = try? c.decodeIfPresent(String.self, forKey: .header)
        question = try? c.decodeIfPresent(String.self, forKey: .question)
        multiSelect = try? c.decodeIfPresent(Bool.self, forKey: .multiSelect)
        options = (try? c.decodeIfPresent([LossyAsk<AskOption>].self, forKey: .options))?.compactMap(\.value)
    }
}

struct AskAnswer: Decodable, Equatable {
    let question: String?
    let selected: [String]?
    let other: String?
    let notes: String?
    private enum CodingKeys: String, CodingKey { case question, selected, other, notes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        question = try? c.decodeIfPresent(String.self, forKey: .question)
        selected = try? c.decodeIfPresent([String].self, forKey: .selected)
        other = try? c.decodeIfPresent(String.self, forKey: .other)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
    }
}

/// One malformed element drops out of its array instead of failing the block.
struct LossyAsk<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

struct AskRowOption: Equatable {
    let label: String
    let description: String?
    let chosen: Bool
}

struct AskRowQuestion: Equatable {
    let header: String
    let question: String
    let multiSelect: Bool
    let options: [AskRowOption]
    /// Everything picked: option labels first, then the "Other" text.
    let chosen: [String]
    let other: String?
    let notes: String?
    let answered: Bool
}

struct AskRow: Equatable {
    let questions: [AskRowQuestion]
    /// serve sent `answers: []`: the dialog was closed without answering.
    let dismissed: Bool

    /// Closed row, one short line per question: "Fruit: apple, banana".
    var summary: [String] {
        if dismissed { return ["Not answered / dismissed"] }
        return questions.map { q in
            let label = q.header.isEmpty ? q.question : q.header
            return label + ": " + (q.answered ? q.chosen.joined(separator: ", ") : "not answered")
        }
    }
}

private func nonBlank(_ s: String?) -> String? {
    let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

/// The expandable row for a finished AskUserQuestion block; nil (today's plain tool row) for any other block,
/// one without `questions`, and one still waiting (`answers` null/absent: the live card owns it).
func askRow(_ b: ChatBlock) -> AskRow? {
    guard b.kind == .tool, b.name == "AskUserQuestion", let qs = b.questions, !qs.isEmpty, let answers = b.answers else { return nil }
    var rows: [AskRowQuestion] = []
    var used = Set<Int>()
    for (i, q) in qs.enumerated() {
        let text = nonBlank(q.question) ?? ""
        // Match by question text; an answer that carries no usable text falls back to its position.
        let at = answers.indices.first { !used.contains($0) && nonBlank(answers[$0].question) == text && !text.isEmpty }
            ?? (answers.indices.contains(i) && !used.contains(i) && nonBlank(answers[i].question) == nil ? i : nil)
        let a = at.map { used.insert($0); return answers[$0] }
        let selected = (a?.selected ?? []).compactMap(nonBlank)
        let other = nonBlank(a?.other)
        let opts = (q.options ?? []).compactMap { o -> AskRowOption? in
            guard let l = nonBlank(o.label) else { return nil }
            return AskRowOption(label: l, description: nonBlank(o.description), chosen: selected.contains(l))
        }
        // A selected label serve did not list as an option still counts as picked.
        let chosen = selected + (other.map { [$0] } ?? [])
        rows.append(AskRowQuestion(header: nonBlank(q.header) ?? "", question: text, multiSelect: q.multiSelect ?? false,
                                   options: opts, chosen: chosen, other: other, notes: nonBlank(a?.notes),
                                   answered: a != nil && !(selected.isEmpty && other == nil)))
    }
    return AskRow(questions: rows, dismissed: answers.isEmpty)
}

// MARK: - Question text with its structure kept

/// One paragraph or list item of a question; `text` is inline markdown (labels already wrapped in **).
struct BriefBlock: Equatable {
    enum Kind: Equatable { case para, item(String) }
    var kind: Kind
    var text: String
}

/// Lines of a question (or a whole brief) -> blocks. A blank line (`gaps` = indices of lines that follow one, or an empty
/// line itself when `hardBreaks`) starts a paragraph; "- ", "* ", "1." and "1)" start a list item; "GOAL:" style
/// all-caps labels start a paragraph with the label bold. Any other line continues the block: joined with a newline when
/// `hardBreaks` (the text has real newlines), else with a space unless the previous line is clearly shorter than the
/// longest one (screen text is wrapped at the terminal width, so a short line before another means a real break).
// ponytail: the short-line test is a guess; a hand-wrapped brief at a ragged width may join lines it should not.
func briefBlocks(_ lines: [String], gaps: Set<Int> = [], hardBreaks: Bool) -> [BriefBlock] {
    let width = lines.map(\.count).max() ?? 0
    var out: [BriefBlock] = []
    var prev = ""
    for (i, raw) in lines.enumerated() {
        let l = raw.trimmingCharacters(in: .whitespaces)
        if l.isEmpty { prev = ""; if hardBreaks { out.append(BriefBlock(kind: .para, text: "")) } ; continue }
        defer { prev = l }
        if let m = l.wholeMatch(of: #/([-*•]|\d+[.)])\s+(.*)/#) {
            let mark = String(m.1)
            out.append(BriefBlock(kind: .item(mark.first!.isNumber ? mark : "•"), text: String(m.2)))
        } else if let m = l.wholeMatch(of: #/([A-Z][A-Z0-9 \/&-]*[A-Z0-9]):(?:\s+(.*))?/#) {
            out.append(BriefBlock(kind: .para, text: "**\(m.1):**" + (m.2.map { " " + $0 } ?? "")))
        } else if let last = out.last, !last.text.isEmpty, !gaps.contains(i), prev != "" {
            let soft = !hardBreaks && prev.count >= width * 85 / 100
            out[out.count - 1].text += (soft ? " " : "\n") + l
        } else {
            out.append(BriefBlock(kind: .para, text: l))
        }
    }
    return out.filter { !$0.text.isEmpty }
}
