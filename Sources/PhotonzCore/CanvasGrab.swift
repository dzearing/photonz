import CoreGraphics
import Foundation

/// Which draggable part of the selected object the pointer is resting on.
///
/// A few things on the canvas can be taken hold of on their own: a captioned
/// arrow's caption, a caliper's number, and a caliper's feet and head dot.
/// Nothing said so until you tried it, so the canvas asks this on every pointer
/// move and shows a hand when the answer is not nil.
///
/// The precedence here MIRRORS the press precedence in `CanvasView.mouseDown`:
/// an arrow's endpoint handles win over its caption pill, and a caliper's dots
/// win over its number, so the cue never promises a drag the press would not
/// start.
public enum CanvasGrab: String, Hashable, Sendable, CaseIterable {
    /// A captioned arrow's pill. Dragging it moves the caption.
    case captionPill
    /// A caliper's readout. Dragging it moves the head (the number's own grab).
    case measureReadout
    /// One of a caliper's dots: either foot, or the head dot where the number
    /// is not sitting on it. Dragging one reshapes the measurement.
    case measureHandle

    /// Screen-point slop around the caption pill, matching the press.
    public static let captionTolerance: CGFloat = 6
    /// Screen-point slop around a caliper's dots and its readout, matching the press.
    public static let measureTolerance: CGFloat = 9

    /// What a press at `p` (document coordinates) would take hold of on
    /// `layer`, for cue purposes. `layer` must be the SELECTED layer: an
    /// unselected object offers none of these grabs, a press just moves the
    /// whole thing.
    ///
    /// Returns nil when the point is over something else — an arrow's endpoint
    /// handle, the bar between a caliper's grabs, or plain canvas.
    public static func hit(at p: CGPoint, layer: Layer, zoom: CGFloat,
                           captionsEnabled: Bool) -> CanvasGrab? {
        guard !layer.isLocked else { return nil }
        if layer.annotation != nil { return captionHit(at: p, layer: layer, zoom: zoom,
                                                       captionsEnabled: captionsEnabled) }
        if layer.measure != nil { return measureHit(at: p, layer: layer, zoom: zoom) }
        return nil
    }

    /// The caption pill's footprint in document space (the same estimate the
    /// model reserves and hit-tests with), or nil when the arrow has no caption.
    public static func captionPillRect(of layer: Layer) -> CGRect? {
        guard let a = layer.annotation, a.hasCaption else { return nil }
        let anchor = a.captionAnchor()
        let size = a.estimatedCaptionSize
        return CGRect(x: layer.frame.minX + anchor.x - size.width / 2,
                      y: layer.frame.minY + anchor.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    private static func captionHit(at p: CGPoint, layer: Layer, zoom: CGFloat,
                                   captionsEnabled: Bool) -> CanvasGrab? {
        guard captionsEnabled, let pill = captionPillRect(of: layer) else { return nil }
        // The tail handle overlaps the pill on a short arrow, and the press
        // gives it priority; so does the cue.
        guard AnnotationEndpoints.hit(at: p, layer: layer, zoom: zoom) == nil else { return nil }
        return pill.insetBy(dx: -slop(captionTolerance, zoom), dy: -slop(captionTolerance, zoom))
            .contains(p) ? .captionPill : nil
    }

    private static func measureHit(at p: CGPoint, layer: Layer, zoom: CGFloat) -> CanvasGrab? {
        guard let m = MeasureBuilder.documentSpaceContent(of: layer),
              m.alignment == nil else { return nil }
        let chip = m.estimatedLabelSize
        let tolerance = slop(measureTolerance, zoom)
        let g = m.caliperGeometry()
        // The feet are grabs with their own dots and their own drag, and they
        // beat the number where the two overlap. So is the head dot — but only
        // while it is DRAWN: once the readout covers it the number is the only
        // grab there, and the whole number should say so.
        var dots = [g.footA, g.footB]
        if !m.labelCoversHeadHandle(chipSize: chip) { dots.append(m.headHandle) }
        for dot in dots where hypot(p.x - dot.x, p.y - dot.y) <= tolerance { return .measureHandle }
        // A caliper can be shown without its number; then there is no pill to
        // rest on, but the dots above still drag.
        guard m.showLabel else { return nil }
        return m.labelRect(chipSize: chip).insetBy(dx: -tolerance, dy: -tolerance)
            .contains(p) ? .measureReadout : nil
    }

    /// Screen-point slop expressed in document units, so the target feels the
    /// same size at every zoom.
    private static func slop(_ screenPoints: CGFloat, _ zoom: CGFloat) -> CGFloat {
        zoom > 0 ? screenPoints / zoom : screenPoints
    }
}
