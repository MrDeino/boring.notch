import Foundation

/// Finished AskUserQuestion blocks (synthetic fixtures in serve's shape) -> the expandable row model.
func runQuickAskTests() {
    func block(_ q: String, answers: String? = nil) -> ChatBlock {
        let a = answers.map { #","answers":\#($0)"# } ?? ""
        let json = #"{"id":"t1","kind":"tool","name":"AskUserQuestion","target":"x","result":"ok","questions":\#(q)\#(a)}"#
        return decodeChatBlocks(Data("[\(json)]".utf8))!.blocks[0]
    }
    let fruit = #"{"header":"Fruit","question":"Which fruit?","multiSelect":false,"options":[{"label":"apple","description":"Crunchy"},{"label":"banana","description":"Soft"},{"label":"cherry"}]}"#
    let color = #"{"header":"Color","question":"Which colors?","multiSelect":true,"options":[{"label":"red","description":"Warm"},{"label":"blue","description":"Cool"},{"label":"green","description":"Leafy"}]}"#

    // Single question.
    let one = askRow(block("[\(fruit)]", answers: #"[{"question":"Which fruit?","selected":["banana"],"other":null,"notes":null}]"#))!
    precondition(one.questions.count == 1 && !one.dismissed)
    precondition(one.questions[0].options.map(\.chosen) == [false, true, false] && one.questions[0].chosen == ["banana"])
    precondition(one.questions[0].options[0].description == "Crunchy" && one.questions[0].options[2].description == nil)
    precondition(one.summary == ["Fruit: banana"])

    // Multi-question, answers in a different order than the questions: matched by question text.
    let two = askRow(block("[\(fruit),\(color)]", answers: #"[{"question":"Which colors?","selected":["red"]},{"question":"Which fruit?","selected":["cherry"]}]"#))!
    precondition(two.summary == ["Fruit: cherry", "Color: red"])
    precondition(two.questions[1].options.map(\.chosen) == [true, false, false])

    // Multi-select with several picks.
    let multi = askRow(block("[\(color)]", answers: #"[{"question":"Which colors?","selected":["red","green"]}]"#))!
    precondition(multi.questions[0].multiSelect && multi.questions[0].options.map(\.chosen) == [true, false, true])
    precondition(multi.summary == ["Color: red, green"])

    // "Other" free text and notes: no option is marked, the text is shown and counted as the pick.
    let other = askRow(block("[\(fruit)]", answers: #"[{"question":"Which fruit?","selected":[],"other":"  mango  ","notes":"ripe please"}]"#))!
    precondition(other.questions[0].options.allSatisfy { !$0.chosen })
    precondition(other.questions[0].other == "mango" && other.questions[0].notes == "ripe please" && other.questions[0].answered)
    precondition(other.summary == ["Fruit: mango"])

    // Unanswered: `answers: []` = dismissed; one question missing from the answers = not answered.
    let dismissed = askRow(block("[\(fruit),\(color)]", answers: "[]"))!
    precondition(dismissed.dismissed && dismissed.questions.allSatisfy { !$0.answered } && dismissed.summary == ["Not answered / dismissed"])
    let partial = askRow(block("[\(fruit),\(color)]", answers: #"[{"question":"Which fruit?","selected":["apple"]}]"#))!
    precondition(!partial.dismissed && partial.questions[0].answered && !partial.questions[1].answered)
    precondition(partial.summary == ["Fruit: apple", "Color: not answered"])

    // Fallback: still waiting (answers null or absent), no questions, empty questions, other tools -> no row, today's plain tool row.
    precondition(askRow(block("[\(fruit)]", answers: "null")) == nil)
    precondition(askRow(block("[\(fruit)]")) == nil)
    precondition(askRow(block("[]", answers: "[]")) == nil)
    let old = decodeChatBlocks(Data(#"[{"id":"t2","kind":"tool","name":"AskUserQuestion","target":"Which fruit?","result":"ok"}]"#.utf8))!.blocks[0]
    precondition(old.questions == nil && old.answers == nil && askRow(old) == nil)
    let bash = decodeChatBlocks(Data(#"[{"id":"t3","kind":"tool","name":"Bash","questions":[],"answers":[]}]"#.utf8))!.blocks[0]
    precondition(askRow(bash) == nil)

    // Lossy decoding: wrong types never fail the block.
    let bad = decodeChatBlocks(Data(#"[{"id":"t4","kind":"tool","name":"AskUserQuestion","questions":"nope","answers":7},{"id":"t5","kind":"tool","name":"AskUserQuestion","questions":[5,{"question":"Q?","options":[1,{"label":"a"}]}],"answers":[{"question":"Q?","selected":"a"}]}]"#.utf8))!.blocks
    precondition(bad.count == 2 && bad[0].questions == nil && bad[0].answers == nil)
    let r = askRow(bad[1])!
    precondition(r.questions.count == 1 && r.questions[0].options.map(\.label) == ["a"] && !r.questions[0].answered)
}
