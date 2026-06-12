import CoreGraphics
import Foundation

/// An in-progress rectangular marquee drag, tracked in document coordinates
/// (top-left origin). The canvas view feeds it pointer positions converted
/// through `Viewport`; all selection geometry decisions live here so they
/// stay unit-tested.
public struct MarqueeDrag: Equatable, Sendable {
    /// Where the drag started.
    public var anchor: CGPoint
    /// Where the pointer is now.
    public var current: CGPoint

    public init(anchor: CGPoint) {
        self.anchor = anchor
        self.current = anchor
    }

    public mutating func update(to point: CGPoint) {
        current = point
    }

    /// The selection this drag describes: standardized, optionally constrained
    /// to a square (⇧), and clamped to the canvas. `nil` when the drag is
    /// empty or lies entirely outside the canvas.
    public func selectionRect(constrainSquare: Bool = false, in canvasSize: CGSize) -> CGRect? {
        var dx = current.x - anchor.x
        var dy = current.y - anchor.y
        if constrainSquare {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        let rect = CGRect(x: anchor.x, y: anchor.y, width: dx, height: dy).standardized
        let clamped = rect.intersection(CGRect(origin: .zero, size: canvasSize))
        guard !clamped.isNull, !clamped.isEmpty else { return nil }
        return clamped
    }

    /// Whether the pointer has moved so little that this is a click, not a
    /// marquee. The tolerance is in view points, so it feels the same at any
    /// zoom level.
    public func isClick(atZoom zoom: CGFloat, tolerance: CGFloat = 4) -> Bool {
        hypot(current.x - anchor.x, current.y - anchor.y) * zoom < tolerance
    }
}

extension Geometry {
    /// Snaps a rect's edges to the pixel grid (nearest integer per edge).
    /// A non-empty rect never collapses below 1×1.
    public static func pixelAligned(_ rect: CGRect) -> CGRect {
        let r = rect.standardized
        let minX = r.minX.rounded()
        let minY = r.minY.rounded()
        var width = r.maxX.rounded() - minX
        var height = r.maxY.rounded() - minY
        if r.width > 0 { width = max(width, 1) }
        if r.height > 0 { height = max(height, 1) }
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
}
