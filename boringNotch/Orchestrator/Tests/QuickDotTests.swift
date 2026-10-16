import Foundation

// Fixtures multiq3-1/2/3 are modeled on multiq-tab2.txt, multiq3-review on review-submit.txt and multiq3-done on
// inputbox.txt (real Claude Code 2.1.299 captures), with three single-select questions Fruit, Color, Size.

func runQuickDotTests() {
    let names = ["multiq3-1", "multiq3-2", "multiq3-3", "multiq3-review"]
    let cards = names.map { detectPromptCard(screen: fixture($0))! }
    let heads = ["Fruit", "Color", "Size"]
    for i in 0..<3 {
        let c = cards[i]
        precondition(c.kind == .question && !c.review)
        precondition(c.tabs.map(\.label) == ["Fruit", "Color", "Size", "Submit"])
        precondition(c.header == heads[i] && c.progress == "\(i + 1) of 3" && c.currentTab == i)
        precondition(!hidesOnAnswer(c, keys: ["1"]))
    }
    for i in 0..<3 { precondition(promptIdentity(cards[i]) != promptIdentity(cards[i + 1])) }

    let r = cards[3]
    precondition(r.review && r.items.map(\.label) == ["Submit answers", "Cancel"] && r.currentTab == 3)
    precondition(hidesOnAnswer(r, keys: ["1"]) && hidesOnAnswer(r, keys: ["2"]))

    precondition(detectPromptCard(screen: fixture("multiq3-done")) == nil)
    precondition(detectPrompt(screen: fixture("multiq3-done")).isEmpty)

    precondition(hidesOnAnswer(detectPromptCard(screen: fixture("question"))!, keys: ["1"]))
    precondition(hidesOnAnswer(detectPromptCard(screen: fixture("permission"))!, keys: ["1"]))
    for c in cards + [detectPromptCard(screen: fixture("multiselect-single"))!] {
        precondition(!hidesOnAnswer(c, keys: ["Tab"]) && !hidesOnAnswer(c, keys: [promptBackKey]))
    }
}
