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

    /// Moves the camera the least it can so `rect` (in document points) is
    /// fully on screen, with `padding` view points of air around it.
    ///
    /// Nothing happens when the rect is already on screen: a canvas that jumps
    /// when it did not need to is more disorienting than one that never moves.
    /// The zoom is left alone unless the rect is too big to see at this scale,
    /// and then the camera only ever pulls BACK, never pushes in, so revealing
    /// something small never magnifies it out of the blue.
    public func revealing(_ rect: CGRect, padding: CGFloat = 24) -> Viewport {
        guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0, zoom > 0
        else { return self }
        let room = CGSize(width: max(1, viewSize.width - padding * 2),
                          height: max(1, viewSize.height - padding * 2))
        let fitting = min(zoom, room.width / rect.width, room.height / rect.height)
        let next = min(max(fitting, Self.minZoom), Self.maxZoom)

        var moved = self
        if next < zoom {
            // Pull back around the rect's own middle, so what we came to see is
            // what stays put while the scale changes.
            moved = zoomed(to: next, anchorInView: viewPoint(fromDocument: CGPoint(x: rect.midX, y: rect.midY)))
        }
        let box = CGRect(origin: moved.viewPoint(fromDocument: rect.origin),
                         size: CGSize(width: rect.width * moved.zoom, height: rect.height * moved.zoom))
        let wanted = CGRect(origin: .zero, size: viewSize).insetBy(dx: padding, dy: padding)
        var delta = CGPoint.zero
        // Per axis, the shortest push that puts the box back inside. A box
        // wider than the room is pushed only until its near edge lines up, so
        // the camera lands on the start of it rather than the middle of it.
        if box.width <= wanted.width {
            if box.minX < wanted.minX { delta.x = wanted.minX - box.minX }
            else if box.maxX > wanted.maxX { delta.x = wanted.maxX - box.maxX }
        } else if box.minX > wanted.minX || box.maxX < wanted.maxX {
            delta.x = wanted.minX - box.minX
        }
        if box.height <= wanted.height {
            if box.minY < wanted.minY { delta.y = wanted.minY - box.minY }
            else if box.maxY > wanted.maxY { delta.y = wanted.maxY - box.maxY }
        } else if box.minY > wanted.minY || box.maxY < wanted.maxY {
            delta.y = wanted.minY - box.minY
        }
        return delta == .zero ? moved : moved.panned(by: delta)
    }

    /// Reveals `rect` and brings `companion` along when the two fit on screen
    /// together at the zoom we are already at.
    ///
    /// What a command calls when it puts something new down NEXT TO something
    /// old: seeing only the new thing answers "what appeared" but not "where
    /// did it come from", and those are one question. When the pair is too far
    /// apart to hold at this zoom the new thing wins, because pulling the
    /// camera back to a bird's eye view of both is a bigger surprise than
    /// losing sight of the old one.
    public func revealing(_ rect: CGRect, alongside companion: CGRect,
                          padding: CGFloat = 24) -> Viewport {
        guard !companion.isNull, !companion.isInfinite,
              companion.width > 0, companion.height > 0 else { return revealing(rect, padding: padding) }
        let pair = rect.union(companion)
        let room = CGSize(width: viewSize.width - padding * 2, height: viewSize.height - padding * 2)
        guard pair.width * zoom <= room.width, pair.height * zoom <= room.height
        else { return revealing(rect, padding: padding) }
        return revealing(pair, padding: padding)
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
