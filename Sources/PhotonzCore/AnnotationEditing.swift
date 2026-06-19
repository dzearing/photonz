import CoreGraphics
import Foundation

/// Which end of a line/arrow annotation an endpoint handle controls.
public enum AnnotationEndpoint: String, CaseIterable, Hashable, Sendable {
    case start
    case end
}

extension Layer {
    /// The layer's annotation content, nil for other content kinds.
    public var annotation: AnnotationContent? {
        if case .annotation(let a) = content { return a }
        return nil
    }

    /// Lines/arrows edit by dragging their endpoints, not a frame.
    public var hasEndpointHandles: Bool {
        guard let a = annotation else { return false }
        return a.shape == .line || a.shape == .arrow
    }

    /// Whether the selection chrome offers the eight frame-resize handles.
    /// Lines/arrows use endpoint handles instead. Text never frame-resizes
    /// (the renderer re-wraps/rescales at frame size, which is unpredictable;
    /// text size changes go through the font picker — decided in 3.5).
    public var allowsFrameResize: Bool {
        switch content {
        case .text: false
        case .annotation: !hasEndpointHandles
        case .image, .zoomCallout: true
        }
    }

    /// An annotation endpoint's position in document coordinates.
    public func annotationEndpoint(_ endpoint: AnnotationEndpoint) -> CGPoint? {
        guard let a = annotation else { return nil }
        let local = endpoint == .start ? a.start : a.end
        return CGPoint(x: frame.minX + local.x, y: frame.minY + local.y)
    }

    /// The layer with its frame set to `frame`. Annotation content remaps its
    /// endpoints so the drawn shape scales with the frame (a bare frame
    /// assignment would clip or distort it); zoom callouts re-derive their
    /// magnification from the new frame; other content just moves.
    public func resized(to frame: CGRect) -> Layer {
        if annotation != nil { return AnnotationBuilder.resized(self, to: frame) }
        if zoomCallout != nil { return ZoomCalloutBuilder.resized(self, to: frame) }
        var layer = self
        layer.frame = frame
        return layer
    }
}

extension AnnotationBuilder {
    /// The layer with its annotation redrawn between document-space `start`
    /// and `end`: identity and style survive, the frame is rebuilt with render
    /// padding exactly like a fresh drag. Non-annotation layers pass through.
    public static func updating(_ layer: Layer, start: CGPoint, end: CGPoint) -> Layer {
        guard let a = layer.annotation else { return layer }
        let rebuilt = self.layer(content: a, from: start, to: end)
        var updated = layer
        updated.frame = rebuilt.frame
        updated.content = rebuilt.content
        return updated
    }

    /// Handle-resize remap: endpoints scale proportionally into the proposed
    /// frame, then the layer is rebuilt so the (unchanged) stroke width keeps
    /// its full render padding even after a downscale.
    public static func resized(_ layer: Layer, to frame: CGRect) -> Layer {
        guard let a = layer.annotation,
              layer.frame.width > 0, layer.frame.height > 0 else { return layer }
        func remap(_ p: CGPoint) -> CGPoint {
            CGPoint(x: frame.minX + p.x / layer.frame.width * frame.width,
                    y: frame.minY + p.y / layer.frame.height * frame.height)
        }
        return updating(layer, start: remap(a.start), end: remap(a.end))
    }

    /// Style edit on an existing annotation: endpoints stay anchored in
    /// document space while the frame re-pads for the new stroke width.
    public static func restyled(_ layer: Layer, colorHex: String? = nil,
                                strokeWidth: CGFloat? = nil,
                                arrowheadScale: CGFloat? = nil) -> Layer {
        guard var a = layer.annotation,
              let start = layer.annotationEndpoint(.start),
              let end = layer.annotationEndpoint(.end) else { return layer }
        if let colorHex { a.colorHex = colorHex }
        if let strokeWidth { a.strokeWidth = strokeWidth }
        if let arrowheadScale { a.arrowheadScale = arrowheadScale }
        var updated = layer
        updated.content = .annotation(a)
        return updating(updated, start: start, end: end)
    }
}

/// An in-progress endpoint drag on a line/arrow layer. Mirrors
/// `AnnotationDrag`: the canvas feeds it pointer positions, the geometry
/// (including ⇧ 45° snap around the fixed endpoint) lives here.
public struct AnnotationEndpointDrag: Equatable, Sendable {
    public let endpoint: AnnotationEndpoint
    public let shape: AnnotationShape
    /// The endpoint that stays put, in document coordinates.
    public let fixed: CGPoint
    /// The dragged endpoint's current position, in document coordinates.
    public var current: CGPoint

    public init?(layer: Layer, endpoint: AnnotationEndpoint) {
        guard layer.hasEndpointHandles, let a = layer.annotation,
              let fixed = layer.annotationEndpoint(endpoint == .start ? .end : .start),
              let moving = layer.annotationEndpoint(endpoint) else { return nil }
        self.endpoint = endpoint
        self.shape = a.shape
        self.fixed = fixed
        self.current = moving
    }

    public mutating func update(to point: CGPoint) {
        current = point
    }

    /// The annotation's document-space endpoints with this drag applied.
    /// Constrained (⇧) snaps the moved endpoint to 45° around the fixed one,
    /// the same rule drag-to-create uses.
    public func endpoints(constrained: Bool) -> (start: CGPoint, end: CGPoint) {
        var target = current
        if constrained {
            var drag = AnnotationDrag(anchor: fixed)
            drag.update(to: current)
            target = drag.end(constrained: true, shape: shape)
        }
        return endpoint == .start ? (start: target, end: fixed) : (start: fixed, end: target)
    }
}

/// Endpoint-handle hit-testing, mirroring `Handles`: document coordinates in,
/// tolerance in screen points so handles feel the same size at any zoom.
public enum AnnotationEndpoints {
    public static func hit(at p: CGPoint, layer: Layer, zoom: CGFloat,
                           screenTolerance: CGFloat = 8) -> AnnotationEndpoint? {
        guard layer.hasEndpointHandles else { return nil }
        let tolerance = zoom > 0 ? screenTolerance / zoom : screenTolerance
        var best: (endpoint: AnnotationEndpoint, distance: CGFloat)?
        for endpoint in AnnotationEndpoint.allCases {
            guard let ep = layer.annotationEndpoint(endpoint) else { continue }
            let distance = hypot(p.x - ep.x, p.y - ep.y)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (endpoint, distance)
            }
        }
        return best?.endpoint
    }
}
