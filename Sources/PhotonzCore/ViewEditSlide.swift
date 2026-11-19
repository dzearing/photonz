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
///
/// Since 2026-11-19 the slide itself is Core Animation's: the start of each
/// move is handed to the layers that hold the canvas, the panel, the dock and
/// the tool bar, and the render server slides them home, so the main thread
/// draws nothing while they move. Driven by SwiftUI keyframes, every frame
/// was a whole-window SwiftUI render of 11 to 14ms (8.5ms even with nothing
/// moving), and the slide's longest still ran 33 to 47ms.
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

    /// `pictureMove` at the start of the slide, as the transform of the layer
    /// that holds the canvas, for Core Animation to slide home: about the
    /// layer's `anchor`, in the coordinates of the layer it sits in, where the
    /// canvas's top-left corner is `canvasOrigin` and y runs down when `yDown`.
    /// Identity when the two are not the same picture.
    public func pictureLayerTransform(to: Viewport, canvasOrigin: CGPoint, anchor: CGPoint,
                                      yDown: Bool) -> CGAffineTransform {
        let move = pictureMove(to: to, progress: 1)
        guard move != .identity else { return .identity }
        // A canvas point v sits at canvasOrigin + D v; it has to be drawn at
        // canvasOrigin + D (s v + t). About the anchor that is a scale by s and
        // a shift of (1 - s)(canvasOrigin - anchor) + D t.
        let s = move.a
        let t = CGPoint(x: move.tx, y: yDown ? move.ty : -move.ty)
        return CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                 tx: (1 - s) * (canvasOrigin.x - anchor.x) + t.x,
                                 ty: (1 - s) * (canvasOrigin.y - anchor.y) + t.y)
    }

    /// How far down the dock is drawn, so it starts as tall as View had it
    /// (its tracks below the window's foot) and rises.
    public func dockDrop(dockHeight: CGFloat, progress: CGFloat) -> CGFloat {
        max(0, dockHeight - dockHeightFrom) * progress
    }
}
