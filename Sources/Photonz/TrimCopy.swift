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
