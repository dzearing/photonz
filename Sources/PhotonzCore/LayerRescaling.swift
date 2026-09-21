import CoreGraphics
import Foundation

/// Restating a drawing in a different unit, so it keeps the SIZE IT LOOKS.
///
/// This is not magnification (`DocumentMagnification.swift`) and the difference
/// is the whole point of it. Magnifying a document says "draw this at more
/// pixels": the boxes grow and the content payloads — the size of the type, the
/// thickness of a line, the points of an outline — are deliberately left alone,
/// because the rasterizer is handed the box along with how much to magnify it
/// by and does that part itself.
///
/// Rescaling says something else: this drawing was written in a unit where two
/// numbers make a point, and it is moving somewhere one number makes a point,
/// so rewrite EVERY number in it, the type and the line thickness included. The
/// picture that comes out looks identical; only the unit it is measured in has
/// changed. That is what a component built on a Retina capture needs on its way
/// into a one-to-one document, or it arrives twice the size it was drawn
/// (`SharedComponentScale`).
///
/// A count, a colour, a switch, an angle and a multiplier have no unit, so
/// nothing here touches them.
extension Layer {

    /// This layer, and everything inside it, with every length multiplied by
    /// `scale`. A scale of one, nothing, or a number that is not a number
    /// hands the layer back untouched.
    public func rescaled(by scale: CGFloat) -> Layer {
        guard scale > 0, scale != 1, scale.isFinite else { return self }
        var out = self
        out.frame = frame.magnified(by: scale)
        out.crop = crop?.magnified(by: scale)
        out.style = style.magnified(by: scale)
        out.heightChosenByHand = heightChosenByHand.map { $0 * scale }
        out.content = content.rescaled(by: scale)
        return out
    }
}

extension LayerContent {

    /// This content with the lengths INSIDE it restated: the size of the type,
    /// the thickness of a line, the points an outline runs through, the feet of
    /// a caliper. A photo has none of its own — it is drawn to fill whatever
    /// box it is given — so it passes straight through.
    func rescaled(by scale: CGFloat) -> LayerContent {
        guard scale > 0, scale != 1, scale.isFinite else { return self }
        switch self {
        // Sound states no length of its own: it is a stretch of time, and
        // time is not what a resize changes.
        case .sound:
            return self
        case .image:
            return self
        case .text(var text):
            text.fontSize *= scale
            return .text(text)
        case .annotation(var annotation):
            annotation.strokeWidth *= scale
            annotation.start = annotation.start.magnified(by: scale)
            annotation.end = annotation.end.magnified(by: scale)
            annotation.cornerRadii = annotation.cornerRadii.scaled(by: scale)
            annotation.captionFontSize *= scale
            annotation.captionOffset = annotation.captionOffset.map {
                CGSize(width: $0.width * scale, height: $0.height * scale)
            }
            return .annotation(annotation)
        case .path(var path):
            path.strokeWidth *= scale
            path.anchors = path.anchors.map { anchor in
                var out = anchor
                out.point = anchor.point.magnified(by: scale)
                out.handleIn = anchor.handleIn?.magnified(by: scale)
                out.handleOut = anchor.handleOut?.magnified(by: scale)
                return out
            }
            return .path(path)
        case .zoomCallout(var callout):
            // What it is aimed at is a region of the canvas, so it moves with
            // the canvas exactly as it does under magnification.
            callout.sourceRect = callout.sourceRect.magnified(by: scale)
            return .zoomCallout(callout)
        case .lens(let lens):
            return .lens(lens.magnified(by: scale))
        case .measure(var measure):
            measure.start = measure.start.magnified(by: scale)
            measure.end = measure.end.magnified(by: scale)
            measure.headOffset *= scale
            measure.strokeWidth *= scale
            measure.chipBorderWidth *= scale
            measure.labelNudge *= scale
            measure.labelCrossReach *= scale
            // The readout's own size is a multiplier on a fixed base, so it
            // reads the same however big the picture is. That is what it is
            // for, and it is left alone here for the same reason.
            return .measure(measure)
        case .collage(var collage):
            collage.gutter *= scale
            return .collage(collage)
        case .group(var group):
            group.children = group.children.map { $0.rescaled(by: scale) }
            group.layout = group.layout?.magnified(by: scale)
            group.followedStyle = group.followedStyle?.magnified(by: scale)
            group.instanceSize = group.instanceSize?.rescaled(by: scale)
            group.columns = group.columns?.rescaled(by: scale)
            group.overrides = group.overrides.map { $0.rescaled(by: scale) }
            return .group(group)
        }
    }
}

extension InstanceSize {
    /// A size a copy claimed for itself, restated. A side it has not claimed
    /// is still following its original and stays that way.
    func rescaled(by scale: CGFloat) -> InstanceSize {
        InstanceSize(width: width.map { $0 * scale }, height: height.map { $0 * scale })
    }
}

extension FrameColumns {
    /// A screen's column guides restated. How MANY columns there are is a
    /// count, so only the room between and beside them moves.
    func rescaled(by scale: CGFloat) -> FrameColumns {
        var out = self
        out.gutter = gutter * scale
        out.margin = margin * scale
        return out
    }
}

extension ComponentOverride {
    /// An answer a copy gave one of its knobs, restated.
    ///
    /// Every number a knob can reach is a length — a rounding, a thickness, a
    /// gap, the room inside a group (`ComponentNumberSlot`) — so both numeric
    /// answers move and the others (words, a colour, which version shows,
    /// whether a piece is there at all) have no size to move.
    func rescaled(by scale: CGFloat) -> ComponentOverride {
        switch value {
        case .number(let number):
            return ComponentOverride(property: property, value: .number(number * scale))
        case .room(let answer):
            return ComponentOverride(property: property,
                                     value: .room(answer.magnified(by: scale)))
        case .text, .visible, .variant, .color:
            return self
        }
    }
}

extension CGPoint {
    /// The same point measured in a unit `scale` times smaller.
    func magnified(by scale: CGFloat) -> CGPoint {
        CGPoint(x: x * scale, y: y * scale)
    }
}
