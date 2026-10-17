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
    let description: String?

    private enum CodingKeys: String, CodingKey { case id, kind, text, name, target, result, added, removed, diff, description }

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
        description = try? c.decodeIfPresent(String.self, forKey: .description)
    }
}

/// Serve's one-line tool description (first line, trimmed); nil for non-tools, missing or blank.
func toolDescription(_ b: ChatBlock) -> String? {
    guard b.kind == .tool, let d = b.description else { return nil }
    let first = d.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    return first
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

/// The assistant's prose since the last user message (all of it when there is none), trimmed, blanks dropped,
/// joined by blank lines: the context a question/permission card refers to. nil when there is none.
func latestAssistantProse(_ blocks: [ChatBlock]) -> String? {
    let since = blocks.lastIndex { $0.kind == .user }.map { blocks.index(after: $0) } ?? blocks.startIndex
    let parts = blocks[since...].filter { $0.kind == .prose }
        .compactMap { $0.text?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
}

/// The `⏺` prose right above a prompt dialog on the tmux screen. Claude Code writes a turn's assistant lines to
/// the transcript only once the prompt is answered, so this is the only place the lead-in exists meanwhile.
/// Skips the pending tool's own row; stops at another tool row, the user's ❯ echo, or any other element.
/// Soft wraps are re-joined by terminal width (the rule's length); blank lines stay paragraph breaks.
// ponytail: width heuristic counts Characters, so wide glyphs (CJK, emoji) can leave a stray line break.
func screenLeadIn(screen: String) -> String? {
    let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map {
        String($0.replacingOccurrences(of: "\u{a0}", with: " ").reversed().drop { $0 == " " }.reversed())
    }
    func isRule(_ s: String) -> Bool { s.hasPrefix("───") }
    guard let mark = lines.lastIndex(where: { $0.hasPrefix("⏺") }),
          let top = lines[mark...].firstIndex(where: isRule) else { return nil }
    let width = lines[top].count
    // Elements start at column 0; Claude Code indents their continuation lines.
    let starts = lines.indices.filter { $0 < top && !lines[$0].isEmpty && !lines[$0].hasPrefix(" ") }
    var paragraphs: [String] = []
    for (k, s) in starts.enumerated().reversed() {
        let first = lines[s]
        guard first.hasPrefix("⏺") else { break }
        let isTool = first.range(of: #"^⏺ [^\s(]+\("#, options: .regularExpression) != nil
        if isTool { if paragraphs.isEmpty { continue } else { break } }
        let end = k + 1 < starts.count ? starts[k + 1] : top
        let t = rejoinElement(lines[s..<end], width: width, firstIsMark: true)
        if !t.isEmpty { paragraphs.insert(t, at: 0) }
    }
    return paragraphs.isEmpty ? nil : paragraphs.joined(separator: "\n\n")
}

/// One screen element's lines as text: soft wraps (line filled to the terminal width) re-joined, blank lines kept as paragraph breaks.
private func rejoinElement(_ els: ArraySlice<String>, width: Int, firstIsMark: Bool) -> String {
    var text = "", prevLen = 0
    for (i, l) in els.enumerated() {
        let body = i == 0 && firstIsMark ? String(l.dropFirst(2)) : String(l.drop { $0 == " " })
        if body.isEmpty { if !text.isEmpty, !text.hasSuffix("\n\n") { text += "\n\n" }; prevLen = 0; continue }
        let word = body.prefix { $0 != " " }.count
        if !text.isEmpty && !text.hasSuffix("\n\n") { text += prevLen + 1 + word > width - 1 ? " " : "\n" }
        text += body
        prevLen = l.count
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func proseKey(_ s: String) -> String { String(s.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init)) }

/// The screen lead-in while the transcript doesn't hold it yet (nil once its prose block has arrived).
func heldLeadIn(screen: String, blocks: [ChatBlock]) -> String? {
    guard let lead = screenLeadIn(screen: screen) else { return nil }
    let probe = String(proseKey(lead).prefix(40))
    return (latestAssistantProse(blocks).map { proseKey($0).contains(probe) } ?? false) ? nil : lead
}

/// The reply being written right now, read off the tmux screen: every `⏺` prose element of the turn above the
/// input box that the transcript doesn't hold yet (tool rows and the spinner are skipped). headCut = the first
/// `⏺` scrolled out of the capture, so the head must come from an earlier screen (see mergeLiveReply).
/// nil while a dialog is up (no input box under the text) or when there is nothing.
func screenLiveReply(screen: String, blocks: [ChatBlock]) -> (text: String, headCut: Bool)? {
    let lines = screen.split(separator: "\n", omittingEmptySubsequences: false).map {
        String($0.replacingOccurrences(of: "\u{a0}", with: " ").reversed().drop { $0 == " " }.reversed())
    }
    func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
    guard let top = lines.indices.last(where: { i in
        guard lines[i].hasPrefix("───"), i + 1 < lines.count else { return false }
        let n = trimmed(lines[i + 1])
        return n.hasPrefix("❯") && n.range(of: #"^❯\s*\d+\."#, options: .regularExpression) == nil
    }) else { return nil }
    let width = lines[top].count
    let starts = lines.indices.filter { $0 < top && !lines[$0].isEmpty && !lines[$0].hasPrefix(" ") }
    var parts: [String] = [], headCut = false, stopped = false
    for (k, s) in starts.enumerated().reversed() {
        let first = lines[s]
        let end = k + 1 < starts.count ? starts[k + 1] : top
        if parts.isEmpty, let c = first.first, "✻✢✳✶✽✺✹·*".contains(c) { continue }
        guard first.hasPrefix("⏺") else { stopped = true; break }
        let isTool = first.range(of: #"^⏺ [^\s(]+\("#, options: .regularExpression) != nil
            || lines[(s + 1)..<end].contains { trimmed($0).hasPrefix("⎿") }
        if isTool { continue }
        let t = rejoinElement(lines[s..<end], width: width, firstIsMark: true)
        if !t.isEmpty { parts.insert(t, at: 0) }
    }
    if !stopped {
        // Whatever sits above the first column-0 element is the tail of a ⏺ element that scrolled off.
        let cutEnd = starts.first ?? top
        let region = lines[0..<cutEnd]
        if region.contains(where: { !$0.isEmpty }), !region.contains(where: { trimmed($0).hasPrefix("⎿") }) {
            let t = rejoinElement(region, width: width, firstIsMark: false)
            if !t.isEmpty { parts.insert(t, at: 0); headCut = true }
        }
    }
    let held = latestAssistantProse(blocks).map(proseKey) ?? ""
    parts = parts.filter { !held.contains(String(proseKey($0).prefix(40))) }
    return parts.isEmpty ? nil : (parts.joined(separator: "\n\n"), headCut)
}

/// Joins a head that scrolled off the capture back on: current's first line is located in the accumulated text and
/// the two must agree from there on.
// ponytail: splices by first-line match; a reply whose first visible line repeats earlier text can splice at the wrong
// place, and anything that scrolled off between two captures (more than ~250 lines in 0.5 s) is lost.
func mergeLiveReply(previous: String?, current: String, headCut: Bool) -> String {
    guard headCut, let previous else { return current }
    let first = String(current.prefix { $0 != "\n" }.prefix(80))
    guard !first.isEmpty, let at = previous.range(of: first, options: .backwards) else { return current }
    let tail = previous[at.lowerBound...]
    return tail.hasPrefix(current) || current.hasPrefix(tail) ? String(previous[..<at.lowerBound]) + current : current
}

/// The live reply for the next screen. Idle with nothing showing does no parsing; idle with a row showing keeps it
/// (end-of-turn grace) until the transcript block arrives and screenLiveReply drops it.
func nextLiveReply(previous: String?, screen: String, blocks: [ChatBlock], working: Bool) -> String? {
    if !working && previous == nil { return nil }
    guard let r = screenLiveReply(screen: screen, blocks: blocks) else { return nil }
    return mergeLiveReply(previous: previous, current: r.text, headCut: r.headCut)
}

/// Transcript text is untrusted: inline markdown only, links stripped (T-05-01/02). The size cap only bounds a hostile
/// payload; real messages run past 2000 chars (one did, and lost its last line), and a cut ends in "…" so it shows.
let proseCharCap = 20_000
func proseAttributed(_ s: String) -> AttributedString {
    let plain = s.count > proseCharCap ? s.prefix(proseCharCap) + "…" : s
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

// MARK: - Optimistic sends

struct PendingMessage: Equatable, Identifiable {
    enum State { case queued, sending, sent, failed }
    let id: Int
    let text: String
    var state: State
    var sentAt: Date?
    var images: [Data] = []   // PNG bytes
    var paths: [String] = []  // server paths uploaded so far; Retry reuses them
    var files: [FileChip] = [] // uploaded via /api/chat/file
    var wireText: String { chatTextWithImages(text, paths: paths, files: files.compactMap(\.path)) }
}

func chatTextWithImages(_ text: String, paths: [String], files: [String] = []) -> String {
    ([text.trimmingCharacters(in: .whitespacesAndNewlines)] + paths.map { "[image: \($0)]" } + files.map { "[file: \($0)]" }).filter { !$0.isEmpty }.joined(separator: " ")
}

func normalizeChatText(_ s: String) -> String {
    s.split(whereSeparator: { $0.isWhitespace || $0 == "\u{a0}" }).joined(separator: " ")
}

func reconcilePending(_ pending: [PendingMessage], blocks: [ChatBlock], known: Set<String>, now: Date, staleAfter: TimeInterval = 30) -> (pending: [PendingMessage], known: Set<String>) {
    var known = known
    var out: [PendingMessage] = []
    for p in pending {
        if p.state != .queued {
            let want = normalizeChatText(p.wireText)
            if let b = blocks.last(where: { $0.kind == .user && !known.contains($0.id) && normalizeChatText($0.text ?? "") == want }) {
                known.insert(b.id)
                continue
            }
            // ponytail: a sent message whose block text differs (e.g. a slash command) is dropped after staleAfter;
            // upgrade = serve echoing a client id. Same for images if Claude Code rewrites the path (e.g. [Image #1]).
            if p.state == .sent, let t = p.sentAt, now.timeIntervalSince(t) > staleAfter { continue }
        }
        out.append(p)
    }
    return (out, known)
}

extension ChatBlock {
    init(pendingID: String, text: String, kind: Kind = .user) {
        id = pendingID; self.kind = kind; self.text = text
        name = nil; target = nil; result = nil; added = nil; removed = nil; diff = nil; description = nil
    }
}
