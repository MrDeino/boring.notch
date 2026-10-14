import Foundation

func runQuickQeiTests() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func u(_ id: String, _ t: String) -> ChatBlock { ChatBlock(pendingID: id, text: t) }
    func p(_ id: Int, _ t: String, _ s: PendingMessage.State, sentAt: Date? = nil) -> PendingMessage {
        PendingMessage(id: id, text: t, state: s, sentAt: sentAt)
    }
    precondition(normalizeChatText("  a\n  b\u{a0} c  ") == "a b c")

    var r = reconcilePending([p(1, "fix the  build", .sent, sentAt: now)], blocks: [u("u1", "fix the\nbuild")], known: [], now: now)
    precondition(r.pending.isEmpty && r.known == ["u1"])

    r = reconcilePending([p(1, "x", .sent, sentAt: now)], blocks: [u("u1", "x")], known: ["u1"], now: now)
    precondition(r.pending.count == 1 && r.known == ["u1"])

    r = reconcilePending([p(1, "x", .queued)], blocks: [u("u1", "x")], known: [], now: now)
    precondition(r.pending.count == 1 && r.known.isEmpty)

    let two = [p(1, "ok", .sent, sentAt: now), p(2, "ok", .sent, sentAt: now)]
    r = reconcilePending(two, blocks: [u("a", "ok")], known: [], now: now)
    precondition(r.pending.map(\.id) == [2])
    r = reconcilePending(two, blocks: [u("a", "ok"), u("b", "ok")], known: [], now: now)
    precondition(r.pending.isEmpty && r.known == ["a", "b"])

    r = reconcilePending([p(1, "x", .sent, sentAt: now)], blocks: [u("u3", "x"), u("u5", "x")], known: [], now: now)
    precondition(r.known == ["u5"])

    r = reconcilePending([p(1, "x", .failed)], blocks: [u("u1", "x")], known: [], now: now)
    precondition(r.pending.isEmpty)

    let old = now.addingTimeInterval(-31)
    r = reconcilePending([p(1, "a", .sent, sentAt: old), p(2, "b", .sending), p(3, "c", .failed)], blocks: [], known: [], now: now)
    precondition(r.pending.map(\.id) == [2, 3])

    let prose = decodeChatBlocks(Data(#"{"blocks":[{"id":"p1","kind":"prose","text":"x"}]}"#.utf8))!.blocks
    r = reconcilePending([p(1, "x", .sent, sentAt: now)], blocks: prose, known: [], now: now)
    precondition(r.pending.count == 1)
}
