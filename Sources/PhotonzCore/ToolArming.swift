import Foundation

/// One kind of shape, and what the tool that draws it comes away armed with
/// after a colour row settled the shapes of that kind. A nil paint is an
/// answer too: it means the next box comes out an outline.
public struct ToolArming: Hashable, Sendable {
    public let shape: AnnotationShape
    public let paint: Paint?

    public init(shape: AnnotationShape, paint: Paint?) {
        self.shape = shape
        self.paint = paint
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
    func toolArming(layerIDs: [UUID], slot: ColorSlot) -> [ToolArming] {
        var order: [AnnotationShape] = []
        var painted: [AnnotationShape: [Paint?]] = [:]
        for id in layerIDs {
            guard let layer = layer(id: id), !layer.isLocked,
                  let shape = layer.annotation?.shape,
                  layer.colorSlots.contains(slot) else { continue }
            if painted[shape] == nil { order.append(shape) }
            painted[shape, default: []].append(layer.paint(for: slot))
        }
        return order.compactMap { shape in
            guard let paints = painted[shape], let first = paints.first,
                  paints.allSatisfy({ Self.sameArming($0, first) }) else { return nil }
            return ToolArming(shape: shape, paint: first)
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
    mutating func arm(_ paint: Paint?, slot: ColorSlot, forShape shape: AnnotationShape) {
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
    }
}
