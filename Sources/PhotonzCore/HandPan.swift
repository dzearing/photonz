import CoreGraphics

/// One drag with the Hand: the picture follows the pointer, and nothing in the
/// document is touched.
///
/// Every step is measured from where the press began rather than added up move
/// by move. The camera stops at the picture's edge (`Viewport.clamped`), and
/// summed steps would bank the travel lost there, so a pointer coming back
/// would have to win it back before anything moved. Measured from the press,
/// the picture comes back the moment the pointer does, and a drag that returns
/// to its start puts the view back exactly.
public struct HandPan: Equatable, Sendable {
    /// Where the press landed, in view points.
    public let start: CGPoint
    /// The camera when the press landed.
    public let viewport: Viewport

    public init(at start: CGPoint, viewport: Viewport) {
        self.start = start
        self.viewport = viewport
    }

    /// The camera with the pointer at `point` (view points).
    public func viewport(at point: CGPoint) -> Viewport {
        viewport.panned(by: CGPoint(x: point.x - start.x, y: point.y - start.y))
    }
}
