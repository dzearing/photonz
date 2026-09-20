import PhotonzCore
import SwiftUI

/// The words the trim row and its handles use for the one gesture on this
/// surface that takes a modifier.
///
/// Named here rather than typed into the view because it is the one sentence
/// that has to reach somebody who does not know the key exists, and the next
/// place that wants to say it (a guide, a menu item, the row itself) must say
/// it in exactly these words.
///
/// The row was tried and put back: a pill beside the piece count ran straight
/// into the centred transport, which is drawn over the same strip.
enum TrimCopy {
    /// How to get past a cut the magnet keeps taking. The quiet second line of
    /// a trim handle's tooltip, where every other control on that row names
    /// its key.
    static let freeKeyHint = "hold ⌘ to ignore cuts"
}

/// What a speed is called where it is offered. `Normal` rather than `100%`,
/// because the one everybody picks is the one going back to how it was
/// recorded and nobody thinks of that as a percentage.
enum VideoSpeedNames {
    static func title(_ percent: Int) -> String {
        switch percent {
        case ClipPiece.asRecordedPercent: return "Normal"
        case let p where p < 100: return "\(fraction(p)) Speed"
        default: return "\(percent / 100)x Speed"
        }
    }

    /// `Half`, `Quarter`, else the percentage itself.
    private static func fraction(_ percent: Int) -> String {
        switch percent {
        case 50: return "Half"
        case 25: return "Quarter"
        default: return "\(percent)%"
        }
    }
}
