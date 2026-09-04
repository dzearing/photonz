import CoreGraphics
import Foundation

/// Magnification: the same document, measured in a bigger unit.
///
/// The canvas shows the composite by stretching one picture of the document
/// over however many screen pixels the zoom asks for, so at 200% every baked
/// pixel covers four and the words in a label go soft. Drawing the composite
/// with more pixels to begin with is what keeps them sharp, and that starts
/// with a document whose geometry is stated in those pixels.
///
/// Nothing here changes what the document IS: no layer is added, removed or
/// restyled, and the picture is the same picture. Only the numbers grow, so a
/// renderer handed a magnified document lays everything out at the resolution
/// it is about to be shown at.
///
/// Content payloads (the words in a label, the points of an arrow, the ends of
/// a measure) are deliberately left alone: those are drawn by rasterizers that
/// take their own box, and the renderer hands them the box they always had
/// along with how much to magnify it by.
extension PhotonzDocument {
    /// This document with every geometric number multiplied by `scale`.
    /// `scale <= 0` or `scale == 1` returns it untouched.
    public func magnified(by scale: CGFloat) -> PhotonzDocument {
        guard scale > 0, scale != 1, scale.isFinite else { return self }
        var doc = self
        doc.canvasSize = CGSize(width: canvasSize.width * scale,
                                height: canvasSize.height * scale)
        doc.layers = layers.map { $0.magnified(by: scale) }
        return doc
    }
}

extension Layer {
    /// This layer with its frame, crop, styling and any canvas-space content
    /// geometry multiplied by `scale`, all the way down through a group.
    public func magnified(by scale: CGFloat) -> Layer {
        guard scale > 0, scale != 1, scale.isFinite else { return self }
        var layer = self
        layer.frame = frame.magnified(by: scale)
        layer.crop = crop?.magnified(by: scale)
        layer.style = style.magnified(by: scale)
        // A zoom callout points at a region of the CANVAS, so its aim has to
        // move with the canvas or it magnifies the wrong thing.
        if case .zoomCallout(var callout) = content {
            callout.sourceRect = callout.sourceRect.magnified(by: scale)
            layer.content = .zoomCallout(callout)
        }
        if case .group(var group) = content {
            group.children = group.children.map { $0.magnified(by: scale) }
            layer.content = .group(group)
        }
        return layer
    }
}

extension LayerStyle {
    /// This style with every length (border, corner, blur, shadow) multiplied
    /// by `scale`. Opacity and blend mode have no size, so they stay put.
    public func magnified(by scale: CGFloat) -> LayerStyle {
        guard scale > 0, scale != 1, scale.isFinite else { return self }
        var style = self
        style.blurRadius = blurRadius * scale
        style.cornerRadius = cornerRadius * scale
        style.borderWidth = borderWidth * scale
        if var shadow = style.shadow {
            shadow.radius *= scale
            shadow.spread *= scale
            shadow.offset = CGSize(width: shadow.offset.width * scale,
                                   height: shadow.offset.height * scale)
            style.shadow = shadow
        }
        return style
    }
}

extension CGRect {
    /// The same rect measured in a unit `scale` times smaller.
    public func magnified(by scale: CGFloat) -> CGRect {
        CGRect(x: origin.x * scale, y: origin.y * scale,
               width: width * scale, height: height * scale)
    }
}
