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
            draw(lines)
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
    public static func image(_ pieces: TextRevealPieces, reveal: TextReveal, elapsedMS: Int,
                             shutterMS: Double? = nil) -> CIImage {
        let whole = CGRect(origin: .zero, size: pieces.pixelSize)
        var out = pieces.plate ?? CIImage(color: .clear).cropped(to: whole)
        let ranks = reveal.ranks(count: pieces.pieces.count)
        let em = pieces.emPixels
        for (index, piece) in pieces.pieces.enumerated() {
            let pose = reveal.pose(rank: ranks[index], atElapsedMS: elapsedMS, place: piece.place)
            guard pose.opacity > 0.001, pose.shown > 0.0001 else { continue }
            var image = piece.image
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
        return out.cropped(to: whole)
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
