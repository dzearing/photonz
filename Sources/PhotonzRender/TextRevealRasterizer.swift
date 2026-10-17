import CoreGraphics
import CoreImage
import CoreText
import Foundation
import PhotonzCore

// Title text comes in by line, word or letter (`TextReveal.swift`).
//
// The words are laid out ONCE, exactly as `TextRasterizer.rasterize` lays them
// out, and each piece (a line, a word, a letter) is drawn on its own into a
// small picture of just itself, at the place the full layout puts it. Those
// pictures are kept until the words change, so a frame of a reveal costs a
// handful of small composites and never a fresh layout: editing the text is
// the only thing that lays it out again.
//
// Each piece is drawn by its own glyphs (`CTRunDraw` on its stretch of the
// run), not cut out of the finished picture, so a kerned neighbour reaching
// into its box is never dragged along with it, and an emoji or a right-to-left
// word is drawn by the same runs that draw it on the canvas.

/// A text's pieces for its reveal, each drawn alone where the full layout puts
/// it.
public struct TextRevealPieces: @unchecked Sendable {
    public struct Piece {
        /// Just this piece, transparent round it.
        public let image: CIImage
        /// Where `image` sits in the whole text's picture, in pixels, with the
        /// origin bottom left the way Core Image counts.
        public let rect: CGRect
        /// The piece's own line box, in the same pixels: what a mask reveal
        /// slides it out from behind.
        public let box: CGRect
        /// Where it sits along its line, left to right as drawn.
        public let place: TextRevealPlace
    }

    /// In reading order.
    public let pieces: [Piece]
    /// The size of the whole text's picture, in pixels.
    public let pixelSize: CGSize
    /// The type size, in pixels: what a reveal's distances are multiples of.
    public let emPixels: CGFloat
    /// A caption's plate, drawn whole under the pieces.
    public let plate: CIImage?
}

extension TextRasterizer {

    /// `text`'s pieces for `unit`, laid out in a box of `size` points and
    /// drawn at `scale` pixels a point, with its outlines. Nil where nothing
    /// can be drawn.
    public static func revealPieces(_ text: TextContent, size: CGSize, outlines: [TextOutline] = [],
                                    scale: CGFloat = 1, unit: TextRevealUnit) -> TextRevealPieces? {
        guard scale > 0, scale.isFinite, text.fontSize > 0 else { return nil }
        let text = truncating(text, toFit: size.width)
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width >= 1, height >= 1 else { return nil }
        let box = CGRect(x: 0, y: 0, width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        let path = CGPath(rect: laidOutBox(text, in: box), transform: nil)
        let base = path.boundingBox.origin
        func frame(_ attributed: NSAttributedString) -> CTFrame {
            CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed),
                                     CFRange(location: 0, length: 0), path, nil)
        }
        // The words, and under them each outline, widest first, the order the
        // whole picture is drawn in. Colour and stroke never move a glyph, so
        // all of them share one layout.
        let fill = frame(lit(attributedString(text), text))
        // A ramp through the letters, drawn as the whole picture draws it.
        let ramp = text.highlight == nil ? text.fillPaint : nil
        let rings = outlines.filter { $0.width > 0 }.sorted { $0.width > $1.width }.map { outline in
            var underlay = text
            underlay.colorHex = outline.colorHex
            return frame(attributedString(underlay, borderWidth: outline.width * 2,
                                          borderColorHex: outline.colorHex))
        }
        guard let lines = CTFrameGetLines(fill) as? [CTLine], !lines.isEmpty else { return nil }
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(fill, CFRange(location: 0, length: 0), &origins)

        // Which piece each UTF-16 unit of the string belongs to.
        let string = text.string as NSString
        var owner = [Int](repeating: -1, count: string.length)
        let spans = TextReveal.spans(in: text.string, unit: unit)
        for (index, span) in (spans ?? []).enumerated() {
            for offset in span.location..<min(span.location + span.length, owner.count) { owner[offset] = index }
        }
        func isBlank(_ offset: Int) -> Bool {
            guard offset < string.length, let scalar = Unicode.Scalar(string.character(at: offset)) else {
                return false
            }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }

        /// One stretch of one run that belongs to a piece.
        struct Stretch { let line: Int; let run: Int; let from: Int; let count: Int }
        var stretches: [Int: [Stretch]] = [:]
        var bounds: [Int: CGRect] = [:]
        var lineOf: [Int: Int] = [:]
        for (lineIndex, line) in lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let origin = CGPoint(x: base.x + origins[lineIndex].x, y: base.y + origins[lineIndex].y)
            guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else { continue }
            for (runIndex, run) in runs.enumerated() {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }
                var indices = [CFIndex](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var advances = [CGSize](repeating: .zero, count: count)
                CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                CTRunGetAdvances(run, CFRange(location: 0, length: count), &advances)
                var open: (piece: Int, from: Int)?
                func close(at end: Int) {
                    guard let begun = open else { return }
                    stretches[begun.piece, default: []].append(
                        Stretch(line: lineIndex, run: runIndex, from: begun.from, count: end - begun.from))
                    open = nil
                }
                for glyph in 0..<count {
                    let offset = indices[glyph]
                    let piece: Int
                    switch unit {
                    case .whole: piece = 0
                    case .line: piece = lineIndex
                    case .word, .letter: piece = offset < owner.count ? owner[offset] : -1
                    }
                    if open?.piece != piece { close(at: glyph) }
                    guard piece >= 0, !isBlank(offset) else { continue }
                    if open == nil { open = (piece, glyph) }
                    let glyphBox = CGRect(x: origin.x + positions[glyph].x, y: origin.y - descent,
                                          width: max(advances[glyph].width, 0), height: ascent + descent)
                    bounds[piece] = bounds[piece].map { $0.union(glyphBox) } ?? glyphBox
                    if lineOf[piece] == nil { lineOf[piece] = lineIndex }
                }
                close(at: count)
            }
        }

        // Room round each piece for what reaches past its line box: a
        // swash, an accent, an italic's lean, the outline round it.
        let pad = text.fontSize * 0.3 + (rings.isEmpty ? 0 : (outlines.map(\.width).max() ?? 0)) + 2
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        let ringLines = rings.map { (CTFrameGetLines($0) as? [CTLine]) ?? [] }
        let order = bounds.keys.sorted()
        var drawn: [(piece: Int, image: CIImage, rect: CGRect, box: CGRect)] = []
        for piece in order {
            guard let points = bounds[piece], let parts = stretches[piece] else { continue }
            let rect = CGRect(x: (points.minX - pad) * scale, y: (points.minY - pad) * scale,
                              width: (points.width + pad * 2) * scale, height: (points.height + pad * 2) * scale)
                .integral.intersection(whole)
            guard !rect.isEmpty,
                  let context = CGContext(data: nil, width: Int(rect.width), height: Int(rect.height),
                                          bitsPerComponent: 8, bytesPerRow: Int(rect.width) * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)
                                              ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { continue }
            context.translateBy(x: -rect.minX, y: -rect.minY)
            context.scaleBy(x: scale, y: scale)
            context.textMatrix = .identity
            func draw(_ lines: [CTLine]) {
                for part in parts where part.line < lines.count {
                    guard let runs = CTLineGetGlyphRuns(lines[part.line]) as? [CTRun], part.run < runs.count
                    else { continue }
                    context.textPosition = CGPoint(x: base.x + origins[part.line].x,
                                                   y: base.y + origins[part.line].y)
                    CTRunDraw(runs[part.run], context, CFRange(location: part.from, length: part.count))
                }
            }
            for ring in ringLines { draw(ring) }
            if let ramp {
                // Each piece poured from its own line's ramp, so the letters
                // arrive already the colour they settle in (`TextRamp.swift`).
                for part in parts where part.line < lines.count {
                    guard let runs = CTLineGetGlyphRuns(lines[part.line]) as? [CTRun], part.run < runs.count
                    else { continue }
                    let outlines = CGMutablePath()
                    glyphOutlines(runs[part.run], from: part.from, count: part.count,
                                  at: CGPoint(x: base.x + origins[part.line].x, y: base.y + origins[part.line].y),
                                  into: outlines)
                    let box = text.fillBox(forLine: rampLineBox(lines[part.line], origin: origins[part.line],
                                                                base: base))
                    GradientPainter.fill(path: outlines, with: ramp, across: box, in: context)
                }
            } else {
                draw(lines)
            }
            guard let image = context.makeImage() else { continue }
            let box = CGRect(x: points.minX * scale, y: points.minY * scale,
                             width: points.width * scale, height: points.height * scale)
            drawn.append((piece, CIImage(cgImage: image).transformed(
                by: CGAffineTransform(translationX: rect.minX, y: rect.minY)), rect, box))
        }

        // Left to right along each line, for the pieces Track In spreads.
        var places: [Int: TextRevealPlace] = [:]
        let byLine = Dictionary(grouping: drawn, by: { lineOf[$0.piece] ?? 0 })
        for (_, row) in byLine {
            for (index, item) in row.sorted(by: { $0.box.midX < $1.box.midX }).enumerated() {
                places[item.piece] = TextRevealPlace(index: index, count: row.count)
            }
        }

        var plate: CIImage?
        if let plateHex = text.plateHex,
           let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: width * 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.scaleBy(x: scale, y: scale)
            drawPlate(for: text, hex: plateHex, laidOutIn: path, bounds: box, in: context)
            plate = context.makeImage().map(CIImage.init(cgImage:))
        }
        return TextRevealPieces(
            pieces: drawn.map {
                TextRevealPieces.Piece(image: $0.image, rect: $0.rect, box: $0.box,
                                       place: places[$0.piece] ?? TextRevealPlace(index: 0, count: 1))
            },
            pixelSize: CGSize(width: width, height: height),
            emPixels: text.fontSize * scale,
            plate: plate)
    }
}

/// The whole text's picture at one moment of its reveal.
public enum TextRevealCompositor {

    /// Each piece where `reveal` has it `elapsedMS` in, over the plate, as one
    /// picture exactly the size of the text's own: pieces never reach past
    /// the box the words are laid out in.
    ///
    /// `shutterMS`, where a motion blur covers the text, is how long the
    /// shutter is open, centred on the moment: a piece travelling far enough
    /// in that time is smeared along the way it went (`MotionSmear.swift`),
    /// before its mask, which holds still.
    ///
    /// A piece that turns in depth (`TextRevealStyle.isInDepth`) is seen
    /// through its own lens, close and centred on it (`lens(for:pose:height:eyeDistance:)`),
    /// so a word turned 60 degrees has a near edge plainly taller than its far
    /// one wherever it sits on the line. `eyeDistance` is the document's own
    /// camera in this picture's pixels: a lens is never weaker than it, and a
    /// document with no perspective keeps its words flat.
    ///
    /// `reach` is how far, in pixels, a piece may be drawn past the box the
    /// words are laid out in (`reach(of:reveal:eyeDistance:)`): the picture
    /// comes back that much bigger on every side, its origin still at nought,
    /// so nothing rising in from under it, tracked in from past its end or
    /// turned toward the camera is cut at the box's edge.
    public static func image(_ pieces: TextRevealPieces, reveal: TextReveal, elapsedMS: Int,
                             shutterMS: Double? = nil, eyeDistance: Double? = nil,
                             reach: CGFloat = 0) -> CIImage {
        let whole = CGRect(origin: .zero, size: pieces.pixelSize)
        let ground = CIImage(color: .clear).cropped(to: whole.insetBy(dx: -max(reach, 0), dy: -max(reach, 0)))
        var out = pieces.plate.map { $0.composited(over: ground) } ?? ground
        let ranks = reveal.ranks(count: pieces.pieces.count)
        let em = pieces.emPixels
        let eye = eyeDistance ?? Double(max(pieces.pixelSize.width, pieces.pixelSize.height)) * 1.2
        for (index, piece) in pieces.pieces.enumerated() {
            let pose = reveal.pose(rank: ranks[index], atElapsedMS: elapsedMS, place: piece.place)
            guard pose.opacity > 0.001, pose.shown > 0.0001 else { continue }
            var image = piece.image
            if pose.isTurned {
                // Turned in depth: warped to where the camera sees it, smeared
                // between where it was while the shutter was open.
                guard let now = turnedQuad(piece, pose: pose, em: em, height: whole.height,
                                           eyeDistance: eye) else { continue }
                image = warped(image, onto: now)
                if let shutterMS, shutterMS > 0 {
                    let opens = Double(elapsedMS) - shutterMS / 2
                    let count = 8
                    let quads = (0..<count).compactMap { step -> [CGPoint]? in
                        let at = opens + shutterMS * Double(step) / Double(count - 1)
                        return turnedQuad(piece, pose: reveal.pose(rank: ranks[index], atElapsed: at,
                                                                   place: piece.place),
                                          em: em, height: whole.height, eyeDistance: eye,
                                          ignoringBack: true)
                    }
                    var span: CGFloat = 0
                    for (a, b) in zip(quads, quads.dropFirst()) {
                        var farthest: CGFloat = 0
                        for (p, q) in zip(a, b) { farthest = max(farthest, hypot(q.x - p.x, q.y - p.y)) }
                        span += farthest
                    }
                    if quads.count == count, span > MotionSmear.threshold {
                        image = MotionSmearFilter.averaged(image, over: quads.map { MotionSmear.mapping(now, onto: $0) })
                    }
                }
                if pose.opacity < 0.999 {
                    image = image.applyingFilter("CIColorMatrix", parameters: [
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(pose.opacity)),
                    ])
                }
                out = image.composited(over: out)
                continue
            }
            let keep = mask(of: piece, pose: pose, em: em)
            if let shutterMS, shutterMS > 0 {
                let travel = { (elapsed: Double) -> CGPoint in
                    place(of: piece, pose: reveal.pose(rank: ranks[index], atElapsed: elapsed, place: piece.place),
                          em: em)
                }
                image = smeared(image, travel: travel, at: Double(elapsedMS), shutterMS: shutterMS)
            }
            if pose.slide > 0 {
                let move = slid(piece, pose: pose, em: em)
                image = image.transformed(by: CGAffineTransform(translationX: move.x, y: move.y))
                image = image.cropped(to: keep)
            }
            if pose.shown < 1 {
                // An edge travelling `direction` has uncovered this much.
                let r = piece.rect
                let shown = CGFloat(pose.shown)
                let cut: CGRect = switch pose.direction {
                case .right: CGRect(x: r.minX, y: r.minY, width: r.width * shown, height: r.height)
                case .left: CGRect(x: r.maxX - r.width * shown, y: r.minY, width: r.width * shown, height: r.height)
                case .down: CGRect(x: r.minX, y: r.maxY - r.height * shown, width: r.width, height: r.height * shown)
                case .up: CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * shown)
                }
                image = image.cropped(to: cut)
            }
            if pose.blurEm > 0 {
                let radius = CGFloat(pose.blurEm) * em
                image = image.applyingGaussianBlur(sigma: Double(radius / 2))
                    .cropped(to: keep.insetBy(dx: -radius * 2, dy: -radius * 2))
            }
            if pose.offsetEm != .zero {
                image = image.transformed(by: CGAffineTransform(translationX: pose.offsetEm.x * em,
                                                                y: -pose.offsetEm.y * em))
            }
            if pose.opacity < 0.999 {
                image = image.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(pose.opacity)),
                ])
            }
            out = image.composited(over: out)
        }
        guard reach > 0 else { return out.cropped(to: whole) }
        return out.cropped(to: whole.insetBy(dx: -reach, dy: -reach))
            .transformed(by: CGAffineTransform(translationX: reach, y: reach))
    }

    /// How close a turning piece's own camera stands, in multiples of the
    /// piece's size along the way it turns. At 1.6, a word swung 45 degrees
    /// from its edge has a near edge about 1.45 times its far one, and one
    /// flipped 45 degrees about its middle about 1.55 times: depth a viewer
    /// sees without studying it, the strength animated type has in a browser
    /// with `perspective()` on each letter. The document's camera, thirteen
    /// hundred pixels away at 1080p for a word a hundred tall, gave 1.04.
    static let lensDistance: Double = 1.6

    /// The camera a piece turning as `pose` says is seen through: straight in
    /// front of the middle of its own line box, `lensDistance` times its size
    /// along the way it turns away, so a word and a letter foreshorten alike
    /// and no word leans like italic type for sitting off the middle of the
    /// line. Never further than the document's camera (`eyeDistance`), and
    /// flat where the document has no perspective.
    static func lens(for piece: TextRevealPieces.Piece, pose: TextRevealPose, height: CGFloat,
                     eyeDistance: Double) -> Projection3D {
        var lens = Projection3D(camera: nil, canvas: .zero)
        let box = piece.box
        lens.centre = CGPoint(x: box.midX, y: height - box.midY)
        guard eyeDistance.isFinite else {
            lens.eyeDistance = .infinity
            return lens
        }
        // The size it turns across: its height tipping about its sideways
        // axis, its width swinging about its upright one, whichever it is
        // doing more of.
        let across = abs(pose.turnY) > abs(pose.turnX) ? Double(box.width) : Double(box.height)
        lens.eyeDistance = min(max(across, 1) * lensDistance, eyeDistance)
        return lens
    }

    /// How far past the box the words are laid out, in pixels, any piece of
    /// `pieces` is drawn at any moment of `reveal`: what `image(…, reach:)` is
    /// asked for, so a word rising in from under the bottom line, a letter
    /// tracked in from past the end of it or one turning toward its lens is
    /// drawn whole rather than cut at the box. Nought where every piece stays
    /// inside it, a plain fade or a wipe, so those pictures are exactly the
    /// box's as before.
    ///
    /// Worked out from the reveal itself, not the moment: each piece's drawn
    /// extent is followed through its whole move, so the picture keeps one
    /// size through the reveal. A piece's pose depends on its beat only by
    /// when it starts, and holds its first and last pose either side of its
    /// move, so one beat's worth of moments covers every piece and every
    /// shutter open across them.
    public static func reach(of pieces: TextRevealPieces, reveal: TextReveal,
                             eyeDistance: Double? = nil) -> CGFloat {
        guard !pieces.pieces.isEmpty, reveal.style.hasLength else { return 0 }
        let whole = CGRect(origin: .zero, size: pieces.pixelSize)
        let em = pieces.emPixels
        let eye = eyeDistance ?? Double(max(pieces.pixelSize.width, pieces.pixelSize.height)) * 1.2
        let steps = 48
        let moments = (0...steps).map { Double(max(1, reveal.lengthMS)) * Double($0) / Double(steps) }
        var poses: [TextRevealPlace: [TextRevealPose]] = [:]
        var farthest: CGFloat = 0
        for piece in pieces.pieces {
            let along = poses[piece.place] ?? moments.map { reveal.pose(rank: 0, atElapsed: $0, place: piece.place) }
            poses[piece.place] = along
            for pose in along {
                let drawn: CGRect
                if pose.isTurned {
                    guard let quad = turnedQuad(piece, pose: pose, em: em, height: whole.height,
                                                eyeDistance: eye, ignoringBack: true) else { continue }
                    let xs = quad.map(\.x), ys = quad.map(\.y)
                    guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
                    else { continue }
                    drawn = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                } else {
                    // As `image` draws it: cut to its mask while it slides,
                    // softened past that by its blur, then carried by its
                    // offset. A smear only spreads it between places these
                    // moments already hold.
                    var rect = mask(of: piece, pose: pose, em: em)
                    if pose.blurEm > 0 {
                        let radius = CGFloat(pose.blurEm) * em
                        rect = rect.insetBy(dx: -radius * 2, dy: -radius * 2)
                    }
                    drawn = rect.offsetBy(dx: pose.offsetEm.x * em, dy: -pose.offsetEm.y * em)
                }
                guard drawn.width.isFinite, drawn.height.isFinite else { continue }
                farthest = max(farthest, whole.minX - drawn.minX, drawn.maxX - whole.maxX,
                               whole.minY - drawn.minY, drawn.maxY - whole.maxY)
            }
        }
        guard farthest > 0.5 else { return 0 }
        // A couple of pixels for the moments between the ones followed.
        return min((farthest + 2).rounded(.up), max(pieces.pixelSize.width, pieces.pixelSize.height))
    }

    /// Where the corners of a piece's picture land, clockwise from its
    /// top-left as Core Image counts (y up), turned the way `pose` says about
    /// its hinge on its own line box and seen through its own lens
    /// (`lens(for:pose:height:eyeDistance:)`). Nil where it has turned its
    /// back and hides it, or come up to the camera.
    static func turnedQuad(_ piece: TextRevealPieces.Piece, pose: TextRevealPose, em: CGFloat, height: CGFloat,
                           eyeDistance: Double, ignoringBack: Bool = false) -> [CGPoint]? {
        let projection = lens(for: piece, pose: pose, height: height, eyeDistance: eyeDistance)
        // The maths is y-down, the way a layer's turn is stated.
        func down(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: height - p.y) }
        let box = piece.box
        let boxDown = CGRect(x: box.minX, y: height - box.maxY, width: box.width, height: box.height)
        let pivot = CGPoint(x: boxDown.minX + boxDown.width * pose.hinge.x,
                            y: boxDown.minY + boxDown.height * pose.hinge.y)
        // How far back it is, stated against the document's camera, is kept
        // as the same share of the lens's distance, so it looks exactly as
        // far off and as small as it would through the document's camera;
        // only the foreshortening is the lens's own.
        var turn3D = pose.turn3D(em: Double(em))
        if projection.hasPerspective, eyeDistance.isFinite, eyeDistance > 0 {
            turn3D.depth *= projection.eyeDistance / eyeDistance
        }
        let turn = turn3D.affine(pivot: pivot)
        if pose.hidesBack, !ignoringBack {
            guard let front = Space3D.quad(of: boxDown, through: turn, projection),
                  Space3D.facesViewer(front) else { return nil }
        }
        let shift = CGPoint(x: pose.offsetEm.x * em, y: -pose.offsetEm.y * em)
        let r = piece.rect.offsetBy(dx: shift.x, dy: shift.y)
        var landed: [CGPoint] = []
        for corner in [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
                       CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.minY)] {
            guard let p = projection.project(turn.apply(Point3D(down(corner)))) else { return nil }
            landed.append(down(p))
        }
        return landed
    }

    /// A piece's picture warped so the corners of its extent land on `quad`
    /// (top-left, top-right, bottom-right, bottom-left, y up).
    private static func warped(_ image: CIImage, onto quad: [CGPoint]) -> CIImage {
        let warp = CIFilter(name: "CIPerspectiveTransform")
        warp?.setValue(image, forKey: kCIInputImageKey)
        warp?.setValue(CIVector(cgPoint: quad[0]), forKey: "inputTopLeft")
        warp?.setValue(CIVector(cgPoint: quad[1]), forKey: "inputTopRight")
        warp?.setValue(CIVector(cgPoint: quad[2]), forKey: "inputBottomRight")
        warp?.setValue(CIVector(cgPoint: quad[3]), forKey: "inputBottomLeft")
        return warp?.outputImage ?? image
    }

    /// What a piece sliding out from behind its own line box is cut to: that
    /// box, on the axis it travels, and the whole piece where it is not
    /// sliding at all.
    private static func mask(of piece: TextRevealPieces.Piece, pose: TextRevealPose, em: CGFloat) -> CGRect {
        guard pose.slide > 0 else { return piece.rect }
        return pose.direction == .up || pose.direction == .down
            ? CGRect(x: piece.rect.minX, y: piece.box.minY - em * 0.08,
                     width: piece.rect.width, height: piece.box.height + em * 0.16)
            : CGRect(x: piece.box.minX - em * 0.04, y: piece.rect.minY,
                     width: piece.box.width + em * 0.08, height: piece.rect.height)
    }

    /// How far a piece has slid out from behind its box, in pixels, y up.
    private static func slid(_ piece: TextRevealPieces.Piece, pose: TextRevealPose, em: CGFloat) -> CGPoint {
        guard pose.slide > 0 else { return .zero }
        let keep = mask(of: piece, pose: pose, em: em)
        let vertical = pose.direction == .up || pose.direction == .down
        let span = vertical ? keep.height : keep.width
        // Coming UP means it starts below; Core Image's y runs up.
        let shift = CGFloat(pose.slide) * span
        return switch pose.direction {
        case .up: CGPoint(x: 0, y: -shift)
        case .down: CGPoint(x: 0, y: shift)
        case .left: CGPoint(x: shift, y: 0)
        case .right: CGPoint(x: -shift, y: 0)
        }
    }

    /// Everything that carries a piece away from home in a pose, in pixels,
    /// y up: its slide and its offset together.
    private static func place(of piece: TextRevealPieces.Piece, pose: TextRevealPose, em: CGFloat) -> CGPoint {
        let slide = slid(piece, pose: pose, em: em)
        return CGPoint(x: slide.x + pose.offsetEm.x * em, y: slide.y - pose.offsetEm.y * em)
    }

    /// A piece smeared along where `travel` has it while a shutter of
    /// `shutterMS` is open about `elapsed`, or as it was where it moved less
    /// than a pixel.
    private static func smeared(_ image: CIImage, travel: (Double) -> CGPoint, at elapsed: Double,
                                shutterMS: Double) -> CIImage {
        let opens = elapsed - shutterMS / 2
        var stops = [opens]
        var whole = opens.rounded(.down) + 1
        while whole < opens + shutterMS {
            stops.append(whole)
            whole += 1
        }
        stops.append(opens + shutterMS)
        let path = stops.map(travel)
        let span = zip(path, path.dropFirst()).reduce(CGFloat(0)) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
        guard span > MotionSmear.threshold, span.isFinite else { return image }
        let home = travel(elapsed)
        let count = MotionSmear.sampleCount(forSpan: span)
        return MotionSmearFilter.averaged(image, over: (0..<count).map { index in
            let at = travel(opens + shutterMS * Double(index) / Double(count - 1))
            return CGAffineTransform(translationX: at.x - home.x, y: at.y - home.y)
        })
    }
}
