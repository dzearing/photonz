import CoreGraphics
import CoreText
import Foundation
import ImageIO
import PhotonzCore
@testable import PhotonzMedia
@testable import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The older title set, before and after it was toned down (task
/// `the-existing-title-pages-are-toned-down-to-calm`).
///
/// The user, 2026-10-18, after the Apple-level pages landed: "The existing
/// title pages are far too busy so i think we need to audit them and tone them
/// down." This films each of the twelve as the app inserts it, measures how
/// much its background moves while it holds (the mean difference of two frames
/// half a second apart, 0 to 255, with only the background showing), how much
/// the whole frame moves, and the busyness of its design (travel, effects per
/// part, springs and turns in depth, glows, grain, colours, type contrast,
/// timing), and writes the frames of a contact sheet and a reel.
///
/// Run once as `before` on the old designs and once as `after`; the after run
/// lays the two side by side when the before frames are there.
///
///     PHOTONZ_REEL=1 PHOTONZ_CALM_PHASE=before PHOTONZ_CALM_DIR=/tmp/calm \
///         Scripts/test.sh --filter TitleMoreStylesCalmReel
///
/// Not part of the suite: it writes the files the audit carries. The bar it
/// measures is held in the suite by `TitleMoreStylesCalmTests`.
@Suite("The older title set, toned down: before and after", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_REEL"] == "1"))
struct TitleMoreStylesCalmReelTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let set = BuiltInTitle.shelved.filter { !$0.isCalm }
    /// The frames the sheet shows, in ms from the title's start.
    static let moments = [0, 150, 300, 500, 800, 1200, 2000]
    /// Two frames of the hold, half a second apart.
    static let hold = (2000, 2500)

    static var fixtures: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Scripts/playtest/fixtures")
    }

    static func picture(_ name: String) throws -> CGImage {
        let url = fixtures.appendingPathComponent(name)
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "\(name)")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// `preset` placed at the start of a ten second recording of `footage`.
    static func titled(_ preset: BuiltInTitle, over footage: CGImage, store: ImageStore) throws
        -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording", content: .image(store.register(footage)),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let landed = doc.insertTitle(preset, atTimeMS: 0, motionBlur: true)
        return (doc, try #require(landed, "\(preset.name)").layerID)
    }

    /// The same document with nothing of the title showing but its background.
    static func backgroundOnly(_ doc: PhotonzDocument, _ id: UUID) throws -> PhotonzDocument {
        var bare = doc
        let group = try #require(doc.layer(id: id))
        for piece in group.children where !["Background", "Shade"].contains(piece.name) {
            bare.updateLayer(id: piece.id) { $0.isVisible = false }
        }
        return bare
    }

    static func pixels(_ image: CGImage, width: Int = 960, height: Int = 540) -> [UInt8] {
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

    /// Mean difference of the colour channels, 0 to 255.
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

    // MARK: - How busy a design is, read off the model

    struct Busyness: Codable {
        var name: String
        var bgMotion: Double = 0
        var frameMotion: Double = 0
        var liveSpeed: Double?
        var liveStrength: Double?
        var maxEffectsPerPart = 0
        var maxRise: Double = 0
        var maxScaleOff: Double = 0
        var maxTrack: Double = 0
        var springsAndTurns: [String] = []
        var glows: [String] = []
        var grain: [Double] = []
        var colours: [String] = []
        var typeRatio: Double = 0
        var longestInMS = 0
        var outsMS: [Int] = []
        var inCurves: [String] = []
        var holds: [String] = []
        var entrance = ""
    }

    static func saturated(_ hex: String) -> Bool {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count >= 6, let value = UInt32(digits.prefix(6), radix: 16) else { return false }
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b)
        return high > 0.25 && (high - low) / high > 0.3
    }

    static func busyness(_ preset: BuiltInTitle) -> Busyness {
        var report = Busyness(name: preset.name)
        let design = preset.design
        for part in design.parts {
            if let build = part.in {
                var count = build.kind == .fade ? 0 : 1
                if build.blur != nil { count += 1 }
                if build.scale != nil { count += 1 }
                if part.hold.kind != .none { count += 1 }
                report.maxEffectsPerPart = max(report.maxEffectsPerPart, count)
                report.longestInMS = max(report.longestInMS, build.lengthMS)
                report.inCurves.append("\(part.path) \(build.kind.rawValue) \(build.curve)")
                if part.role == .headline || part.path == "Headline" {
                    report.entrance += "\(build.kind.rawValue)/\((build.unit ?? build.kind.defaultUnit).rawValue) "
                }
            } else if part.hold.kind != .none {
                report.maxEffectsPerPart = max(report.maxEffectsPerPart, 1)
            }
            if let out = part.out { report.outsMS.append(out.lengthMS) }
            if part.hold.kind != .none { report.holds.append("\(part.path) \(part.hold.kind.rawValue) \(part.hold.amount)") }
            for build in [part.in, part.out].compactMap({ $0 }) {
                if build.kind == .rise { report.maxRise = max(report.maxRise, build.amount) }
                if build.kind == .scaleFrom { report.maxScaleOff = max(report.maxScaleOff, abs(build.amount - 100)) }
                if let scale = build.scale { report.maxScaleOff = max(report.maxScaleOff, abs(scale - 100)) }
                if build.kind == .trackIn { report.maxTrack = max(report.maxTrack, build.amount) }
                if build.kind.isInDepth || build.kind == .springPop || build.curve == .easeOutBack {
                    report.springsAndTurns.append("\(part.path) \(build.kind.rawValue) \(build.curve)")
                }
            }
        }
        let layer = preset.layer(in: canvas)
        var colours: Set<String> = []
        var sizes: [Double] = []
        for piece in layer.selfAndDescendants {
            for effect in piece.style.effects {
                if let glow = effect.glow {
                    report.glows.append("\(piece.name) \(glow.colorHex) r\(Int(glow.radius)) \(glow.opacity)")
                }
                if let grain = effect.grain { report.grain.append(grain.amount) }
            }
            if let text = piece.text {
                sizes.append(Double(text.fontSize))
                if saturated(text.colorHex) { colours.insert(text.colorHex.uppercased()) }
            }
            if let fill = piece.annotation?.fill {
                if let live = fill.live, piece.name == "Background" {
                    report.liveSpeed = live.speed
                    report.liveStrength = live.strength
                }
                for hex in [fill.hex] + fill.stops.map(\.hex) where saturated(hex) { colours.insert(hex.uppercased()) }
            }
        }
        report.colours = colours.sorted()
        if let high = sizes.max(), let low = sizes.min(), low > 0 { report.typeRatio = high / low }
        return report
    }

    // MARK: - The run

    @Test("Measure and film the older set")
    func film() async throws {
        TextMeasurement.use { text, maxWidth in TextRasterizer.naturalSize(text, maxWidth: maxWidth) }
        let environment = ProcessInfo.processInfo.environment
        let phase = environment["PHOTONZ_CALM_PHASE"] ?? "after"
        let root = URL(fileURLWithPath: environment["PHOTONZ_CALM_DIR"] ?? "/tmp/calm")
        let directory = root.appendingPathComponent(phase)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let footage = try Self.picture("Dark artboard with glow 800x500.png")
        let store = ImageStore()
        var reports: [Busyness] = []
        var docs: [(BuiltInTitle, PhotonzDocument)] = []
        for preset in Self.set {
            let (doc, id) = try Self.titled(preset, over: footage, store: store)
            docs.append((preset, doc))
            var report = Self.busyness(preset)
            let bare = try Self.backgroundOnly(doc, id)
            let render = { (d: PhotonzDocument, ms: Int) throws -> CGImage in
                try #require(DocumentRenderer().render(d.drawn(atTimeMS: ms), store: store))
            }
            report.bgMotion = Self.difference(Self.pixels(try render(bare, Self.hold.0)),
                                              Self.pixels(try render(bare, Self.hold.1)))
            report.frameMotion = Self.difference(Self.pixels(try render(doc, Self.hold.0)),
                                                 Self.pixels(try render(doc, Self.hold.1)))
            for ms in Self.moments {
                try Self.write(try render(doc, ms), to: directory.appendingPathComponent("\(preset.rawValue)-\(ms).png"))
            }
            reports.append(report)
            print("[calm-old] \(phase) \(preset.name): bg \(String(format: "%.2f", report.bgMotion)) frame \(String(format: "%.2f", report.frameMotion))")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(reports).write(to: root.appendingPathComponent("\(phase).json"))

        // One reel of the twelve, one after another, each labelled.
        if environment["PHOTONZ_CALM_MOVIE"] != "0" {
            let spans = docs.map { ($0.0, $0.1, $0.0.kind.lengthMS) }
            let total = spans.reduce(0) { $0 + $1.2 }
            let label = phase == "before" ? "Before" : "After"
            let frame: @Sendable (Int) -> CGImage? = { ms in
                var start = 0
                for (preset, doc, length) in spans {
                    if ms < start + length {
                        guard let image = DocumentRenderer().render(doc.drawn(atTimeMS: ms - start), store: store)
                        else { return nil }
                        return Self.labelled(image, "\(label): \(preset.name)")
                    }
                    start += length
                }
                return nil
            }
            let mp4 = root.appendingPathComponent("\(phase).mp4")
            let plan = DocumentVideoExport.plan(durationMS: total, canvasSize: Self.canvas, format: .mp4,
                                                quality: .high, size: .p720)
            try await DocumentMovieWriter.write(plan: plan, mix: [], soundURLs: [:], to: mp4, frames: frame)
            print("[calm-old] reel \(mp4.path)")
        }

        // Before beside after, when both have been filmed.
        let before = root.appendingPathComponent("before")
        if phase == "after", FileManager.default.fileExists(atPath: before.path) {
            var rows: [(String, [CGImage])] = []
            for preset in Self.set {
                for (side, folder) in [("before", before), ("after", directory)] {
                    let frames = Self.moments.compactMap { ms in
                        Self.load(folder.appendingPathComponent("\(preset.rawValue)-\(ms).png"))
                    }
                    rows.append(("\(preset.name), \(side)", frames))
                }
            }
            let sheet = try #require(Self.sheet(rows))
            try Self.write(sheet, to: root.appendingPathComponent("before-after-contact.png"))
            print("[calm-old] sheet \(root.appendingPathComponent("before-after-contact.png").path)")
        }
    }

    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func write(_ image: CGImage, to url: URL) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                                       1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// `image` with `text` in its top left corner on a dark tab.
    static func labelled(_ image: CGImage, _ text: String) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let scale = CGFloat(height) / 1080
        context.setFillColor(CGColor(gray: 0, alpha: 0.6))
        context.fill(CGRect(x: 0, y: CGFloat(height) - 70 * scale, width: 760 * scale, height: 70 * scale))
        DepthReelStudyTests.draw(text, at: CGPoint(x: 24 * scale, y: CGFloat(height) - 48 * scale), size: 34 * scale,
                                 in: context, colour: CGColor(gray: 1, alpha: 1))
        return context.makeImage()
    }

    static func sheet(_ rows: [(String, [CGImage])], thumb: CGSize = CGSize(width: 240, height: 135)) -> CGImage? {
        let label: CGFloat = 230, gap: CGFloat = 6, header: CGFloat = 40, pairGap: CGFloat = 10
        let width = Int(label + (thumb.width + gap) * CGFloat(moments.count) + gap)
        let pairs = rows.count / 2
        let height = Int(header + ((thumb.height + gap) * 2 + pairGap) * CGFloat(pairs) + gap)
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
