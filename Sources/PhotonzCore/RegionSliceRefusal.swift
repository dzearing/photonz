import Foundation

/// Why a marquee cannot take a piece out of the layer you picked, in the words
/// the canvas says it in.
///
/// A marquee says WHERE and the picked layer says WHAT (`RegionTarget`), and
/// most of the time those two agree. They do not when the thing you picked is
/// not made of pixels: a rectangle, a piece of text, an arrow or a measurement
/// is a description of a drawing, not the drawing itself, so there is no
/// bitmap for a hole to go in.
///
/// Before this, both keys answered that by lying. Cut took the WHOLE layer and
/// put it on the clipboard, so a marquee over half a rectangle made the whole
/// rectangle disappear; delete did nothing at all and said nothing about it.
/// Either way the person is left looking at a marquee over a result they did
/// not ask for, with no idea which part of what they did was wrong. A refusal
/// with a reason costs one line and is the whole difference.
///
/// Session chrome only: it rides `CopyConfirmation` to the notice pill at the
/// bottom of the canvas and never enters the document or the undo history.
public struct RegionSliceRefusal: Hashable, Sendable {
    /// The key that was pressed, because the way out differs: clearing the
    /// marquee makes ⌘X cut the whole layer and ⌫ delete it.
    public enum Action: Hashable, Sendable {
        /// ⌘X.
        case cut
        /// ⌫ with a marquee up.
        case erase
    }

    /// Why this layer cannot take it, which is the half a person can act on.
    public enum Reason: Hashable, Sendable {
        /// There is no bitmap at all: a shape, text, a measurement, a group.
        /// Nothing about the marquee will help, so the words point at the
        /// layer.
        case notPixels
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
        return RegionSliceRefusal(action: action,
                                  reason: layer.imageRef == nil ? .notPixels : .adjustedPicture)
    }

    /// The verdict, set in its own weight at the head of the pill: what the key
    /// you just pressed did not do.
    public var title: String {
        switch action {
        case .cut: return "Cannot cut a piece out"
        case .erase: return "Cannot delete a piece"
        }
    }

    /// One line: why, then the thing to do instead. The way out is always the
    /// same one, because the whole layer is what both keys fall back to once
    /// the marquee is gone.
    public var detail: String {
        let wayOut: String
        switch action {
        case .cut: wayOut = "Clear the marquee to cut the whole layer."
        case .erase: wayOut = "Clear the marquee to delete the whole layer."
        }
        switch reason {
        case .notPixels:
            return "Only a picture can have a piece taken out. \(wayOut)"
        case .adjustedPicture:
            return "This picture is cropped or turned. \(wayOut)"
        }
    }
}
