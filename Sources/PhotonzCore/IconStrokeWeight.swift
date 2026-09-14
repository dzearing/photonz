import CoreGraphics
import Foundation

/// The weight a freshly drawn line starts at, decided by the canvas it lands on
/// (`next-icon-frames`).
///
/// Every new shape and path in this app took four points of line, whatever it
/// was drawn on. On a screen that is a sensible redline weight. On a 24 pixel
/// icon frame it is a sixth of the whole canvas, so the first mark anybody made
/// on an icon was a blob and the only way out was to find the width slider
/// before drawing anything.
///
/// ## The rule
///
/// A sixteenth of the frame, rounded to whole pixels, never under one. An icon
/// grid IS pixels: a line sitting half on one is the blur that icon drawing
/// exists to avoid, so the answer is always a whole number. The sizes come out
/// where icon design already puts them — 1 at 16, 2 at 24, 3 at 48 — and 2 at
/// 24 is the weight Material's 24dp grid uses.
///
/// ## Two things it will not do
///
/// **It never makes a line heavier.** The rule is here to rescue a line too fat
/// for its canvas; a 512 point app icon would otherwise be handed 32 points of
/// stroke nobody asked for.
///
/// **It stops the moment you choose.** It applies only while the tool is still
/// holding the width every tool ships with. Pick any other weight and that is
/// the weight you get, on an icon frame or anywhere else, because a starting
/// value that reimposed itself after every change would be a lock.
public enum IconStrokeWeight {

    /// How many lines of the starting weight lie across an icon. Sixteen is
    /// what puts 16 on one pixel and 24 on two.
    public static let linesAcrossAnIcon: CGFloat = 16

    /// The weight a freshly drawn line takes on a frame this size. `nil` is a
    /// shape landing on bare canvas, which is nobody's icon.
    public static func startingWidth(armed: CGFloat, onFrameSized size: CGSize?) -> CGFloat {
        // A weight somebody picked is theirs. Only the one every tool ships
        // with is the app's to change.
        guard armed == AnnotationContent.defaultStrokeWidth else { return armed }
        guard let size, IconPreviews.isIconSize(size) else { return armed }
        return min(armed, max(1, (size.width / linesAcrossAnIcon).rounded()))
    }
}

extension PhotonzDocument {

    /// The size of the icon frame a shape centred on this point would join, or
    /// nil when that is a screen, or no frame at all.
    ///
    /// The same question `addLayerDrawnOnFrame` asks when it decides which
    /// frame adopts a new shape, so the weight a shape arrives at and the frame
    /// it arrives in can never disagree.
    public func iconFrameSize(under point: CGPoint) -> CGSize? {
        guard let id = frameID(under: point), let frame = layer(id: id),
              IconPreviews.isIconSize(frame.frame.size) else { return nil }
        return frame.frame.size
    }

    /// The weight a freshly drawn line takes, landing centred on this point.
    public func startingStrokeWidth(armed: CGFloat, drawnAt point: CGPoint) -> CGFloat {
        IconStrokeWeight.startingWidth(armed: armed, onFrameSized: iconFrameSize(under: point))
    }

    /// A freshly drawn shape's line, started at the weight the canvas under
    /// `point` can carry.
    ///
    /// The width is handed back on whichever half of the shape is actually
    /// wearing it: a line and an arrow ARE their stroke, a box and an oval wear
    /// a Border in their Effects list (`OutlineRetirement.swift`). Both halves
    /// come back together because the draft under the hand is drawn from the
    /// same pair, and a draft that previewed one weight and landed another
    /// would jump on release.
    ///
    /// A highlight is a wash rather than a line, so it is left alone.
    public func startingOutline(content: AnnotationContent, style: LayerStyle?,
                                drawnAt point: CGPoint)
        -> (content: AnnotationContent, style: LayerStyle?) {
        guard content.shape != .highlight else { return (content, style) }
        let border = style?.borderWidth ?? 0
        let armed = max(content.strokeWidth, border)
        let started = startingStrokeWidth(armed: armed, drawnAt: point)
        guard started != armed else { return (content, style) }
        var content = content
        var style = style
        if content.strokeWidth > 0 { content.strokeWidth = started }
        if border > 0 { style?.borderWidth = started }
        return (content, style)
    }
}
