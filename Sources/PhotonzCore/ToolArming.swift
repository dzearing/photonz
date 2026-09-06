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
