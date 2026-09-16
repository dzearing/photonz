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

    /// Asked for a picture of `layer`, whose frame sits at the given point in
    /// canvas coordinates. Nil where no picture could be made.
    public typealias PictureMaker = @Sendable (_ layer: Layer, _ canvasOrigin: CGPoint) -> Picture?

    /// Asked for the outline of a text layer's letters, as path data in the
    /// layer's OWN top-left coordinates. Nil where the words cannot be
    /// outlined.
    public typealias TextOutliner = @Sendable (_ layer: Layer, _ text: TextContent) -> String?

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
                             flatImages: [UUID: RGBA] = [:]) -> Result {
        var writer = Writer(picture: picture, outlineText: outlineText,
                            animation: animation, flatImages: flatImages)
        return writer.run(document)
    }

    /// What WOULD go out as a picture, asked before anything is written, so
    /// the export dialog can say so before you save rather than after you
    /// open the file.
    public static func fallbacks(in document: PhotonzDocument,
                                 flatImages: [UUID: RGBA] = [:]) -> [Fallback] {
        var found: [Fallback] = []
        func walk(_ layers: [Layer]) {
            for layer in layers where layer.isVisible {
                switch answer(for: layer, canOutlineText: true, flatImages: flatImages) {
                case .picture(let reason?):
                    found.append(Fallback(layerName: layer.name, reason: reason))
                case .picture:
                    break
                case .vector:
                    if case .group(let group) = layer.content { walk(group.children) }
                }
            }
        }
        walk(document.layers)
        return found
    }

    /// Every layer that goes out as an embedded picture rather than as shapes,
    /// the honest ones included.
    ///
    /// A photograph is not a failure — it was never shapes — but somebody about
    /// to hand an SVG to somebody else still wants to know there is a bitmap
    /// inside it, so the Export sheet asks this rather than `fallbacks(in:)`.
    public static func embeddedPictures(in document: PhotonzDocument,
                                        flatImages: [UUID: RGBA] = [:]) -> [Fallback] {
        var found: [Fallback] = []
        func walk(_ layers: [Layer]) {
            for layer in layers where layer.isVisible {
                switch answer(for: layer, canOutlineText: true, flatImages: flatImages) {
                case .picture(let reason):
                    found.append(Fallback(layerName: layer.name,
                                          reason: reason ?? "it is a picture rather than shapes"))
                case .vector:
                    if case .group(let group) = layer.content { walk(group.children) }
                }
            }
        }
        walk(document.layers)
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
                       flatImages: [UUID: RGBA] = [:]) -> Answer {
        if let reason = styleReason(layer) { return .picture(reason) }
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
                return .picture("an arrow is a shaft, a head and a label rather than one shape")
            case .highlight:
                return .picture("a highlight paints through what is under it")
            case .rectangle, .ellipse, .line:
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
        case .group(let group):
            if group.clipsContents {
                return .picture("a group that cuts off what sticks out of it")
            }
            return .vector
        case .zoomCallout:
            return .picture("a zoom callout magnifies the picture under it")
        case .lens:
            return .picture("a lens adjusts the picture under it")
        case .measure:
            return .picture("a measurement is a caliper, ticks and a chip of type")
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
    private static func styleReason(_ layer: Layer) -> String? {
        if layer.style.blendMode != .normal {
            return "it is blended with what is under it"
        }
        for effect in layer.style.effects where effect.isOn {
            switch effect.kind {
            case .shadow: return "it wears a shadow"
            case .blur: return "it wears a blur"
            case .glow: return "it wears a glow"
            case .border: continue
            }
        }
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
        case .path, .annotation, .text: return true
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
    var animation: SVGExport.Animation = .still
    /// Which of the document's bitmaps are one flat colour, by bitmap id.
    var flatImages: [UUID: RGBA] = [:]
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

    mutating func run(_ document: PhotonzDocument) -> SVGExport.Result {
        let body = write(document.layers, groupOffset: .zero, level: 1)
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
                                      flatImages: flatImages)
        let isPicture: Bool = if case .picture = answer { true } else { false }
        // What this layer is told to do over time, as the groups that do it.
        // A still export asks for none of this, and a layer with nothing
        // moving comes back with nothing to wrap it in.
        let wrap = animation.cycleMS.map {
            MotionSVG.wrap(for: layer, cycleMS: $0, level: level, isPicture: isPicture)
        } ?? MotionSVG.Wrap()
        unmoved.append(contentsOf: wrap.dropped)
        let inner = level + wrap.levels

        let body: [String]
        switch answer {
        case .picture(let reason):
            if let reason {
                fallbacks.append(SVGExport.Fallback(layerName: layer.name, reason: reason))
            }
            body = picture(of: layer, canvasOrigin: canvasOrigin,
                           groupOffset: groupOffset, level: inner, wrap: wrap)
        case .vector:
            body = shapes(of: layer, canvasOrigin: canvasOrigin,
                          groupOffset: groupOffset, level: inner, wrap: wrap)
        }
        // A layer that drew nothing needs no groups round the nothing.
        guard !body.isEmpty else { return [] }
        return wrap.opens + body + wrap.closes
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
    mutating func shapes(of layer: Layer, canvasOrigin: CGPoint,
                         groupOffset: CGPoint, level: Int,
                         wrap: MotionSVG.Wrap = MotionSVG.Wrap()) -> [String] {
        // Everything inside is written in the layer's OWN coordinates and the
        // layer is put in its place once, on the way in.
        var inside: [String] = []
        let inner = level + 1

        if case .group(let group) = layer.content {
            inside.append(contentsOf: surface(of: layer, group: group, level: inner))
            inside.append(contentsOf: write(group.children,
                                            groupOffset: CGPoint(x: canvasOrigin.x,
                                                                 y: canvasOrigin.y),
                                            level: inner))
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
        // A group stays a group, so the file has the nesting the layers list
        // shows. A layer that turned out to be one shape carries its own
        // placing instead of sitting alone inside a wrapper.
        if !layer.isGroup, inside.count == 1 {
            return [fold(place + fade, into: inside[0], level: level)]
        }
        return [indent(level) + "<g\(place)\(fade)>"] + inside + [indent(level) + "</g>"]
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
        switch layer.content {
        case .path(let path):
            return self.path(path, level: level)
        case .annotation(let annotation):
            return self.annotation(annotation, size: layer.frame.size, level: level)
        case .text(let text):
            return self.text(text, layer: layer, level: level)
        case .image:
            return flatPicture(of: layer, level: level)
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
                + width(annotation.strokeWidth) + " stroke-linecap=\"round\"/>"]
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
        case .arrow, .highlight:
            return []
        }
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
