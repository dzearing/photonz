import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The reel for the user to judge (task `title-text-visibly-comes-in-and-every-built-in-t`):
/// every built-in title as the app inserts it, filmed by the real renderer as
/// a five second MP4 and GIF through the app's own export, and a contact sheet
/// of its first 800 ms and its hold over a dark recording and a light one.
///
/// Not part of the suite: it writes files the audit carries. Run it with
///
///     PHOTONZ_REEL=1 PHOTONZ_REEL_DIR=queue/audits Scripts/test.sh --filter TitleSetReel
///
/// `PHOTONZ_REEL_SHEET_ONLY=1` writes only the contact sheet, for a quick look.
@Suite("A reel of the built-in titles", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct TitleSetReelTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let lengthMS = 5000
    static let at = 500
    static let prefix = "2026-10-12-title-set"
    /// The frames the sheet shows, in ms from the title's start: its first
    /// 800 ms, then once it holds.
    static let moments = [0, 100, 200, 300, 400, 600, 800, 1600]

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts/playtest/fixtures")
    }

    static func picture(_ name: String) throws -> CGImage {
        let url = fixtures.appendingPathComponent(name)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "\(name)")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// `preset` placed half a second into a ten second recording of `footage`.
    static func titled(_ preset: BuiltInTitle, over footage: CGImage, store: ImageStore) throws -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording", content: .image(store.register(footage)),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let landed = doc.insertTitle(preset, atTimeMS: at, motionBlur: true)
        _ = try #require(landed, "\(preset.name)")
        return doc
    }

    @Test("Film every built-in, write the contact sheet")
    func film() async throws {
        TextMeasurement.use { text, maxWidth in TextRasterizer.naturalSize(text, maxWidth: maxWidth) }
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: environment["PHOTONZ_REEL_DIR"]
                            ?? FileManager.default.temporaryDirectory.path)
        let sheetOnly = environment["PHOTONZ_REEL_SHEET_ONLY"] == "1"
        let only = environment["PHOTONZ_REEL_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let footage = [("dark", try Self.picture("Dark artboard with glow 800x500.png")),
                       ("light", try Self.picture("Busy screenshot 800x500.png"))]
        let store = ImageStore()
        var rows: [(String, [CGImage])] = []
        for preset in BuiltInTitle.shelved where only?.contains(preset.rawValue) ?? true {
            for (shade, backdrop) in footage {
                let doc = try Self.titled(preset, over: backdrop, store: store)
                let frame: @Sendable (Int) -> CGImage? = { ms in
                    DocumentRenderer().render(doc.drawn(atTimeMS: Self.at + ms), store: store)
                }
                if !sheetOnly, shade == "dark" {
                    let slug = preset.rawValue
                    let mp4 = directory.appendingPathComponent("\(Self.prefix)-\(slug).mp4")
                    let gif = directory.appendingPathComponent("\(Self.prefix)-\(slug).gif")
                    let moviePlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                             format: .mp4, quality: .high, size: .p720)
                    try await DocumentMovieWriter.write(plan: moviePlan, mix: [], soundURLs: [:], to: mp4,
                                                        frames: frame)
                    let gifPlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                           format: .gif, quality: .small, size: .p480)
                    try await DocumentMovieWriter.writeAnimated(plan: gifPlan, format: .gif, to: gif, frames: frame)
                    print("[reel] \(preset.name): \(mp4.lastPathComponent), \(gif.lastPathComponent)")
                }
                let stills = try Self.moments.map { ms -> CGImage in
                    let image = try #require(frame(ms))
                    // A card is small on the whole frame: its corner, larger.
                    guard preset.kind == .nameCard else { return image }
                    let corner = CGRect(x: 0, y: image.height * 2 / 5, width: image.width * 3 / 5,
                                        height: image.height * 3 / 5)
                    return try #require(image.cropping(to: corner))
                }
                rows.append(("\(preset.name), \(shade)", stills))
            }
        }
        let sheet = try #require(Self.contactSheet(rows))
        let name = only == nil ? "\(Self.prefix)-contact.png" : "\(Self.prefix)-contact-part.png"
        let sheetURL = directory.appendingPathComponent(name)
        let destination = try #require(CGImageDestinationCreateWithURL(sheetURL as CFURL,
                                                                       UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, sheet, nil)
        #expect(CGImageDestinationFinalize(destination))
        print("[reel] contact sheet \(sheetURL.path)")
    }

    static func contactSheet(_ rows: [(String, [CGImage])],
                             thumb: CGSize = CGSize(width: 288, height: 162)) -> CGImage? {
        let label: CGFloat = 250, gap: CGFloat = 8, header: CGFloat = 40
        let columns = moments.count
        let width = Int(label + (thumb.width + gap) * CGFloat(columns) + gap)
        let height = Int(header + (thumb.height + gap) * CGFloat(rows.count) + gap)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.09, green: 0.1, blue: 0.13, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let white = CGColor(gray: 1, alpha: 1), dim = CGColor(gray: 0.7, alpha: 1)
        for (column, ms) in moments.enumerated() {
            let title = column == moments.count - 1 ? "holding" : "\(ms) ms"
            DepthReelStudyTests.draw(title, at: CGPoint(x: label + gap + CGFloat(column) * (thumb.width + gap),
                                                        y: CGFloat(height) - 28),
                                     size: 15, in: context, colour: dim)
        }
        for (row, entry) in rows.enumerated() {
            let y = CGFloat(height) - header - CGFloat(row + 1) * (thumb.height + gap)
            DepthReelStudyTests.draw(entry.0, at: CGPoint(x: 14, y: y + thumb.height / 2 - 6), size: 16,
                                     in: context, colour: white)
            for (column, image) in entry.1.enumerated() {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: label + gap + CGFloat(column) * (thumb.width + gap), y: y,
                                               width: thumb.width, height: thumb.height))
            }
        }
        return context.makeImage()
    }
}
