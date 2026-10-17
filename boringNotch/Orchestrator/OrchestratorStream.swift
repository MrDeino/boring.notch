import Foundation

// Phase 8 pure code (harness-compiled): Foundation only.

/// Composer box text and draft flag. Old serve (no `input` key) keeps the Phase 5 heuristic;
/// new serve's `input` is exact: suggested = ghost suggestion, not suggested = typed draft.
func resolveInput(hasKey: Bool, input: ChatInput?, screen: String, chatRunning: Bool,
                  previous: String?, wasDraft: Bool, editing: Bool) -> (line: String?, draft: Bool) {
    guard chatRunning else { return (nil, false) }
    if !hasKey {
        let il = parseInputLine(screen: screen)
        return (il, boxIsDraft(previous: previous, current: il, wasDraft: wasDraft, editing: editing))
    }
    guard let t = input?.text, !t.isEmpty else { return (nil, false) }
    return (t, !(input?.suggested ?? true))
}

// MARK: - SSE (GET /api/events)

enum OrchestratorStreamEvent {
    case state(StateResponse)
    case chat(ChatResponse)
    case blocks(running: Bool?, blocks: [ChatBlock], reset: Bool)
    /// nil = serve says none pending.
    case approval(OrchestratorApproval?)
    /// The full deploys list (a bare array or `{"deploys":[…]}`); one bare deploy object is a single upsert by project.
    case deploys([Deploy])
    case deploy(Deploy)
}

/// `URLSession.bytes.lines` drops blank lines, so events are dispatched on each `data:` line using the last `event:` name.
struct SSELineParser {
    private var event: String?
    private struct ResetFlag: Decodable { let reset: Bool? }

    mutating func feed(_ line: String) -> OrchestratorStreamEvent? {
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            event = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        var v = line.dropFirst(5)
        if v.first == " " { v = v.dropFirst() }
        let name = event
        event = nil
        guard let name, v.utf8.count <= 2_000_000 else { return nil }
        let data = Data(v.utf8)
        let dec = JSONDecoder()
        switch name {
        case "state": return (try? dec.decode(StateResponse.self, from: data)).map { .state($0) }
        case "chat": return (try? dec.decode(ChatResponse.self, from: data)).map { .chat($0) }
        case "blocks":
            guard let b = decodeChatBlocks(data) else { return nil }
            return .blocks(running: b.running, blocks: b.blocks, reset: (try? dec.decode(ResetFlag.self, from: data))?.reset ?? false)
        case "approval":
            if v.trimmingCharacters(in: .whitespaces) == "null" { return .approval(nil) }
            return (try? dec.decode(OrchestratorApproval.self, from: data)).map { .approval($0) } // malformed: keep current
        case "deploy":
            if let list = (try? dec.decode(StateResponse.self, from: data))?.deploys { return .deploys(list) }
            if let list = try? dec.decode([Deploy].self, from: data) { return .deploys(list) }
            return (try? dec.decode(Deploy.self, from: data)).map { .deploy($0) }
        default: return nil
        }
    }
}

func streamHealthy(lastLineAt: Date, now: Date, limit: TimeInterval = 20) -> Bool {
    now.timeIntervalSince(lastLineAt) <= limit
}

// MARK: - Caret (08-03)

/// Streaming caret on the newest prose row while a turn is live. serve's `live` wins when present;
/// old serve (nil) falls back to the working status line.
func caretVisible(live: Bool?, working: Bool, kind: ChatBlock.Kind, id: String, newestID: String?) -> Bool {
    (live ?? working) && kind == .prose && id == newestID
}

/// Whether applyChat must GET /api/chat/blocks itself. Polling always does; while streaming the `blocks`
/// event feeds the store, except when a chat event brings a NEW prompt: its context rows must be in the
/// store before the card is published (the blocks event may arrive after the chat event).
func shouldFetchBlocks(streaming: Bool, running: Bool, newPrompt: Bool) -> Bool {
    !(streaming && running) || newPrompt
}
