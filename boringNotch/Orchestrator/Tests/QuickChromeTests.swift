import Foundation

func runQuickChromeTests() {
    // Review step with the input box's rules and the titled session rule right under "2. Cancel".
    let c = detectPromptCard(screen: fixture("review-chrome"))!
    precondition(c.review && c.items.map(\.label) == ["Submit answers", "Cancel"])
    precondition(c.items.allSatisfy { $0.detail == nil })

    // Same on a question: a real description is kept, the chrome under the last option never is.
    let heavy = String(repeating: "━", count: 30), titled = "─── Upstairs printer slow to print ──"
    let q = "\(heavy)\n☐ Pet\n\nWhich pet?\n\n❯ 1. Cat\n     Purrs.\n  2. Dog\n\(titled)\n\(heavy)\nEnter to select · Esc to cancel\n"
    let p = detectPromptCard(screen: q)!
    precondition(p.items.map(\.detail) == ["Purrs.", nil])
}
