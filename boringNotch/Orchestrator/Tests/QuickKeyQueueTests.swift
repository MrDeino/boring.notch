import Foundation

/// The prompt-card key queue: order, no drops, flush on failure, settle waits; and the screen comparison behind reconcile.
@MainActor
func runQuickKeyQueueTests() async {
    var sent: [String] = []
    var failOn: String?
    let q = PromptKeyQueue { k in
        try? await Task.sleep(for: .milliseconds(20)) // a POST in flight
        if k == failOn { return false }
        sent.append(k)
        return true
    }
    // Three rapid taps return at once; nothing is sent yet, and all three arrive in tap order.
    q.enqueue(["1"]); q.enqueue(["2"]); q.enqueue(["3"])
    precondition(sent.isEmpty && !q.isIdle)
    var ok = await q.settle()
    precondition(ok && sent == ["1", "2", "3"] && q.isIdle)
    // Keys enqueued while the sender is mid-drain join the same run, behind the earlier ones; a submit enqueued last goes last.
    q.enqueue(["1"])
    try? await Task.sleep(for: .milliseconds(5))
    q.enqueue(["2", "Tab"])
    ok = await q.settle()
    precondition(ok && sent == ["1", "2", "3", "1", "2", "Tab"])
    // A failed send discards the rest (they would land on the wrong state), reports once, and the queue works again.
    sent = []; failOn = "2"
    q.enqueue(["1", "2", "3"])
    ok = await q.settle()
    precondition(!ok && sent == ["1"] && q.isIdle)
    failOn = nil
    ok = await q.settle()
    precondition(ok)
    q.enqueue(["3"])
    ok = await q.settle()
    precondition(ok && sent == ["1", "3"])
    // cancel drops what is unsent (Esc).
    sent = []
    q.enqueue(["1", "2", "3"])
    try? await Task.sleep(for: .milliseconds(30))
    q.cancel()
    ok = await q.settle()
    precondition(ok && sent.count < 3 && sent.first == "1")

    // Reconcile's comparison: ticks 1 and 3 shown; a lost key shows up as a mismatch, a matching screen as none.
    let blank = detectPromptCard(screen: fixture("multiselect-1"))!
    let both = detectPromptCard(screen: fixture("multiselect-toggled"))! // 1 and 3 ticked
    precondition(promptMismatches(expected: [1: true, 3: true], card: both).isEmpty)
    precondition(promptMismatches(expected: [1: true, 3: true], card: blank) == [1, 3])
    precondition(promptMismatches(expected: [1: true, 2: true, 3: true], card: both) == [2])
    precondition(promptMismatches(expected: [:], card: blank).isEmpty)
}
