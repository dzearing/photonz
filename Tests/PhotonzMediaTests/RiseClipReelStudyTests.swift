import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The reel for the user to judge (task `words-that-rise-into-a-title-are-never-cut-off-b`):
/// built-in titles' words travelling in, BEFORE (the picture cut at the box the
/// words are laid out in, which is what the renderer drew until this task) over
/// AFTER (the picture given room for the whole move), with that box drawn
/// faintly round both so the cut is plain to see. Then Keynote Clean as the
/// real renderer draws and exports it.
///
/// Not part of the suite: it writes files the audit carries. Run it with
///
///     PHOTONZ_REEL=1 PHOTONZ_REEL_DIR=queue/audits Scripts/test.sh --filter RiseClipReelStudy
@Suite("A reel of words travelling into a title, cut and whole", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct RiseClipReelStudyTests {

    static let canvas = CGSize(width: 1280, height: 720)
    static let at = 1000
    static let lead = 300
    static let context = CIContext()

    /// `preset` placed at `at` over a dark ten second recording, as the app
    /// places it.
    static func placed(_ preset: BuiltInTitle) throws -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 0,
                                                                colorHex: "#20242C", start: .zero,
                                                                end: CGPoint(x: canvas.width, y: canvas.height),
                                                                fillColorHex: "#20242C")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let inserted = doc.insertTitle(preset, atTimeMS: at, motionBlur: true)
        let id = try #require(inserted, "\(preset.name)").layerID
        for words in try #require(doc.layer(id: id)).selfAndDescendants {
            guard let text = words.text else { continue }
            let needed = TextRasterizer.naturalSize(text, maxWidth: .greatestFiniteMagnitude)
            doc.updateLayer(id: words.id) { box in
                box.frame.size.width = max(box.frame.width, needed.width.rounded(.up))
                box.frame.size.height = max(box.frame.height, needed.height.rounded(.up))
            }
        }
        return (doc, id)
    }

    struct Item {
        let slug: String
        let name: String
        let pieces: TextRevealPieces
        let reveal: TextReveal
        let shutterMS: Double?
        let eye: Double
        let reach: CGFloat
        var lengthMS: Int { reveal.lengthMS(count: pieces.pieces.count) + 500 + RiseClipReelStudyTests.lead }
    }

    static func item(_ preset: BuiltInTitle, part: String) throws -> Item {
        let (doc, id) = try placed(preset)
        let group = try #require(doc.layer(id: id))
        let words = try #require(TitleDesign.find(part, in: group), "\(preset.name) \(part)")
        let text = try #require(words.text)
        let reveal = try #require(text.reveal, "\(preset.name) \(part) has no reveal")
        var still = text
        still.reveal = nil
        still.revealElapsedMS = nil
        still.revealShutterMS = nil
        let outlines = words.letterBorders.map { TextRasterizer.TextOutline(width: $0.width, colorHex: $0.colorHex) }
        let start = try #require(group.time).inMS
        let shutter = doc.drawn(atTimeMS: start + 600).layer(id: words.id)?.text?.revealShutterMS
        return try item(slug: preset.rawValue + "-" + part.lowercased().replacingOccurrences(of: " ", with: "-"),
                        name: "\(preset.name): \(reveal.style.title) by \(reveal.unit)", text: still,
                        size: words.frame.size, outlines: outlines, reveal: reveal, shutterMS: shutter,
                        eye: doc.projection.eyeDistance)
    }

    /// Words laid out in a box of `size`, drawn as big as fits a panel of the
    /// reel's 1080p frame.
    static func item(slug: String, name: String, text: TextContent, size: CGSize,
                     outlines: [TextRasterizer.TextOutline] = [], reveal: TextReveal, shutterMS: Double?,
                     eye: Double) throws -> Item {
        let scale = min(1500 / size.width, 300 / size.height, 3)
        let pieces = try #require(TextRasterizer.revealPieces(text, size: size, outlines: outlines, scale: scale,
                                                              unit: reveal.unit))
        let eyePixels = eye * Double(scale)
        return Item(slug: slug, name: name, pieces: pieces, reveal: reveal, shutterMS: shutterMS, eye: eyePixels,
                    reach: TextRevealCompositor.reach(of: pieces, reveal: reveal, eyeDistance: eyePixels))
    }

    /// "Ship it faster." in a box as tight as its words, coming in by `style`.
    static func tight(_ style: TextRevealStyle, unit: TextRevealUnit) throws -> Item {
        let text = TextContent(string: "Ship it faster.", fontSize: 72, colorHex: "#FFFFFF", weight: .bold)
        let size = TextRasterizer.naturalSize(text, maxWidth: .greatestFiniteMagnitude)
        let reveal = TextReveal(style: style, unit: unit)
        return try item(slug: "\(style.rawValue)-by-\(unit)", name: "\(style.title) by \(unit)", text: text,
                        size: CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up)),
                        reveal: reveal, shutterMS: 1000.0 / 60,
                        eye: Projection3D(camera: nil, canvas: CGSize(width: 1920, height: 1080)).eyeDistance)
    }

    /// Before over after, `ms` into the reel, on a 1080p frame.
    static func frame(_ item: Item, ms: Int) -> CGImage? {
        let width = 1920, height = 1080
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setFillColor(CGColor(srgbRed: 0.08, green: 0.09, blue: 0.15, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let elapsed = ms - lead
        let size = item.pieces.pixelSize
        let x = (CGFloat(width) - size.width) / 2 + 80
        for (row, reach) in [(0, CGFloat(0)), (1, item.reach)] {
            // Before in the top half, after in the bottom, each box centred.
            let middle = CGFloat(height) * (row == 0 ? 0.73 : 0.27)
            let box = CGRect(x: x, y: middle - size.height / 2, width: size.width, height: size.height)
            DepthReelStudyTests.draw(row == 0 ? "Before" : "After", at: CGPoint(x: 60, y: middle - 14), size: 40,
                                     in: cg, colour: CGColor(gray: 1, alpha: 1))
            cg.setStrokeColor(CGColor(gray: 1, alpha: 0.3))
            cg.setLineWidth(2)
            cg.setLineDash(phase: 0, lengths: [10, 8])
            cg.stroke(box.insetBy(dx: -1, dy: -1))
            let image = TextRevealCompositor.image(item.pieces, reveal: item.reveal, elapsedMS: max(elapsed, 0),
                                                   shutterMS: item.shutterMS, eyeDistance: item.eye, reach: reach)
            guard elapsed >= 0, let drawn = context.createCGImage(image, from: image.extent) else { continue }
            cg.draw(drawn, in: CGRect(x: box.minX - reach, y: box.minY - reach,
                                      width: image.extent.width, height: image.extent.height))
        }
        DepthReelStudyTests.draw(item.name, at: CGPoint(x: 60, y: CGFloat(height) - 70), size: 30, in: cg,
                                 colour: CGColor(gray: 0.7, alpha: 1))
        return cg.makeImage()
    }

    static func write(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test("Film before and after, and Keynote Clean as exported")
    func film() async throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PHOTONZ_REEL_DIR"]
                            ?? FileManager.default.temporaryDirectory.path)
        let prefix = "2026-10-16-words-whole"
        let items = [
            try Self.item(.keynote, part: "Title"),
            try Self.item(.underline, part: "Name"),
            try Self.tight(.trackIn, unit: .letter),
            try Self.tight(.flipUp, unit: .letter),
        ]
        var sheet: [(String, [CGImage])] = []
        for item in items {
            guard let first = Self.frame(item, ms: 0) else { continue }
            let size = CGSize(width: first.width, height: first.height)
            let length = item.lengthMS
            let mp4 = directory.appendingPathComponent("\(prefix)-\(item.slug).mp4")
            let gif = directory.appendingPathComponent("\(prefix)-\(item.slug).gif")
            try? FileManager.default.removeItem(at: mp4)
            try? FileManager.default.removeItem(at: gif)
            try await DocumentMovieWriter.write(plan: DocumentVideoExport.plan(durationMS: length, canvasSize: size,
                                                                                format: .mp4, quality: .high),
                                                mix: [], soundURLs: [:], to: mp4,
                                                frames: { ms in Self.frame(item, ms: ms) })
            try await DocumentMovieWriter.writeAnimated(plan: DocumentVideoExport.plan(durationMS: length,
                                                                                        canvasSize: size,
                                                                                        format: .gif, quality: .small),
                                                        format: .gif, to: gif,
                                                        frames: { ms in Self.frame(item, ms: ms) })
            // The first beat, where the cut is worst, then on through the move.
            let move = item.reveal.lengthMS(count: item.pieces.pieces.count)
            let stills = [0.05, 0.15, 0.3, 0.5, 1.0].compactMap { share in
                Self.frame(item, ms: Self.lead + Int(Double(move) * share))
            }
            sheet.append((item.name, stills))
            print("[reel] \(item.name) reach \(item.reach): \(mp4.lastPathComponent)")
        }
        // Keynote Clean as the app draws it and an export writes it.
        let (doc, id) = try Self.placed(.keynote)
        let start = try #require(doc.layer(id: id)?.time).inMS
        let store = ImageStore()
        let whole = [150, 300, 450, 700, 1400].compactMap {
            DocumentRenderer().render(doc.drawn(atTimeMS: start + $0), store: store)
        }
        sheet.append(("Keynote Clean, exported", whole))
        let movie = directory.appendingPathComponent("\(prefix)-keynote-exported.mp4")
        try? FileManager.default.removeItem(at: movie)
        try await DocumentMovieWriter.write(plan: DocumentVideoExport.plan(durationMS: 2600, canvasSize: Self.canvas,
                                                                            format: .mp4, quality: .high),
                                            mix: [], soundURLs: [:], to: movie,
                                            frames: { ms in
                                                DocumentRenderer().render(doc.drawn(atTimeMS: start - 200 + ms),
                                                                          store: store)
                                            })
        let contact = try #require(DepthReelStudyTests.contactSheet(sheet, thumb: CGSize(width: 448, height: 252)))
        try Self.write(contact, to: directory.appendingPathComponent("\(prefix)-contact.png"))
        // One big still of the worst moment, before over after, per item.
        for item in items {
            let move = item.reveal.lengthMS(count: item.pieces.pieces.count)
            if let still = Self.frame(item, ms: Self.lead + Int(Double(move) * 0.15)) {
                try Self.write(still, to: directory.appendingPathComponent("\(prefix)-\(item.slug)-early.png"))
            }
        }
        print("[reel] contact sheet \(prefix)-contact.png")
    }
}
