import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The reel for the user to judge (task `title-backgrounds-that-are-alive-auroras-energy`):
/// every moving title background behind a real title, filmed by the real
/// renderer as a four second MP4 and GIF through the app's own export, and a
/// contact sheet of six frames across two seconds.
///
/// Not part of the suite: it writes files the audit carries. Run it with
///
///     PHOTONZ_REEL=1 PHOTONZ_REEL_DIR=queue/audits swift test --filter LiveBackdropReel
///
/// `PHOTONZ_REEL_SHEET_ONLY=1` writes only the contact sheet, for a quick look.
@Suite("A reel of the moving title backgrounds", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct LiveBackdropReelTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let lengthMS = 4000
    static let prefix = "2026-10-12-live-backdrops"

    /// The Midnight title page wearing `look`, over its own four seconds.
    static func titled(_ look: LiveLook, theme: TitleTheme? = nil) throws -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#0C0E14")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let landed = doc.insertTitle(.midnight, atTimeMS: 0)
        let inserted = try #require(landed)
        #expect(doc.restyleTitle(layerID: inserted.layerID) { recipe in
            recipe.background = TitleBackgroundKind(look: look)
            if let theme { recipe.theme = theme }
        })
        return doc
    }

    @Test("Film every look, write the contact sheet")
    func film() async throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = URL(fileURLWithPath: environment["PHOTONZ_REEL_DIR"]
                            ?? FileManager.default.temporaryDirectory.path)
        let sheetOnly = environment["PHOTONZ_REEL_SHEET_ONLY"] == "1"
        let store = ImageStore()
        var rows: [(String, [CGImage])] = []
        for look in LiveLook.allCases {
            let doc = try Self.titled(look)
            let slug = look.rawValue
            if !sheetOnly {
                let mp4 = directory.appendingPathComponent("\(Self.prefix)-\(slug).mp4")
                let gif = directory.appendingPathComponent("\(Self.prefix)-\(slug).gif")
                let moviePlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                         format: .mp4, quality: .high, size: .p720)
                try await DocumentMovieWriter.write(plan: moviePlan, mix: [], soundURLs: [:], to: mp4,
                                                    frames: { ms in
                                                        DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store)
                                                    })
                let gifPlan = DocumentVideoExport.plan(durationMS: Self.lengthMS, canvasSize: Self.canvas,
                                                       format: .gif, quality: .small, size: .p480)
                try await DocumentMovieWriter.writeAnimated(plan: gifPlan, format: .gif, to: gif,
                                                            frames: { ms in
                                                                DocumentRenderer().render(doc.drawn(atTimeMS: ms),
                                                                                          store: store)
                                                            })
                print("[reel] \(look.title): \(mp4.lastPathComponent), \(gif.lastPathComponent)")
            }
            let stills = Self.sheetMoments.compactMap { ms in
                DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store)
            }
            rows.append((look.title, stills))
        }
        let sheet = try #require(Self.contactSheet(rows))
        let sheetURL = directory.appendingPathComponent("\(Self.prefix)-contact.png")
        let destination = try #require(CGImageDestinationCreateWithURL(sheetURL as CFURL,
                                                                       UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, sheet, nil)
        #expect(CGImageDestinationFinalize(destination))
        print("[reel] contact sheet \(sheetURL.path)")
    }

    /// Six frames across two seconds, from a second in.
    static let sheetMoments = [1000, 1400, 1800, 2200, 2600, 3000]

    static func contactSheet(_ rows: [(String, [CGImage])],
                             thumb: CGSize = CGSize(width: 320, height: 180)) -> CGImage? {
        let label: CGFloat = 230, gap: CGFloat = 10, header: CGFloat = 40
        let columns = sheetMoments.count
        let width = Int(label + (thumb.width + gap) * CGFloat(columns) + gap)
        let height = Int(header + (thumb.height + gap) * CGFloat(rows.count) + gap)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.09, green: 0.1, blue: 0.13, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let white = CGColor(gray: 1, alpha: 1), dim = CGColor(gray: 0.7, alpha: 1)
        for (column, ms) in sheetMoments.enumerated() {
            DepthReelStudyTests.draw(String(format: "%.1f s", Double(ms) / 1000),
                                     at: CGPoint(x: label + gap + CGFloat(column) * (thumb.width + gap),
                                                 y: CGFloat(height) - 28),
                                     size: 15, in: context, colour: dim)
        }
        for (row, entry) in rows.enumerated() {
            let y = CGFloat(height) - header - CGFloat(row + 1) * (thumb.height + gap)
            DepthReelStudyTests.draw(entry.0, at: CGPoint(x: 16, y: y + thumb.height / 2 - 6), size: 17,
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
