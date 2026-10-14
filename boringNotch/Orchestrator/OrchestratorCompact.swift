import SwiftUI

/// Closed-notch overlay: attention dot + usage hairline. Overlay only, no layout effect.
struct OrchestratorClosedIndicators: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var manager = OrchestratorManager.shared
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var wings = OrchestratorWingsModel.shared
    @ObservedObject var music = MusicManager.shared

    var hardwareHeightOverride: CGFloat? = nil // snapshots only

    /// Bottom of the hardware notch / menu-bar band on the notch's screen, 0 on a notch-less display.
    private var hardwareNotchHeight: CGFloat {
        if let h = hardwareHeightOverride { return h }
        guard let sc = vm.screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }), sc.safeAreaInsets.top > 0 else { return 0 }
        return max(sc.safeAreaInsets.top, sc.frame.maxY - sc.visibleFrame.maxY)
    }

    /// The wing or the music dot already shows the attention state.
    private var dotCovered: Bool {
        if case .needsYou = wings.kind { return true }
        return (music.isPlaying || !music.isPlayerIdle) && coordinator.musicLiveActivityEnabled
    }

    var body: some View {
        if vm.notchState == .closed && !vm.hideOnClosed && vm.effectiveClosedNotchHeight > 0
            && !coordinator.helloAnimationRunning && !manager.offline {
            ZStack {
                if manager.needsAttention && !dotCovered {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                        .padding(.trailing, 10).padding(.top, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if let f = usageFraction(manager.usage) {
                    GeometryReader { g in
                        let r = usageHairlineRect(shape: g.size, notchWidth: vm.closedNotchSize.width, hardwareHeight: hardwareNotchHeight, fraction: f)
                        Capsule().fill(f >= 0.8 ? Color.orange : Color.white.opacity(0.5))
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}
