import Foundation

// Quick jlm: chat never loses, reorders or drops messages (audit B1-B4). Synthetic blocks only.
func runQuickJlmTests() {
    func b(_ id: String, _ kind: String = "prose", result: String? = nil) -> ChatBlock {
        let r = result.map { "\"\($0)\"" } ?? "null"
        return try! JSONDecoder().decode(ChatBlock.self, from: Data(#"{"id":"\#(id)","kind":"\#(kind)","result":\#(r)}"#.utf8))
    }
    func ids(_ l: [ChatBlock]) -> [String] { l.map(\.id) }

    // B2: a filled gap lands in place, a leading unknown block goes before what it precedes, plain appends unchanged.
    precondition(ids(mergeChatBlocks([b("A"), b("C")], [b("A"), b("B"), b("C")], reset: false).blocks) == ["A", "B", "C"])
    precondition(ids(mergeChatBlocks([b("B"), b("C")], [b("A"), b("B")], reset: false).blocks) == ["A", "B", "C"])
    precondition(ids(mergeChatBlocks([b("A"), b("B")], [b("C"), b("D")], reset: false).blocks) == ["A", "B", "C", "D"])
    precondition(ids(mergeChatBlocks([b("A"), b("D")], [b("A"), b("B"), b("C"), b("D"), b("E")], reset: false).blocks) == ["A", "B", "C", "D", "E"])
    precondition(ids(mergeChatBlocks([b("A")], [b("A"), b("B"), b("B")], reset: false).blocks) == ["A", "B"])

    // B1: a late full fetch keeps a block the stream added meanwhile, and a stream update beats the stale copy.
    let snap = [b("A"), b("T", "tool")]
    let cur = [b("A"), b("T", "tool", result: "ok"), b("Z")]
    let m = mergeFullFetch(current: cur, snapshot: snap, incoming: [b("A"), b("T", "tool")])
    precondition(ids(m) == ["A", "T", "Z"] && m[1].result == "ok")
    // A fetch with more history than we held fills it in order, newer stream blocks stay last.
    precondition(ids(mergeFullFetch(current: [b("B"), b("Z")], snapshot: [b("B")], incoming: [b("A"), b("B")])) == ["A", "B", "Z"])
    // A real /clear (snapshot's last block gone) replaces, keeping only what arrived during the fetch.
    precondition(ids(mergeFullFetch(current: snap, snapshot: snap, incoming: [b("X"), b("Y")])) == ["X", "Y"])
    precondition(ids(mergeFullFetch(current: snap + [b("Y2")], snapshot: snap, incoming: [b("X"), b("Y")])) == ["X", "Y", "Y2"])
    precondition(ids(mergeFullFetch(current: [], snapshot: [], incoming: [b("X")])) == ["X"])

    // B3: a sent row isn't stale while the turn is live; the 30 s starts at the later of send and turn end.
    let now = Date(timeIntervalSince1970: 2_000_000)
    let sent = [PendingMessage(id: 1, text: "queued mid-turn", state: .sent, sentAt: now.addingTimeInterval(-120))]
    precondition(reconcilePending(sent, blocks: [], known: [], now: now, idleSince: nil).pending.count == 1)
    precondition(reconcilePending(sent, blocks: [], known: [], now: now, idleSince: now.addingTimeInterval(-10)).pending.count == 1)
    precondition(reconcilePending(sent, blocks: [], known: [], now: now, idleSince: now.addingTimeInterval(-31)).pending.isEmpty)
    precondition(reconcilePending(sent, blocks: [], known: [], now: now).pending.isEmpty) // default: old behaviour
    let rec = reconcilePending(sent, blocks: [ChatBlock(pendingID: "u9", text: "queued mid-turn")], known: [], now: now, idleSince: nil)
    precondition(rec.pending.isEmpty && rec.known == ["u9"]) // recorded at turn end: the row hands over to the block

    // B4: the chat coming back while streaming resyncs the history.
    precondition(shouldFetchBlocks(streaming: true, running: true, newPrompt: false, cameBack: true))
    precondition(!shouldFetchBlocks(streaming: true, running: true, newPrompt: false, cameBack: false))
}
