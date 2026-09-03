import CoreGraphics
import Foundation

/// One frame's name as it sits on the canvas: which frame it belongs to, the
/// box that frame draws in (view space, top-left origin), and how wide the name
/// itself measured out.
///
/// The width matters because the label BOX is generous — up to 240 points, so a
/// long name has room — while the name inside it may be four letters. Only the
/// letters answer a click; the empty space beside them is still bare canvas.
public struct FrameNameLabel: Hashable, Sendable, Identifiable {
    public let id: UUID
    /// Where the frame draws, in view points.
    public let frameRect: CGRect
    /// How wide the name draws, in view points.
    public let textWidth: CGFloat

    public init(id: UUID, frameRect: CGRect, textWidth: CGFloat) {
        self.id = id
        self.frameRect = frameRect
        self.textWidth = textWidth
    }
}

/// Where a frame's name draws, and what a click on it means.
///
/// The name hangs above a frame's top left corner and is the same size at every
/// zoom, so all of this is view-space geometry rather than document geometry.
/// It lives here, away from AppKit, because the interesting part is a rule
/// rather than a drawing call: **the letters are the target, the box is not.**
/// A frame called "Home" prints thirty points of text in a box that may be two
/// hundred wide, and a click on the empty part of that box has to keep meaning
/// what it always meant on bare canvas.
public enum FrameNameLabels {

    /// The distance from a frame's top edge up to the strip its name sits in.
    /// Close enough to belong to the frame, clear enough not to touch it.
    public static let gap: CGFloat = 4
    /// The height of that strip.
    public static let height: CGFloat = 14
    /// The widest a name box gets, however long the name is.
    public static let maximumWidth: CGFloat = 240
    /// The narrowest, so a small frame's name still has somewhere to print.
    public static let minimumWidth: CGFloat = 40
    /// The narrowest a name's clickable area gets, so a frame called "A" is
    /// still something a person can hit.
    public static let minimumHitWidth: CGFloat = 24
    /// How far past the letters a click still counts, to the sides and above.
    public static let slop: CGFloat = 3

    /// Where the name draws for a frame drawn at `frameRect`.
    public static func box(forFrameRect frameRect: CGRect) -> CGRect {
        CGRect(x: frameRect.minX,
               y: frameRect.minY - height - gap,
               width: max(min(frameRect.width, maximumWidth), minimumWidth),
               height: height)
    }

    /// The area a click on that name lands in: the letters plus a little slop,
    /// never wider than the box that drew them (past its right edge the name is
    /// truncated, so there is nothing there to click), and never reaching down
    /// onto the frame's own top edge, which belongs to the frame.
    public static func hitBox(forFrameRect frameRect: CGRect, textWidth: CGFloat) -> CGRect {
        let box = box(forFrameRect: frameRect)
        let letters = min(max(textWidth, minimumHitWidth), box.width)
        return CGRect(x: box.minX - slop,
                      y: box.minY - slop,
                      width: letters + slop * 2,
                      // The bottom stops one point short of the frame, so the
                      // gap never swallows a click meant for the picture.
                      height: box.height + slop + (gap - 1))
    }

    /// The frame whose name is under `point`, or nil for anywhere else.
    ///
    /// `labels` comes in drawing order, back to front, so where two names
    /// overlap — which happens as soon as you zoom out far enough for two
    /// screens to sit close together — the one you can actually read wins.
    public static func hit(at point: CGPoint, labels: [FrameNameLabel]) -> UUID? {
        for label in labels.reversed()
        where hitBox(forFrameRect: label.frameRect, textWidth: label.textWidth).contains(point) {
            return label.id
        }
        return nil
    }
}
