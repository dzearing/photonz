import CoreGraphics

/// **The slide into Edit, drawn as layers.** The window is laid out as Edit
/// once, at the key: the panel at its width, the dock at its height, the
/// canvas at what is left and the picture fitted to it. Then the three are
/// moved back to where View had them and slid home on the switch's curve, by
/// moving what is already drawn rather than laying the window out again.
///
/// Until 2026-11-17 the slide animated the panel's width and the dock's
/// height, so every frame re-laid out the whole window and refitted the
/// picture: on a five minute captioned recording that kept the main thread
/// busy for most of the slide and left its first frames sitting still for 35
/// to 49ms.
///
/// `progress` runs from 1 (where View had everything) to 0 (Edit, home).
public struct ViewEditSlide: Equatable, Sendable {
    /// The picture as View drew it, the moment before the key.
    public var from: Viewport
    /// How tall the dock was in View: the transport alone.
    public var dockHeightFrom: CGFloat

    /// How long the slide's keyframes run: the switch's curve, and a little
    /// more for its spring to settle.
    public static let seconds: Double = ViewEditMode.transitionSeconds + 0.05

    public init(from: Viewport, dockHeightFrom: CGFloat) {
        self.from = from
        self.dockHeightFrom = dockHeightFrom
    }

    /// What to do to the canvas, in its own top-left points, so the picture
    /// `to` draws sits `progress` of the way back to where View drew it. The
    /// canvas's top-left corner is the same point of the window in both modes,
    /// so the two viewports share one space. Identity when the two are not
    /// the same picture.
    public func pictureMove(to: Viewport, progress: CGFloat) -> CGAffineTransform {
        guard to.zoom > 0, from.zoom > 0, to.documentSize == from.documentSize, progress != 0 else {
            return .identity
        }
        // View's point for a point Edit draws at v: from.origin + s(v - to.origin).
        let scale = from.zoom / to.zoom
        let tx = from.origin.x - scale * to.origin.x
        let ty = from.origin.y - scale * to.origin.y
        let s = 1 + (scale - 1) * progress
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx * progress, ty: ty * progress)
    }

    /// How far down the dock is drawn, so it starts as tall as View had it
    /// (its tracks below the window's foot) and rises.
    public func dockDrop(dockHeight: CGFloat, progress: CGFloat) -> CGFloat {
        max(0, dockHeight - dockHeightFrom) * progress
    }

    /// How far right the panel is drawn: just off the window's edge at the
    /// start.
    public static func panelShift(width: CGFloat, progress: CGFloat) -> CGFloat {
        width * progress
    }
}
