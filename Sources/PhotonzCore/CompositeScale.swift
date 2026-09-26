import CoreGraphics

/// How big to composite a document with time for the canvas
/// (`scrubbing-is-smooth-never-goes-black-and-the-pic`).
///
/// A full-screen Retina recording fitted in a window is shown at under half its
/// own pixels, and compositing every one of them, every refresh of a scrub, is
/// what kept the picture a frame or two behind the hand. So it is composited
/// at the size it is shown, in steps of an eighth (the same steps its frames
/// are read in, `MovieRef.decodePixelSize`) so a small zoom does not throw
/// every cached layer away, and never bigger than its own size: zoomed in past
/// that, the sharp tile draws over it anyway.
public enum CompositeScale {

    /// `shown` is screen pixels per document point.
    public static func forShown(_ shown: CGFloat) -> CGFloat {
        guard shown.isFinite else { return 1 }
        return min(8, max(1, (max(0, shown) * 8).rounded(.up))) / 8
    }
}
