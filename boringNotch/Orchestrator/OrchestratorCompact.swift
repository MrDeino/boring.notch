import SwiftUI

/// Closed-notch overlay: attention dot. Overlay only, no layout effect.
struct OrchestratorClosedIndicators: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var wings = OrchestratorWingsModel.shared
    @ObservedObject var inputs = OrchestratorWingsInputs.shared
    @ObservedObject var music = MusicManager.shared
    @ObservedObject var approvals = OrchestratorApprovalCenter.shared
    @ObservedObject var manager = OrchestratorManager.shared

    /// The wing or the music dot already shows the attention state.
    private var dotCovered: Bool {
        if case .needsYou = wings.kind { return true }
        return (music.isPlaying || !music.isPlayerIdle) && coordinator.musicLiveActivityEnabled
    }

    var body: some View {
        if vm.notchState == .closed && !vm.hideOnClosed && vm.effectiveClosedNotchHeight > 0
            && !coordinator.helloAnimationRunning && approvals.approval == nil {
            ZStack {
                if !manager.offline && bgRunningCount(manager.bgTasks) > 0 { // background work is running
                    Circle().fill(OT.C.run).frame(width: 6, height: 6)
                        .padding(.trailing, inputs.attentionDot && !dotCovered ? 20 : 10).padding(.top, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if inputs.attentionDot && !dotCovered {
                    Circle().fill(.orange).frame(width: 6, height: 6)
                        .padding(.trailing, 10).padding(.top, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
