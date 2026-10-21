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
