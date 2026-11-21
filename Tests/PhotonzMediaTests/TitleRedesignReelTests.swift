import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// Five title pages redesigned from a reference board (task
/// `keynote-clean-soft-gradient-glass-kinetic-bold-t`).
///
/// The user, 2026-11-21: Keynote Clean and Soft Gradient Glass "look like
/// clipart ... These purple colors are just not what you would see on high
/// quality refined title slides", then "same with kinetic bold, tech terminal,
/// stacked stagger". This films the five as the app inserts them, writes the
/// frames of a contact sheet, a held frame of each for blind scoring, the
/// background's motion while it holds (the mean difference of two frames half
/// a second apart, 0 to 255, only the background showing) and, after, a reel.
///
/// Run once as `before` on the old designs and once as `after`; the after run
/// also writes the calm set's held frames and lays old beside new:
///
///     PHOTONZ_REEL=1 PHOTONZ_REDESIGN_PHASE=before PHOTONZ_REDESIGN_DIR=/tmp/redesign \
///         Scripts/test.sh --filter TitleRedesignReel
///
/// Not part of the suite: it writes the files the audit carries.
@Suite("Five title pages redesigned: before and after", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct TitleRedesignReelTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let five: [BuiltInTitle] = [.keynote, .softGlass, .kinetic, .terminal, .stacked]
    /// The frames the sheet shows, in ms from the title's start.
    static let moments = [0, 200, 400, 700, 1100, 1600, 2400]
    static let hold = (2000, 2500)

    @Test("Film the five")
    func film() async throws {
        TextMeasurement.use { text, maxWidth in TextRasterizer.naturalSize(text, maxWidth: maxWidth) }
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["PHOTONZ_REDESIGN_PHASE"] ?? "after"
        let root = URL(fileURLWithPath: environment["PHOTONZ_REDESIGN_DIR"] ?? "/tmp/redesign")
        let directory = root.appendingPathComponent(phase)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let footage = try TitleMoreStylesCalmReelTests.picture("Dark artboard with glow 800x500.png")
        let store = ImageStore()
        let render = { (d: PhotonzDocument, ms: Int) throws -> CGImage in
            try #require(DocumentRenderer().render(d.drawn(atTimeMS: ms), store: store))
        }
        var docs: [(BuiltInTitle, PhotonzDocument)] = []
        var motion: [String: Double] = [:]
        for preset in Self.five {
            let (doc, id) = try TitleMoreStylesCalmReelTests.titled(preset, over: footage, store: store)
            docs.append((preset, doc))
            let bare = try TitleMoreStylesCalmReelTests.backgroundOnly(doc, id)
            motion[preset.rawValue] = TitleMoreStylesCalmReelTests.difference(
                TitleMoreStylesCalmReelTests.pixels(try render(bare, Self.hold.0)),
                TitleMoreStylesCalmReelTests.pixels(try render(bare, Self.hold.1)))
            for ms in Self.moments {
                try TitleMoreStylesCalmReelTests.write(try render(doc, ms),
                                                       to: directory.appendingPathComponent("\(preset.rawValue)-\(ms).png"))
            }
            try TitleMoreStylesCalmReelTests.write(try render(doc, 2400),
                                                   to: directory.appendingPathComponent("hold-\(preset.rawValue).png"))
            print("[redesign] \(phase) \(preset.name): bg motion \(String(format: "%.3f", motion[preset.rawValue] ?? 0))")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(motion).write(to: root.appendingPathComponent("\(phase)-motion.json"))

        guard phase == "after" else { return }
        // The calm set, held, for the blind score.
        let calm = root.appendingPathComponent("calm")
        try FileManager.default.createDirectory(at: calm, withIntermediateDirectories: true)
        for preset in BuiltInTitle.calmSet {
            let (doc, _) = try TitleMoreStylesCalmReelTests.titled(preset, over: footage, store: store)
            try TitleMoreStylesCalmReelTests.write(try render(doc, 2400),
                                                   to: calm.appendingPathComponent("hold-\(preset.rawValue).png"))
        }

        // The reel: the five new ones, one after another, each labelled.
        if environment["PHOTONZ_REDESIGN_MOVIE"] != "0" {
            let spans = docs.map { ($0.0, $0.1, $0.0.kind.lengthMS) }
            let total = spans.reduce(0) { $0 + $1.2 }
            let frame: @Sendable (Int) -> CGImage? = { ms in
                var start = 0
                for (preset, doc, length) in spans {
                    if ms < start + length {
                        guard let image = DocumentRenderer().render(doc.drawn(atTimeMS: ms - start), store: store)
                        else { return nil }
                        return TitleMoreStylesCalmReelTests.labelled(image, preset.name)
                    }
                    start += length
                }
                return nil
            }
            let mp4 = root.appendingPathComponent("reel.mp4")
            let plan = DocumentVideoExport.plan(durationMS: total, canvasSize: Self.canvas, format: .mp4,
                                                quality: .high, size: .p720)
            try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: mp4, frames: frame)
            print("[redesign] reel \(mp4.path)")
        }

        // Old beside new, when the old has been filmed.
        let before = root.appendingPathComponent("before")
        guard FileManager.default.fileExists(atPath: before.path) else { return }
        var rows: [(String, [CGImage])] = []
        for preset in Self.five {
            for (side, folder) in [("old", before), ("new", directory)] {
                let frames = Self.moments.compactMap { ms in
                    TitleMoreStylesCalmReelTests.load(folder.appendingPathComponent("\(preset.rawValue)-\(ms).png"))
                }
                rows.append(("\(side == "old" ? "Old" : preset.name)", frames))
            }
        }
        let sheet = try #require(Self.sheet(rows))
        try TitleMoreStylesCalmReelTests.write(sheet, to: root.appendingPathComponent("old-new-contact.png"))
        print("[redesign] sheet \(root.appendingPathComponent("old-new-contact.png").path)")
    }

    static func sheet(_ rows: [(String, [CGImage])], thumb: CGSize = CGSize(width: 288, height: 162)) -> CGImage? {
        let label: CGFloat = 230, gap: CGFloat = 6, header: CGFloat = 40, pairGap: CGFloat = 14
        let width = Int(label + (thumb.width + gap) * CGFloat(moments.count) + gap)
        let pairs = rows.count / 2
        let height = Int(header + ((thumb.height + gap) * 2 + pairGap) * CGFloat(pairs) + gap)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.09, green: 0.1, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let white = CGColor(gray: 1, alpha: 1), dim = CGColor(gray: 0.6, alpha: 1)
        for (column, ms) in moments.enumerated() {
            let title = column == moments.count - 1 ? "holding" : "\(ms) ms"
            DepthReelStudyTests.draw(title, at: CGPoint(x: label + gap + CGFloat(column) * (thumb.width + gap),
                                                        y: CGFloat(height) - 28),
                                     size: 15, in: context, colour: dim)
        }
        var y = CGFloat(height) - header
        for (row, entry) in rows.enumerated() {
            if row > 0, row % 2 == 0 { y -= pairGap }
            y -= thumb.height + gap
            DepthReelStudyTests.draw(entry.0, at: CGPoint(x: 12, y: y + thumb.height / 2 - 6), size: 15,
                                     in: context, colour: row % 2 == 0 ? dim : white)
            for (column, image) in entry.1.enumerated() {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: label + gap + CGFloat(column) * (thumb.width + gap), y: y,
                                               width: thumb.width, height: thumb.height))
            }
        }
        return context.makeImage()
    }
}
