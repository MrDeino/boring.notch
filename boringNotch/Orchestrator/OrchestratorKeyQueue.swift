import Foundation

/// Prompt-card keys, delivered to serve one POST at a time in the order they were tapped. Taps return at once;
/// the single sender runs back-to-back (each POST waits for serve's 200, which is the pace the pty accepts), so a
/// key is never dropped, doubled or reordered. A failed send discards what is still queued and reports it once.
@MainActor
final class PromptKeyQueue {
    private let send: (String) async -> Bool
    private var queued: [String] = []
    private var worker: Task<Void, Never>?
    private var failed = false

    init(send: @escaping (String) async -> Bool) { self.send = send }

    var isIdle: Bool { worker == nil }

    func enqueue(_ keys: [String]) {
        queued += keys
        if worker == nil { worker = Task { await run() } }
    }

    /// Unsent keys belong to a card that is gone: drop them.
    func cancel() { queued = [] }

    /// Waits until every key enqueued so far is sent. False (once) if a send failed since the last settle.
    func settle() async -> Bool {
        while let w = worker { await w.value }
        defer { failed = false }
        return !failed
    }

    private func run() async {
        while !queued.isEmpty {
            let k = queued.removeFirst()
            if !(await send(k)) { queued = []; failed = true }
        }
        worker = nil
    }
}

/// Checkbox numbers whose optimistic state the screen disagrees with (a key was lost or doubled).
func promptMismatches(expected: [Int: Bool], card: PromptCard) -> [Int] {
    expected.compactMap { n, v in card.items.first { $0.number == n }?.checked == v ? nil : n }.sorted()
}
