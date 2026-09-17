import CoreGraphics
import Foundation

/// Writes a document out as a real SVG: the shapes you drew, as shapes
/// (`docs/design/svg-export.md`).
///
/// It is here, in the pure layer, because it is geometry and string building
/// and nothing else — no Core Image, no AppKit, no font machinery. The two
/// things it cannot do for itself are handed in:
///
/// * a **picture** of a layer that has no vector answer (an image layer, or a
///   shape wearing an effect SVG cannot say), made by whoever owns the
///   renderer;
/// * the **outline of a text layer's letters**, made by whoever owns the type
///   engine.
///
/// **Nothing is flipped on the way out.** The document model counts y from the
/// top and so does SVG, which is the one place in this codebase where the two
/// spaces already agree, so the flip `DocumentRenderer` owns has no business
/// here (`docs/design/overview.md`). A shape thirty points down the canvas is
/// thirty points down the file.
public enum SVGExport {

    /// Something the app could have said in shapes and could not, and what was
    /// written in its place.
    public struct Fallback: Hashable, Sendable {
        /// The layer as the layers list names it.
        public var layerName: String
        /// Why, in words a person can read: it goes on a dialog and in the
        /// export's own report.
        public var reason: String

        public init(layerName: String, reason: String) {
            self.layerName = layerName
            self.reason = reason
        }
    }

    /// A picture of one layer, and the box in CANVAS points it covers. The box
    /// is the picture's own reach, not the layer's frame: a shadow falls past
    /// the frame and the picture has to carry it.
    public struct Picture: Hashable, Sendable {
        public var png: Data
        public var box: CGRect

        public init(png: Data, box: CGRect) {
            self.png = png
            self.box = box
        }
    }

    /// What an export does with the canvas the drawing was made on.
    public enum Background: String, Hashable, Sendable, Codable, CaseIterable {
        /// Write it, exactly as the canvas shows it. What a screenshot, a
        /// photograph or a whole screen wants.
        case keep
        /// Leave the canvas out, so there is nothing painted behind the
        /// drawing and it sits on any colour it is dropped onto. Only the
        /// canvas goes: everything that is part of the drawing stays.
        case drop
    }

    /// The layer that is only the canvas the drawing sits on, and the colour
    /// it is.
    public struct Backdrop: Hashable, Sendable {
        /// The layer an export would leave out.
        public var layerID: UUID
        /// What colour it is, so the Export sheet can show what would go.
        public var color: RGBA

        public init(layerID: UUID, color: RGBA) {
            self.layerID = layerID
            self.color = color
        }
    }

    /// Asked for a picture of `layer`, whose frame sits at the given point in
    /// canvas coordinates. Nil where no picture could be made.
    public typealias PictureMaker = @Sendable (_ layer: Layer, _ canvasOrigin: CGPoint) -> Picture?

    /// Asked for the outline of a text layer's letters, as path data in the
    /// layer's OWN top-left coordinates. Nil where the words cannot be
    /// outlined.
    public typealias TextOutliner = @Sendable (_ layer: Layer, _ text: TextContent) -> String?

    /// What the labels the app draws FOR ITSELF need from whoever owns the type
    /// engine: how big the words come out, and what their outline is.
    ///
    /// A text layer is outlined through `TextOutliner`, which has a layer to
    /// read the box off. A caption on an arrow and the readout on a
    /// measurement have no layer of their own — they are parts of the thing
    /// they belong to, and their plate is sized from the words inside it — so
    /// the writer has to be able to ask, in the same words the canvas asks.
    public struct TypeSetter: Sendable {
        /// How big `text` is at `fontSize`, laid out unconstrained.
        public var size: @Sendable (_ text: String, _ fontSize: CGFloat) -> CGSize
        /// How far right of that box's left edge the ink really starts. The
        /// box carries its slack on the right, so centring the box would leave
        /// the word sitting left of the middle of its plate.
        public var inkOffset: @Sendable (_ text: String, _ fontSize: CGFloat) -> CGFloat
        /// The outline of `text` laid out in a box of `size`, as path data in
        /// that box's OWN top-left coordinates.
        public var outline: @Sendable (_ text: String, _ fontSize: CGFloat,
                                       _ size: CGSize) -> String?

        public init(size: @escaping @Sendable (String, CGFloat) -> CGSize,
                    inkOffset: @escaping @Sendable (String, CGFloat) -> CGFloat,
                    outline: @escaping @Sendable (String, CGFloat, CGSize) -> String?) {
            self.size = size
            self.inkOffset = inkOffset
            self.outline = outline
        }

        /// The plate `text` is drawn in: its words plus `padding` on every
        /// side, never narrower than `minWidth` — the same footprint
        /// `PillRasterizer` bakes.
        public func plateSize(for text: String, fontSize: CGFloat, padding: CGFloat,
                              minWidth: CGFloat = 0) -> CGSize {
            let words = size(text, fontSize)
            return CGSize(width: max(words.width + 2 * padding, minWidth),
                          height: words.height + 2 * padding)
        }
    }

    public struct Result: Sendable {
        /// The file.
        public var text: String
        /// Everything that could not be written as shapes, in the order it was
        /// met.
        public var fallbacks: [Fallback]
        /// Parts of the MOTION the file could not carry, each with the reason
        /// in words a person can read. Empty for a still file.
        public var unmoved: [Fallback]

        public init(text: String, fallbacks: [Fallback], unmoved: [Fallback] = []) {
            self.text = text
            self.fallbacks = fallbacks
            self.unmoved = unmoved
        }
    }

    /// The whole document as SVG.
    ///
    /// `animation` decides whether the motions in the document travel with it.
    /// A document with nothing moving writes exactly the same file either way.
    /// `flatImages` says which of the document's bitmaps are one flat colour,
    /// by the id of the bitmap. A picture that is one colour is a rectangle,
    /// and a rectangle is something this can write, which is what keeps a
    /// blank canvas's white background out of the file as base64
    /// (`FlatBitmap` in PhotonzRender is what reads the pixels).
    public static func write(_ document: PhotonzDocument,
                             animation: Animation = .still,
                             picture: PictureMaker? = nil,
                             outlineText: TextOutliner? = nil,
                             typeSetter: TypeSetter? = nil,
                             flatImages: [UUID: RGBA] = [:],
                             background: Background = .keep) -> Result {
        let omit = background == .drop
            ? backdrop(in: document, flatImages: flatImages)?.layerID
            : nil
        var writer = Writer(picture: picture, outlineText: outlineText,
                            type: typeSetter,
                            animation: animation, flatImages: flatImages,
                            omitLayer: omit)
        return writer.run(document)
    }

    /// The layer that is nothing but the canvas the drawing sits on: the
    /// bottom-most layer anyone can see, where that layer is one flat colour
    /// reaching every edge of the canvas and wearing nothing.
    ///
    /// A blank canvas starts life as a full-size bitmap of white, so an icon
    /// drawn on one exports with a white rectangle the size of the canvas
    /// behind it, and handed over, that icon cannot sit on a coloured page or
    /// a dark theme. This is what lets Export offer to leave it out — and what
    /// keeps the offer away from everything else, because a screenshot is a
    /// photograph rather than a flat colour, and a screen's own background is
    /// inside the frame rather than under the canvas.
    public static func backdrop(in document: PhotonzDocument,
                                flatImages: [UUID: RGBA]) -> Backdrop? {
        guard let bottom = document.layers.first(where: \.isVisible),
              let colour = flatColor(of: bottom, in: flatImages), colour.a > 0,
              bottom.transform.isIdentity,
              bottom.style.blendMode == .normal,
              !bottom.style.effects.contains(where: { $0.isOn }),
              covers(document.canvasSize, bottom.frame) else { return nil }
        return Backdrop(layerID: bottom.id, color: colour)
    }

    /// Whether `frame` reaches every corner of a canvas that size. Half a
    /// point of slack, so a canvas laid out in fractions is not disqualified
    /// by arithmetic nobody could see.
    private static func covers(_ canvas: CGSize, _ frame: CGRect) -> Bool {
        frame.insetBy(dx: -0.5, dy: -0.5)
            .contains(CGRect(origin: .zero, size: canvas))
    }

    /// What WOULD go out as a picture, asked before anything is written, so
    /// the export dialog can say so before you save rather than after you
    /// open the file.
    ///
    /// `isMoving` is whether the file being written is the one that PLAYS: a
    /// layer that moves is written as groups that slide and turn it, and those
    /// are transforms standing above everything inside it, which costs what is
    /// inside a filter (`Writer.write(_:groupOffset:level:)`).
    public static func fallbacks(in document: PhotonzDocument,
                                 flatImages: [UUID: RGBA] = [:],
                                 isMoving: Bool = false) -> [Fallback] {
        var found: [Fallback] = []
        func walk(_ layers: [Layer], carried: Bool) {
            for layer in layers where layer.isVisible {
                switch answer(for: layer, canOutlineText: true, flatImages: flatImages,
                              carried: carried) {
                case .picture(let reason?):
                    found.append(Fallback(layerName: layer.name, reason: reason))
                case .picture:
                    break
                case .vector:
                    if case .group(let group) = layer.content {
                        walk(group.children, carried: carried || moves(layer, isMoving)
                            || (carries(layer) && !placesByViewport(layer)))
                    }
                }
            }
        }
        walk(document.layers, carried: false)
        return found
    }

    /// Every layer that goes out as an embedded picture rather than as shapes,
    /// the honest ones included.
    ///
    /// A photograph is not a failure — it was never shapes — but somebody about
    /// to hand an SVG to somebody else still wants to know there is a bitmap
    /// inside it, so the Export sheet asks this rather than `fallbacks(in:)`.
    public static func embeddedPictures(in document: PhotonzDocument,
                                        flatImages: [UUID: RGBA] = [:],
                                        isMoving: Bool = false) -> [Fallback] {
        var found: [Fallback] = []
        func walk(_ layers: [Layer], carried: Bool) {
            for layer in layers where layer.isVisible {
                switch answer(for: layer, canOutlineText: true, flatImages: flatImages,
                              carried: carried) {
                case .picture(let reason):
                    found.append(Fallback(layerName: layer.name,
                                          reason: reason ?? "it is a picture rather than shapes"))
                case .vector:
                    if case .group(let group) = layer.content {
                        walk(group.children, carried: carried || moves(layer, isMoving)
                            || (carries(layer) && !placesByViewport(layer)))
                    }
                }
            }
        }
        walk(document.layers, carried: false)
        return found
    }

    /// Path data for one outline, in the shape's own coordinates. A run with
    /// no handle on either end is written as a straight run, exactly as the
    /// rasterizer draws it, so a straight edge stays straight in the file.
    public static func pathData(_ content: PathContent) -> String {
        guard !content.anchors.isEmpty else { return "" }
        var parts: [String] = []
        // One M per ring, so a shape with a hole in it leaves as one path of
        // two loops rather than as a rim with a line drawn across it.
        var runs = content.segments[...]
        for range in content.ringRanges {
            let ring = content.anchors[range]
            guard let first = ring.first else { continue }
            parts.append("M\(num(first.point.x)) \(num(first.point.y))")
            guard ring.count >= 2 else { continue }
            let count = ring.count - 1 + (content.isClosed ? 1 : 0)
            for run in runs.prefix(count) {
                if run.isStraight {
                    parts.append("L\(num(run.end.x)) \(num(run.end.y))")
                } else {
                    parts.append("C\(num(run.control1.x)) \(num(run.control1.y))"
                        + " \(num(run.control2.x)) \(num(run.control2.y))"
                        + " \(num(run.end.x)) \(num(run.end.y))")
                }
            }
            runs = runs.dropFirst(count)
            if content.isClosed { parts.append("Z") }
        }
        return parts.joined(separator: " ")
    }

    /// Path data for any Core Graphics outline: what a text layer's letters
    /// come back as, once somebody who owns a type engine has turned them into
    /// a shape.
    public static func pathData(_ path: CGPath) -> String {
        var parts: [String] = []
        path.applyWithBlock { element in
            let piece = element.pointee
            let points = piece.points
            switch piece.type {
            case .moveToPoint:
                parts.append("M\(num(points[0].x)) \(num(points[0].y))")
            case .addLineToPoint:
                parts.append("L\(num(points[0].x)) \(num(points[0].y))")
            case .addQuadCurveToPoint:
                parts.append("Q\(num(points[0].x)) \(num(points[0].y))"
                    + " \(num(points[1].x)) \(num(points[1].y))")
            case .addCurveToPoint:
                parts.append("C\(num(points[0].x)) \(num(points[0].y))"
                    + " \(num(points[1].x)) \(num(points[1].y))"
                    + " \(num(points[2].x)) \(num(points[2].y))")
            case .closeSubpath:
                parts.append("Z")
            @unknown default:
                break
            }
        }
        return parts.joined(separator: " ")
    }

    /// Path data for a box whose corners are rounded one at a time, which is
    /// the one rounding `<rect>` cannot say.
    public static func pathData(roundedBox box: CGRect, radii: CornerRadii) -> String {
        let r = radii.fitted(in: box.size)
        func arc(_ radius: CGFloat, _ x: CGFloat, _ y: CGFloat) -> String {
            radius <= 0 ? "L\(num(x)) \(num(y))"
                        : "A\(num(radius)) \(num(radius)) 0 0 1 \(num(x)) \(num(y))"
        }
        // Clockwise from just past the top left corner, in a space where y
        // grows downwards — the same walk `CornerRadii.path` makes.
        var parts = ["M\(num(box.minX + r.topLeft)) \(num(box.minY))"]
        parts.append("L\(num(box.maxX - r.topRight)) \(num(box.minY))")
        parts.append(arc(r.topRight, box.maxX, box.minY + r.topRight))
        parts.append("L\(num(box.maxX)) \(num(box.maxY - r.bottomRight))")
        parts.append(arc(r.bottomRight, box.maxX - r.bottomRight, box.maxY))
        parts.append("L\(num(box.minX + r.bottomLeft)) \(num(box.maxY))")
        parts.append(arc(r.bottomLeft, box.minX, box.maxY - r.bottomLeft))
        parts.append("L\(num(box.minX)) \(num(box.minY + r.topLeft))")
        parts.append(arc(r.topLeft, box.minX + r.topLeft, box.minY))
        parts.append("Z")
        return parts.joined(separator: " ")
    }

    // MARK: - What each layer gets

    /// What can be done with a layer: written as shapes, or handed to the
    /// picture maker. A picture with no reason is one that SHOULD be a picture
    /// — a photograph is not a shape and never was — so it is not reported as
    /// something that went wrong.
    enum Answer {
        case vector
        case picture(String?)
    }

    static func answer(for layer: Layer, canOutlineText: Bool,
                       flatImages: [UUID: RGBA] = [:],
                       carried: Bool = false) -> Answer {
        if let reason = styleReason(layer, carried: carried) { return .picture(reason) }
        switch layer.content {
        case .image:
            return flatColor(of: layer, in: flatImages) == nil ? .picture(nil) : .vector
        case .path(let path):
            if let reason = sweepReason(path.fill) ?? sweepReason(path.paint) {
                return .picture(reason)
            }
            return .vector
        case .annotation(let annotation):
            switch annotation.shape {
            case .arrow:
                if let reason = sweepReason(annotation.paint) ?? sweepReason(annotation.headPaint) {
                    return .picture(reason)
                }
                // The caption is type, and type is only shapes where somebody
                // can turn letters into outlines.
                if annotation.hasCaption, !canOutlineText {
                    return .picture("its caption's letters could not be turned into outlines")
                }
                return .vector
            case .highlight, .rectangle, .ellipse, .line:
                if let reason = sweepReason(annotation.fill) ?? sweepReason(annotation.paint) {
                    return .picture(reason)
                }
                return .vector
            }
        case .text:
            guard canOutlineText else {
                return .picture("the letters could not be turned into outlines")
            }
            // A halo round each letter is painted into the words themselves,
            // so it is not a ring this can draw round the box.
            if layer.style.effects.contains(where: {
                guard case .border(let border) = $0 else { return false }
                return border.isOn && border.width > 0 && border.follows == .letters
            }) {
                return .picture("its letters wear a line of their own")
            }
            return .vector
        case .group:
            // A frame cuts off what sticks out of it, and so does anything
            // else told to; SVG says that with a `<clipPath>`, so the drawing
            // stays shapes (`Writer.cut`).
            return .vector
        case .zoomCallout:
            return .picture("a zoom callout magnifies the picture under it")
        case .lens:
            return .picture("a lens adjusts the picture under it")
        case .measure(let measure):
            if measure.showLabel, !canOutlineText {
                return .picture("its readout's letters could not be turned into outlines")
            }
            return .vector
        case .collage:
            return .picture("a collage is an arrangement of pictures")
        }
    }

    /// The one flat colour this layer's picture is, where that is what lets it
    /// go out as a rectangle instead of as pixels.
    ///
    /// A CROPPED picture keeps its pixels even when they are all one colour: a
    /// crop can reach past the edge of the bitmap, and what shows there is not
    /// the colour inside it.
    static func flatColor(of layer: Layer, in flatImages: [UUID: RGBA]) -> RGBA? {
        guard case .image(let ref) = layer.content, layer.crop == nil else { return nil }
        return flatImages[ref.id]
    }

    /// Why this layer's STYLING has no vector answer, or nil when it has one.
    private static func styleReason(_ layer: Layer, carried: Bool) -> String? {
        if layer.style.blendMode != .normal {
            return "it is blended with what is under it"
        }
        if case .beyondSVG(let reason) = effects(of: layer, carried: carried) { return reason }
        // A picture carries its own rounding in the picture, so this is only
        // about the shapes.
        if layer.style.cornerRadii.isRound, layer.content.isDrawnAsShapes {
            return "its box is rounded off around what it draws"
        }
        if layer.crop != nil, layer.content.isDrawnAsShapes {
            return "it is cropped"
        }
        return nil
    }

    // MARK: - Softness and shadow

    /// The softness and the shadows a layer wears, as the one SVG filter that
    /// says them.
    ///
    /// Nearest the eye first, which is the order the Appearance list holds
    /// them in and the order the canvas paints them
    /// (`DocumentRenderer.shadowed`).
    struct EffectFilter: Hashable, Sendable {
        var blur: CGFloat = 0
        var shadows: [ShadowStyle] = []

        var isEmpty: Bool { blur <= 0 && shadows.isEmpty }
    }

    /// What a layer's blur and shadows can be written as.
    enum Effects: Equatable {
        /// It wears none, so there is no filter to write.
        case plain
        /// It wears some, and SVG can say all of them.
        case filter(EffectFilter)
        /// It wears something SVG has no answer for, in words a person can
        /// read on the Export sheet.
        case beyondSVG(String)
    }

    /// Whether this layer's own motion is written as groups that move it,
    /// which puts a transform above everything inside it.
    static func moves(_ layer: Layer, _ isMoving: Bool) -> Bool {
        isMoving && layer.motions?.contains(where: \.isOn) == true
    }

    /// Whether a group draws what is inside it anywhere but where their own
    /// coordinates put them, which is what `carried` means below.
    static func carries(_ group: Layer) -> Bool {
        group.frame.origin != .zero || !group.transform.isIdentity
    }

    /// Whether this layer's softness and shadows can go out as a filter, and
    /// where they cannot, why not (`docs/design/svg-export.md`).
    ///
    /// `carried` says something round this layer moves it: a group that draws
    /// away from the canvas corner, or the layer's own motion, which is
    /// written as groups that slide and turn it. Apple's SVG reader draws a
    /// filtered shape in the wrong place whenever anything round it does that,
    /// so a shadow there would land somewhere else in Preview, Quick Look and
    /// Xcode than it does in a browser. Such a layer keeps its picture.
    static func effects(of layer: Layer, carried: Bool = false) -> Effects {
        var filter = EffectFilter()
        // Only the FIRST blur paints, so only the first one goes out
        // (`LayerStyle.blurRadius`).
        filter.blur = max(layer.style.blurRadius, 0)
        for effect in layer.style.effects where effect.isOn {
            switch effect {
            case .blur, .border:
                continue
            case .glow:
                return .beyondSVG("it wears a glow")
            case .shadow(let shadow):
                guard shadow.paints else { continue }
                guard shadow.kind == .drop else {
                    return .beyondSVG("it wears a shadow cast into it")
                }
                // Growing or shrinking the silhouette before it is blurred is
                // a rounded-off shape on the canvas and a square-cornered one
                // in every SVG reader, so a spread shadow keeps its picture.
                guard shadow.spread == 0 else {
                    return .beyondSVG("its shadow is spread wider than the shape it falls from")
                }
                filter.shadows.append(shadow)
            }
        }
        guard !filter.isEmpty else { return .plain }
        // A halo is cast in the canvas's own directions: the canvas turns the
        // shape first and throws the shadow afterwards, and a file cannot say
        // that, because a filter on a turned drawing turns the shadow with it.
        guard layer.transform.isIdentity else {
            return .beyondSVG("it is turned, and its shadow would turn with it")
        }
        // A label's halo is not always the halo on its list: type on a
        // designed surface drops the contrast halo it was given
        // (`Layer.drawnShadows(onDesignedSurface:)`), and the file has no way
        // of knowing what it is sitting on.
        guard layer.content.isDrawnAsShapes, !layer.content.isText else {
            return .beyondSVG(filter.shadows.isEmpty ? "it wears a blur" : "it wears a shadow")
        }
        // Fading is the one thing that cannot ride alongside a filter. Apple's
        // SVG reader applies a fade twice to anything filtered, once to the
        // drawing going in and once to what comes out, so a half-faded shape
        // comes back a quarter of itself. Its picture is right everywhere.
        guard layer.style.opacity >= 1 else {
            return .beyondSVG(filter.shadows.isEmpty
                ? "it wears a blur and is faded at the same time"
                : "it wears a shadow and is faded at the same time")
        }
        guard !carried, layer.motions?.contains(where: \.isOn) != true else {
            return .beyondSVG(filter.shadows.isEmpty
                ? "it wears a blur, and something round it moves it"
                : "it wears a shadow, and something round it moves it")
        }
        return .filter(filter)
    }

    /// Whether anything inside this group wears a filter, which is what buys
    /// the group a viewport of its own instead of a transform
    /// (`Writer.drawing(of:…)`).
    ///
    /// Asked of the contents as if nothing moved them, because the answer is
    /// what decides whether anything does. A child that is turned carries its
    /// own contents whatever this group does, so the search stops there.
    static func holdsAFilter(_ layer: Layer) -> Bool {
        guard case .group(let group) = layer.content else { return false }
        return group.children.contains { child in
            guard child.isVisible else { return false }
            if case .filter = effects(of: child, carried: false) { return true }
            return child.transform.isIdentity && holdsAFilter(child)
        }
    }

    /// Whether this group puts what is in it in its place with a VIEWPORT of
    /// its own rather than with a transform.
    ///
    /// Apple's SVG reader draws a filtered element a second step along for
    /// every transform standing above it, so a shadow inside a group that
    /// draws away from the canvas corner would land somewhere else in Preview
    /// and Quick Look than in a browser. A nested viewport moves what is in it
    /// without a transform, and the reader gets that right. It costs an
    /// element that reads less plainly than a `<g>`, so it is only bought
    /// where there is a filter inside to save.
    static func placesByViewport(_ layer: Layer) -> Bool {
        guard layer.isGroup, layer.transform.isIdentity, carries(layer) else { return false }
        return holdsAFilter(layer)
    }

    private static func sweepReason(_ paint: Paint?) -> String? {
        guard let paint, paint.isGradient, paint.kind == .angular else { return nil }
        return "a sweeping gradient, which SVG has no way to say"
    }

    // MARK: - Numbers and strings

    /// A number the way a file should carry one: three decimals at most, no
    /// trailing zeros, and never "-0".
    static func num(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 1000).rounded() / 1000
        if abs(rounded) < 0.0005 { return "0" }
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private extension LayerContent {
    /// Whether this content is drawn as shapes rather than as pixels, which is
    /// what decides whether a rounding or a crop on the layer costs it its
    /// vectors.
    var isText: Bool {
        if case .text = self { return true }
        return false
    }

    var isDrawnAsShapes: Bool {
        switch self {
        case .path, .annotation, .text, .measure: return true
        default: return false
        }
    }
}

// MARK: - The writer

/// Holds what one export is building: the body, the gradient definitions it
/// discovered on the way, and everything it had to fall back on.
private struct Writer {
    let picture: SVGExport.PictureMaker?
    let outlineText: SVGExport.TextOutliner?
    /// How the labels the app draws for itself are measured and outlined.
    let type: SVGExport.TypeSetter?
    var animation: SVGExport.Animation = .still
    /// Which of the document's bitmaps are one flat colour, by bitmap id.
    var flatImages: [UUID: RGBA] = [:]
    /// The one top-level layer this export leaves out: the canvas the drawing
    /// was made on, when Export was asked for a file with nothing behind it.
    var omitLayer: UUID?
    var defs: [String] = []
    var fallbacks: [SVGExport.Fallback] = []
    var unmoved: [SVGExport.Fallback] = []
    /// Paint roles the group around the layer being written is animating, so
    /// the shape itself must leave them unsaid and inherit them instead.
    var omitPaint: Set<String> = []
    /// The same for the width of the one line the layer draws.
    var omitsStrokeWidth = false
    var nextPaintNumber = 1
    var nextClipNumber = 1
    var nextCutNumber = 1
    var nextFilterNumber = 1
    var nextPlateNumber = 1
    /// How many image pixels the document counts to the point, which is what a
    /// measurement's readout is worded from.
    var pixelScale: CGFloat = 1
    /// Where on the canvas the layer being written sits, so a filter's region
    /// can be stated in both the spaces the readers disagree about.
    var placedAt: CGPoint = .zero
    /// Whether a group round whatever is being written moves it, which costs
    /// a shadow its filter (`SVGExport.effects(of:carried:)`).
    var carried = false

    mutating func run(_ document: PhotonzDocument) -> SVGExport.Result {
        pixelScale = document.pixelScale
        let top = omitLayer.map { id in document.layers.filter { $0.id != id } }
            ?? document.layers
        let body = write(top, groupOffset: .zero, level: 1)
        let size = document.canvasSize
        var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\""
            + " width=\"\(n(size.width))\" height=\"\(n(size.height))\""
            + " viewBox=\"0 0 \(n(size.width)) \(n(size.height))\">"]
        if !defs.isEmpty {
            lines.append("  <defs>")
            lines.append(contentsOf: defs)
            lines.append("  </defs>")
        }
        lines.append(contentsOf: body)
        lines.append("</svg>")
        return SVGExport.Result(text: lines.joined(separator: "\n") + "\n",
                                fallbacks: fallbacks, unmoved: unmoved)
    }

    // MARK: A stack of layers

    mutating func write(_ layers: [Layer], groupOffset: CGPoint, level: Int) -> [String] {
        var lines: [String] = []
        for layer in layers where layer.isVisible {
            lines.append(contentsOf: write(layer, groupOffset: groupOffset, level: level))
        }
        return lines
    }

    // MARK: One layer

    mutating func write(_ layer: Layer, groupOffset: CGPoint, level: Int) -> [String] {
        let canvasOrigin = CGPoint(x: groupOffset.x + layer.frame.minX,
                                   y: groupOffset.y + layer.frame.minY)
        let answer = SVGExport.answer(for: layer, canOutlineText: outlineText != nil,
                                      flatImages: flatImages, carried: carried)
        let isPicture: Bool = if case .picture = answer { true } else { false }
        // What this layer is told to do over time, as the groups that do it.
        // A still export asks for none of this, and a layer with nothing
        // moving comes back with nothing to wrap it in.
        let wrap = animation.cycleMS.map {
            MotionSVG.wrap(for: layer, cycleMS: $0, level: level, isPicture: isPicture)
        } ?? MotionSVG.Wrap()
        unmoved.append(contentsOf: wrap.dropped)
        let inner = level + wrap.levels
        // The groups that do the animating are transforms standing above
        // everything inside this layer, and a filter under a transform is
        // drawn a step along by Apple's SVG reader. So a layer that moves
        // carries whatever it holds (`SVGExport.effects(of:carried:)`).
        let outerCarried = carried
        if !wrap.isEmpty { carried = true }
        defer { carried = outerCarried }

        let body: [String]
        switch answer {
        case .picture(let reason):
            if let reason {
                fallbacks.append(SVGExport.Fallback(layerName: layer.name, reason: reason))
            }
            if animation.cycleMS != nil { reportMotionsBaked(into: layer) }
            body = picture(of: layer, canvasOrigin: canvasOrigin,
                           groupOffset: groupOffset, level: inner, wrap: wrap)
        case .vector:
            body = drawing(of: layer, canvasOrigin: canvasOrigin,
                           groupOffset: groupOffset, level: inner, wrap: wrap)
        }
        // A layer that drew nothing needs no groups round the nothing.
        guard !body.isEmpty else { return [] }
        return wrap.opens + body + wrap.closes
    }

    /// Names everything moving INSIDE a layer that goes out as a picture.
    ///
    /// The picture holds one moment of the drawing, so a piece moving inside it
    /// is painted where it happened to be and never moves again. The layer's
    /// OWN motions are not lost — a picture can still be slid, turned and faded
    /// — so only what is under it is named here, and it is named before you save
    /// rather than noticed later by an icon that sits still.
    mutating func reportMotionsBaked(into layer: Layer) {
        guard case .group(let group) = layer.content else { return }
        func walk(_ layers: [Layer]) {
            for child in layers where child.isVisible {
                if child.motions?.contains(where: \.isOn) == true {
                    unmoved.append(SVGExport.Fallback(
                        layerName: child.name,
                        reason: "motion is drawn into the picture of "
                            + "\(layer.name) and cannot play"))
                }
                if case .group(let inside) = child.content { walk(inside.children) }
            }
        }
        walk(group.children)
    }

    /// A layer with no vector answer, as the picture somebody else made of it,
    /// in the place it belongs.
    mutating func picture(of layer: Layer, canvasOrigin: CGPoint,
                          groupOffset: CGPoint, level: Int,
                          wrap: MotionSVG.Wrap = MotionSVG.Wrap()) -> [String] {
        guard let made = picture?(layer, canvasOrigin), !made.png.isEmpty,
              made.box.width > 0, made.box.height > 0 else { return [] }
        // The picture's box is stated against the canvas; inside a group, the
        // file is already that far in.
        let box = made.box.offsetBy(dx: -groupOffset.x, dy: -groupOffset.y)
        let data = made.png.base64EncodedString()
        return [indent(level) + "<image x=\"\(n(box.minX))\" y=\"\(n(box.minY))\""
            + " width=\"\(n(box.width))\" height=\"\(n(box.height))\""
            + " preserveAspectRatio=\"none\""
            + attribute("opacity", wrap.omitsOpacity ? nil : opacity(layer.style.opacity))
            + " href=\"data:image/png;base64,\(data)\"/>"]
    }

    /// A layer as the shapes it is made of.
    ///
    /// Whether a layer can be shapes at all is decided by looking at it
    /// (`SVGExport.answer(for:…)`), before this is called. Nothing found while
    /// drawing can change that answer, so this never hands a picture back.
    mutating func drawing(of layer: Layer, canvasOrigin: CGPoint,
                          groupOffset: CGPoint, level: Int,
                          wrap: MotionSVG.Wrap = MotionSVG.Wrap()) -> [String] {
        // Everything inside is written in the layer's OWN coordinates and the
        // layer is put in its place once, on the way in.
        var inside: [String] = []
        let inner = level + 1
        // A group holding anything filtered puts its contents in their place
        // with a viewport of its own rather than with a transform
        // (`SVGExport.placesByViewport`), and then nothing inside it is
        // carried.
        // The box the layer's drawing can touch, which both a viewport and a
        // filter's region are stated from. Read once: on a group it is the
        // union of everything inside.
        let reach = layer.renderBounds
        let viewport = reach.width > 0 && reach.height > 0 && SVGExport.placesByViewport(layer)

        if case .group(let group) = layer.content {
            // A frame is a window: what hangs off its edge is not in the file.
            // The cut sits on a group of its own, INSIDE the one that places
            // the layer, so its box is stated in the frame's own coordinates
            // and nothing has to reason about a transform; the ring round the
            // frame is written outside it, since a border is painted over the
            // edge rather than cut by it.
            let cut = cutBox(of: layer)
            let held = cut == nil ? inner : inner + 1
            var body = surface(of: layer, group: group, level: held)
            let outside = carried
            carried = outside || (SVGExport.carries(layer) && !viewport)
            body.append(contentsOf: write(group.children,
                                          groupOffset: CGPoint(x: canvasOrigin.x,
                                                               y: canvasOrigin.y),
                                          level: held))
            carried = outside
            if let cut, !body.isEmpty {
                let name = defineCut(cut, radii: layer.style.cornerRadii)
                inside.append(indent(inner) + "<g clip-path=\"url(#\(name))\">")
                inside.append(contentsOf: body)
                inside.append(indent(inner) + "</g>")
            } else {
                inside.append(contentsOf: body)
            }
        } else {
            // What the group around this layer is animating, the shape leaves
            // unsaid: an inherited colour or width is how the animation
            // reaches a shape SMIL is not attached to.
            omitPaint = wrap.omitPaint
            omitsStrokeWidth = wrap.omitsStrokeWidth
            inside.append(contentsOf: content(of: layer, canvasOrigin: canvasOrigin,
                                              level: inner))
            omitPaint = []
            omitsStrokeWidth = false
        }
        inside.append(contentsOf: rings(of: layer, level: inner))
        // A group with nothing left in it is nothing at all, rather than an
        // empty pair of tags for somebody to wonder about.
        guard !inside.isEmpty else { return [] }

        let place = placement(of: layer, withoutTurn: wrap.ownsTheTurn)
        let fade = attribute("opacity", wrap.omitsOpacity ? nil : opacity(layer.style.opacity))
        // Its softness and its shadows, as the filter that says them. The fade
        // stays outside the filter, because the canvas fades the layer and its
        // shadow together once the shadow has been cast.
        if case .filter(let effects) = SVGExport.effects(of: layer, carried: carried) {
            // Where the region is read is the one thing the readers disagree
            // about. This file says it in plain user units, and a browser
            // reads them in the shape's own space where CoreSVG reads them in
            // the space the shape is placed in. So the region covers the
            // drawing's whole reach in BOTH: a bigger rectangle than either
            // needs, and right whichever is meant.
            let inPlace = reach
            let itsOwn = inPlace.offsetBy(dx: -layer.frame.minX, dy: -layer.frame.minY)
            let mark = " filter=\"url(#\(defineFilter(effects, reach: inPlace.union(itsOwn))))\""
            // The filter rides the drawing itself, never a plain group round
            // it: Apple's SVG reader ignores a filter on a `<g>` outright.
            // Where the drawing came out as ONE element that is the element
            // itself, placed and filtered together, which is both the smallest
            // thing to write and the one every reader gets right.
            //
            // More than one element — a ring round the shape, or an inside or
            // an outside line — goes inside a viewport of its own, a nested
            // `<svg>`, which the same reader DOES honour a filter on. The
            // viewport is the drawing's whole reach, because CoreSVG clips a
            // nested viewport whatever `overflow` says, and it is stated so
            // that the space inside it is the space outside it: the pieces
            // keep their own coordinates and one group puts them in place,
            // below the filter rather than above it.
            let body: [String]
            if inside.count == 1 {
                body = [fold(mark + place, into: inside[0], level: level + (fade.isEmpty ? 0 : 1))]
            } else {
                body = viewportElement(mark, box: inPlace, seenAs: inPlace, holding: inside,
                                       placedBy: place,
                                       level: level + (fade.isEmpty ? 0 : 1))
            }
            // A fade belongs OUTSIDE the filter, since the canvas fades the
            // layer and the shadow it has already cast together. On the same
            // element, one reader fades the drawing before it casts anything
            // and the shadow shows through it.
            guard !fade.isEmpty else { return body }
            return [indent(level) + "<g\(fade)>"] + body + [indent(level) + "</g>"]
        }
        // A group that holds something filtered is placed by a viewport rather
        // than by a transform, so the filter inside it is not carried.
        if viewport {
            return viewportElement("", box: reach,
                                   seenAs: reach.offsetBy(dx: -layer.frame.minX,
                                                          dy: -layer.frame.minY),
                                   holding: inside, fade: fade, level: level)
        }
        // A group stays a group, so the file has the nesting the layers list
        // shows. A layer that turned out to be one shape carries its own
        // placing instead of sitting alone inside a wrapper.
        if !layer.isGroup, inside.count == 1 {
            return [fold(place + fade, into: inside[0], level: level)]
        }
        return [indent(level) + "<g\(place)\(fade)>"] + inside + [indent(level) + "</g>"]
    }

    /// A nested `<svg>` standing where a `<g transform>` would have stood.
    ///
    /// `box` is where the viewport goes, in the space the layer is PLACED in,
    /// and `seenAs` is the same rectangle in whichever space the things inside
    /// it were written in. The two are the same rectangle when the contents
    /// already carry their own placing, and differ by the layer's frame origin
    /// when the viewport is doing the placing itself.
    ///
    /// Which of the two to use is not a matter of taste. A viewport that
    /// carries the FILTER has to be the first kind: CoreSVG draws a filtered
    /// element twice over, once where it belongs and once a step along, if the
    /// element's own coordinates are shifted from the ones it is placed in. A
    /// viewport standing in for a group's transform has to be the second, so
    /// that what is inside keeps the coordinates the layers list gave it.
    ///
    /// The box is the drawing's whole REACH rather than its frame, because
    /// CoreSVG clips a nested viewport whatever `overflow` says, and a shadow
    /// falls outside the box it is cast from.
    func viewportElement(_ mark: String, box: CGRect, seenAs: CGRect, holding inside: [String],
                         placedBy placement: String = "", fade: String = "",
                         level: Int) -> [String] {
        var lines = [indent(level) + "<svg x=\"\(n(box.minX))\" y=\"\(n(box.minY))\""
            + " width=\"\(n(box.width))\" height=\"\(n(box.height))\""
            + " viewBox=\"\(n(seenAs.minX)) \(n(seenAs.minY))"
            + " \(n(seenAs.width)) \(n(seenAs.height))\""
            + " overflow=\"visible\"\(mark)\(fade)>"]
        if placement.isEmpty {
            lines.append(contentsOf: inside)
        } else {
            lines.append(indent(level + 1) + "<g\(placement)>")
            lines.append(contentsOf: inside.map { "  " + $0 })
            lines.append(indent(level + 1) + "</g>")
        }
        lines.append(indent(level) + "</svg>")
        return lines
    }

    /// The box a group cuts its contents at, in the group's OWN coordinates,
    /// or nil where it cuts nothing.
    ///
    /// Two things cut: being told to (a frame is told to by default), and
    /// having rounded corners, which the canvas cuts round whether or not
    /// anything asked it to (`DocumentRenderer.groupImage`).
    func cutBox(of layer: Layer) -> CGRect? {
        guard layer.isGroup, layer.clipsToBounds || layer.style.cornerRadii.isRound
        else { return nil }
        let box = layer.localBounds.offsetBy(dx: -layer.frame.origin.x,
                                             dy: -layer.frame.origin.y)
        guard box.width > 0, box.height > 0 else { return nil }
        return box
    }

    /// Writes one cut into the definitions and hands back its name.
    mutating func defineCut(_ box: CGRect, radii: CornerRadii) -> String {
        let name = "clip-\(nextCutNumber)"
        nextCutNumber += 1
        defs.append("    <clipPath id=\"\(name)\">")
        defs.append(boxElement(box, radii: radii.fitted(in: box.size), paint: "", level: 3))
        defs.append("    </clipPath>")
        return name
    }

    /// Writes the layer's softness and shadows into the definitions as one
    /// filter, and hands back its name.
    ///
    /// Said the long way round, in the five primitives a drop shadow is made
    /// of, rather than in the one-word `feDropShadow` that means the same
    /// thing. Apple's SVG reader parses `feDropShadow` and then draws nothing
    /// for it, and does the same with `feMerge`, so an icon with either in it
    /// loses its shadow in Preview, Quick Look and Xcode while a browser draws
    /// it. The long way round is honoured everywhere
    /// (`docs/design/svg-export.md`).
    ///
    /// `reach` is the box the drawing can touch, in the layer's own
    /// coordinates: a filter clips whatever falls outside its region, and the
    /// default region is a tenth of the shape's box, which cuts a long shadow
    /// off in mid air.
    mutating func defineFilter(_ effects: SVGExport.EffectFilter, reach: CGRect) -> String {
        let name = "effect-\(nextFilterNumber)"
        nextFilterNumber += 1
        // Colours are mixed the way the canvas mixes them. SVG's own default
        // is to mix a filter in linear light, which would come back a
        // different shade from the app's.
        var lines = ["    <filter id=\"\(name)\" filterUnits=\"userSpaceOnUse\""
            + " x=\"\(n(reach.minX))\" y=\"\(n(reach.minY))\""
            + " width=\"\(n(reach.width))\" height=\"\(n(reach.height))\""
            + " color-interpolation-filters=\"sRGB\">"]
        // The layer's own softness goes on before the shadows, so a soft shape
        // throws a soft shadow, exactly as the canvas does it
        // (`DocumentRenderer.styled`). The shadows are cast from the
        // silhouette, which is softened by the same amount.
        var body = "SourceGraphic"
        var silhouette = "SourceAlpha"
        if effects.blur > 0 {
            let last = effects.shadows.isEmpty
            lines.append(blurStep(in: body, sigma: effects.blur,
                                  result: last ? nil : "softened"))
            if !last {
                body = "softened"
                lines.append(blurStep(in: silhouette, sigma: effects.blur, result: "soft-edge"))
                silhouette = "soft-edge"
            }
        }
        var cast: [String] = []
        for (index, shadow) in effects.shadows.enumerated() {
            cast.append(shadowSteps(shadow, number: index + 1, from: silhouette, into: &lines))
        }
        // Stacked the way the canvas stacks them: the foot of the list is
        // furthest from the eye, so everything above it goes over it, and the
        // drawing itself goes over the lot.
        if var under = cast.last {
            for (index, name) in cast.dropLast().enumerated().reversed() {
                let stacked = "shadows-\(index + 1)"
                lines.append(overStep(name, over: under, result: stacked))
                under = stacked
            }
            lines.append(overStep(body, over: under, result: nil))
        }
        lines.append("    </filter>")
        defs.append(contentsOf: lines)
        return name
    }

    /// One shadow, as the steps that cast it: soften the silhouette, move it,
    /// paint it, and keep the paint only where the silhouette is. Hands back
    /// the name of what it made.
    mutating func shadowSteps(_ shadow: ShadowStyle, number: Int, from silhouette: String,
                              into lines: inout [String]) -> String {
        var mask = silhouette
        if shadow.radius > 0 {
            mask = "shadow-\(number)-soft"
            lines.append(blurStep(in: silhouette, sigma: shadow.radius, result: mask))
        }
        if shadow.offset.width != 0 || shadow.offset.height != 0 {
            let moved = "shadow-\(number)-cast"
            lines.append("      <feOffset in=\"\(mask)\" dx=\"\(n(shadow.offset.width))\""
                + " dy=\"\(n(shadow.offset.height))\" result=\"\(moved)\"/>")
            mask = moved
        }
        // The colour's own see-through-ness and the shadow's opacity multiply,
        // the same way the canvas multiplies them (`DocumentRenderer.ciColor`).
        let colour = RGBA(hex: shadow.colorHex) ?? RGBA(r: 0, g: 0, b: 0)
        let ink = "shadow-\(number)-ink"
        let name = "shadow-\(number)"
        lines.append("      <feFlood flood-color=\"\(colour.hexString)\""
            + " flood-opacity=\"\(n(CGFloat(colour.a * shadow.opacity)))\""
            + " result=\"\(ink)\"/>")
        lines.append("      <feComposite in=\"\(ink)\" in2=\"\(mask)\" operator=\"in\""
            + " result=\"\(name)\"/>")
        return name
    }

    func blurStep(in source: String, sigma: CGFloat, result: String?) -> String {
        "      <feGaussianBlur in=\"\(source)\" stdDeviation=\"\(n(sigma))\""
            + attribute("result", result) + "/>"
    }

    func overStep(_ top: String, over bottom: String, result: String?) -> String {
        "      <feComposite in=\"\(top)\" in2=\"\(bottom)\" operator=\"over\""
            + attribute("result", result) + "/>"
    }

    /// A frame's own surface, under everything in it.
    mutating func surface(of layer: Layer, group: GroupContent, level: Int) -> [String] {
        guard group.isFrame, let background = group.background,
              layer.frame.width > 0, layer.frame.height > 0 else { return [] }
        let box = CGRect(origin: .zero, size: layer.frame.size)
        let paint = fill(background, box: box)
        return [indent(level) + "<rect x=\"0\" y=\"0\" width=\"\(n(box.width))\""
            + " height=\"\(n(box.height))\"\(paint)/>"]
    }

    /// What the layer itself draws, in its own coordinates.
    mutating func content(of layer: Layer, canvasOrigin: CGPoint, level: Int) -> [String] {
        placedAt = canvasOrigin
        switch layer.content {
        case .path(let path):
            return self.path(path, level: level)
        case .annotation(let annotation):
            return self.annotation(annotation, size: layer.frame.size, level: level)
        case .text(let text):
            return self.text(text, layer: layer, level: level)
        case .image:
            return flatPicture(of: layer, level: level)
        case .measure(let measure):
            return self.measure(measure, level: level)
        default:
            return []
        }
    }

    /// A picture that is one flat colour, as the rectangle it really is.
    ///
    /// Reached only for a layer `answer` already called vector, so the colour
    /// is there. Whatever rounds the layer's box rounds the rectangle with it,
    /// exactly as the rendered picture used to carry its own corners.
    mutating func flatPicture(of layer: Layer, level: Int) -> [String] {
        guard let colour = SVGExport.flatColor(of: layer, in: flatImages), colour.a > 0,
              layer.frame.width > 0, layer.frame.height > 0 else { return [] }
        let box = CGRect(origin: .zero, size: layer.frame.size)
        let paint = fill(Paint(hex: colour.hexStringWithAlpha), box: box)
        return [boxElement(box, radii: layer.style.cornerRadii.fitted(in: box.size),
                           paint: paint, level: level)]
    }

    // MARK: The shapes themselves

    mutating func path(_ content: PathContent, level: Int) -> [String] {
        guard content.anchors.count >= 2 else { return [] }
        let data = SVGExport.pathData(content)
        let box = content.bounds
        var attributes = ""
        if content.paintsAnInside, let inside = content.fill {
            attributes += fill(inside, box: box)
            if content.fillRule == .evenOdd { attributes += " fill-rule=\"evenodd\"" }
        } else {
            attributes += " fill=\"none\""
        }
        guard content.strokeWidth > 0 else {
            return [indent(level) + "<path d=\"\(data)\"\(attributes)/>"]
        }
        let edge = stroke(content.paint, box: box.insetBy(dx: -content.strokeWidth / 2,
                                                          dy: -content.strokeWidth / 2))
        // What KIND of line it is, in SVG's own words (`PathLineStyle.swift`).
        // The miter limit is stated because SVG's default is 4 and Core
        // Graphics' is 10, so a file that stayed quiet would come back a
        // different shape in a browser than it is on the canvas.
        var join = " stroke-linejoin=\"\(content.lineCorner.svgName)\""
            + " stroke-linecap=\"\(content.lineEnd.svgName)\""
        if content.lineCorner == .sharp { join += " stroke-miterlimit=\"\(n(pathMiterLimit))\"" }
        // The marks and gaps are the ones the eye sees. An inside or outside
        // line is drawn at DOUBLE width below and half of it cut away, and
        // doubling the pattern with it would make its dashes twice as long.
        if let dash = content.dashPattern {
            join += " stroke-dasharray=\"\(dash.map { n($0) }.joined(separator: " "))\""
        }
        switch content.effectiveStrokePosition {
        case .center:
            return [indent(level) + "<path d=\"\(data)\"\(attributes)\(edge)"
                + width(content.strokeWidth) + join + "/>"]
        case .inside, .outside:
            // There is no such thing as a path inset by half a line width, so
            // the line is drawn DOUBLE width and the half that should not be
            // there is cut off — exactly what `PathRasterizer` does with a
            // clip.
            let rule = content.fillRule == .evenOdd ? " clip-rule=\"evenodd\"" : ""
            let keep = content.effectiveStrokePosition == .inside
            let name = "edge-\(nextClipNumber)"
            nextClipNumber += 1
            if keep {
                defs.append("    <clipPath id=\"\(name)\">")
                defs.append("      <path d=\"\(data)\"\(rule)/>")
                defs.append("    </clipPath>")
            } else {
                let reach = content.strokeWidth * 2
                let sheet = box.insetBy(dx: -reach, dy: -reach)
                defs.append("    <mask id=\"\(name)\">")
                defs.append("      <rect x=\"\(n(sheet.minX))\" y=\"\(n(sheet.minY))\""
                    + " width=\"\(n(sheet.width))\" height=\"\(n(sheet.height))\""
                    + " fill=\"#FFFFFF\"/>")
                defs.append("      <path d=\"\(data)\" fill=\"#000000\"\(rule)/>")
                defs.append("    </mask>")
            }
            let cut = keep ? " clip-path=\"url(#\(name))\"" : " mask=\"url(#\(name))\""
            return [indent(level) + "<path d=\"\(data)\"\(attributes)/>",
                    indent(level) + "<path d=\"\(data)\" fill=\"none\"\(edge)"
                        + " stroke-width=\"\(n(content.strokeWidth * 2))\"\(join)\(cut)/>"]
        }
    }

    mutating func annotation(_ annotation: AnnotationContent, size: CGSize,
                             level: Int) -> [String] {
        let box = CGRect(x: min(annotation.start.x, annotation.end.x),
                         y: min(annotation.start.y, annotation.end.y),
                         width: abs(annotation.end.x - annotation.start.x),
                         height: abs(annotation.end.y - annotation.start.y))
        switch annotation.shape {
        case .line:
            guard annotation.strokeWidth > 0 else { return [] }
            let ink = stroke(annotation.paint, box: box.insetBy(dx: -annotation.strokeWidth / 2,
                                                                dy: -annotation.strokeWidth / 2))
            return [indent(level) + "<line x1=\"\(n(annotation.start.x))\""
                + " y1=\"\(n(annotation.start.y))\" x2=\"\(n(annotation.end.x))\""
                + " y2=\"\(n(annotation.end.y))\"\(ink)"
                + width(annotation.strokeWidth)
                + " stroke-linecap=\"\(annotation.lineEnd.svgName)\"/>"]
        case .ellipse:
            var lines: [String] = []
            if let inside = annotation.fill {
                let painted = box.insetBy(dx: max(0, annotation.strokeWidth / 2 - annotation.strokeOutset),
                                          dy: max(0, annotation.strokeWidth / 2 - annotation.strokeOutset))
                lines.append(indent(level) + "<ellipse cx=\"\(n(painted.midX))\""
                    + " cy=\"\(n(painted.midY))\" rx=\"\(n(painted.width / 2))\""
                    + " ry=\"\(n(painted.height / 2))\"\(fill(inside, box: painted))/>")
            }
            if annotation.strokeWidth > 0 {
                let ring = box.insetBy(dx: annotation.strokeWidth / 2 - annotation.strokeOutset,
                                       dy: annotation.strokeWidth / 2 - annotation.strokeOutset)
                let ink = stroke(annotation.paint, box: ring)
                lines.append(indent(level) + "<ellipse cx=\"\(n(ring.midX))\""
                    + " cy=\"\(n(ring.midY))\" rx=\"\(n(ring.width / 2))\""
                    + " ry=\"\(n(ring.height / 2))\" fill=\"none\"\(ink)"
                    + width(annotation.strokeWidth) + "/>")
            }
            return lines
        case .rectangle:
            var lines: [String] = []
            let radii = annotation.cornerRadii
            if let inside = annotation.fill {
                let painted = box.insetBy(dx: max(0, annotation.strokeWidth / 2 - annotation.strokeOutset),
                                          dy: max(0, annotation.strokeWidth / 2 - annotation.strokeOutset))
                lines.append(boxElement(painted, radii: radii.fitted(in: painted.size),
                                 paint: fill(inside, box: painted), level: level))
            }
            if annotation.strokeWidth > 0 {
                let ring = box.insetBy(dx: annotation.strokeWidth / 2 - annotation.strokeOutset,
                                       dy: annotation.strokeWidth / 2 - annotation.strokeOutset)
                let ink = stroke(annotation.paint, box: ring)
                    + width(annotation.strokeWidth)
                lines.append(boxElement(ring, radii: radii.fitted(in: ring.size),
                                 paint: " fill=\"none\"" + ink, level: level))
            }
            return lines
        case .arrow:
            return arrow(annotation, level: level)
        case .highlight:
            // A highlighter paints THROUGH what is under it, which CSS says
            // with one word. Apple's own SVG reader ignores that word and
            // draws the mark flat over the picture, so Preview, Quick Look
            // and Xcode show a solid bar where a browser shows a highlight
            // (`docs/design/svg-export.md`). The embedded picture this
            // replaced was flat in every reader, browsers included.
            let ink = annotation.paint
            guard box.width > 0, box.height > 0 else { return [] }
            return [indent(level) + "<rect x=\"\(n(box.minX))\" y=\"\(n(box.minY))\""
                + " width=\"\(n(box.width))\" height=\"\(n(box.height))\""
                + fill(ink, box: box)
                + " style=\"mix-blend-mode:multiply\"/>"]
        }
    }

    // MARK: An arrow

    /// An arrow as the pieces it is drawn in: the shaft, the ending it stops
    /// in, and the caption on its tail. The same pieces, from the same
    /// geometry, that `AnnotationRasterizer` paints.
    mutating func arrow(_ annotation: AnnotationContent, level: Int) -> [String] {
        var lines: [String] = []
        let style = annotation.arrowheadStyle
        let end = Geometry.arrowShaftEnd(start: annotation.start, end: annotation.end,
                                         strokeWidth: annotation.strokeWidth,
                                         scale: annotation.arrowheadScale, style: style)
        if annotation.strokeWidth > 0 {
            // What the two ends of the line look like. An arrow's own ending
            // is the head; the choice only reaches the tail
            // (`AnnotationContent.showsLineEnds`).
            let cap = annotation.showsLineEnds ? annotation.lineEnd.svgName : "round"
            let ink = stroke(annotation.paint,
                             box: reach(annotation.start, end)
                                 .insetBy(dx: -annotation.strokeWidth / 2,
                                          dy: -annotation.strokeWidth / 2))
            lines.append(indent(level) + "<line x1=\"\(n(annotation.start.x))\""
                + " y1=\"\(n(annotation.start.y))\" x2=\"\(n(end.x))\""
                + " y2=\"\(n(end.y))\"\(ink)" + width(annotation.strokeWidth)
                + " stroke-linecap=\"\(cap)\"/>")
        }
        lines.append(contentsOf: arrowhead(annotation, style: style, level: level))
        lines.append(contentsOf: caption(annotation, level: level))
        return lines
    }

    /// The mark an arrow ends in: a solid triangle, a fine open V, a dot or a
    /// hollow one — whichever `Geometry` says this arrow wears.
    mutating func arrowhead(_ annotation: AnnotationContent, style: ArrowheadStyle,
                            level: Int) -> [String] {
        if let circle = Geometry.arrowheadCircle(at: annotation.end,
                                                 strokeWidth: annotation.strokeWidth,
                                                 scale: annotation.arrowheadScale, style: style) {
            let box = CGRect(x: circle.center.x - circle.radius,
                             y: circle.center.y - circle.radius,
                             width: 2 * circle.radius, height: 2 * circle.radius)
            let dot = "<circle cx=\"\(n(circle.center.x))\" cy=\"\(n(circle.center.y))\""
                + " r=\"\(n(circle.radius))\""
            if style == .dot {
                return [indent(level) + dot + ownPaint(annotation.headPaint, box: box,
                                                       as: "fill") + "/>"]
            }
            guard annotation.strokeWidth > 0 else { return [] }
            let ink = ownPaint(annotation.headPaint,
                               box: box.insetBy(dx: -annotation.strokeWidth / 2,
                                                dy: -annotation.strokeWidth / 2), as: "stroke")
            return [indent(level) + dot + " fill=\"none\"\(ink)"
                + width(annotation.strokeWidth) + "/>"]
        }
        let head = Geometry.arrowhead(start: annotation.start, end: annotation.end,
                                      strokeWidth: annotation.strokeWidth,
                                      scale: annotation.arrowheadScale, style: style)
        guard head.count == 3 else { return [] }
        let box = reach(head[1], head[2]).union(reach(head[0], head[0]))
        if style == .open {
            // Two fine strokes through the tip, not a filled body: wing, tip,
            // wing, left open at the back.
            guard annotation.strokeWidth > 0 else { return [] }
            let ink = ownPaint(annotation.headPaint,
                               box: box.insetBy(dx: -annotation.strokeWidth / 2,
                                                dy: -annotation.strokeWidth / 2), as: "stroke")
            let data = "M\(n(head[1].x)) \(n(head[1].y)) L\(n(head[0].x)) \(n(head[0].y))"
                + " L\(n(head[2].x)) \(n(head[2].y))"
            return [indent(level) + "<path d=\"\(data)\" fill=\"none\"\(ink)"
                + width(annotation.strokeWidth)
                + " stroke-linejoin=\"round\" stroke-linecap=\"round\"/>"]
        }
        let data = head.enumerated().map { index, point in
            "\(index == 0 ? "M" : "L")\(n(point.x)) \(n(point.y))"
        }.joined(separator: " ") + " Z"
        return [indent(level) + "<path d=\"\(data)\""
            + ownPaint(annotation.headPaint, box: box, as: "fill") + "/>"]
    }

    /// The caption on an arrow's tail, on the plate every label in this app is
    /// drawn on.
    mutating func caption(_ annotation: AnnotationContent, level: Int) -> [String] {
        guard annotation.hasCaption, let type else { return [] }
        let words = ArrowCaptionEntry.caption(from: annotation.caption ?? "") ?? ""
        guard !words.isEmpty else { return [] }
        let chip = annotation.captionPillSize(forTextSize: type.size(words,
                                                                    annotation.captionFontSize))
        return plate(Plate(center: annotation.captionPillCenter(forPillSize: chip),
                           size: chip,
                           cornerRadius: annotation.captionCornerRadius(pillHeight: chip.height),
                           fill: plateColour(annotation.captionFill),
                           border: plateColour(annotation.captionBorder),
                           borderWidth: annotation.drawnCaptionBorderWidth,
                           text: words, fontSize: annotation.captionFontSize,
                           textHex: annotation.captionTextHex),
                     level: level)
    }

    /// The box two points make between them.
    func reach(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// A paint that belongs to a PART rather than to the layer: an arrowhead's
    /// own colour, a plate's fill. A group animating the layer's colour must
    /// not reach these, so the attribute is written even where the shape's own
    /// paint would have been left to inherit.
    mutating func ownPaint(_ paint: Paint, box: CGRect, as role: String) -> String {
        let held = omitPaint
        omitPaint = []
        defer { omitPaint = held }
        return paints(paint, box: box, as: role)
    }


    /// A box, as the simplest element that can say its rounding.
    func boxElement(_ rect: CGRect, radii: CornerRadii, paint: String, level: Int) -> String {
        guard rect.width > 0, rect.height > 0 else { return "" }
        if radii.isRound, radii.uniform == nil {
            // Corners rounded one at a time are not something `<rect>` can
            // say, so the box becomes a path with the arcs in it.
            return indent(level) + "<path d=\"\(SVGExport.pathData(roundedBox: rect, radii: radii))\""
                + "\(paint)/>"
        }
        let rounding = (radii.uniform ?? 0) > 0 ? " rx=\"\(n(radii.uniform ?? 0))\"" : ""
        return indent(level) + "<rect x=\"\(n(rect.minX))\" y=\"\(n(rect.minY))\""
            + " width=\"\(n(rect.width))\" height=\"\(n(rect.height))\"\(rounding)\(paint)/>"
    }

    // MARK: The plate a label sits on

    /// A caption's bubble and a measurement's readout are the same plate: a
    /// rounded fill, a ring round it, and words centred on it
    /// (`PillRasterizer`, `LabelPlate`).
    ///
    /// **No plate in a file carries the soft lift the canvas draws behind a
    /// caption.** That lift is a filter, and Apple's SVG reader moves any
    /// filtered shape one more step along for every transform standing above
    /// it; a label is always inside the group that places the arrow or the
    /// caliper it belongs to, so the halo would land somewhere else entirely
    /// in Preview, Quick Look and Xcode while a browser drew it in the right
    /// place. Leaving it out is the one answer that looks the same in every
    /// reader, and it costs nothing that matters: the legibility was never in
    /// the shadow, it is in the opaque plate (`LabelPlate`), which the file
    /// carries in full (`docs/design/svg-export.md`).
    struct Plate {
        var center: CGPoint
        var size: CGSize
        var cornerRadius: CGFloat
        var fill: RGBA
        var border: RGBA
        var borderWidth: CGFloat
        var text: String
        var fontSize: CGFloat
        var textHex: String
    }

    mutating func plate(_ plate: Plate, level: Int) -> [String] {
        guard plate.size.width > 0, plate.size.height > 0 else { return [] }
        let rect = CGRect(x: plate.center.x - plate.size.width / 2,
                          y: plate.center.y - plate.size.height / 2,
                          width: plate.size.width, height: plate.size.height)
        let radius = min(max(plate.cornerRadius, 0), min(rect.width, rect.height) / 2)
        func capsule(_ attributes: String) -> String {
            indent(level) + "<rect x=\"\(n(rect.minX))\" y=\"\(n(rect.minY))\""
                + " width=\"\(n(rect.width))\" height=\"\(n(rect.height))\""
                + (radius > 0 ? " rx=\"\(n(radius))\"" : "") + attributes + "/>"
        }
        var lines: [String] = []
        if plate.fill.a > 0 {
            lines.append(capsule(colour(plate.fill, as: "fill")))
        }
        if plate.border.a > 0 {
            lines.append(capsule(" fill=\"none\"" + colour(plate.border, as: "stroke")
                + " stroke-width=\"\(n(max(1, plate.borderWidth)))\""))
        }
        return lines + words(plate, level: level)
    }

    /// The label's own words, as the outline of their letters, centred on the
    /// plate exactly as the canvas centres them.
    mutating func words(_ plate: Plate, level: Int) -> [String] {
        guard let type, !plate.text.isEmpty else { return [] }
        let box = type.size(plate.text, plate.fontSize)
        guard box.width > 0, box.height > 0,
              let data = type.outline(plate.text, plate.fontSize, box), !data.isEmpty
        else { return [] }
        // Centre the INK, not the measured box: the box carries its slack
        // entirely to the right of the glyphs, so centring it would leave the
        // word a couple of points left of the middle of the plate. Rounded to
        // a whole point, which is what the canvas rounds it to at document
        // scale (`PillRasterizer.draw`).
        let ink = type.inkOffset(plate.text, plate.fontSize).rounded()
        let corner = CGPoint(x: plate.center.x - box.width / 2 - ink,
                             y: plate.center.y - box.height / 2)
        return [indent(level) + "<path d=\"\(data)\""
            + " transform=\"translate(\(n(corner.x)) \(n(corner.y)))\""
            + colour(RGBA(hex: plate.textHex) ?? RGBA(r: 1, g: 1, b: 1), as: "fill") + ">"
            + "<title>\(SVGExport.escaped(plate.text))</title></path>"]
    }

    /// One of a plate's own colours, which may be nothing at all: a caption
    /// with no fill really shows what is behind it rather than a black bubble.
    func plateColour(_ paint: Paint?) -> RGBA {
        guard let paint, let rgba = RGBA(hex: paint.hex) else {
            return RGBA(r: 0, g: 0, b: 0, a: 0)
        }
        return rgba
    }

    /// A flat colour as the one or two attributes that say it.
    func colour(_ rgba: RGBA, as role: String) -> String {
        var text = " \(role)=\"\(rgba.hexString)\""
        if rgba.a < 1 { text += " \(role)-opacity=\"\(n(CGFloat(rgba.a)))\"" }
        return text
    }

    // MARK: A measurement

    /// A caliper as the shapes it is drawn in: two rounded legs that stop on
    /// the readout, the leader that keeps a moved readout attached, and the
    /// plate the number sits on. An alignment check draws a dashed guide, its
    /// ticks and its bracket instead (`MeasureRasterizer` paints the same
    /// pieces from the same plan).
    mutating func measure(_ measure: MeasureContent, level: Int) -> [String] {
        guard let type else { return [] }
        let g = measure.caliperGeometry()
        let words = measure.chipText(pixelScale: pixelScale)
        let chip = measure.showLabel
            ? type.plateSize(for: words, fontSize: measure.labelPointSize,
                             padding: measure.labelPadding,
                             minWidth: measure.labelMinPillWidth)
            : .zero
        let plan = MeasurePlan.make(measure, geometry: g, chipSize: chip)
        let ink = RGBA(hex: measure.strokeColorHex) ?? RGBA(r: 1, g: 0.23, b: 0.19)
        // Round caps and joins, so the corners read refined rather than sharp.
        let stroke = colour(ink, as: "stroke") + " fill=\"none\""
            + " stroke-width=\"\(n(measure.strokeWidth))\""
            + " stroke-linecap=\"round\" stroke-linejoin=\"round\""

        var lines: [String] = []
        if let check = measure.alignment {
            lines.append(contentsOf: alignmentCheck(measure, check: check, geometry: g,
                                                    plan: plan, stroke: stroke, level: level))
        } else {
            for (foot, head) in [(g.footA, g.headA), (g.footB, g.headB)] {
                if let data = side(foot: foot, head: head, mid: g.labelAnchor, plan: plan) {
                    lines.append(indent(level) + "<path d=\"\(data)\"\(stroke)/>")
                }
            }
        }
        if let leader = plan.leader {
            lines.append(indent(level) + "<line x1=\"\(n(leader.from.x))\""
                + " y1=\"\(n(leader.from.y))\" x2=\"\(n(leader.to.x))\""
                + " y2=\"\(n(leader.to.y))\"\(stroke)/>")
        }
        guard measure.showLabel, !words.isEmpty else { return lines }
        lines.append(contentsOf: plate(Plate(center: plan.center, size: plan.size,
                                             cornerRadius: LabelCapsule.capsuleRadius(for: plan.size),
                                             fill: chipFill(measure),
                                             border: chipEdge(measure),
                                             borderWidth: measure.chipBorderWidth,
                                             text: words, fontSize: measure.labelPointSize,
                                             textHex: measure.textColorHex),
                                       level: level))
        return lines
    }

    /// One side of the caliper: foot, a rounded corner at the head, and as far
    /// along the head bar as the readout allows.
    func side(foot: CGPoint, head: CGPoint, mid: CGPoint, plan: MeasurePlan) -> String? {
        guard let pill = plan.pill else { return leg(foot: foot, head: head, toward: mid) }
        if let armEnd = pill.entry(from: head, toward: pill.center) {
            return leg(foot: foot, head: head, toward: armEnd)
        }
        // The plate has swallowed the corner, so the leg ends on its outline
        // and there is no corner left to round. Wider still and it has
        // swallowed the foot too, and this side draws nothing at all.
        guard let legEnd = pill.entry(from: foot, toward: head) else { return nil }
        return "M\(n(foot.x)) \(n(foot.y)) L\(n(legEnd.x)) \(n(legEnd.y))"
    }

    /// `foot → (rounded corner at head) → toward`, the same corner Core
    /// Graphics draws from a tangent radius.
    func leg(foot: CGPoint, head: CGPoint, toward: CGPoint) -> String {
        let legLength = hypot(head.x - foot.x, head.y - foot.y)
        let armLength = hypot(toward.x - head.x, toward.y - head.y)
        let radius = max(0, min(MeasureContent.cornerRadius, legLength / 2, armLength))
        var parts = ["M\(n(foot.x)) \(n(foot.y))"]
        guard radius > 0.5, armLength > 0.5, legLength > 0 else {
            parts.append("L\(n(head.x)) \(n(head.y))")
            if armLength > 0.5 { parts.append("L\(n(toward.x)) \(n(toward.y))") }
            return parts.joined(separator: " ")
        }
        // Where the curve leaves each straight run: back along the leg and out
        // along the arm by the tangent length the corner's own angle asks for.
        let into = CGPoint(x: (head.x - foot.x) / legLength, y: (head.y - foot.y) / legLength)
        let outOf = CGPoint(x: (toward.x - head.x) / armLength,
                            y: (toward.y - head.y) / armLength)
        let cosine = min(max(-into.x * outOf.x - into.y * outOf.y, -1), 1)
        let halfAngle = acos(cosine) / 2
        let tangent = halfAngle > 0.0001 ? radius / tan(halfAngle) : 0
        guard tangent > 0, tangent.isFinite, tangent <= legLength, tangent <= armLength else {
            parts.append("L\(n(head.x)) \(n(head.y))")
            parts.append("L\(n(toward.x)) \(n(toward.y))")
            return parts.joined(separator: " ")
        }
        let start = CGPoint(x: head.x - into.x * tangent, y: head.y - into.y * tangent)
        let finish = CGPoint(x: head.x + outOf.x * tangent, y: head.y + outOf.y * tangent)
        // y grows downwards here, so a positive turn is the clockwise one SVG
        // calls the positive sweep.
        let sweep = into.x * outOf.y - into.y * outOf.x > 0 ? 1 : 0
        parts.append("L\(n(start.x)) \(n(start.y))")
        parts.append("A\(n(radius)) \(n(radius)) 0 0 \(sweep) \(n(finish.x)) \(n(finish.y))")
        parts.append("L\(n(toward.x)) \(n(toward.y))")
        return parts.joined(separator: " ")
    }

    /// An alignment check: a dashed guide along the feet, a short tick where
    /// each element that agrees crosses it, and a heavier bracket enclosing
    /// the gap where one does not.
    mutating func alignmentCheck(_ measure: MeasureContent, check: AlignmentCheck,
                                 geometry g: CaliperGeometry, plan: MeasurePlan,
                                 stroke: String, level: Int) -> [String] {
        var lines: [String] = []
        let dashed = stroke + " stroke-dasharray=\"6 4\""
        func line(_ a: CGPoint, _ b: CGPoint, _ paint: String) {
            lines.append(indent(level) + "<line x1=\"\(n(a.x))\" y1=\"\(n(a.y))\""
                + " x2=\"\(n(b.x))\" y2=\"\(n(b.y))\"\(paint)/>")
        }
        // The guide is split around the plate ONLY while the plate still rides
        // it: once the verdict has moved out of the way of the rows it judges,
        // a gap in the guide would be decoration.
        if let pill = plan.pill {
            for foot in [g.footA, g.footB] {
                guard let cut = pill.entry(from: foot, toward: pill.center) else { continue }
                line(foot, cut, dashed)
            }
        } else {
            line(g.footA, g.footB, dashed)
        }

        let vertical = measure.mode == .vertical
        let guidePos = vertical ? g.footA.x : g.footA.y
        let outlier = check.verdict?.outlierIndex
        let tick = MeasureBuilder.alignmentTickHalf
        let gap = plan.guideGap(vertical: vertical)
        for (index, item) in check.items.enumerated() {
            let lo = min(item.spanStart, item.spanEnd)
            let hi = max(item.spanStart, item.spanEnd)
            if index == outlier {
                // The offender gets a bracket, not a tick: out from the guide
                // to where this element's edge really sits, down that edge for
                // the element's whole run, and back to the guide.
                let heavy = stroke.replacingOccurrences(
                    of: " stroke-width=\"\(n(measure.strokeWidth))\"",
                    with: " stroke-width=\"\(n(max(measure.strokeWidth * 2, 2)))\"")
                let corners = [MeasurePlan.point(cross: guidePos, along: lo, vertical: vertical),
                               MeasurePlan.point(cross: item.edge, along: lo, vertical: vertical),
                               MeasurePlan.point(cross: item.edge, along: hi, vertical: vertical),
                               MeasurePlan.point(cross: guidePos, along: hi, vertical: vertical)]
                let data = corners.enumerated().map { spot, point in
                    "\(spot == 0 ? "M" : "L")\(n(point.x)) \(n(point.y))"
                }.joined(separator: " ")
                lines.append(indent(level) + "<path d=\"\(data)\"\(heavy)/>")
            } else {
                // The dashes are the guide travelling; solid is the guide
                // confirming, so what the check covered is visible without
                // counting anything.
                for run in MeasurePlan.clip(lo...hi, around: gap) {
                    line(MeasurePlan.point(cross: guidePos, along: run.lowerBound,
                                           vertical: vertical),
                         MeasurePlan.point(cross: guidePos, along: run.upperBound,
                                           vertical: vertical), stroke)
                }
                let middle = (item.spanStart + item.spanEnd) / 2
                line(MeasurePlan.point(cross: guidePos - tick, along: middle, vertical: vertical),
                     MeasurePlan.point(cross: guidePos + tick, along: middle, vertical: vertical),
                     stroke)
            }
        }
        return lines
    }

    /// The readout plate's fill: its own colour at its own strength.
    func chipFill(_ measure: MeasureContent) -> RGBA {
        var tone = RGBA(hex: measure.chipColorHex) ?? RGBA(r: 1, g: 1, b: 1)
        tone.a = Double(min(max(measure.chipOpacity, 0), 1))
        return tone
    }

    /// Its ring, or nothing at all where the ring has been switched off.
    func chipEdge(_ measure: MeasureContent) -> RGBA {
        guard measure.hasChipBorder, let rgba = RGBA(hex: measure.chipBorderColorHex) else {
            return RGBA(r: 0, g: 0, b: 0, a: 0)
        }
        return rgba
    }

    /// Words, as the outline of their letters.
    ///
    /// A `<text>` element would render in whatever face the machine opening it
    /// happens to have, so an icon handed to somebody without the font comes
    /// out wrong. Outlines look the same everywhere; the words themselves ride
    /// along in a `<title>`, so the file is still searchable and a screen
    /// reader still has something to say.
    mutating func text(_ text: TextContent, layer: Layer, level: Int) -> [String] {
        guard let data = outlineText?(layer, text), !data.isEmpty else { return [] }
        let colour = fill(Paint(hex: text.colorHex),
                          box: CGRect(origin: .zero, size: layer.frame.size))
        return [indent(level) + "<path d=\"\(data)\"\(colour)>"
            + "<title>\(SVGExport.escaped(text.string))</title></path>"]
    }

    /// Every ring round the layer's box, from the foot of the Effects list up,
    /// which is the order the canvas paints them in.
    mutating func rings(of layer: Layer, level: Int) -> [String] {
        let isLabel = layer.content.isText
        let borders = layer.style.effects.compactMap { effect -> BorderEffect? in
            guard case .border(let border) = effect, border.isOn, border.width > 0
            else { return nil }
            // On a label, a ring that goes round the LETTERS is painted into
            // the words rather than round the box (`BorderFollows.swift`).
            if isLabel, border.follows == .letters { return nil }
            return border
        }
        guard !borders.isEmpty, layer.frame.width > 0, layer.frame.height > 0 else { return [] }
        let box = CGRect(origin: .zero, size: layer.frame.size)
        let shapeRadii = layer.annotation?.boxCornerRadii(in: layer.frame.size) ?? .none
        let radii = shapeRadii.isRound ? shapeRadii : layer.style.cornerRadii
        let oval = layer.ringShape == .ellipse
        // A PATH has a silhouette of its own, and the canvas rings it by
        // sweeping that outline rather than by drawing a box round it
        // (`DocumentRenderer.ringed`). A file that wrote the box instead came
        // out as a chevron in a picture frame.
        if let outline = layer.path, outline.anchors.count >= 2 {
            return pathRings(borders, outline: outline, level: level)
        }
        var lines: [String] = []
        for border in borders.reversed() {
            let outset = border.ringOutset
            let outer = outset == 0 ? box : box.insetBy(dx: -outset, dy: -outset)
            guard outer.width > 0, outer.height > 0 else { continue }
            // The ring fills the band from the outer edge inwards by its own
            // width, so the line it rides is half a width in from there.
            let ride = outer.insetBy(dx: border.width / 2, dy: border.width / 2)
            guard ride.width > 0, ride.height > 0 else { continue }
            let ink = stroke(border.paint, box: outer)
                + " stroke-width=\"\(n(border.width))\""
            if oval {
                lines.append(indent(level) + "<ellipse cx=\"\(n(ride.midX))\""
                    + " cy=\"\(n(ride.midY))\" rx=\"\(n(ride.width / 2))\""
                    + " ry=\"\(n(ride.height / 2))\" fill=\"none\"\(ink)/>")
            } else {
                let ringRadii = radii.grown(by: outset).grown(by: -border.width / 2)
                lines.append(boxElement(ride, radii: ringRadii.fitted(in: ride.size),
                                 paint: " fill=\"none\"" + ink, level: level))
            }
        }
        return lines
    }

    /// Every ring round a PATH, riding the outline itself.
    ///
    /// SVG has no such thing as a curve offset from another curve, so a band
    /// that sits a given distance out from a shape is written the way this
    /// exporter already writes a path's own inside and outside line: the
    /// outline is stroked wide enough to cover the whole band, and everything
    /// that should not be in the band is masked off. A ring standing `s` out
    /// and `w` thick is a stroke of `2(s + w)` with the shape itself and a
    /// stroke of `2s` taken out of it, which leaves exactly the band from `s`
    /// to `s + w`.
    ///
    /// An OPEN path has no inside for any of that to cut against, so all three
    /// positions come out as the one centred stroke down the middle of the
    /// line, which is what the canvas draws too
    /// (`BorderEffect.ringOutset(aroundOpenLine:)`).
    mutating func pathRings(_ borders: [BorderEffect], outline: PathContent,
                            level: Int) -> [String] {
        let data = SVGExport.pathData(outline)
        let box = outline.bounds
        let openLine = !outline.isClosed
        let rule = outline.fillRule == .evenOdd ? " fill-rule=\"evenodd\"" : ""
        // The same joins the canvas sweeps the silhouette with, so a sharp
        // corner carries as far in the file as it does on screen.
        let joins = " stroke-linejoin=\"miter\" stroke-miterlimit=\"\(n(pathMiterLimit))\""
            + " stroke-linecap=\"round\""
        var lines: [String] = []
        for border in borders.reversed() {
            let width = border.width
            guard width > 0 else { continue }
            let stand = openLine ? 0 : max(0, border.appliesOffset ? border.offset : 0)
            let ink = stroke(border.paint, box: box.insetBy(dx: -(stand + width),
                                                            dy: -(stand + width)))
            // Centred on the edge, and every ring round an open line: half in
            // and half out, which a plain stroke of the asked-for width IS.
            guard !openLine, border.position != .center else {
                lines.append(indent(level) + "<path d=\"\(data)\" fill=\"none\"\(ink)"
                    + " stroke-width=\"\(n(width))\"\(joins)/>")
                continue
            }
            let keepsInside = border.position == .inside
            let name = "ring-\(nextClipNumber)"
            nextClipNumber += 1
            // White shows, black hides. Inside keeps what is within the shape
            // and outside keeps what is beyond it; either way the standoff
            // nearest the edge is struck out with a stroke of its own.
            let reach = (stand + width) * 2
            let sheet = box.insetBy(dx: -reach, dy: -reach)
            defs.append("    <mask id=\"\(name)\">")
            defs.append("      <rect x=\"\(n(sheet.minX))\" y=\"\(n(sheet.minY))\""
                + " width=\"\(n(sheet.width))\" height=\"\(n(sheet.height))\""
                + " fill=\"\(keepsInside ? "#000000" : "#FFFFFF")\"/>")
            defs.append("      <path d=\"\(data)\""
                + " fill=\"\(keepsInside ? "#FFFFFF" : "#000000")\"\(rule)/>")
            if stand > 0 {
                defs.append("      <path d=\"\(data)\" fill=\"none\" stroke=\"#000000\""
                    + " stroke-width=\"\(n(stand * 2))\"\(joins)/>")
            }
            defs.append("    </mask>")
            lines.append(indent(level) + "<path d=\"\(data)\" fill=\"none\"\(ink)"
                + " stroke-width=\"\(n(reach))\"\(joins)"
                + " mask=\"url(#\(name))\"/>")
        }
        return lines
    }

    // MARK: Paint

    /// The width of the one line this layer draws, or nothing where the group
    /// around it is animating that width and the shape inherits it.
    func width(_ value: CGFloat) -> String {
        omitsStrokeWidth ? "" : " stroke-width=\"\(n(value))\""
    }

    mutating func fill(_ paint: Paint, box: CGRect) -> String {
        paints(paint, box: box, as: "fill")
    }

    mutating func stroke(_ paint: Paint, box: CGRect) -> String {
        paints(paint, box: box, as: "stroke")
    }

    /// A paint as the one or two attributes that say it: a colour and, where
    /// the colour is see-through, its own opacity; or a pointer at a ramp
    /// written into the definitions.
    mutating func paints(_ paint: Paint, box: CGRect, as role: String) -> String {
        // Said by the group around it, which is animating it.
        if omitPaint.contains(role) { return "" }
        guard paint.isGradient, let id = define(paint, box: box) else {
            let rgba = RGBA(hex: paint.hex) ?? RGBA(r: 0, g: 0, b: 0)
            var text = " \(role)=\"\(rgba.hexString)\""
            if rgba.a < 1 { text += " \(role)-opacity=\"\(n(CGFloat(rgba.a)))\"" }
            return text
        }
        return " \(role)=\"url(#\(id))\""
    }

    /// Writes a ramp into the definitions and hands back its name. Aimed at
    /// the box it is painted across, in the same user space the shape is drawn
    /// in, so the ramp lands exactly where the canvas puts it.
    mutating func define(_ paint: Paint, box: CGRect) -> String? {
        guard !box.isEmpty else { return nil }
        let id = "gradient-\(nextPaintNumber)"
        nextPaintNumber += 1
        var lines: [String] = []
        switch paint.kind {
        case .linear:
            let ends = paint.linearEnds(in: box)
            lines.append("    <linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\""
                + " x1=\"\(n(ends.start.x))\" y1=\"\(n(ends.start.y))\""
                + " x2=\"\(n(ends.end.x))\" y2=\"\(n(ends.end.y))\">")
        case .radial:
            let middle = paint.centerPoint(in: box)
            lines.append("    <radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\""
                + " cx=\"\(n(middle.x))\" cy=\"\(n(middle.y))\""
                + " r=\"\(n(paint.radialRadius(in: box)))\">")
        case .solid, .angular:
            return nil
        }
        for stop in paint.orderedStops {
            let rgba = RGBA(hex: stop.hex) ?? RGBA(r: 0, g: 0, b: 0)
            var line = "      <stop offset=\"\(n(CGFloat(min(max(stop.position, 0), 1))))\""
                + " stop-color=\"\(rgba.hexString)\""
            if rgba.a < 1 { line += " stop-opacity=\"\(n(CGFloat(rgba.a)))\"" }
            lines.append(line + "/>")
        }
        lines.append(paint.kind == .linear ? "    </linearGradient>" : "    </radialGradient>")
        defs.append(contentsOf: lines)
        return id
    }

    // MARK: Placing it

    /// Where the layer sits and how it is turned, as one transform — or
    /// nothing at all, which is what a layer at the origin deserves.
    func placement(of layer: Layer, withoutTurn: Bool = false) -> String {
        var parts: [String] = []
        let origin = layer.frame.origin
        if origin.x != 0 || origin.y != 0 {
            parts.append("translate(\(n(origin.x)) \(n(origin.y)))")
        }
        // A turn that is animated is stated by the group doing the animating,
        // which starts from the angle the motion starts at. Saying it here as
        // well would turn the drawing twice.
        if !layer.transform.isIdentity, !withoutTurn {
            let middle = CGPoint(x: layer.frame.width / 2, y: layer.frame.height / 2)
            if layer.transform.rotation != 0, layer.transform.skewX == 0,
               layer.transform.skewY == 0, !layer.transform.flipHorizontal,
               !layer.transform.flipVertical {
                let degrees = layer.transform.rotation * 180 / .pi
                parts.append("rotate(\(n(degrees)) \(n(middle.x)) \(n(middle.y)))")
            } else {
                // A flip and a skew together are not a list of named turns, so
                // the matrix itself is the honest way to say them.
                let t = layer.transform.affineTransform(around: middle)
                parts.append("matrix(\(n(t.a)) \(n(t.b)) \(n(t.c)) \(n(t.d))"
                    + " \(n(t.tx)) \(n(t.ty)))")
            }
        }
        guard !parts.isEmpty else { return "" }
        return " transform=\"\(parts.joined(separator: " "))\""
    }

    func opacity(_ value: Double) -> String? {
        value < 1 ? n(CGFloat(value)) : nil
    }

    func attribute(_ name: String, _ value: String?) -> String {
        guard let value else { return "" }
        return " \(name)=\"\(value)\""
    }

    /// Puts the layer's own attributes onto the one shape it turned out to be,
    /// at the level the wrapper it did not need would have sat at.
    func fold(_ attributes: String, into element: String, level: Int) -> String {
        let body = element.drop { $0 == " " }
        guard !attributes.isEmpty, let space = body.firstIndex(of: " ") else {
            return indent(level) + body
        }
        // After the element's name: `<path d=…` becomes `<path transform=… d=…`.
        return indent(level) + body[..<space] + attributes + body[space...]
    }

    func indent(_ level: Int) -> String { String(repeating: "  ", count: max(level, 0)) }

    func n(_ value: CGFloat) -> String { SVGExport.num(value) }
}
