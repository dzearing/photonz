import CoreGraphics
import Foundation

extension Layer {
    /// The layer's zoom-callout content, nil for other content kinds.
    public var zoomCallout: ZoomCalloutContent? {
        if case .zoomCallout(let c) = content { return c }
        return nil
    }
}

extension ZoomCalloutShape {
    /// What the Shape row calls this, in words. The row used to be two glyphs
    /// in a popover; a box and a circle are easy enough to draw, but the dock
    /// says its settings in words so a collapsed section can still be read.
    public var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        }
    }
}

/// Builds zoom-callout layers from completed drags and keeps their
/// magnification honest through frame edits.
public enum ZoomCalloutBuilder {

    public static let defaultMagnification: CGFloat = 2

    /// Sources smaller than this (either axis, document points) are stray
    /// clicks, not regions worth magnifying.
    public static let minimumSourceSide: CGFloat = 4

    /// What the Magnification slider offers. Below 1.25 a callout shows the
    /// picture at nearly its own size, which is a box saying nothing; past six
    /// the source is a handful of pixels and the box is a wall.
    public static let magnificationRange: ClosedRange<CGFloat> = 1.25...6

    /// The slider's range with `value` guaranteed inside it.
    ///
    /// Dragging a callout's corner sets its magnification from the frame, so
    /// the number can land outside what the slider offers. A thumb pinned at
    /// the end beside a readout saying 9.4x reads as broken, so the range
    /// stretches to hold what is already there instead.
    public static func magnificationRange(including value: CGFloat) -> ClosedRange<CGFloat> {
        guard value.isFinite else { return magnificationRange }
        return min(magnificationRange.lowerBound, value)...max(magnificationRange.upperBound, value)
    }

    /// What the readout beside the slider says: one decimal and a times sign.
    public static func magnificationLabel(_ value: CGFloat) -> String {
        Double(value).formatted(.number.precision(.fractionLength(1))) + "\u{00D7}"
    }

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
    /// `shape` is what the tool in your hand is set to draw: a box, or a
    /// circle. It reaches the new callout here so the choice is made BEFORE the
    /// drag rather than corrected after it.
    public static func layer(from start: CGPoint, to end: CGPoint, canvas: CGSize,
                             magnification: CGFloat = ZoomCalloutBuilder.defaultMagnification,
                             style: LayerStyle = ZoomCalloutBuilder.defaultStyle,
                             shape: ZoomCalloutShape = .rectangle) -> Layer? {
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
        let source = Geometry.pixelAligned(box.intersection(CGRect(origin: .zero, size: canvas)))
        guard source.width >= minimumSourceSide, source.height >= minimumSourceSide else { return nil }
        let frame = Geometry.zoomCalloutPlacement(source: source, magnification: magnification,
                                                  canvas: canvas)
        return Layer(name: "Zoom",
                     content: .zoomCallout(ZoomCalloutContent(sourceRect: source,
                                                              magnification: magnification,
                                                              shape: shape)),
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
