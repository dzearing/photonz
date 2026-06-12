import CoreGraphics
import Foundation

/// The canvas camera: where the document sits inside the view and at what scale.
/// All math is in top-left-origin coordinates (model space and view space alike).
/// The canvas view renders whatever this says; tools convert pointer locations
/// through it. Pure value type so every behavior is unit-tested.
public struct Viewport: Equatable, Sendable {
    public var documentSize: CGSize
    public var viewSize: CGSize
    /// View points per document point.
    public var zoom: CGFloat
    /// View-space position of the document's top-left corner.
    public var origin: CGPoint

    public static let minZoom: CGFloat = 1.0 / 32.0
    public static let maxZoom: CGFloat = 32

    public init(documentSize: CGSize, viewSize: CGSize, zoom: CGFloat, origin: CGPoint) {
        self.documentSize = documentSize
        self.viewSize = viewSize
        self.zoom = zoom
        self.origin = origin
    }

    /// A viewport showing the whole document centered (⌘0). Never upscales:
    /// a document smaller than the view is shown at 100%, not stretched.
    public static func fit(documentSize: CGSize, in viewSize: CGSize, padding: CGFloat = 24) -> Viewport {
        let usable = CGSize(width: max(1, viewSize.width - padding * 2),
                            height: max(1, viewSize.height - padding * 2))
        var zoom: CGFloat = 1
        if documentSize.width > 0, documentSize.height > 0 {
            zoom = min(usable.width / documentSize.width,
                       usable.height / documentSize.height,
                       1)
        }
        zoom = min(max(zoom, minZoom), maxZoom)
        return Viewport(documentSize: documentSize, viewSize: viewSize, zoom: zoom, origin: .zero)
            .clamped()
    }

    /// The document's frame in view coordinates.
    public var documentFrameInView: CGRect {
        CGRect(origin: origin,
               size: CGSize(width: documentSize.width * zoom, height: documentSize.height * zoom))
    }

    // MARK: Coordinate mapping

    public func viewPoint(fromDocument p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * zoom, y: origin.y + p.y * zoom)
    }

    public func documentPoint(fromView p: CGPoint) -> CGPoint {
        guard zoom > 0 else { return .zero }
        return CGPoint(x: (p.x - origin.x) / zoom, y: (p.y - origin.y) / zoom)
    }

    // MARK: Mutations (always return a clamped viewport)

    /// Changes zoom keeping the document point under `anchorInView` fixed on screen.
    public func zoomed(to newZoom: CGFloat, anchorInView: CGPoint) -> Viewport {
        let clampedZoom = min(max(newZoom, Self.minZoom), Self.maxZoom)
        let anchorDoc = documentPoint(fromView: anchorInView)
        var next = self
        next.zoom = clampedZoom
        next.origin = CGPoint(x: anchorInView.x - anchorDoc.x * clampedZoom,
                              y: anchorInView.y - anchorDoc.y * clampedZoom)
        return next.clamped()
    }

    /// Moves the content by `delta` view points (positive x moves content right).
    public func panned(by delta: CGPoint) -> Viewport {
        var next = self
        next.origin = CGPoint(x: origin.x + delta.x, y: origin.y + delta.y)
        return next.clamped()
    }

    /// Adopts a new view size, keeping the document point at the view center fixed.
    public func resized(viewSize newSize: CGSize) -> Viewport {
        let centerDoc = documentPoint(fromView: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2))
        var next = self
        next.viewSize = newSize
        next.origin = CGPoint(x: newSize.width / 2 - centerDoc.x * zoom,
                              y: newSize.height / 2 - centerDoc.y * zoom)
        return next.clamped()
    }

    /// Per axis: content smaller than the view is centered; content larger than
    /// the view scrolls but never past its edges.
    public func clamped() -> Viewport {
        var next = self
        next.origin.x = Self.clampAxis(origin: origin.x, content: documentSize.width * zoom, view: viewSize.width)
        next.origin.y = Self.clampAxis(origin: origin.y, content: documentSize.height * zoom, view: viewSize.height)
        if !next.origin.x.isFinite { next.origin.x = 0 }
        if !next.origin.y.isFinite { next.origin.y = 0 }
        return next
    }

    private static func clampAxis(origin: CGFloat, content: CGFloat, view: CGFloat) -> CGFloat {
        if content <= view {
            return (view - content) / 2
        }
        return min(max(origin, view - content), 0)
    }
}
