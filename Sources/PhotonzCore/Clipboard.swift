import CoreGraphics
import Foundation

/// The pasteboard payload for copying layers within (or between) Photonz
/// windows. Image-content layers carry their bitmap as encoded data because
/// `ImageRef` only means something inside the source window's ImageStore.
public struct LayerTransfer: Codable, Sendable {
    public var layer: Layer
    /// Encoded bitmap (PNG) for image-content layers; nil for text,
    /// annotation, and zoom-callout layers, which are pure model data.
    public var imageData: Data?

    public init(layer: Layer, imageData: Data? = nil) {
        self.layer = layer
        self.imageData = imageData
    }

    private enum CodingKeys: String, CodingKey { case layer, imageData }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A layer copied out of a build from before the Outline row left
        // Appearance arrives with its edge as its own stroke; it lands here as
        // a Border in the Effects list, painting the same pixels
        // (`OutlineRetirement.swift`).
        layer = try c.decode(Layer.self, forKey: .layer).retiringItsOutline()
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
    }

    /// Custom pasteboard type identifying a serialized Photonz layer.
    public static let pasteboardType = "com.photonz.layer"
}

public enum PastePlacement {
    /// Where an image pasted from the system clipboard lands: centered on the
    /// canvas at full size, scaled down (aspect-fit) only when it would
    /// overflow.
    public static func frame(forImageOf size: CGSize, canvas: CGSize) -> CGRect {
        frame(forImageOf: size, in: CGRect(origin: .zero, size: canvas))
    }

    /// The same rule against any box, which is what lets an image dropped on a
    /// screen sit centred in THAT screen rather than in the whole canvas: full
    /// size when it fits, aspect-fitted when it does not.
    public static func frame(forImageOf size: CGSize, in box: CGRect) -> CGRect {
        var placed = size
        if size.width > box.width || size.height > box.height {
            placed = Geometry.aspectFit(size, in: box.size)
        }
        return CGRect(x: box.midX - placed.width / 2,
                      y: box.midY - placed.height / 2,
                      width: placed.width, height: placed.height)
    }

    /// A box of `size` centred on `point`, nudged just far enough to sit
    /// wholly inside `box`. This is what letting go of something means: it
    /// lands under the pointer, and never half over an edge where half of it
    /// would be invisible.
    public static func frame(of size: CGSize, centeredOn point: CGPoint, in box: CGRect) -> CGRect {
        CGRect(x: min(max(point.x - size.width / 2, box.minX), box.maxX - size.width),
               y: min(max(point.y - size.height / 2, box.minY), box.maxY - size.height),
               width: size.width, height: size.height)
    }
}

/// Where each paste of one thing lands when you paste it again and again.
///
/// Pasting a copied layer steps it down and right off the layer it came from,
/// so the copy is visible instead of hiding exactly on top of its original.
/// Pasting the same thing again used to take that same single step every time,
/// which stacked every copy in one spot: the picture looked unchanged and only
/// the layers list showed that anything had happened. Each paste now steps past
/// the last one, the way duplicating a duplicate walks down the picture.
///
/// The ladder is anchored to where the FIRST paste went, not to wherever a copy
/// has since been dragged, so a run of pastes stays beside the layer it came
/// from. And because the caller passes the previous landing only while that copy
/// is still in the document, undoing a paste frees its spot for the next one
/// instead of leaving a hole in the ladder.
public enum PasteCascade {

    /// How far each paste steps, in canvas points.
    public static let step = CGPoint(x: 16, y: 16)

    /// One step down and right: where a copy goes so it does not hide the thing
    /// it was made from.
    public static func stepped(_ frame: CGRect) -> CGRect {
        frame.offsetBy(dx: step.x, dy: step.y)
    }

    /// The frame the next paste should take.
    ///
    /// `first` is where the first paste of this clipboard belongs — beside the
    /// layer it was copied from, or the middle of the canvas for a picture that
    /// came from outside. `previous` is where this same clipboard's last paste
    /// actually landed in this window, and is nil when there has not been one
    /// or that copy is gone again.
    ///
    /// A ladder that has walked off the picture starts over at the first rung,
    /// so pasting can never march a copy somewhere nobody can see it.
    public static func frame(landingAt first: CGRect, after previous: CGRect?,
                             canvas: CGSize) -> CGRect {
        guard let previous else { return first }
        let box = CGRect(origin: .zero, size: canvas)
        let candidate = stepped(previous)
        if candidate.intersects(box) { return candidate }
        return first.intersects(box) ? first : candidate
    }
}

extension PhotonzDocument {

    /// A layer ready to leave the document: itself, with its position moved
    /// into CANVAS space.
    ///
    /// Copying a button out of a screen has to remember where that button was
    /// on the canvas, not where it was inside its screen, or pasting it back
    /// would fling it to the top left of the world. Only the layer's own
    /// origin moves: a group's contents stay in the group's space, exactly as
    /// they are stored, so nothing inside it shifts.
    public func detachedLayer(id: UUID) -> Layer? {
        guard var layer = layer(id: id), let origin = parentOrigin(of: id) else { return nil }
        layer.frame = layer.frame.offsetBy(dx: origin.x, dy: origin.y)
        return layer
    }

    /// Where an image arriving from outside the document should land, in
    /// canvas coordinates.
    ///
    /// `point` is where the pointer let go, in canvas coordinates, or nil for
    /// a paste, which has no pointer.
    ///
    /// Letting go of something puts it where you let go, so a dropped picture
    /// lands centred on the pointer — the same way a component dragged off the
    /// shelf does. The box it lands in is the screen under the pointer, or the
    /// whole canvas when there is no screen there. Either way it is sized to
    /// fit that box (a picture that arrives four times too big and clipped to
    /// its middle is not what anybody meant) and nudged just far enough to sit
    /// wholly inside it rather than half over an edge.
    ///
    /// A paste has no pointer, so it keeps arriving in the middle of whatever
    /// box it falls on.
    public func placementForIncomingImage(size: CGSize, at point: CGPoint? = nil) -> CGRect {
        let canvas = CGRect(origin: .zero, size: canvasSize)
        let probe = point ?? CGPoint(x: canvas.midX, y: canvas.midY)
        let box = frameID(under: probe).flatMap { canvasBounds(of: $0) } ?? canvas
        let fitted = PastePlacement.frame(forImageOf: size, in: box)
        guard let point else { return fitted }
        return PastePlacement.frame(of: fitted.size, centeredOn: point, in: box)
    }

    /// Where an image let go on the right hand PANEL lands, in canvas
    /// coordinates: centred on, and fitted into, whatever list it is joining —
    /// the frame it lands inside, or the whole canvas.
    ///
    /// A drop on the panel has no canvas point behind it: you are pointing at
    /// a place in the STACK, not at a place on the picture. So it lands in the
    /// middle of its new home, which is where the drop line already promised
    /// it would be.
    public func placementForIncomingImage(size: CGSize, landingAt drop: LayerDrop) -> CGRect {
        PastePlacement.frame(forImageOf: size, in: incomingPlacementBox(drop))
    }
}

/// The tool a paste took out of your hand, and when to give it back.
///
/// A paste hands you the pointer, because the obvious next move after pasting
/// something is dragging it into place, and leaving a drawing tool in hand
/// means that drag draws a new shape instead. That is a good trade while the
/// pasted thing is standing, and a bad one the moment you take it back: press
/// Command Z and being left holding a tool you never picked is its own
/// surprise.
///
/// So the tool you were holding is remembered against the layer the paste made,
/// and it comes back when, and only when, that layer goes away again. Three
/// rules keep it from ever arriving unasked:
///
/// - A run of pastes remembers what the FIRST of them displaced, so undoing
///   the whole run puts back what you started with and undoing one copy out of
///   several leaves the pointer in hand for the ones still there.
/// - A tool picked by hand wins. If the pointer is no longer what is in hand,
///   the paste no longer owns the tool and nothing is taken away.
/// - The caller drops the memory as soon as any other edit lands, so a tool
///   can never come back several steps later, long after the paste it belonged
///   to stopped being what you were thinking about.
public struct PasteToolReturn: Equatable, Sendable {
    /// The layer the run of pastes started with. The memory lives and dies
    /// with it: it is the one whose disappearance means the whole run is gone.
    public var layer: UUID
    /// The tool that was in hand when that run started.
    public var previous: Tool
    /// Whether an undo has already handed that tool back, so a redo of the
    /// same paste knows to take the pointer up again.
    public var isReturned: Bool

    public init(layer: UUID, previous: Tool, isReturned: Bool = false) {
        self.layer = layer
        self.previous = previous
        self.isReturned = isReturned
    }

    /// What to remember after a paste lands, given the tool that was in hand
    /// on the way in and whatever an earlier paste in the same run left behind.
    ///
    /// Nil means there is nothing to give back: the pointer was already in
    /// hand and no earlier paste took anything away.
    public static func after(pasting layer: UUID, holding tool: Tool,
                             carrying carried: PasteToolReturn?) -> PasteToolReturn? {
        // Still the same run, so the first paste's tool is the one owed back.
        if let carried, !carried.isReturned { return carried }
        // Nothing to give back when the pointer is already in hand. Crop is
        // left out too: it is a mode with a pending rectangle, the paste threw
        // that rectangle away, and dropping somebody back into a half-finished
        // crop on Command Z would be a bigger surprise than the one this is
        // here to prevent.
        guard tool != .select, tool != .crop else { return nil }
        return PasteToolReturn(layer: layer, previous: tool)
    }

    /// The tool to put back once an undo has run, or nil to leave what is in
    /// hand alone. `pastedLayerGone` says whether that undo is the one that
    /// took the remembered layer out of the document.
    public func toolAfterUndo(pastedLayerGone: Bool, holding tool: Tool) -> Tool? {
        guard !isReturned, pastedLayerGone, tool == .select else { return nil }
        return previous
    }

    /// The tool to take up again once a redo has put the remembered layer
    /// back: the pointer, exactly as the paste first handed it over.
    public func toolAfterRedo(pastedLayerBack: Bool, holding tool: Tool) -> Tool? {
        guard isReturned, pastedLayerBack, tool != .select else { return nil }
        return .select
    }

    /// Records that the tool has been handed back, so it is not handed back
    /// twice.
    public mutating func markReturned() {
        isReturned = true
    }
}
