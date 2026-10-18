import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The calm title pages beside the mock they were built from (task
/// `title-pages-that-look-like-apple-designed-them`): each one inserted as the
/// app inserts it, drawn by the real renderer at the moments the mock is
/// photographed at (0, 25, 50 and 100 percent of its in, and the middle of its
/// hold), laid beside the mock's frame of the same moment, and measured as the
/// mean difference of their pixels. The mock's frames come from
/// `docs/design/title-mock-capture.mjs --frames`.
///
/// Not part of the suite: it needs the mock's frames and writes files the
/// audit carries. Run it with
///
///     PHOTONZ_REEL=1 PHOTONZ_MOCK_DIR=/tmp/tp-mock PHOTONZ_REEL_DIR=queue/audits \
///         Scripts/test.sh --filter TitleCalmMock
///
/// `PHOTONZ_REEL_MOVIES=1` also films each page through the app's own export.
@Suite("The calm title pages beside their mock", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct TitleCalmMockTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let prefix = "2026-10-18-apple-titles"

    /// Each page, the mock's id for it, and when its last part has arrived
    /// in the mock (`d.inEnd`).
    static let pages: [(BuiltInTitle, String, Int)] = [
        (.keynoteSection, "keynote-section", 1030), (.filmSuper, "film-super", 1030),
        (.sessionTitle, "wwdc-session", 1270), (.chapterCard, "event-chapter", 1000),
        (.editorialNY, "editorial", 1350), (.sessionsStage, "stripe-sessions", 1220),
        (.launch, "linear-launch", 1050), (.gradientWord, "gradient-word", 900),
        (.bigNumber, "keynote-stat", 1110), (.endCard, "end-card", 1200),
    ]

    static let labels = ["0", "25", "50", "100", "hold"]

    static func moments(_ inEnd: Int) -> [Int] {
        [0, inEnd / 4, inEnd / 2, inEnd, inEnd + 1100]
    }

    static func placed(_ preset: BuiltInTitle) throws -> PhotonzDocument {
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.durationMS = TitleKind.titlePage.lengthMS
        let inserted = doc.insertTitle(preset, atTimeMS: 0, motionBlur: true)
        _ = try #require(inserted, "\(preset.name)")
        return doc
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// RGBA bytes of `image` drawn at 1920 by 1080.
    static func pixels(_ image: CGImage) -> [UInt8] {
        let width = Int(canvas.width), height = Int(canvas.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return bytes
    }

    /// The mean difference of two frames' colour channels, 0 to 255, and the
    /// bounds of the ink that differs by more than a quarter.
    static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var total = 0
        var index = 0
        while index < a.count {
            total += abs(Int(a[index]) - Int(b[index])) + abs(Int(a[index + 1]) - Int(b[index + 1]))
                + abs(Int(a[index + 2]) - Int(b[index + 2]))
            index += 4
        }
        return Double(total) / Double(a.count / 4 * 3)
    }

    /// The rows and columns where `a` has ink against its own corner colour:
    /// the box of the words, for a quick read of where they sit.
    static func inkBox(_ a: [UInt8]) -> CGRect {
        let width = Int(canvas.width), height = Int(canvas.height)
        let ground = (Int(a[0]), Int(a[1]), Int(a[2]))
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in stride(from: 0, to: height, by: 1) {
            for x in stride(from: 0, to: width, by: 1) {
                let i = (y * width + x) * 4
                let d = abs(Int(a[i]) - ground.0) + abs(Int(a[i + 1]) - ground.1) + abs(Int(a[i + 2]) - ground.2)
                if d > 120 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return maxX < 0 ? .null : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    @Test("Draw every calm page beside its mock and measure the difference")
    func besideTheMock() async throws {
        TextMeasurement.use { text, maxWidth in TextRasterizer.naturalSize(text, maxWidth: maxWidth) }
        let environment = ProcessInfo.processInfo.environment
        let mock = URL(fileURLWithPath: environment["PHOTONZ_MOCK_DIR"] ?? "/tmp/tp-mock")
        let directory = URL(fileURLWithPath: environment["PHOTONZ_REEL_DIR"]
                            ?? FileManager.default.temporaryDirectory.path)
        let only = environment["PHOTONZ_REEL_ONLY"].map { Set($0.split(separator: ",").map(String.init)) }
        let store = ImageStore()
        var rows: [(String, [CGImage])] = []
        var report: [String] = []
        for (preset, id, inEnd) in Self.pages where only?.contains(preset.rawValue) ?? true {
            let doc = try Self.placed(preset)
            var cells: [CGImage] = []
            var line: [String] = []
            for (label, ms) in zip(Self.labels, Self.moments(inEnd)) {
                let app = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store))
                let theirs = try #require(Self.load(mock.appendingPathComponent("\(id)-\(label).png")), "\(id)-\(label)")
                if let frames = environment["PHOTONZ_REEL_FRAMES"] {
                    let url = URL(fileURLWithPath: frames).appendingPathComponent("\(id)-\(label).png")
                    if let out = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                        CGImageDestinationAddImage(out, app, nil)
                        CGImageDestinationFinalize(out)
                    }
                }
                let a = Self.pixels(app), b = Self.pixels(theirs)
                let diff = Self.difference(a, b)
                line.append("\(label) \(String(format: "%.2f", diff))")
                if label == "hold" {
                    let mine = Self.inkBox(a), wanted = Self.inkBox(b)
                    line.append("ink app \(Self.text(mine)) mock \(Self.text(wanted))")
                }
                cells += [theirs, app]
            }
            report.append("\(preset.name): " + line.joined(separator: " · "))
            rows.append((preset.name, cells))
            if environment["PHOTONZ_REEL_MOVIES"] == "1" {
                let frame: @Sendable (Int) -> CGImage? = { ms in
                    DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: store)
                }
                let mp4 = directory.appendingPathComponent("\(Self.prefix)-\(preset.rawValue).mp4")
                let plan = DocumentVideoExport.plan(durationMS: TitleKind.titlePage.lengthMS, canvasSize: Self.canvas,
                                                    format: .mp4, quality: .high, size: .p720)
                try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: mp4, frames: frame)
            }
        }
        print("[calm] " + report.joined(separator: "\n[calm] "))
        let sheet = try #require(Self.sheet(rows))
        let url = directory.appendingPathComponent(only == nil ? "\(Self.prefix)-beside-mock.png"
                                                   : "\(Self.prefix)-beside-mock-part.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, sheet, nil)
        #expect(CGImageDestinationFinalize(destination))
        try report.joined(separator: "\n").write(to: directory.appendingPathComponent("\(Self.prefix)-beside-mock.txt"),
                                                 atomically: true, encoding: .utf8)
        print("[calm] sheet \(url.path)")
    }

    static func text(_ box: CGRect) -> String {
        box.isNull ? "none" : "\(Int(box.minX)),\(Int(box.minY)) \(Int(box.width))x\(Int(box.height))"
    }

    /// Mock then app for each moment, a row per page.
    static func sheet(_ rows: [(String, [CGImage])], thumb: CGSize = CGSize(width: 240, height: 135)) -> CGImage? {
        let label: CGFloat = 170, gap: CGFloat = 6, pair: CGFloat = 14, header: CGFloat = 40
        let columns = labels.count
        let cellWidth = thumb.width * 2 + gap
        let width = Int(label + (cellWidth + pair) * CGFloat(columns) + gap)
        let height = Int(header + (thumb.height + gap) * CGFloat(rows.count) + gap)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.09, green: 0.1, blue: 0.13, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let white = CGColor(gray: 1, alpha: 1), dim = CGColor(gray: 0.7, alpha: 1)
        let titles = ["start", "25% of in", "50% of in", "in", "holding"]
        for (column, title) in titles.enumerated() {
            DepthReelStudyTests.draw("\(title): mock | app", at: CGPoint(x: label + gap + CGFloat(column) * (cellWidth + pair),
                                                                        y: CGFloat(height) - 28),
                                     size: 14, in: context, colour: dim)
        }
        for (row, entry) in rows.enumerated() {
            let y = CGFloat(height) - header - CGFloat(row + 1) * (thumb.height + gap)
            DepthReelStudyTests.draw(entry.0, at: CGPoint(x: 12, y: y + thumb.height / 2 - 6), size: 15,
                                     in: context, colour: white)
            for (index, image) in entry.1.enumerated() {
                let column = index / 2, side = index % 2
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: label + gap + CGFloat(column) * (cellWidth + pair)
                                                + CGFloat(side) * (thumb.width + gap),
                                               y: y, width: thumb.width, height: thumb.height))
            }
        }
        return context.makeImage()
    }
}
