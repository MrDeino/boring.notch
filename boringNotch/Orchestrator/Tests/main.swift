import Foundation

let d = JSONDecoder()
let a = try! d.decode(ChatResponse.self, from: Data(#"{"running":true,"screen":"a  \n\nb   \n"}"#.utf8))
precondition(a.running == true && a.screen != nil)
precondition(try! d.decode(ChatResponse.self, from: Data(#"{"running":false}"#.utf8)).screen == nil)
precondition(try! d.decode(ChatResponse.self, from: Data("{}".utf8)).running == nil)

precondition(chatTail(screen: a.screen!, maxLines: 10) == ["a", "b"])
precondition(chatTail(screen: "", maxLines: 5) == [])
precondition(chatTail(screen: "1\n2\n3\n4", maxLines: 2) == ["3", "4"])
precondition(chatTail(screen: "x\u{a0}\u{a0} \ny \u{a0}", maxLines: 5) == ["x", "y"])

let box = "─────────────────  \n❯\u{a0}merge 199" + String(repeating: " ", count: 150) + "\n─────────────────  \n  ? for shortcuts   \n"
let t = chatTail(screen: box, maxLines: 8)
precondition(t.count == 4)
precondition(t[1] == "❯\u{a0}merge 199")
print("OK")
