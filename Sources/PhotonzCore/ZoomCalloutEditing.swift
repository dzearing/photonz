import CoreGraphics
import Foundation

extension Layer {
    /// The layer's zoom-callout content, nil for other content kinds.
    public var zoomCallout: ZoomCalloutContent? {
        if case .zoomCallout(let c) = content { return c }
        return nil
    }
}

/// Builds zoom-callout layers from completed drags and keeps their
/// magnification honest through frame edits.
public enum ZoomCalloutBuilder {

    public static let defaultMagnification: CGFloat = 2

    /// Sources smaller than this (either axis, document points) are stray
    /// clicks, not regions worth magnifying.
    public static let minimumSourceSide: CGFloat = 4

    /// What new callouts look like: a bordered, rounded, floating box. The
    /// border color matches the annotation default so the tools share one
    /// visual language; the inspector restyles it per layer.
    public static var defaultStyle: LayerStyle {
        LayerStyle(cornerRadius: 6, borderWidth: 3, borderColorHex: "#FF3B30",
                   shadow: ShadowStyle())
    }

    /// The layer a drag from `start` to `end` (document coordinates) creates:
    /// the pixel-aligned drag box becomes the magnified source, and the frame
    /// lands where `Geometry.zoomCalloutPlacement` finds the most free space.
    /// Nil when the box is degenerate or off-canvas.
    public static func layer(from start: CGPoint, to end: CGPoint, canvas: CGSize,
                             magnification: CGFloat = ZoomCalloutBuilder.defaultMagnification,
                             style: LayerStyle = ZoomCalloutBuilder.defaultStyle) -> Layer? {
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
        let source = Geometry.pixelAligned(box.intersection(CGRect(origin: .zero, size: canvas)))
        guard source.width >= minimumSourceSide, source.height >= minimumSourceSide else { return nil }
        let frame = Geometry.zoomCalloutPlacement(source: source, magnification: magnification,
                                                  canvas: canvas)
        return Layer(name: "Zoom",
                     content: .zoomCallout(ZoomCalloutContent(sourceRect: source,
                                                              magnification: magnification)),
                     frame: frame, style: style)
    }

    /// Where the callout's frame lands when the inspector slider sets a new
    /// magnification: the box grows/shrinks around its current center. The
    /// caller routes the result through the regular frame preview/commit path,
    /// and `resized(to:)` re-derives the same magnification from it.
    public static func frame(for magnification: CGFloat, of layer: Layer) -> CGRect {
        guard let callout = layer.zoomCallout else { return layer.frame }
        let size = CGSize(width: callout.sourceRect.width * magnification,
                          height: callout.sourceRect.height * magnification)
        return CGRect(x: layer.frame.midX - size.width / 2,
                      y: layer.frame.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// Frame edit on a callout: magnification follows the frame so the stored
    /// value (what the inspector slider shows, and what scales the source
    /// outline's corner radius) keeps matching what's rendered.
    public static func resized(_ layer: Layer, to frame: CGRect) -> Layer {
        var layer = layer
        layer.frame = frame
        if var callout = layer.zoomCallout, callout.sourceRect.width > 0 {
            callout.magnification = frame.width / callout.sourceRect.width
            layer.content = .zoomCallout(callout)
        }
        return layer
    }
}
