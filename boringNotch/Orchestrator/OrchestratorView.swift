import SwiftUI

struct OrchestratorView: View {
    @ObservedObject var manager = OrchestratorManager.shared

    var body: some View {
        Group {
            if !manager.hasLoaded {
                Text("connecting…").font(.system(size: 11)).foregroundStyle(.gray)
            } else if manager.offline {
                VStack(spacing: 4) {
                    Image(systemName: "bolt.horizontal.circle").font(.system(size: 22)).foregroundStyle(.gray)
                    Text("orchestrator offline").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                    Text("start `node orch.js serve` · 127.0.0.1:4777").font(.system(size: 11)).foregroundStyle(.gray)
                }
            } else if !manager.chatRunning {
                Text("chat not running").font(.system(size: 11)).foregroundStyle(.gray)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(chatTail(screen: manager.screen, maxLines: 8).enumerated()), id: \.offset) { _, line in
                        Text(verbatim: line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }
}
