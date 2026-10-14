import Foundation

func runQuickX18Tests() {
    func act(_ j: String) -> RunActivity? { try? JSONDecoder().decode(RunActivity.self, from: Data(j.utf8)) }
    func line(_ j: String) -> String? { runActivityLine(act(j)) }
    precondition(runActivityLine(nil) == nil)
    precondition(line(#"{"step":null,"agents":[],"doing":""}"#) == nil)
    precondition(line(#"{"agents":[],"doing":"  "}"#) == nil)
    precondition(line(#"{"step":"plan-phase","agents":[{"type":"gsd-planner","desc":"Plan Phase 125"}]}"#) == "plan-phase → gsd-planner · Plan Phase 125")
    precondition(line(#"{"step":"execute-phase","agents":[],"doing":"Create quick dir"}"#) == "execute-phase — Create quick dir")
    precondition(line(#"{"doing":"Waiting on xcodebuild"}"#) == "Waiting on xcodebuild")
    precondition(line(#"{"step":"s","agents":[{"type":"a","desc":"d"},{"type":"b"}]}"#) == "s → a · d → b")
    precondition(act(#"{"step":"x","agents":[],"doing":"y"}"#)?.doing == "y")
    precondition(act(#"{"step":"x"}"#)?.doing == nil)
    precondition(act(#"{"doing":null}"#) != nil)

    func t(_ s: String) -> String? { logToolLine(s).map { $0.tool + "|" + $0.summary } }
    precondition(t(#"[Bash] {"command":"ls; ls .planning 2>/dev/null | head"#) == "Bash|ls; ls .planning 2>/dev/null | head")
    precondition(t(#"[Edit] {"file_path":"/a/b.swift","old_string":"x"#) == "Edit|/a/b.swift")
    precondition(t(#"[Grep] {"pattern":"foo.*bar","path":"x"#) == "Grep|foo.*bar")
    precondition(t(#"[Task] {"description":"Plan it","prompt":"x"#) == "Task|Plan it")
    precondition(t(#"[WebFetch] {"url":"https://x.y","prompt":"x"#) == "WebFetch|https://x.y")
    precondition(t(#"[Weird] {"a":"b"}"#) == "Weird|")
    precondition(t("All tests pass.") == nil && t("RESULT success: done") == nil && t("[not a tool line") == nil)

    for ok in ["261014103917-a29f", "a_B-9"] { precondition(isRunID(ok)) }
    for bad in ["../x", "", "a/b", "a b", String(repeating: "a", count: 65)] { precondition(!isRunID(bad)) }
}
