import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Text that swings, flips or flies in from depth is drawn with real
/// perspective (task `text-that-swings-flips-or-flies-in-from-depth-is`).
///
/// The user, 2026-10-11, of the depth entrances: "that has no perspective,
/// those are just 2d animations". A word seen through the document's camera,
/// a thousand pixels away and centred on the whole text, barely foreshortens
/// and leans like italic type where it sits off the middle. So each piece
/// turning in depth is seen through its own lens, close and centred on it, the
/// way animated type is everywhere else: the bar is that the near edge of a
/// turning word or letter is at least 1.3 times the far one half way in.
@Suite("Text turning in depth is drawn in perspective", .serialized)
struct TextDepthPerspectiveTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let styles: [TextRevealStyle] = [.swingIn, .flipUp, .flyInFromDepth, .tiltSettle]

    static func pieces(_ unit: TextRevealUnit, string: String = "Ship it faster.") throws -> TextRevealPieces {
        try #require(TextRasterizer.revealPieces(TextContent(string: string, fontSize: 112, colorHex: "#FFFFFF",
                                                             weight: .bold),
                                                 size: CGSize(width: 1000, height: 160), unit: unit))
    }

    /// The document's own camera at its default, in a 1080p frame.
    static var documentEye: Double { Projection3D(camera: nil, canvas: canvas).eyeDistance }

    /// The ratio between a turned quad's near and far edges, on the axis it
    /// turns most about: 1 for a flat slant, more the stronger the perspective.
    static func edgeRatio(_ quad: [CGPoint], pose: TextRevealPose) -> Double {
        func length(_ a: CGPoint, _ b: CGPoint) -> Double { Double(hypot(a.x - b.x, a.y - b.y)) }
        let (one, two) = abs(pose.turnY) > abs(pose.turnX)
            ? (length(quad[0], quad[3]), length(quad[1], quad[2]))
            : (length(quad[0], quad[1]), length(quad[3], quad[2]))
        return max(one, two) / max(min(one, two), 0.0001)
    }

    static func quad(_ piece: TextRevealPieces.Piece, _ pieces: TextRevealPieces, pose: TextRevealPose)
        -> [CGPoint]? {
        TextRevealCompositor.turnedQuad(piece, pose: pose, em: pieces.emPixels, height: pieces.pixelSize.height,
                                        eyeDistance: documentEye)
    }

    /// Where the corners of a piece's own line box land, clockwise from its
    /// top-left, y down: the picture's corners go to `quad` (y up) and the
    /// box sits inside the picture, padded round for swashes and accents.
    static func box(_ piece: TextRevealPieces.Piece, _ pieces: TextRevealPieces, quad: [CGPoint]) throws
        -> [CGPoint] {
        let height = pieces.pixelSize.height
        func down(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: height - p.y) }
        let rect = CGRect(x: piece.rect.minX, y: height - piece.rect.maxY,
                          width: piece.rect.width, height: piece.rect.height)
        let map = try #require(Homography(box: rect, to: quad.map(down)))
        let box = CGRect(x: piece.box.minX, y: height - piece.box.maxY,
                         width: piece.box.width, height: piece.box.height)
        return try [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                    CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            .map { try #require(map.apply($0)) }
    }

    @Test("Half way in, a turning word or letter has a near edge at least 1.3 times its far one",
          arguments: styles, [TextRevealUnit.word, .letter])
    func midpointForeshortens(style: TextRevealStyle, unit: TextRevealUnit) throws {
        let pieces = try Self.pieces(unit)
        let reveal = TextReveal(style: style, unit: unit)
        let piece = try #require(pieces.pieces.first)
        let pose = reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS / 2)
        let quad = try #require(Self.quad(piece, pieces, pose: pose))
        let ratio = Self.edgeRatio(try Self.box(piece, pieces, quad: quad), pose: pose)
        print(String(format: "[perspective] %@ by %@: turned %.0f/%.0f deg, near:far %.2f", style.title,
                     "\(unit)", pose.turnX, pose.turnY, ratio))
        #expect(ratio >= 1.3, "\(style.title) by \(unit): near:far \(ratio)")
        // A tenth of a second apart the piece has visibly moved: a corner
        // travels at least a tenth of the type size.
        let later = reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS / 2 + 100)
        let then = try #require(Self.quad(piece, pieces, pose: later))
        let moved = zip(quad, then).map { Double(hypot($0.x - $1.x, $0.y - $1.y)) }.max() ?? 0
        #expect(moved >= Double(pieces.emPixels) * 0.1, "\(style.title) by \(unit) moved \(moved) px in 100 ms")
    }

    @Test("Every word leans the same way wherever it sits on the line: no italic slant off the middle")
    func noSlantOffTheMiddle() throws {
        let pieces = try Self.pieces(.word)
        let reveal = TextReveal(style: .swingIn, unit: .word)
        let pose = reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS / 2)
        for piece in pieces.pieces {
            let corners = try Self.box(piece, pieces, quad: try #require(Self.quad(piece, pieces, pose: pose)))
            // Swinging up about its bottom edge, the top edge narrows evenly
            // from both ends: its middle stays over the bottom edge's middle.
            let topMiddle = (corners[0].x + corners[1].x) / 2
            let bottomMiddle = (corners[3].x + corners[2].x) / 2
            #expect(abs(topMiddle - bottomMiddle) < 1, "a word leans by \(topMiddle - bottomMiddle) px")
            #expect(corners[1].x - corners[0].x < (corners[2].x - corners[3].x) * 0.85, "the top is not narrower")
        }
    }

    @Test("Turned toward the camera, a word may draw past its text box rather than be cut at it")
    func reachesPastTheBox() throws {
        let pieces = try Self.pieces(.word)
        let reach = TextRevealCompositor.reach(of: pieces)
        #expect(reach > 0)
        let reveal = TextReveal(style: .flipUp, unit: .word, staggerMS: 0)
        let image = TextRevealCompositor.image(pieces, reveal: reveal, elapsedMS: reveal.lengthMS / 2,
                                               eyeDistance: Self.documentEye, reach: reach)
        #expect(image.extent == CGRect(x: 0, y: 0, width: pieces.pixelSize.width + reach * 2,
                                       height: pieces.pixelSize.height + reach * 2))
        // Without any reach asked for, the picture is the text's own size.
        let plain = TextRevealCompositor.image(pieces, reveal: reveal, elapsedMS: reveal.lengthMS / 2,
                                               eyeDistance: Self.documentEye)
        #expect(plain.extent == CGRect(origin: .zero, size: pieces.pixelSize))
    }

    @Test("A document with its perspective turned off keeps the words flat as it asked")
    func noPerspectiveStaysFlat() throws {
        let pieces = try Self.pieces(.word)
        let piece = try #require(pieces.pieces.first)
        let reveal = TextReveal(style: .swingIn, unit: .word)
        let pose = reveal.pose(rank: 0, atElapsedMS: reveal.lengthMS / 2)
        let quad = try #require(TextRevealCompositor.turnedQuad(piece, pose: pose, em: pieces.emPixels,
                                                                height: pieces.pixelSize.height,
                                                                eyeDistance: .infinity))
        #expect(abs(Self.edgeRatio(try Self.box(piece, pieces, quad: quad), pose: pose) - 1) < 0.001)
    }

    @Test("Title builds and word reveals start the depth entrances from the same angles, on a curve that is half way at half time")
    func defaultsAgree() {
        let pairs: [(TitleBuildKind, TextRevealStyle)] = [(.swingIn, .swingIn), (.flipUp, .flipUp),
                                                          (.flyInFromDepth, .flyInFromDepth),
                                                          (.tiltSettle, .tiltSettle)]
        for (kind, style) in pairs {
            // Fly In's distance is points of the frame on a title and percent
            // of the type on its words: two units, so only the angles compare.
            if kind != .flyInFromDepth {
                #expect(kind.defaultAmount == style.defaultAmount, "\(kind.title)")
            }
            #expect(kind.defaultCurve == style.defaultCurve, "\(kind.title)")
            #expect(abs(style.defaultCurve.value(at: 0.5) - 0.5) < 0.01, "\(kind.title)")
        }
        // A flip starts edge on, so none of its time is spent facing away.
        #expect(TextRevealStyle.flipUp.defaultAmount == 90)
    }

    @Test("1080p, a headline flipping up by letter, motion blur on: a frame in under 16ms")
    func perf() throws {
        var reveal = TextReveal(style: .flipUp, unit: .letter)
        reveal.startMS = 0
        var (doc, id) = TextRevealRenderTests.document(reveal, string: "Ship faster with every release")
        if let index = doc.layers.firstIndex(where: { $0.id == id }) {
            doc.layers[index].style.effects.append(.motionBlur(MotionBlurEffect(shutterAngle: 180, isOn: true)))
        }
        let renderer = DocumentRenderer()
        let store = ImageStore()
        _ = renderer.renderInteractive(doc.drawn(atTimeMS: 1_100), store: store)
        var samples: [Double] = []
        for step in 0..<30 {
            let drawn = doc.drawn(atTimeMS: 1_100 + step * 33)
            let began = ContinuousClock.now
            _ = renderer.renderInteractive(drawn, store: store)
            let spent = ContinuousClock.now - began
            samples.append(Double(spent.components.seconds) * 1000 + Double(spent.components.attoseconds) / 1e15)
        }
        samples.sort()
        let median = samples[samples.count / 2], slowest = samples[samples.count - 1]
        print(String(format: "[perf] headline flipping up by letter, 1920x1080: median %.1fms, slowest %.1fms",
                     median, slowest))
        #expect(median < 16)
        MachineSpeed.check("text flipping up by letter at 1080p", medianMS: median, baselineMS: 8)
    }
}
