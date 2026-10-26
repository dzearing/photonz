import CoreGraphics
import CoreImage
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Words that travel into a title are never cut off by their own box (task
/// `words-that-rise-into-a-title-are-never-cut-off-b`).
///
/// A word rising in from below starts under its resting place, and on the
/// bottom line of a title that is under the bottom of the box the words are
/// laid out in: the picture of the words was cut at that box, so the word
/// arrived sliced across its feet, and only the depth flips were given room
/// past it. Measured before the fix on Keynote Clean, the headline's rising
/// words had as little as half of their ink on screen in the first frames of
/// the move.
///
/// The bar, at every frame of every entrance: of a travelling piece's ink as
/// it is posed (faded, blurred, smeared, turned, all as drawn), the share that
/// the picture the renderer asks for actually holds. The reference is the
/// same pose drawn with room enough for anything, so the only thing measured
/// is what the box cuts off. It is all of it, every frame.
@Suite("Words that travel into a title are never cut off by their own box")
struct TextRevealUnclippedTests {

    static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull(),
                                             .workingFormat: NSNumber(value: CIFormat.RGBAf.rawValue)])

    /// The total alpha in `image`, over its whole extent.
    static func ink(_ image: CIImage) -> Double {
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1, extent.width.isFinite, extent.height.isFinite else { return 0 }
        let average = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
        var pixel = [Float](repeating: 0, count: 4)
        context.render(average, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBAf, colorSpace: nil)
        return Double(pixel[3]) * Double(extent.width * extent.height)
    }

    /// For each piece of `pieces` that is on screen `elapsed` ms into
    /// `reveal`, the share of its posed ink that a picture with `reach` holds.
    static func shares(_ pieces: TextRevealPieces, reveal: TextReveal, elapsed: Int, shutterMS: Double? = nil,
                       reach: CGFloat) -> [Double] {
        let ranks = reveal.ranks(count: pieces.pieces.count)
        let room = max(pieces.pixelSize.width, pieces.pixelSize.height) * 2
        var out: [Double] = []
        for (index, piece) in pieces.pieces.enumerated() {
            // One piece alone, at its own beat: a piece on rank r is where a
            // piece on rank 0 is r beats earlier.
            let alone = TextRevealPieces(pieces: [piece], pixelSize: pieces.pixelSize, emPixels: pieces.emPixels,
                                         plate: nil)
            let shifted = elapsed - ranks[index] * reveal.staggerMS
            let pose = reveal.pose(rank: ranks[index], atElapsedMS: elapsed, place: piece.place)
            guard pose.opacity > 0.02, pose.shown > 0.0001 else { continue }
            let full = ink(TextRevealCompositor.image(alone, reveal: reveal, elapsedMS: shifted,
                                                      shutterMS: shutterMS, reach: room))
            guard full > 1 else { continue }
            let drawn = ink(TextRevealCompositor.image(alone, reveal: reveal, elapsedMS: shifted,
                                                       shutterMS: shutterMS, reach: reach))
            out.append(drawn / full)
        }
        return out
    }

    /// The worst share over every frame (30 a second) of `reveal` on `pieces`.
    static func worst(_ pieces: TextRevealPieces, reveal: TextReveal, shutterMS: Double? = nil,
                      reach: CGFloat) -> (share: Double, atMS: Int) {
        let length = reveal.lengthMS(count: pieces.pieces.count)
        var worst = (share: 1.0, atMS: 0)
        for elapsed in stride(from: 0, through: length, by: 33) {
            for share in shares(pieces, reveal: reveal, elapsed: elapsed, shutterMS: shutterMS, reach: reach)
                where share < worst.share {
                worst = (share, elapsed)
            }
        }
        return worst
    }

    static func percent(_ share: Double) -> String { String(format: "%.1f%%", share * 100) }

    /// The bar: everything, give or take a rounding.
    static let whole = 0.998

    // MARK: - Every entrance a title can give its words

    /// "Ship it faster." on one line, in a box as tight as a title's words
    /// sit in, with an entrance at its most travelled. By letter, "Ship"
    /// alone: a capital, an ascender, a dot and a descender, the first and
    /// last at the box's two ends, which is every way a letter meets the box.
    /// The fifteen letters of the line were five times the drawing for no
    /// letter that differs from these (2026-10-26: 218 s of a GitHub run).
    static func tight(_ unit: TextRevealUnit) throws -> TextRevealPieces {
        let text = TextContent(string: unit == .letter ? "Ship" : "Ship it faster.", fontSize: 64,
                               colorHex: "#FFFFFF", weight: .bold)
        let size = TextRasterizer.naturalSize(text, maxWidth: .greatestFiniteMagnitude)
        return try #require(TextRasterizer.revealPieces(text, size: CGSize(width: size.width.rounded(.up),
                                                                           height: size.height.rounded(.up)),
                                                        unit: unit))
    }

    static let travelling: [TextRevealStyle] = TextRevealStyle.allCases.filter { $0 != .typewriter }

    @Test("Every entrance, by word and by letter, every way it comes in, keeps all of every piece on screen",
          arguments: travelling)
    func everyEntrance(_ style: TextRevealStyle) throws {
        for unit in [TextRevealUnit.word, .letter] {
            let pieces = try Self.tight(unit)
            for direction in [TitleDirection.up, .down, .left, .right] {
                // A rise of a whole em, past anything a built-in title asks.
                let amount = style == .riseAndFade ? 100 : nil as Double?
                let reveal = TextReveal(style: style, unit: unit, amount: amount, direction: direction)
                for shutter in [nil, 1000.0 / 60] as [Double?] {
                    let reach = TextRevealCompositor.reach(of: pieces, reveal: reveal)
                    let worst = Self.worst(pieces, reveal: reveal, shutterMS: shutter, reach: reach)
                    #expect(worst.share >= Self.whole,
                            "\(style.title) by \(unit) \(direction) shutter \(shutter ?? 0): \(Self.percent(worst.share)) at \(worst.atMS) ms")
                }
            }
        }
    }

    @Test("A mask reveal still comes out from behind its own line, and nothing that stays inside its box is given room")
    func maskStillMasksAndStillWordsAreUntouched() throws {
        let pieces = try Self.tight(.word)
        // Mask Reveal's pieces are hidden behind their own line on purpose:
        // that edge is the look, not a cut.
        let mask = TextReveal(style: .maskReveal, unit: .word)
        let early = TextRevealCompositor.image(pieces, reveal: mask, elapsedMS: mask.lengthMS / 6,
                                              reach: TextRevealCompositor.reach(of: pieces, reveal: mask))
        let rest = TextRevealCompositor.image(pieces, reveal: mask, elapsedMS: mask.lengthMS(count: 3) + 1)
        #expect(Self.ink(early) < Self.ink(rest) * 0.9)
        // A plain fade, a wipe and a typewriter never leave their box, so the
        // picture is exactly the box's.
        for style in [TextRevealStyle.wipe, .typewriter] {
            #expect(TextRevealCompositor.reach(of: pieces, reveal: TextReveal(style: style, unit: .word)) == 0)
        }
        #expect(TextRevealCompositor.reach(of: pieces, reveal: TextReveal(style: .riseAndFade, unit: .word,
                                                                          amount: 0)) == 0)
    }

    // MARK: - The built-in titles, as placed

    @Test("Every built-in title's travelling words are all on screen at every frame of their entrance",
          arguments: BuiltInTitle.shelved)
    func builtInTitles(_ preset: BuiltInTitle) throws {
        let (doc, id) = try TitleEntranceInkTests.placed(preset)
        let group = try #require(doc.layer(id: id))
        let start = try #require(group.time).inMS
        let length = try #require(group.time).lengthMS
        var measured: [String] = []
        for words in group.selfAndDescendants {
            guard let text = words.text, let reveal = text.reveal else { continue }
            var still = text
            still.reveal = nil
            still.revealElapsedMS = nil
            still.revealShutterMS = nil
            let outlines = words.letterBorders.map {
                TextRasterizer.TextOutline(width: $0.width, colorHex: $0.colorHex)
            }
            let pieces = try #require(TextRasterizer.revealPieces(still, size: words.frame.size, outlines: outlines,
                                                                   unit: reveal.unit), "\(preset.name) \(words.name)")
            // The shutter the title is drawn with while it plays.
            let drawn = doc.drawn(atTimeMS: start + length / 4)
            let shutter = drawn.layer(id: words.id)?.text?.revealShutterMS
            let reach = TextRevealCompositor.reach(of: pieces, reveal: reveal)
            let worst = Self.worst(pieces, reveal: reveal, shutterMS: shutter, reach: reach)
            measured.append("\(words.name) \(reveal.style.title) by \(reveal.unit): \(Self.percent(worst.share)) at \(worst.atMS) ms reach \(reach) box \(words.frame.size) shutter \(shutter ?? 0)")
            #expect(worst.share >= Self.whole,
                    "\(preset.name) \(words.name) (\(reveal.style.title) by \(reveal.unit)): \(Self.percent(worst.share)) of a piece on screen at \(worst.atMS) ms")
        }
        if ProcessInfo.processInfo.environment["PHOTONZ_CLIP_PRINT"] == "1" {
            print("[clip] \(preset.name): " + measured.joined(separator: "; "))
        }
    }

    // MARK: - On the canvas and in an export

    @Test("A word rising in on the canvas is drawn below its box while it travels, and the frame matches the export")
    func onTheCanvas() throws {
        let canvas = CGSize(width: 640, height: 360)
        var doc = PhotonzDocument(canvasSize: canvas)
        var text = TextContent(string: "Rise", fontSize: 80, colorHex: "#FFFFFF", weight: .bold)
        let size = TextRasterizer.naturalSize(text, maxWidth: .greatestFiniteMagnitude)
        let box = CGRect(x: 100, y: 100, width: size.width.rounded(.up), height: size.height.rounded(.up))
        text.reveal = TextReveal(style: .riseAndFade, unit: .word, lengthMS: 600, amount: 100,
                                 curve: .linear)
        text.revealElapsedMS = 300
        doc.layers = [Layer(name: "Words", content: .text(text), frame: box)]
        // The canvas draws at the document's size; an export can draw the same
        // frame bigger, with the very same renderer.
        for scale in [1, 2] as [CGFloat] {
            let image = try #require(scale == 1 ? DocumentRenderer().render(doc, store: ImageStore())
                                                : DocumentRenderer().render(doc, store: ImageStore(), scale: scale))
            let width = image.width, height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            // Half way up a rise of an em, the word's feet are half an em under
            // where they rest, past the bottom of the box: rows under the box
            // (top-left origin in the document, so bitmap rows counted from the
            // top) hold ink.
            let pixels = CGFloat(width) / canvas.width
            let below = Int((box.maxY + 2) * pixels)..<Int((box.maxY + 80 * 0.4) * pixels)
            var lit = 0
            for row in below {
                for column in Int(box.minX * pixels)..<Int(box.maxX * pixels) {
                    if bytes[(row * width + column) * 4] > 40 { lit += 1 }
                }
            }
            #expect(lit > Int(50 * pixels * pixels), "only \(lit) lit pixels under the box at \(scale)x")
        }
    }
}
