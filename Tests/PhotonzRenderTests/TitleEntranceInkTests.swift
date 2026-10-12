import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Every built-in title's headline visibly comes in and goes off (task
/// `title-text-visibly-comes-in-and-every-built-in-t`).
///
/// The user, 2026-10-11: "The text itself doesn't even move in." Measured,
/// every headline was nowhere on its first frame and fully in a third of a
/// second later: ins of half a second on Ease out expo, which is nine tenths of
/// the way home a third of the way through, moving words twelve points. Nobody
/// sees an entrance that is over before the eye finds it.
///
/// So the bar is measured on the real renderer, as ink: of the headline's
/// pixels once it has arrived, how much is already there, in place, at a
/// moment (the frame with the headline less the frame without it, each pixel
/// counted up to what it holds once arrived). Words faded, blurred, still
/// travelling, still behind their mask or not yet typed all count short.
///
/// - On the title's first frame, under a tenth.
/// - Half way through the headline's in, between a fifth and four fifths.
/// - Never all there before 400 ms.
/// - The same on the way off: under a tenth on the last frame, between a
///   fifth and four fifths half way through its out, and already leaving
///   400 ms before the end.
@Suite("Every built-in title's headline visibly comes in and goes off")
struct TitleEntranceInkTests {

    static let canvas = CGSize(width: 1280, height: 720)
    /// Where the title lands on the recording.
    static let at = 1000

    /// A ten second dark recording with `preset` placed at `at`, as the app
    /// places it (motion blur on, Normal energy).
    static func placed(_ preset: BuiltInTitle) throws -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        var clip = Layer(name: "Recording",
                         content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#20242C")),
                         frame: CGRect(origin: .zero, size: canvas))
        clip.time = LayerTime(inMS: 0, outMS: 10_000, sourceInMS: 0, sourceLengthMS: 10_000)
        doc.layers = [clip]
        doc.durationMS = 10_000
        let placed = doc.insertTitle(preset, atTimeMS: at, motionBlur: true)
        let id = try #require(placed, "\(preset.name)").layerID
        // A suite run measures words by the model's estimate, a little short
        // for a tall face like Avenir Next, and a box shorter than its line
        // draws nothing. Each box is given the height the real type needs,
        // here and not for the whole run (`TitleSetFramesTests` says why).
        for words in try #require(doc.layer(id: id)).selfAndDescendants {
            guard let text = words.text else { continue }
            let needed = TextRasterizer.naturalSize(text, maxWidth: .greatestFiniteMagnitude)
            let short = TextMeasurement.size(of: text).height < needed.height
            doc.updateLayer(id: words.id) { box in
                box.frame.size.width = max(box.frame.width, needed.width.rounded(.up))
                box.frame.size.height = max(box.frame.height, needed.height.rounded(.up))
                // A slow push magnifies the words and fits their box again by
                // the same short estimate, so where the estimate is short the
                // hold's two percent is left out of the measuring: it is not
                // what this bar is about, and the app measures for real.
                if short { box.motions = box.motions?.filter { $0.property != .scale } }
            }
        }
        return (doc, id)
    }

    /// The part whose ink is measured: the headline, or the group drawing it
    /// where its words are filled by something above them.
    static func headline(_ preset: BuiltInTitle) -> TitlePart? {
        preset.design.parts.first { $0.path == "Headline" } ?? preset.design.parts.first { $0.role == .headline }
    }

    /// Measures one placed title's headline.
    struct Meter {
        let doc: PhotonzDocument
        let without: PhotonzDocument
        let start: Int
        let store = ImageStore()
        var held: [Int] = []

        init(_ doc: PhotonzDocument, title id: UUID, headline path: String) throws {
            self.doc = doc
            let group = try #require(doc.layer(id: id))
            let piece = try #require(TitleDesign.find(path, in: group), "no \(path)")
            var bare = doc
            bare.updateLayer(id: piece.id) { $0.isVisible = false }
            without = bare
            start = try #require(group.time).inMS
        }

        /// The headline's ink at `ms` into the title, pixel by pixel.
        func ink(_ ms: Int) -> [Int] {
            guard let with = DocumentRenderer().render(doc.drawn(atTimeMS: start + ms), store: store),
                  let bare = DocumentRenderer().render(without.drawn(atTimeMS: start + ms), store: store),
                  let a = TitleEntranceInkTests.pixels(with), let b = TitleEntranceInkTests.pixels(bare)
            else { return [] }
            return stride(from: 0, to: a.count, by: 4).map { i in
                (0..<3).map { abs(Int(a[i + $0]) - Int(b[i + $0])) }.max() ?? 0
            }
        }

        /// How much of `held` is there at `ms`, as a share.
        func share(_ ms: Int) -> Double {
            let now = ink(ms)
            let total = held.reduce(0, +)
            guard total > 0, now.count == held.count else { return 0 }
            return Double(zip(now, held).reduce(0) { $0 + min($1.0, $1.1) }) / Double(total)
        }
    }

    /// The headline's in and out, as spans of the title: from the design the
    /// title was compiled from, its stagger across however many pieces its
    /// words split into.
    static func spans(_ doc: PhotonzDocument, _ id: UUID, _ part: TitlePart) throws
        -> (in: ClosedRange<Int>, out: ClosedRange<Int>) {
        let group = try #require(doc.layer(id: id))
        let length = try #require(group.time).lengthMS
        let design = try #require(doc.titleRecipe(layerID: id)).compiled
        let compiled = try #require(design.parts.first { $0.path == part.path })
        let entrance = try #require(compiled.in, "\(part.path) has no in")
        var inEnd = entrance.delayMS + entrance.lengthMS
        // Words coming in a piece at a time have arrived when the last has.
        let piece = try #require(TitleDesign.find(part.path, in: group))
        for words in piece.selfAndDescendants {
            if let text = words.text, let reveal = text.reveal {
                let count = TextReveal.spans(in: text.string, unit: reveal.unit)?.count
                    ?? max(1, text.string.split(whereSeparator: \.isNewline).count)
                inEnd = max(inEnd, reveal.startMS - group.time!.sourceInMS + reveal.lengthMS(count: count))
            }
        }
        let exit = compiled.out ?? TitleBuild(.fade, delayMS: 0, lengthMS: TitleAnimation.lengthMS)
        return (entrance.delayMS...inEnd,
                (length - exit.delayMS - exit.lengthMS)...(length - exit.delayMS))
    }

    @Test("Every headline is nowhere on its first frame, part way in half way through its in, and all there no earlier than 400 ms; the same going off",
          arguments: BuiltInTitle.shelved)
    func headlineVisiblyArrivesAndLeaves(_ preset: BuiltInTitle) throws {
        let part = try #require(Self.headline(preset), "\(preset.name) has no headline")
        let (doc, id) = try Self.placed(preset)
        var meter = try Meter(doc, title: id, headline: part.path)
        let (entrance, exit) = try Self.spans(doc, id, part)
        let length = try #require(doc.layer(id: id)?.time).lengthMS
        // Arrived and not yet leaving: the reference every other frame is
        // measured against.
        meter.held = meter.ink(entrance.upperBound + 40)
        #expect(meter.held.reduce(0, +) > 0, "\(preset.name) draws no headline")

        if ProcessInfo.processInfo.environment["PHOTONZ_INK_PRINT"] == "1" {
            let moments = [0, 100, 200, 300, 400, 600, 800, 1000, 1200, length - 600, length - 400, length - 200]
            print("[ink] \(preset.name) in \(entrance) out \(exit): "
                  + moments.map { "\($0)=\(Self.percent(meter.share($0)))" }.joined(separator: " "))
        }
        let first = meter.share(0)
        #expect(first < 0.1, "\(preset.name): \(Self.percent(first)) of the headline on its first frame")
        let middle = (entrance.lowerBound + entrance.upperBound) / 2
        let half = meter.share(middle)
        #expect((0.2...0.8).contains(half),
                "\(preset.name): \(Self.percent(half)) half way through its in (\(middle) ms of \(entrance))")
        for ms in stride(from: 0, to: 400, by: 50) {
            let early = meter.share(ms)
            #expect(early < 0.97, "\(preset.name): \(Self.percent(early)) already at \(ms) ms")
        }
        #expect(entrance.upperBound >= 400, "\(preset.name)'s headline is in by \(entrance.upperBound) ms")

        let last = meter.share(length - 1)
        #expect(last < 0.1, "\(preset.name): \(Self.percent(last)) of the headline on its last frame")
        let leaving = (exit.lowerBound + exit.upperBound) / 2
        let halfOff = meter.share(leaving)
        #expect((0.2...0.8).contains(halfOff),
                "\(preset.name): \(Self.percent(halfOff)) half way through its out (\(leaving) ms of \(exit))")
        let going = meter.share(length - 400)
        #expect(going < 0.97, "\(preset.name): \(Self.percent(going)) still there 400 ms before the end")
    }

    static func percent(_ share: Double) -> String { String(format: "%.0f%%", share * 100) }

    /// The frame at a quarter of 1280 by 720: fine enough that words a few
    /// points from home, or soft, count short.
    static func pixels(_ image: CGImage) -> [UInt8]? {
        let width = 320, height = 180
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }
}

