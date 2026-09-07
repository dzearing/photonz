import Foundation

/// One kind of shape, and what the tool that draws it comes away armed with
/// after a colour row settled the shapes of that kind. A nil paint is an
/// answer too: it means the next box comes out an outline.
public struct ToolArming: Hashable, Sendable {
    public let shape: AnnotationShape
    public let paint: Paint?
    /// The saved colour the shapes were wearing, when they all wore the same
    /// one. Nil means the colour is just a colour, so the tool comes away
    /// holding a colour rather than a name — which is also the honest answer
    /// when only some of them wore it.
    public let styleID: UUID?

    public init(shape: AnnotationShape, paint: Paint?, styleID: UUID? = nil) {
        self.shape = shape
        self.paint = paint
        self.styleID = styleID
    }
}

public extension PhotonzDocument {

    /// Which tools a colour row's pick leaves armed, and with what.
    ///
    /// Painting something that already exists arms the tool that draws it, so
    /// the next one of that kind comes out the colour you just chose. The
    /// toolbar swatch has always worked that way; so do Thickness, Corner
    /// Radius and the Effects sliders in the right-hand panel. This is the
    /// reading that lets the panel's colour rows work that way too.
    ///
    /// Every KIND of shape the pick reached is answered for on its own, which
    /// is why painting a box and an arrow blue leaves both of those tools blue
    /// and leaves the ellipse tool alone. A kind whose shapes do not agree
    /// after the change is left out rather than guessed at: there is no single
    /// colour to hand the tool, and handing it one of them would arm it with a
    /// colour nobody chose.
    ///
    /// Locked layers have no say. A pick on the row could not repaint them, so
    /// letting one hold the old colour would stop the pick arming anything.
    /// A saved colour comes away with it. Point three boxes at Accent and the
    /// box tool is holding Accent, so the next box wears the NAME and still
    /// follows it the day Accent is edited. A kind whose shapes wear DIFFERENT
    /// names, or where only some of them wear one, comes away with the colour
    /// and no name: printing a name half of them wear is how you carry one into
    /// work that never asked for it.
    func toolArming(layerIDs: [UUID], slot: ColorSlot) -> [ToolArming] {
        var order: [AnnotationShape] = []
        var painted: [AnnotationShape: [Paint?]] = [:]
        var named: [AnnotationShape: [UUID?]] = [:]
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  let shape = layer.annotation?.shape,
                  layer.colorSlots.contains(slot) else { continue }
            if painted[shape] == nil { order.append(shape) }
            painted[shape, default: []].append(layer.paint(for: slot))
            named[shape, default: []].append(layer.colorStyleID(for: slot))
        }
        return order.compactMap { shape in
            guard let paints = painted[shape], let first = paints.first,
                  paints.allSatisfy({ Self.sameArming($0, first) }) else { return nil }
            let names = named[shape] ?? []
            let name = names.first.flatMap { first in
                names.allSatisfy { $0 == first } ? first : nil
            }
            return ToolArming(shape: shape, paint: first, styleID: name)
        }
    }

    /// Paint-deep, so two boxes with the same base colour under different
    /// ramps do NOT agree — arming a tool from them would flatten a gradient
    /// somebody aimed.
    private static func sameArming(_ a: Paint?, _ b: Paint?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return a.draws(sameAs: b)
        default: return false
        }
    }
}

public extension AnnotationStyles {

    /// Arms `shape`'s tool from a colour row, on the part of the shape that row
    /// paints: its outline, or its inside.
    ///
    /// A ring and a text block's ink go past without doing anything. A border
    /// is styling laid over whatever the layer is rather than part of the shape
    /// itself, so it is remembered with the rest of a shape's look; new text
    /// takes the foreground colour, so there is no text default to arm.
    ///
    /// `styleID` is the saved colour the shapes were wearing. Passing one means
    /// the tool holds the NAME, so the next shape follows it when it is edited;
    /// passing none puts the tool back to holding a plain colour, which is what
    /// picking one off a swatch row means. `name` is what that colour is called,
    /// remembered beside the id so the app can name it in a document that does
    /// not have it.
    mutating func arm(_ paint: Paint?, styleID: UUID? = nil, name: String? = nil,
                      slot: ColorSlot, forShape shape: AnnotationShape) {
        switch slot {
        case .stroke:
            // A line always has a colour, so there is no "nothing" to arm with.
            guard let paint else { return }
            setPaint(paint, forShape: shape)
        case .fill:
            guard shape == .rectangle || shape == .ellipse else { return }
            setFillPaint(paint, forShape: shape)
        case .text, .border:
            return
        }
        // After the paint, never before: painting a slot is exactly how a tool
        // lets go of the name it was holding.
        setColorStyleID(styleID, slot: slot, forShape: shape, name: name)
    }
}

/// One kind of shape, and the line the tool that draws it comes away with after
/// the Outline switch settled the shapes of that kind.
public struct OutlineArming: Hashable, Sendable {
    public let shape: AnnotationShape
    /// Zero when the line was switched off, which is a real answer: the next
    /// box of that kind comes out with no line round it, exactly the way a nil
    /// paint on the Fill row means the next one comes out empty.
    ///
    /// Nil means the line is ON but there is no ONE thickness to hand over,
    /// because the shapes it reached came back at widths that differ. The tool
    /// keeps the thickness it already had rather than being given a number
    /// nobody chose.
    public let width: CGFloat?

    public init(shape: AnnotationShape, width: CGFloat?) {
        self.shape = shape
        self.width = width
    }
}

public extension PhotonzDocument {

    /// Which tools the Outline switch leaves armed, and with what line.
    ///
    /// Switching a box's outline off is the person saying they want boxes with
    /// no outline, the same way emptying its inside says they want boxes with
    /// no fill and pulling Thickness says how thick the next one is. Read AFTER
    /// the change, so it is the line the shapes are wearing now rather than the
    /// one that was aimed at them.
    ///
    /// Every KIND is answered for on its own, so taking the outline off a box
    /// leaves the ellipse tool alone.
    ///
    /// WHETHER the line is there is always handed over: the switch just set it,
    /// so there is nothing to guess. The THICKNESS is only handed over when the
    /// shapes agree on one. Switch two boxes of 2 and 10 off and then on again
    /// and they come back different, so the tool learns that boxes have a line
    /// and keeps its own thickness — being left saying "no line" right after
    /// somebody put the line back is the thing that would surprise them.
    ///
    /// Locked layers have no say, for the same reason they have none on a
    /// colour row: the switch could not reach them, so letting one hold the old
    /// width would stop the press arming anything.
    ///
    /// A ring round a picture, a label or a highlight is not here. That ring is
    /// styling laid over the layer rather than part of the shape, so it rides
    /// along with the rest of that layer's remembered look — the same way
    /// pulling its width in the Effects section already does.
    func outlineArming(layerIDs: [UUID]) -> [OutlineArming] {
        var order: [AnnotationShape] = []
        var widths: [AnnotationShape: [CGFloat]] = [:]
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked, layer.drawsItsOwnOutline,
                  let shape = layer.annotation?.shape else { continue }
            if widths[shape] == nil { order.append(shape) }
            widths[shape, default: []].append(layer.outlineWidth)
        }
        return order.compactMap { shape in
            guard let seen = widths[shape], let first = seen.first else { return nil }
            // A kind that cannot even agree whether it HAS a line is a kind the
            // switch only half reached, so it teaches nothing.
            let on = first > 0
            guard seen.allSatisfy({ ($0 > 0) == on }) else { return nil }
            let agreed = seen.allSatisfy { $0 == first }
            return OutlineArming(shape: shape, width: agreed ? first : nil)
        }
    }
}
