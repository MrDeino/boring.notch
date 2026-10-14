import SwiftUI

// Snapshot harness only: minimal stand-ins for the app types the Orchestrator views touch.
// Not part of the Xcode target (Orchestrator files are listed explicitly in project.pbxproj).

enum NotchState { case closed, open }
enum NotchViews { case home, shelf, orchestrator }

let openNotchSize = CGSize(width: 640, height: 190)
let shadowPadding: CGFloat = 20
let windowSize = CGSize(width: openNotchSize.width, height: openNotchSize.height + shadowPadding)
let cornerRadiusInsets: (opened: (top: CGFloat, bottom: CGFloat), closed: (top: CGFloat, bottom: CGFloat)) = (opened: (top: 19, bottom: 24), closed: (top: 6, bottom: 14))

final class BoringViewModel: NSObject, ObservableObject {
    @Published var notchState: NotchState = .open
    @Published var hideOnClosed = false
    @Published var notchSize = openNotchSize
    @Published var closedNotchSize = CGSize(width: 185, height: 34)
    @Published var screenUUID: String? = nil
    var effectiveClosedNotchHeight: CGFloat { closedNotchSize.height }
    func close() {}
}

final class BoringViewCoordinator: ObservableObject {
    static let shared = BoringViewCoordinator()
    @Published var currentView: NotchViews = .orchestrator
    var musicLiveActivityEnabled = false
    var helloAnimationRunning = false
}

final class MusicManager: ObservableObject {
    static let shared = MusicManager()
    @Published var isPlaying = false
    @Published var isPlayerIdle = true
}

final class SharingStateManager {
    static let shared = SharingStateManager()
    func beginInteraction() {}
    func endInteraction() {}
}

extension NSScreen {
    @MainActor static func screen(withUUID uuid: String) -> NSScreen? { nil }
}
