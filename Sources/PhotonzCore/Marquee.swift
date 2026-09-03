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

/// What a press that lands on bare canvas means for the selection.
///
/// A rubber band starts either way, so these two only differ in what happens
/// to what was already picked. The ⇧ case exists because ⇧ means "and this
/// too": a ⇧-click that misses a layer by a few pixels must not throw away
/// the selection it was about to be added to, and a ⇧-sweep hands what it
/// takes in to that selection rather than starting over.
public enum BareCanvasPress: Equatable, Sendable {
    /// No modifier: bare canvas means "nothing", so the press lets go of the
    /// selection and letting go without moving leaves nothing picked.
    case replaces
    /// ⇧: nothing is taken away. The selection survives the press, survives a
    /// release that never moved, and a real sweep ADDS its catch to it.
    case spares

    public init(shift: Bool) {
        self = shift ? .spares : .replaces
    }

    /// Whether the press itself lets go of the current selection.
    public var clearsSelectionOnPress: Bool { self == .replaces }

    /// Whether letting go decides the selection at all. A spared click is the
    /// one gesture on bare canvas that changes nothing.
    public func commitsOnRelease(isClick: Bool) -> Bool {
        !(isClick && self == .spares)
    }

    /// Whether a finished sweep ADDS what it took in to what was already
    /// picked, instead of becoming the whole selection. ⇧ means "and this
    /// too" everywhere else you pick something — a row in the list, a layer
    /// on the picture — so it means it for a rubber band as well, and a
    /// selection can be built out of two or three sweeps.
    public var sweepAddsToSelection: Bool { self == .spares }

    /// What is picked once a sweep that took in `swept` lets go. Adding is
    /// adding and never toggling: sweeping back over something already
    /// picked leaves it picked.
    public func selection(afterSweeping swept: [UUID],
                          startingFrom existing: Set<UUID>) -> Set<UUID> {
        sweepAddsToSelection ? existing.union(swept) : Set(swept)
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
