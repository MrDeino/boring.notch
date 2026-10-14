// Phase 5 owns: ChatBlock decoding, /api/chat/blocks merge, inputLine parse.
import Foundation

struct ChatDiffHunk: Decodable, Equatable {
    let oldStart: Int?
    let newStart: Int?
    let lines: [String]?
}

/// One /api/chat/blocks entry. Only id and kind are required; every other field is lossy (wrong type -> nil).
struct ChatBlock: Decodable, Equatable, Identifiable {
    enum Kind: String { case user, tool, prose }
    let id: String
    let kind: Kind
    let text: String?
    let name: String?
    let target: String?
    let result: String?
    let added: Int?
    let removed: Int?
    let diff: [ChatDiffHunk]?

    private enum CodingKeys: String, CodingKey { case id, kind, text, name, target, result, added, removed, diff }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) { id = s }
        else if let n = try? c.decode(Int.self, forKey: .id) { id = String(n) }
        else { throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "id") }
        guard let k = Kind(rawValue: try c.decode(String.self, forKey: .kind)) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "kind")
        }
        kind = k
        text = try? c.decodeIfPresent(String.self, forKey: .text)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        target = try? c.decodeIfPresent(String.self, forKey: .target)
        result = try? c.decodeIfPresent(String.self, forKey: .result)
        added = try? c.decodeIfPresent(Int.self, forKey: .added)
        removed = try? c.decodeIfPresent(Int.self, forKey: .removed)
        diff = try? c.decodeIfPresent([ChatDiffHunk].self, forKey: .diff)
    }
}

private struct LossyChatBlock: Decodable {
    let value: ChatBlock?
    init(from decoder: Decoder) throws { value = try? ChatBlock(from: decoder) }
}

private struct ChatBlocksEnvelope: Decodable {
    let running: Bool?
    let blocks: [LossyChatBlock]?
}

/// Accepts `{running, blocks}` or a bare array; drops unknown kinds and malformed blocks.
func decodeChatBlocks(_ data: Data) -> (running: Bool?, blocks: [ChatBlock])? {
    let d = JSONDecoder()
    // `blocks` is required: `{}` or `{"error":…}` is a failure (chatTail fallback), not an empty transcript.
    if let e = try? d.decode(ChatBlocksEnvelope.self, from: data), let b = e.blocks {
        return (e.running, b.compactMap(\.value))
    }
    if let a = try? d.decode([LossyChatBlock].self, from: data) { return (nil, a.compactMap(\.value)) }
    return nil
}

func mergeChatBlocks(_ existing: [ChatBlock], _ incoming: [ChatBlock], reset: Bool, cap: Int = 200) -> (blocks: [ChatBlock], appended: Bool) {
    // Reset de-dups like the append path (repeated JSONL lines, 7 vs "7") so ForEach ids stay unique.
    if reset { return (mergeChatBlocks([], incoming, reset: false, cap: cap).blocks, false) }
    var out = existing
    var index = Dictionary(out.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { _, b in b })
    var appended = false
    for b in incoming {
        if let i = index[b.id] { out[i] = b } else { index[b.id] = out.count; out.append(b); appended = true }
    }
    return (Array(out.suffix(cap)), appended)
}

/// A non-empty since-response sharing no id with what we hold is ambiguous: serve didn't know `since`
/// (/clear, new transcript, >80 missed; it then sends its last 80) or `since` was a non-tool block with
/// new blocks after it. The caller resolves it with a full fetch.
func blocksDiscontinuous(sinceSent: Bool, incoming: [ChatBlock], existing: [ChatBlock]) -> Bool {
    guard sinceSent, !incoming.isEmpty else { return false }
    let have = Set(existing.map(\.id))
    return !incoming.contains { have.contains($0.id) }
}

// ponytail: duplicates chatTail's box rule (Models is not Phase 5's file); merge them when Models is free.
func parseInputLine(screen: String) -> String? {
    let junk = CharacterSet(charactersIn: " \u{a0}\t\r")
    let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).compactMap { line -> String? in
        var s = Substring(line)
        while let l = s.unicodeScalars.last, junk.contains(l) { s = s.dropLast() }
        return s.isEmpty ? nil : String(s)
    }
    let edge = CharacterSet(charactersIn: " \u{a0}")
    func isRule(_ s: String) -> Bool { s.trimmingCharacters(in: edge).hasPrefix("───") }
    guard let top = lines.indices.last(where: { i in
        isRule(lines[i]) && i + 1 < lines.count && lines[i + 1].trimmingCharacters(in: edge).hasPrefix("❯")
            && lines[(i + 2)...].contains(where: isRule)
    }) else { return nil }
    var parts: [String] = []
    for l in lines[(top + 1)...] {
        if isRule(l) { break }
        var t = l.trimmingCharacters(in: edge)
        if parts.isEmpty { t = String(t.dropFirst()).trimmingCharacters(in: edge) }
        if !t.isEmpty { parts.append(t) }
    }
    return parts.joined(separator: " ")
}

// ponytail: Phase A heuristic (R-04). A draft is box text seen changing from one non-empty value to another
// while the notch field is not editing; a suggestion appears in one step from empty and then stays static.
// A suggestion swapping to a different suggestion is misread as a draft; Phase 8's serve `suggested` flag replaces this.
func boxIsDraft(previous: String?, current: String?, wasDraft: Bool, editing: Bool) -> Bool {
    guard let current, !current.isEmpty else { return false }
    if editing { return wasDraft }
    if let previous, !previous.isEmpty, previous != current { return true }
    return wasDraft
}

func clearToCaret(_ text: String, caretUTF16: Int?) -> String {
    guard let caret = caretUTF16, caret < text.utf16.count else { return "" }
    if caret <= 0 { return text }
    let loc = (text as NSString).rangeOfComposedCharacterSequence(at: caret).location
    return String(text[String.Index(utf16Offset: loc, in: text)...])
}

/// "✻ Brewed for 2m 4s" when the last conversation line is the finished-turn line, else nil.
func parseIdleStatus(screen: String) -> String? {
    guard let last = chatTail(screen: screen, maxLines: 1).last else { return nil }
    let s = last.trimmingCharacters(in: CharacterSet(charactersIn: " \u{a0}"))
    guard let g = s.first, "✻✢✳✶✽✺✹".contains(g), s.contains(" for "), !s.contains("esc to interrupt") else { return nil }
    return s.split(separator: "·", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces) }
}

func toolTargetDisplay(name: String?, target: String?) -> String {
    guard let t = target else { return "" }
    return t.hasPrefix("/") && !t.contains(" ") ? (t as NSString).lastPathComponent : t
}

func toolResultDisplay(name: String?, result: String?, added: Int?) -> String? {
    guard var r = result, added == nil else { return nil }
    var more: Int?
    if r.hasSuffix(" lines)"), let o = r.range(of: " (+", options: .backwards),
       let n = Int(r[o.upperBound...].dropLast(" lines)".count)) { more = n; r = String(r[..<o.lowerBound]) }
    if name == "Read", r != "(no output)", !r.hasPrefix("error:") {
        let n = (more ?? 0) + 1
        return n == 1 ? "1 line" : "\(n) lines"
    }
    return r
}

func toolResultIsError(_ s: String?) -> Bool { s?.hasPrefix("error:") ?? false }

/// Colour of a tool row's ⏺ marker: no result yet = running, "error:" = error, anything else = done.
enum ToolMarker: Equatable { case running, done, error }
func toolMarker(result: String?) -> ToolMarker {
    guard let result else { return .running }
    return toolResultIsError(result) ? .error : .done
}

/// Transcript text is untrusted: truncated, inline markdown only, links stripped (T-05-01/02).
func proseAttributed(_ s: String) -> AttributedString {
    let plain = String(s.prefix(2000))
    var a = (try? AttributedString(markdown: plain, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
        ?? AttributedString(plain)
    for run in a.runs { a[run.range].link = nil }
    return a
}

struct DiffRow: Equatable {
    enum Kind { case context, removed, added }
    let kind: Kind
    let number: Int?
    let text: String
}

/// Unified-diff hunk lines as numbered rows: context and added show the new line number, removed the old one.
/// A line without a ' '/'-'/'+' prefix ("\ No newline") is context with no number and advances nothing.
func diffRows(_ hunks: [ChatDiffHunk]) -> [DiffRow] {
    var rows: [DiffRow] = []
    for h in hunks {
        var old = h.oldStart, new = h.newStart
        for l in h.lines ?? [] {
            switch l.first {
            case "-": rows.append(DiffRow(kind: .removed, number: old, text: String(l.dropFirst()))); old = old.map { $0 + 1 }
            case "+": rows.append(DiffRow(kind: .added, number: new, text: String(l.dropFirst()))); new = new.map { $0 + 1 }
            case " ": rows.append(DiffRow(kind: .context, number: new, text: String(l.dropFirst()))); old = old.map { $0 + 1 }; new = new.map { $0 + 1 }
            default: rows.append(DiffRow(kind: .context, number: nil, text: l))
            }
        }
    }
    return rows
}
