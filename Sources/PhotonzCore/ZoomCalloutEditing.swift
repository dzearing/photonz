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

    /// `value` pulled inside what the slider offers, for the number the TOOL
    /// holds as opposed to the one a drawn callout holds.
    ///
    /// The two are deliberately not treated alike. A drawn callout's number
    /// comes out of its frame, so a corner pull can legitimately leave it at
    /// 9.4x and the slider stretches to show it. The tool's number is only
    /// ever set from its own control, so anything outside the range is a
    /// corrupt stored value, and coming back as something drawable beats
    /// coming back as a callout nobody can see past.
    public static func clampedMagnification(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return defaultMagnification }
        return min(max(value, magnificationRange.lowerBound), magnificationRange.upperBound)
    }

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
    /// `avoiding` is the callouts already on the picture, in canvas
    /// coordinates — `PhotonzDocument.placedZoomCalloutRects` is what the
    /// editor passes — so a second callout steps clear of the first instead of
    /// burying it.
    public static func layer(from start: CGPoint, to end: CGPoint, canvas: CGSize,
                             magnification: CGFloat = ZoomCalloutBuilder.defaultMagnification,
                             style: LayerStyle = ZoomCalloutBuilder.defaultStyle,
                             shape: ZoomCalloutShape = .rectangle,
                             avoiding occupied: [CGRect] = []) -> Layer? {
        let box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
        let source = Geometry.pixelAligned(box.intersection(CGRect(origin: .zero, size: canvas)))
        guard source.width >= minimumSourceSide, source.height >= minimumSourceSide else { return nil }
        let frame = Geometry.zoomCalloutPlacement(source: source, magnification: magnification,
                                                  canvas: canvas, avoiding: occupied)
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
    ///
    /// The box never takes a shape its source does not have, because the
    /// picture is the source blown up onto the box and two shapes mean a
    /// stretched picture. A box handed a new shape (Shift on a handle, a
    /// height typed on its own, a group scaled one way) takes the source with
    /// it: the source keeps its width and its centre, and its height becomes
    /// the box's at the same magnification. A box of the same shape, which is
    /// every plain handle drag (`draggedFrame`), leaves the source exactly as
    /// it was.
    public static func resized(_ layer: Layer, to frame: CGRect) -> Layer {
        var layer = layer
        layer.frame = frame
        if var callout = layer.zoomCallout, callout.sourceRect.width > 0 {
            let magnification = frame.width / callout.sourceRect.width
            callout.magnification = magnification
            let source = callout.sourceRect.standardized
            let height = abs(frame.height) / magnification
            // A hair of slack, so float noise from a shape-keeping drag never
            // nudges a pixel-aligned source off its pixels.
            if magnification > 0, height.isFinite, abs(height - source.height) > 0.001 {
                callout.sourceRect = CGRect(x: source.minX, y: source.midY - height / 2,
                                            width: source.width, height: height)
            }
            layer.content = .zoomCallout(callout)
        }
        return layer
    }

    /// The box a handle drag on `layer` lands on, before any magnet: `start`
    /// is the box when the handle was taken, `p` the pointer in the same space.
    ///
    /// A callout keeping its shape (the default; Shift lets it go) keeps its
    /// SOURCE's proportions, so the magnified picture is the source and never
    /// a stretched copy of it. A corner holds its opposite corner and an edge
    /// grows the other side about its own middle, the way a shape-kept drag
    /// does on any layer. A box already out of shape (a callout saved before
    /// this rule) is brought back to the source's shape by the first drag
    /// rather than having the stretch locked in.
    ///
    /// Anything else, or a callout let go, is the plain resize every layer has.
    public static func draggedFrame(_ layer: Layer, from start: CGRect, handle: ResizeHandle,
                                    to p: CGPoint, keepingShape: Bool) -> CGRect {
        guard keepingShape, let source = layer.zoomCallout?.sourceRect.standardized,
              source.width > 0, source.height > 0, start.width > 0 else {
            return Handles.resize(start, dragging: handle, to: p, preserveAspect: keepingShape)
        }
        let size = CGSize(width: start.width, height: start.width * source.height / source.width)
        let anchor = Handles.point(for: handle.opposite, in: start)
        let held = Handles.point(for: handle.opposite, in: CGRect(origin: .zero, size: size))
        let shaped = CGRect(origin: CGPoint(x: anchor.x - held.x, y: anchor.y - held.y), size: size)
        return Handles.resize(shaped, dragging: handle, to: p, preserveAspect: true)
    }
}

extension Layer {
    /// Whether a handle drag keeps this layer's proportions with no key held,
    /// so Shift is the key that lets them go rather than the one that keeps
    /// them. Only a zoom callout: its picture is its source blown up, and a
    /// box of another shape is that picture stretched.
    public var resizeKeepsShapeByDefault: Bool { zoomCallout != nil }
}

extension PhotonzDocument {

    /// Every zoom callout already on the picture, in canvas coordinates, with
    /// the ones inside frames reached into and the hidden ones left out — a
    /// callout you cannot see is not in anyone's way.
    ///
    /// This is the list a new callout steers around. It is callouts only, not
    /// every layer: the picture underneath covers the whole canvas, so counting
    /// everything would leave a new callout nowhere to go and change nothing.
    public var placedZoomCalloutRects: [CGRect] {
        flattenedLayers.compactMap { layer in
            layer.isVisible && layer.zoomCallout != nil ? layer.frame : nil
        }
    }
}
