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
/// **It stops the moment you choose.** It applies only while NOBODY HAS CHOSEN
/// a weight. Pick one and that is the weight you get, on an icon frame or
/// anywhere else, because a starting value that reimposed itself after every
/// change would be a lock.
///
/// Whether somebody has chosen is something the app remembers
/// (`AnnotationStyles.strokeWidthWasChosen(for:)`) rather than something it
/// guesses from the number. It used to guess, by comparing the armed weight
/// against the four every tool ships with, and that cost two things at once: a
/// Width row reading 4 over a frame where the line would land at 2, and no way
/// to ask for a 4 on an icon frame at all, since asking looked exactly like not
/// having asked.
public enum IconStrokeWeight {

    /// How many lines of the starting weight lie across an icon. Sixteen is
    /// what puts 16 on one pixel and 24 on two.
    public static let linesAcrossAnIcon: CGFloat = 16

    /// The weight a freshly drawn line takes on a frame this size. `nil` is a
    /// shape landing on bare canvas, which is nobody's icon.
    ///
    /// `chosen` is whether the weight in `armed` is one somebody asked for. A
    /// weight somebody picked is theirs, whatever number it happens to be; only
    /// a weight nobody has picked is the app's to decide.
    public static func startingWidth(armed: CGFloat, chosen: Bool,
                                     onFrameSized size: CGSize?) -> CGFloat {
        guard !chosen else { return armed }
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
        guard let id = iconFrameID(under: point), let frame = layer(id: id) else { return nil }
        return frame.frame.size
    }

    /// The size of the icon frame this layer is being drawn INSIDE, or nil when
    /// it is on a screen, on bare canvas, or is itself a screen.
    ///
    /// The frame itself when the frame is what is picked, and the frame above
    /// whatever is picked while a shape inside it is — which is the same
    /// question the icon previews strip asks to decide which icon it is
    /// showing (`IconPreviews.iconFrameID(containing:)`). So the Width row, the
    /// previews strip and the drawing all mean the same icon.
    public func iconFrameSize(containing id: UUID) -> CGSize? {
        guard let frameID = iconFrameID(containing: id),
              let frame = layer(id: frameID) else { return nil }
        return frame.frame.size
    }

    /// The weight a freshly drawn line takes, landing centred on this point.
    public func startingStrokeWidth(armed: CGFloat, chosen: Bool,
                                    drawnAt point: CGPoint) -> CGFloat {
        IconStrokeWeight.startingWidth(armed: armed, chosen: chosen,
                                       onFrameSized: iconFrameSize(under: point))
    }

    /// The weight a freshly drawn line takes in the frame this layer is in.
    ///
    /// What the Width row on the tool bar reads while an icon is what you are
    /// working in. It is the same rule the drawing itself goes through, asked
    /// of the frame rather than of a point, because a row is read before there
    /// is any point to ask about.
    public func startingStrokeWidth(armed: CGFloat, chosen: Bool,
                                    drawingInside id: UUID) -> CGFloat {
        IconStrokeWeight.startingWidth(armed: armed, chosen: chosen,
                                       onFrameSized: iconFrameSize(containing: id))
    }

    /// The icon the Width row is speaking for, from the two things that can
    /// say so: what is PICKED, and failing that, the frame the POINTER is
    /// resting in.
    ///
    /// What is picked comes first, because a shape you have chosen is the
    /// thing you are working on wherever the hand happens to be. It answers
    /// even when the answer is "no icon": picking a shape on a screen and then
    /// sweeping the pointer across an icon does not make the row speak for the
    /// icon.
    ///
    /// The pointer is the case this was added for. Pick nothing at all, hold
    /// the Pen over a 24 pixel frame and draw, and the line lands at 2 because
    /// the drawing asks about the point it is landing on. The row had nothing
    /// to ask about and went on reading the armed 4, so the app said one number
    /// and drew another — the one thing a box you can type into must not do.
    public func iconFrameSize(picked: UUID?, pointerIn hovered: UUID?) -> CGSize? {
        guard let id = picked ?? hovered else { return nil }
        return iconFrameSize(containing: id)
    }

    /// The weight the Width row reads with a tool in hand and nothing drawn
    /// yet: the armed weight, after whichever icon is being worked in has had
    /// its say (`iconFrameSize(picked:pointerIn:)`).
    public func startingStrokeWidth(armed: CGFloat, chosen: Bool,
                                    picked: UUID?, pointerIn hovered: UUID?) -> CGFloat {
        IconStrokeWeight.startingWidth(armed: armed, chosen: chosen,
                                       onFrameSized: iconFrameSize(picked: picked,
                                                                   pointerIn: hovered))
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
                                chosen: Bool, drawnAt point: CGPoint)
        -> (content: AnnotationContent, style: LayerStyle?) {
        guard content.shape != .highlight else { return (content, style) }
        let border = style?.borderWidth ?? 0
        let armed = max(content.strokeWidth, border)
        let started = startingStrokeWidth(armed: armed, chosen: chosen, drawnAt: point)
        guard started != armed else { return (content, style) }
        var content = content
        var style = style
        if content.strokeWidth > 0 { content.strokeWidth = started }
        if border > 0 { style?.borderWidth = started }
        return (content, style)
    }
}
