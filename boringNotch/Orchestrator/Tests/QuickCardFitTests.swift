import Foundation
import CoreGraphics

/// A prompt card's fit: grow to content past the zero-fit card, nothing when it already fits, and the cap.
func runQuickCardFitTests() {
    precondition(promptFitExtra(need: 100) == 0)
    precondition(promptFitExtra(need: promptCardBase) == 0)
    precondition(promptFitExtra(need: promptCardBase + 87.4) == 87)
    // Taller content asks for more, so a longer question or the next multi-question step resizes the notch.
    precondition(promptFitExtra(need: 389) > promptFitExtra(need: 233) && promptFitExtra(need: 233) > promptFitExtra(need: 181))
    // The cap: most of the screen below the menu bar, never below the expanded height.
    precondition(promptCardMaxHeight(screen: CGSize(width: 1440, height: 900)) == 820)
    precondition(promptCardMaxHeight(screen: CGSize(width: 1440, height: 900)) > expandedSize(screen: CGSize(width: 1440, height: 900)).height)
    precondition(promptCardMaxHeight(screen: CGSize(width: 800, height: 500)) == expandedSize(screen: CGSize(width: 800, height: 500)).height)
}
