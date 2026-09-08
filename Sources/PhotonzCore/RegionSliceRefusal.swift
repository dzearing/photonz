import Foundation

/// Why a marquee cannot work on a piece of the layer you picked, in the words
/// the canvas says it in.
///
/// A marquee says WHERE and the picked layer says WHAT (`RegionTarget`), and
/// most of the time those two agree. They do not when the thing you picked is
/// not made of pixels: a rectangle, a piece of text, an arrow or a measurement
/// is a description of a drawing, not the drawing itself, so there is no
/// bitmap for a hole to go in.
///
/// Before this, all three keys answered that by lying. Cut took the WHOLE layer
/// and put it on the clipboard, so a marquee over half a rectangle made the
/// whole rectangle disappear; delete and fill did nothing at all and said
/// nothing about it. Either way the person is left looking at a marquee over a
/// result they did not ask for, with no idea which part of what they did was
/// wrong. A refusal with a reason costs one line and is the whole difference.
///
/// Session chrome only: it rides `CopyConfirmation` to the notice pill at the
/// bottom of the canvas and never enters the document or the undo history.
public struct RegionSliceRefusal: Hashable, Sendable {
    /// The key that was pressed, because the way out differs: clearing the
    /// marquee makes ⌘X cut the whole layer, ⌫ delete it, and ⌥⌫ fill it.
    public enum Action: Hashable, Sendable {
        /// ⌘X.
        case cut
        /// ⌫ with a marquee up.
        case erase
        /// ⌥⌫ with a marquee up. It was the last key in the family still
        /// going quiet: filling half a rectangle did nothing and said
        /// nothing, while the other two had already learned to explain
        /// themselves over the very same marquee.
        case fill
    }

    /// Why this layer cannot take it, which is the half a person can act on.
    public enum Reason: Hashable, Sendable {
        /// There is no bitmap at all and nothing can make one: a measurement,
        /// a zoom callout, a group. Nothing about the marquee will help, so
        /// the words point at the layer.
        case notPixels
        /// There is no bitmap YET: a shape or a piece of text, which one
        /// command turns into pixels (`RasterizePrompt`). This is the half the
        /// refusal used to be missing. Saying only "only a picture can have a
        /// piece taken out" leaves a person holding a marquee over a rectangle
        /// with nowhere to go, when a picture is one menu row away.
        case canBecomeAPicture
        /// It IS a picture, but it has been cropped or turned, and the region
        /// path maps into the bitmap through the layer's frame, so that
        /// mapping no longer tells the truth. The words must not send someone
        /// looking for a picture they are already holding.
        case adjustedPicture
    }

    public var action: Action
    public var reason: Reason

    public init(action: Action, reason: Reason) {
        self.action = action
        self.reason = reason
    }

    /// The refusal this layer would raise, or nil when it can be sliced.
    ///
    /// The yes/no half is `RegionTarget.canSlice` and nothing else, so the
    /// sentence on screen can never disagree with what the keys actually do.
    public static func refusal(for layer: Layer, action: Action) -> RegionSliceRefusal? {
        guard !RegionTarget.canSlice(layer) else { return nil }
        let reason: Reason
        if layer.imageRef != nil {
            reason = .adjustedPicture
        } else {
            reason = layer.isRasterizable ? .canBecomeAPicture : .notPixels
        }
        return RegionSliceRefusal(action: action, reason: reason)
    }

    /// The verdict, set in its own weight at the head of the pill: what the key
    /// you just pressed did not do.
    public var title: String {
        switch action {
        case .cut: return "Cannot cut a piece out"
        case .erase: return "Cannot delete a piece"
        case .fill: return "Cannot fill a piece"
        }
    }

    /// One line: why, then the thing to do instead. The way out is always the
    /// same one, because the whole layer is what all three keys fall back to
    /// once the marquee is gone.
    public var detail: String {
        let wayOut: String
        switch action {
        case .cut: wayOut = "Clear the marquee to cut the whole layer."
        case .erase: wayOut = "Clear the marquee to delete the whole layer."
        case .fill: wayOut = "Clear the marquee to fill the whole layer."
        }
        switch reason {
        case .notPixels:
            return "Only a picture can have \(pieceClause). \(wayOut)"
        case .canBecomeAPicture:
            // The one way out that gets the person what they actually asked
            // for, so it is the only one printed: clearing the marquee is on
            // the other two lines, and it takes the WHOLE layer, which is not
            // what someone who drew a marquee over half of something wants.
            return "Only a picture can have \(pieceClause). "
                + "Turn it into a picture from the Layer menu, then try again."
        case .adjustedPicture:
            return "This picture is cropped or turned. \(wayOut)"
        }
    }

    /// What the key was going to do to the piece, which is the only word the
    /// three sentences differ by. ⌥⌫ puts colour INTO the marquee rather than
    /// taking anything out of it, and a line that says a piece was taken out
    /// when a person asked for it to be painted is a line they have to stop
    /// and reread.
    private var pieceClause: String {
        switch action {
        case .cut, .erase: return "a piece taken out"
        case .fill: return "a piece filled in"
        }
    }
}
