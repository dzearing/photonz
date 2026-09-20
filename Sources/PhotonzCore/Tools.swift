import CoreGraphics
import Foundation

/// The editor's modal tool. `select` is the resting state (hit-test, move,
/// marquee); annotation tools create layers by dragging; `crop` and `text`
/// have their own interactions (phases 4 and 3.4).
public enum Tool: String, CaseIterable, Hashable, Codable, Sendable {
    case select
    case crop
    /// Bounds in TIME: pick it up in a document that runs for a length of time
    /// and the clip you are on gets a handle at each end, on its own bar in the
    /// timeline (`docs/design/video-surface.md` §10). It shares Crop's slot and
    /// Crop's letter, because shortening a picture and shortening a recording
    /// are the same act on two different axes.
    case trim
    case arrow
    case line
    case rectangle
    case ellipse
    case highlight
    case text
    case zoomCallout
    /// Draws a lens: a box that changes whatever is underneath it (Next,
    /// `next-lens`). Blur an address, pixelate a name, grey out a region.
    case lens
    case measure
    /// Paint bucket: click a layer to fill it with the foreground color
    /// (⌥ = background color). See `Fill` for per-content semantics.
    case fill
    /// Region selection (phase 17): drag a rectangular / elliptical region,
    /// or wand-click a contiguous color area. ⇧ adds, ⌥ subtracts, ⇧⌥
    /// intersects with the existing region (`SelectionRegion.Mode`).
    case rectSelect
    case ellipseSelect
    case wand
    /// Draws a frame: the fixed-size box a screen gets built on (Next,
    /// `next-frames`). A drag makes one the size you drew, a plain click drops
    /// one at the size you picked last.
    case frame
    /// The vector Pen (Next, `next-pen`): click a corner, press and drag a
    /// curve, and the run of anchors becomes a path layer
    /// (`docs/design/vector-paths.md`). The one tool in the app that draws over
    /// several clicks rather than in one drag.
    case pen

    /// The single key that picks this tool, everywhere in the product.
    ///
    /// Photoshop parity is the house rule, so V/C/T/L/R/O/G land where a
    /// Photoshop user reaches for them. Two deliberate departures, both because
    /// Photoshop has no equivalent tool to be compatible with:
    ///
    /// - **Arrow is A**, the Snagit / Preview convention for a callout arrow.
    ///   It is emphatically NOT P: P is the vector Pen everywhere else in the
    ///   product, and a key that means two things depending on which surface
    ///   you are looking at teaches people to stop trusting shortcuts.
    /// - **Measure is I**, not M. M is the Photoshop marquee, and Photoshop
    ///   itself files the Ruler under I.
    ///
    /// Nil for the marquee pair: rectangle and ellipse select share one toolbar
    /// slot and one letter, so the key belongs to the group rather than to
    /// either tool. M hands you a marquee and swaps the box for the ellipse
    /// when you press it again (`ToolGroup.tool(forKey:active:remembered:)`),
    /// which is Photoshop's M with its shift preference turned off; ⇧M walks
    /// the whole slot, wand included.
    public var shortcutKey: Character? {
        switch self {
        case .select: "v"
        // One letter for the pair that changes a thing's bounds: C hands you
        // whichever of Crop and Trim you used last and swaps when you press it
        // again (`ToolGroup.bounds`). Crop keeps the letter of its own rather
        // than handing it to the family, so the ungrouped bar — which is what
        // Current ships and what Next shows with tool groups off — still has a
        // C that crops.
        case .crop, .trim: "c"
        case .arrow: "a"
        case .line: "l"
        case .rectangle: "r"
        case .ellipse: "o"
        case .highlight: "h"
        case .text: "t"
        case .zoomCallout: "z"
        // K is one of the two letters Photoshop leaves unassigned, so a tool
        // Photoshop has no equivalent for displaces nothing. B, E, S, J, U and
        // Y all belong to brushes, erasers and stamps this app will want later.
        case .lens: "k"
        case .measure: "i"
        case .fill: "g"
        case .wand: "w"
        // P is the vector Pen everywhere in the product, which is why the
        // arrow moved off it (see above). Photoshop's P is the pen too, so
        // this is parity rather than a departure.
        case .pen: "p"
        // F is the design-tool convention for a frame. Photoshop's F cycles
        // screen modes, which this app does not have, so nothing is displaced.
        case .frame: "f"
        case .rectSelect, .ellipseSelect: nil
        }
    }

    /// How the key is PRINTED in a tooltip or a menu row. Derived from
    /// `shortcutKey`, so what a surface teaches can never drift from what the
    /// keyboard actually does.
    public var shortcutHint: String? {
        shortcutKey.map { String($0).uppercased() }
    }

    /// The annotation shape this tool draws, nil for non-annotation tools.
    public var annotationShape: AnnotationShape? {
        switch self {
        case .arrow: .arrow
        case .line: .line
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .highlight: .highlight
        case .select, .crop, .trim, .text, .zoomCallout, .lens, .measure, .fill,
             .rectSelect, .ellipseSelect, .wand, .frame, .pen: nil
        }
    }

    /// Whether this tool edits the selection REGION (not layer selection).
    public var isRegionSelectionTool: Bool {
        self == .rectSelect || self == .ellipseSelect || self == .wand
    }

    /// The marquee pair that shares one toolbar slot (Photoshop's M group).
    public var isMarqueeSelectTool: Bool {
        self == .rectSelect || self == .ellipseSelect
    }

    /// Whether switching TO this tool keeps the LAYER selection.
    /// The selection family keeps it, and so does the fill bucket, because
    /// both act on the layer you picked. A drawing, crop or text tool drops
    /// it: its handles are select-mode chrome and would read as interactive.
    ///
    /// The marquee REGION is deliberately NOT gated on the tool. It survives
    /// every tool change, the way it does in Photoshop, so an outline you
    /// placed by hand is never thrown away by a stray tool key (decided
    /// 2026-09-13, "It stays up"). Only a click on bare canvas or ⎋ clears it.
    /// The PEN is on the list as well, for the same reason: a picked path's
    /// points are live under the Pen (`CanvasNSView.editablePath`), so pressing
    /// P over a shape is how its anchors are reached. Dropping the pick on the
    /// way in would take the points off the canvas at the exact moment they
    /// were asked for. Nothing else survives: the Pen's first anchor lets go of
    /// whatever was picked (`penMouseDown`), so a pick only lasts as long as it
    /// is being worked on.
    /// Trim is on the list for the same reason the Pen is: the clip it acts
    /// on is the one you picked, and dropping the pick on the way in would
    /// take away the thing the tool was reached for.
    public var preservesLayerSelection: Bool {
        self == .select || self == .fill || self == .pen || self == .trim
            || isRegionSelectionTool
    }

    public var createsAnnotationByDrag: Bool { annotationShape != nil }

    /// Whether a double click on BARE canvas — the matte, or a locked base
    /// image, anywhere that is not an editable layer — zooms the window.
    ///
    /// The app hides its title bar, so there is no strip left to double click
    /// and the background behind the picture stands in for one. That is a help
    /// while you are looking at a picture and wrong while you are drawing on
    /// it: a tool that places by CLICKING gets two quick clicks a short span
    /// apart delivered as a double click, and the window jumping to full screen
    /// in the middle of a stroke is not something you can undo.
    ///
    /// So the window keeps the gesture only where nothing is being put on the
    /// picture: Select, which is the resting state, Crop, which trims rather
    /// than adds, and the marquee trio, which sweep a region. Every tool that
    /// draws, measures or paints owns its own clicks.
    ///
    /// Exhaustive on purpose. The Pen was carved out of the old rule by name
    /// after it collided with it; a click-to-place tool added later has to
    /// answer here instead of waiting for someone to hit the same thing.
    public var doubleClickOnEmptyCanvasZoomsWindow: Bool {
        switch self {
        // Trim is on the true side with Crop: it shortens rather than adds,
        // and its own gesture lives in the timeline rather than on the picture,
        // so a double click on the matte has nothing of its to collide with.
        case .select, .crop, .trim, .rectSelect, .ellipseSelect, .wand: true
        case .arrow, .line, .rectangle, .ellipse, .highlight, .text,
             .zoomCallout, .lens, .measure, .fill, .frame, .pen: false
        }
    }

    /// Whether this tool MAKES something: finish the gesture and the document
    /// has a layer in it that was not there before.
    ///
    /// It exists so the app's ending rule can be said over the whole set at
    /// once — every tool that makes something hands you back to Select with
    /// the new thing picked (`ArrowCaptionEntry.toolAfterLanding`) — instead of
    /// each tool's own commit remembering to. A tool added later has to answer
    /// here, so it cannot quietly become the exception.
    ///
    /// The other six act on what is already there: Select picks and moves,
    /// Crop trims the picture, the bucket repaints a layer, and the marquee
    /// pair and the wand sweep a region rather than adding to the stack.
    public var createsLayers: Bool {
        switch self {
        case .arrow, .line, .rectangle, .ellipse, .highlight, .text,
             .zoomCallout, .lens, .measure, .frame, .pen: true
        case .select, .crop, .trim, .fill, .rectSelect, .ellipseSelect, .wand: false
        }
    }

    /// What the tool bar's colour capsule carries for this tool.
    ///
    /// The bar used to show SOMETHING whatever was in hand: with Select, which
    /// puts no colour anywhere, it still parked the foreground/background pair
    /// and a swap button in the scarcest strip in the app, setting a colour
    /// nothing was about to use. A control that cannot act on anything is
    /// noise, so which capsule a tool gets is answered here, on the tool, where
    /// a tool added later cannot forget to answer it.
    public var colorControl: ToolColorControl {
        switch self {
        // A box has two tones, an interior and a border, so it gets both.
        case .rectangle, .ellipse: .fillAndBorder
        // A stroke, a highlight or a run of type has one colour. So does a
        // path: it is the line while it is open and the shape once it closes,
        // and both are drawn in the one ink the Pen is armed with, so the Pen
        // wears the same single swatch rather than a pair that would be two
        // places to set what is really one colour.
        case .arrow, .line, .highlight, .text, .pen: .toolColor
        // The bucket paints from the foreground/background pair, and it is the
        // only tool that does, so the pair lives with it.
        case .fill: .foregroundBackground
        // Everything else picks, cuts, measures or frames. None of them put a
        // colour on the picture. The frame tool draws its own fixed grey.
        // A lens puts no colour on the picture either: it shows the colours
        // already there, changed.
        case .select, .crop, .trim, .zoomCallout, .lens, .measure,
             .rectSelect, .ellipseSelect, .wand, .frame: .hidden
        }
    }

    /// Whether this tool puts colour on the picture, and so earns swatches on
    /// the tool bar.
    public var paints: Bool { colorControl != .hidden }

    /// The measure tool drags two reference points to create a dimension layer.
    public var createsMeasureByDrag: Bool { self == .measure }

    /// Smart-default content for this tool: red strokes, yellow highlight
    /// (system palette colors). Nil for non-annotation tools.
    public var defaultAnnotation: AnnotationContent? {
        AnnotationStyles().content(for: self)
    }
}

/// The colour control the tool bar shows for the tool in hand.
///
/// One value per shape the capsule can take, including taking none: `hidden`
/// means no glass, no swatches and no room reserved, so the bar gives the
/// space back to the picture rather than leaving a gap.
public enum ToolColorControl: String, CaseIterable, Hashable, Codable, Sendable {
    /// No capsule at all. The tool paints nothing, so there is nothing to set.
    case hidden
    /// The tool's own single colour, which opens that tool's style popover.
    case toolColor
    /// An interior fill over a border: the two tones a box has.
    case fillAndBorder
    /// The foreground and background paint pair, and the swap between them.
    case foregroundBackground
}

/// An in-progress drag-to-create annotation, tracked in document coordinates.
/// Mirrors `MarqueeDrag`: the canvas feeds it pointer positions, all geometry
/// decisions live here.
public struct AnnotationDrag: Equatable, Sendable {
    public var anchor: CGPoint
    public var current: CGPoint

    public init(anchor: CGPoint) {
        self.anchor = anchor
        self.current = anchor
    }

    public mutating func update(to point: CGPoint) {
        current = point
    }

    /// The effective endpoint. Constrained (⇧): lines/arrows snap to the
    /// nearest 45° preserving length; box shapes square off the longer axis.
    public func end(constrained: Bool, shape: AnnotationShape) -> CGPoint {
        guard constrained else { return current }
        let dx = current.x - anchor.x
        let dy = current.y - anchor.y
        switch shape {
        case .line, .arrow:
            let length = hypot(dx, dy)
            guard length > 0 else { return current }
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            return CGPoint(x: anchor.x + cos(angle) * length,
                           y: anchor.y + sin(angle) * length)
        case .rectangle, .ellipse, .highlight:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: anchor.x + (dx < 0 ? -side : side),
                           y: anchor.y + (dy < 0 ? -side : side))
        }
    }

    /// Whether the pointer moved so little this is a click, not a drag.
    /// Tolerance is in view points so it feels the same at any zoom.
    public func isClick(atZoom zoom: CGFloat, tolerance: CGFloat = 4) -> Bool {
        hypot(current.x - anchor.x, current.y - anchor.y) * zoom < tolerance
    }
}

/// Builds annotation layers from completed drags.
public enum AnnotationBuilder {

    /// The layer a drag from `start` to `end` (document coordinates) creates.
    /// The frame is the drag's bounding box padded by the content's render
    /// overhang (round caps, arrowhead wings) so rasterization never clips,
    /// and the content's start/end are re-expressed in layer-local coords.
    public static func layer(content: AnnotationContent, from start: CGPoint, to end: CGPoint) -> Layer {
        var content = content
        let pad = content.renderPadding
        var box = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                         width: abs(end.x - start.x), height: abs(end.y - start.y))
            .insetBy(dx: -pad, dy: -pad)
        // Reserve room for the caption pill (plus its shadow) hanging off an
        // arrow's tail, so the label never clips at the frame edge — mirrors
        // MeasureBuilder's chip reservation.
        if content.hasCaption {
            var probe = content
            probe.start = start
            probe.end = end
            let size = probe.estimatedCaptionSize
            let anchor = probe.captionAnchor()
            let slack = AnnotationContent.captionShadowPadding
            box = box.union(CGRect(x: anchor.x - size.width / 2, y: anchor.y - size.height / 2,
                                   width: size.width, height: size.height)
                .insetBy(dx: -slack, dy: -slack))
        }
        // The rasterizer needs at least one pixel each way (a perfectly
        // horizontal highlight drag would otherwise collapse).
        box.size.width = max(box.size.width, 1)
        box.size.height = max(box.size.height, 1)
        content.start = CGPoint(x: start.x - box.minX, y: start.y - box.minY)
        content.end = CGPoint(x: end.x - box.minX, y: end.y - box.minY)
        return Layer(name: name(for: content.shape), content: .annotation(content), frame: box)
    }

    private static func name(for shape: AnnotationShape) -> String {
        switch shape {
        case .arrow: "Arrow"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .highlight: "Highlight"
        }
    }
}

extension AnnotationContent {
    /// How far drawing can extend beyond the start/end bounding box.
    /// Rectangles/ellipses inset their stroke and highlights fill, so only
    /// open strokes (caps) and arrowheads (wings) overhang.
    public var renderPadding: CGFloat {
        switch shape {
        case .line:
            // How far the END of the line reaches past the point it stops on,
            // which is half a width for a flat or a round one and further for
            // a square one (`PathLineStyle.swift`).
            (strokeWidth * lineEnd.reach).rounded(.up)
        case .arrow:
            // A round ending hangs past the point it marks, so this is the
            // ending's reach in every direction, not just its width.
            max(strokeWidth * lineEnd.reach,
                Geometry.arrowheadReach(strokeWidth: strokeWidth, scale: arrowheadScale,
                                        style: arrowheadStyle)).rounded(.up)
        case .rectangle, .ellipse, .highlight:
            0
        }
    }
}
