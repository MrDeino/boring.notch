import SwiftUI

// Phase 6 owns this file; Phase 4 holds today's option buttons.
struct OrchestratorPromptCard: View {
    @ObservedObject var manager = OrchestratorManager.shared

    var body: some View {
        HStack(spacing: 6) {
            // Free-text answers aren't supported from the notch yet, so don't offer a dead-end button.
            ForEach(manager.promptOptions.filter { $0.label != "Type something." }, id: \.number) { o in
                Button { manager.pressOption(o.number) } label: {
                    Text(verbatim: "\(o.number) \(o.label)").lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 120)
                }
                .disabled(manager.optionsLocked || manager.sending)
            }
            Spacer(minLength: 0)
            Button("esc") { Task { await manager.pressEscape() } }
                .disabled(manager.sending)
        }
        .font(.system(size: 10))
        .controlSize(.small)
    }
}
