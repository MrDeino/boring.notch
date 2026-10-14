import Foundation

// Phase 8 pure code (harness-compiled): Foundation only.

/// Composer box text and draft flag. Old serve (no `input` key) keeps the Phase 5 heuristic;
/// new serve's `input` is exact: suggested = ghost suggestion, not suggested = typed draft.
func resolveInput(hasKey: Bool, input: ChatInput?, screen: String, chatRunning: Bool,
                  previous: String?, wasDraft: Bool, editing: Bool) -> (line: String?, draft: Bool) {
    guard chatRunning else { return (nil, false) }
    if !hasKey {
        let il = parseInputLine(screen: screen)
        return (il, boxIsDraft(previous: previous, current: il, wasDraft: wasDraft, editing: editing))
    }
    guard let t = input?.text, !t.isEmpty else { return (nil, false) }
    return (t, !(input?.suggested ?? true))
}
