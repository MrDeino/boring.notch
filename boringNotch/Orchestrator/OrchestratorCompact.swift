import SwiftUI

/// Closed-notch overlay: attention dot + usage hairline. Overlay only, no layout effect.
struct OrchestratorClosedIndicators: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared

    var body: some View {
        if vm.notchState == .closed && !vm.hideOnClosed && vm.effectiveClosedNotchHeight > 0
            && !coordinator.helloAnimationRunning && !manager.offline {
            ZStack {
                if manager.needsAttention {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                        .padding(.trailing, 10).padding(.top, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if let f = usageFraction(manager.usage) {
                    GeometryReader { g in
                        Capsule().fill(f >= 0.8 ? Color.orange : Color.white.opacity(0.5))
                            .frame(width: max(0, g.size.width - 28) * f, height: 2)
                            .position(x: 14 + max(0, g.size.width - 28) * f / 2, y: g.size.height - 1)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
