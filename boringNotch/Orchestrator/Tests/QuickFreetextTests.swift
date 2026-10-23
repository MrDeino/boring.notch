import Foundation

/// Typed answer: pressing the free-text row's number only moves the ❯ onto an inline input (Claude Code 2.1.309);
/// the prompt identity stays the same, so "ready to type" is the ❯ on that row, and a multi-question card stays up.
func runQuickFreetextTests() {
    for (name, tabs) in [("freetext-1q", 1), ("freetext-2q", 2)] {
        let before = detectPromptCard(screen: fixture("\(name)-before"))!
        let focused = detectPromptCard(screen: fixture("\(name)-focused"))!
        precondition(promptIdentity(before) == promptIdentity(focused)) // why the old "left the screen" wait never saw it land
        let ft = before.items.first { $0.role == .freeText }!
        precondition(!freeTextFocused(before, number: ft.number) && freeTextFocused(focused, number: ft.number))
        precondition(!freeTextFocused(nil, number: ft.number) && !freeTextFocused(focused, number: 1))
        // Single question: the card hides while sending; with several the next question replaces it, so it stays.
        precondition(hidesOnAnswer(before, keys: []) == (tabs == 1))
    }
    var perm = detectPromptCard(screen: fixture("permission"))!
    perm.highlighted = 3
    precondition(!freeTextFocused(perm, number: 3))
}
