import Foundation

/// Synthetic background agents / monitors for the row and card scenes (dates relative to now).
func snapBgTasks() -> String {
    let iso = ISO8601DateFormatter()
    func t(_ ago: TimeInterval) -> String { "\"" + iso.string(from: Date().addingTimeInterval(-ago)) + "\"" }
    return """
    [{"kind":"agent","id":"a1","description":"Survey the widget modules","status":"running","startedAt":\(t(95)),"endedAt":null,"lastStep":"Grep: widget",
      "steps":[{"at":\(t(80)),"tool":"Glob","summary":"src/**/*.widget"},{"at":\(t(60)),"tool":"Read","summary":"src/alpha/widget.txt"},{"at":\(t(40)),"tool":"Read","summary":"src/beta/widget.txt"},{"at":\(t(20)),"tool":"Grep","summary":"widget"}],
      "report":null,"tokens":null,"toolUses":4},
     {"kind":"agent","id":"a2","description":"Draft the release notes","status":"done","startedAt":\(t(900)),"endedAt":\(t(770)),"lastStep":"Write: notes.md",
      "steps":[{"at":\(t(850)),"tool":"Read","summary":"CHANGELOG.txt"},{"at":\(t(800)),"tool":"Write","summary":"notes.md"}],
      "report":"**Release notes** are drafted.\\n\\n- Added the *sample* feature\\n- Fixed `parse()` on empty input\\n- Renamed two settings\\n\\nNothing else changed; the notes are in `notes.md`.","tokens":18400,"toolUses":7},
     {"kind":"agent","id":"a3","description":"Check the example endpoint","status":"failed","startedAt":\(t(600)),"endedAt":\(t(570)),"lastStep":"Bash: curl",
      "steps":[{"at":\(t(590)),"tool":"Bash","summary":"curl https://example.test/health"}],"report":"The endpoint did not answer within 10 seconds.","tokens":900,"toolUses":1},
     {"kind":"monitor","id":"m1","description":"Watch the build log","status":"running","startedAt":\(t(1800)),"endedAt":null,"lastStep":"line 40: ok",
      "steps":[{"at":\(t(30)),"tool":"event","summary":"line 36: compiling alpha"},{"at":\(t(20)),"tool":"event","summary":"line 38: compiling beta"},{"at":\(t(5)),"tool":"event","summary":"line 40: ok"}],"report":null,"tokens":null,"toolUses":null},
     {"kind":"monitor","id":"m2","description":"Watch the queue depth","status":"stopped","startedAt":\(t(3000)),"endedAt":\(t(1200)),"lastStep":null,"steps":[],"report":null,"tokens":null,"toolUses":null}]
    """
}
