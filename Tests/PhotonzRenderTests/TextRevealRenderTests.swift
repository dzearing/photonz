import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Title text comes in by line, word or letter, as drawn (task
/// `title-text-comes-in-by-line-word-or-letter`).
///
/// Written before the renderer. A text mid-reveal is drawn from each piece's
/// own picture, kept until the words change; once the last piece is home it
/// is the ordinary picture again, pixel for pixel.
@Suite("Text comes in a piece at a time, as drawn", .serialized)
struct TextRevealRenderTests {

    static let canvas = CGSize(width: 1920, height: 1080)
    static let headline = "Ship faster with every single release this year and beyond for real"

    /// A dark frame with one white headline placed from 1s, revealing as asked.
    static func document(_ reveal: TextReveal?, string: String = headline,
                         box: CGRect = CGRect(x: 120, y: 330, width: 1680, height: 420)) -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: canvas)
        var back = Layer(name: "Back", content: .annotation(AnnotationContent(
            shape: .rectangle, strokeWidth: 0, colorHex: "#101318",
            start: .zero, end: CGPoint(x: canvas.width, y: canvas.height))),
            frame: CGRect(origin: .zero, size: canvas))
        back.time = LayerTime(inMS: 0, outMS: 8_000, sourceInMS: 0, sourceLengthMS: 8_000)
        var text = TextContent(string: string, fontSize: 96, colorHex: "#FFFFFF", weight: .bold)
        text.reveal = reveal
        var words = Layer(name: "Headline", content: .text(text), frame: box)
        words.time = LayerTime(inMS: 1_000, outMS: 7_000)
        doc.layers = [back, words]
        doc.durationMS = 8_000
        return (doc, words.id)
    }

    static func render(_ doc: PhotonzDocument, atMS ms: Int, with renderer: DocumentRenderer = DocumentRenderer())
        -> CGImage? {
        renderer.render(doc.drawn(atTimeMS: ms), store: ImageStore())
    }

    /// RGBA bytes of an image, drawn into a known layout.
    static func bytes(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    /// How many bright pixels a stretch of the frame holds, top-left counted.
    static func ink(_ image: CGImage, in rect: CGRect) -> Int {
        let data = bytes(image)
        var count = 0
        let w = image.width
        for y in Int(rect.minY)..<min(Int(rect.maxY), image.height) {
            for x in Int(rect.minX)..<min(Int(rect.maxX), w) {
                let i = (y * w + x) * 4
                if data[i] > 128, data[i + 1] > 128 { count += 1 }
            }
        }
        return count
    }

    @Test("By word with a mask reveal: the first word is in while the last has not started")
    func midRevealByWord() throws {
        var reveal = TextReveal(style: .maskReveal, unit: .word, staggerMS: 200, lengthMS: 300, curve: .linear)
        reveal.startMS = 0
        let (doc, _) = Self.document(reveal, string: "One two three four",
                                     box: CGRect(x: 120, y: 380, width: 1680, height: 140))
        // 410ms in: word one is home, word two is nearly up, word three
        // (400ms) has barely started and word four (600ms) has not.
        let frame = try #require(Self.render(doc, atMS: 1_410))
        let plain = try #require(Self.render(Self.document(nil, string: "One two three four",
                                                           box: CGRect(x: 120, y: 380, width: 1680, height: 140)).0,
                                             atMS: 1_410))
        let first = CGRect(x: 120, y: 380, width: 200, height: 140)
        let last = CGRect(x: 640, y: 380, width: 1_160, height: 140)
        print("[reveal] first \(Self.ink(frame, in: first)) of \(Self.ink(plain, in: first)), "
              + "last \(Self.ink(frame, in: last)) of \(Self.ink(plain, in: last))")
        #expect(Self.ink(frame, in: first) > Self.ink(plain, in: first) * 9 / 10)
        #expect(Self.ink(plain, in: last) > 500)
        #expect(Self.ink(frame, in: last) < Self.ink(plain, in: last) / 3)
        // Nothing of a word still sliding up shows below its own line.
        let below = CGRect(x: 120, y: 520, width: 1680, height: 120)
        #expect(Self.ink(frame, in: below) == 0)
    }

    @Test("Before its first beat nothing is drawn, and once home it is the plain text exactly")
    func startsEmptyEndsExact() throws {
        for style in TextRevealStyle.allCases {
            var reveal = TextReveal(style: style, unit: .letter)
            reveal.startMS = 0
            let (doc, _) = Self.document(reveal)
            let before = try #require(Self.render(doc, atMS: 1_000))
            let words = CGRect(x: 120, y: 330, width: 1680, height: 420)
            // A typewriter's first letter IS its first beat.
            if style != .typewriter {
                #expect(Self.ink(before, in: words) == 0, "\(style.title) shows something before it starts")
            }
            let count = try #require(TextReveal.spans(in: Self.headline, unit: .letter)).count
            let home = 1_000 + reveal.lengthMS(count: count)
            let settled = try #require(Self.render(doc, atMS: home))
            let plain = try #require(Self.render(Self.document(nil).0, atMS: home))
            #expect(Self.bytes(settled) == Self.bytes(plain), "\(style.title) is not the plain text once home")
        }
    }

    @Test("Every behaviour draws something partway through, by every unit")
    func partwayDrawsSomething() throws {
        for style in TextRevealStyle.allCases {
            for unit in TextRevealUnit.allCases {
                var reveal = TextReveal(style: style, unit: unit)
                reveal.startMS = 0
                let (doc, _) = Self.document(reveal)
                let frame = try #require(Self.render(doc, atMS: 1_000 + reveal.lengthMS + 10))
                #expect(Self.ink(frame, in: CGRect(x: 120, y: 330, width: 1680, height: 420)) > 200,
                        "\(style.title) by \(unit.title)")
            }
        }
    }

    @Test("Right-to-left words and emoji come in by letter and land exactly as drawn")
    func rightToLeftAndEmoji() throws {
        let string = "שלום עולם 👋🏽 hello"
        var reveal = TextReveal(style: .riseAndFade, unit: .letter)
        reveal.startMS = 0
        let (doc, _) = Self.document(reveal, string: string)
        let partway = try #require(Self.render(doc, atMS: 1_200))
        let plain = try #require(Self.render(Self.document(nil, string: string).0, atMS: 1_200))
        let words = CGRect(x: 120, y: 330, width: 1680, height: 420)
        #expect(Self.ink(partway, in: words) > 0)
        #expect(Self.ink(partway, in: words) < Self.ink(plain, in: words))
        let count = try #require(TextReveal.spans(in: string, unit: .letter)).count
        #expect(count == 14)
        let settled = try #require(Self.render(doc, atMS: 1_000 + reveal.lengthMS(count: count)))
        #expect(Self.bytes(settled) == Self.bytes(plain))
    }

    @Test("Editing the words mid-reveal lays them out again and the reveal carries on")
    func editingRelaysOut() throws {
        var reveal = TextReveal(style: .riseAndFade, unit: .word)
        reveal.startMS = 0
        var (doc, id) = Self.document(reveal, string: "Short")
        let renderer = DocumentRenderer()
        let before = try #require(Self.render(doc, atMS: 1_100, with: renderer))
        doc.updateLayer(id: id) {
            guard case .text(var text) = $0.content else { return }
            text.string = "Short and now a good deal longer"
            $0.content = .text(text)
        }
        let after = try #require(Self.render(doc, atMS: 1_400, with: renderer))
        let tail = CGRect(x: 700, y: 330, width: 1100, height: 420)
        #expect(Self.ink(before, in: tail) == 0)
        #expect(Self.ink(after, in: tail) > 0)
    }

    /// Playback runs every frame in order through one renderer; a scrub jumps
    /// about through another; an export makes a fresh one. All three agree.
    @Test("Playback, scrubbing and export draw the same frame at three moments")
    func playbackScrubExportAgree() throws {
        var reveal = TextReveal(style: .blurIn, unit: .word)
        reveal.startMS = 0
        let (doc, _) = Self.document(reveal)
        let moments = [1_120, 1_400, 1_760]
        let playback = DocumentRenderer()
        var played: [Int: [UInt8]] = [:]
        for ms in stride(from: 1_000, through: 1_800, by: 40) {
            let image = try #require(Self.render(doc, atMS: ms, with: playback))
            if moments.contains(ms) { played[ms] = Self.bytes(image) }
        }
        let scrub = DocumentRenderer()
        for ms in moments.reversed() + [1_600, 1_050] {
            _ = Self.render(doc, atMS: ms, with: scrub)
        }
        for ms in moments {
            let scrubbed = try #require(Self.render(doc, atMS: ms, with: scrub))
            let exported = try #require(DocumentRenderer().render(doc.drawn(atTimeMS: ms), store: ImageStore(),
                                                                 scale: 1))
            #expect(played[ms] == Self.bytes(scrubbed), "scrub differs at \(ms)")
            #expect(played[ms] == Self.bytes(exported), "export differs at \(ms)")
        }
    }

    /// The perf note for the composite path: a twelve word headline revealing
    /// by letter on a 1080p frame, through the canvas's own render.
    @Test("A twelve word headline revealing by letter at 1080p draws inside a frame")
    func twelveWordsByLetterInsideAFrame() throws {
        #expect(Self.headline.split(separator: " ").count == 12)
        let store = ImageStore()
        var report: [String] = []
        for style in [TextRevealStyle.riseAndFade, .blurIn, .maskReveal] {
            var reveal = TextReveal(style: style, unit: .letter)
            reveal.startMS = 0
            let (doc, _) = Self.document(reveal)
            let renderer = DocumentRenderer()
            let count = try #require(TextReveal.spans(in: Self.headline, unit: .letter)).count
            // The first frame lays the words out and draws every piece once.
            let laidOut = ContinuousClock.now
            _ = renderer.renderInteractive(doc.drawn(atTimeMS: 1_000), store: store)
            let layout = ContinuousClock.now - laidOut
            var samples: [Double] = []
            let length = reveal.lengthMS(count: count)
            for ms in stride(from: 1_016, to: 1_000 + length, by: 16) {
                let shown = doc.drawn(atTimeMS: ms)
                let began = ContinuousClock.now
                _ = renderer.renderInteractive(shown, store: store)
                let took = ContinuousClock.now - began
                samples.append(Double(took.components.attoseconds) / 1e15 + Double(took.components.seconds) * 1000)
            }
            let median = samples.sorted()[samples.count / 2]
            let worst = samples.max() ?? 0
            let first = Double(layout.components.attoseconds) / 1e15 + Double(layout.components.seconds) * 1000
            report.append(String(format: "%@: %d letters, first frame %.1fms, median %.1fms, worst %.1fms over %d frames",
                                 style.title, count, first, median, worst, samples.count))
            #expect(median < 16, "\(style.title) median \(median)ms")
        }
        print("[perf] 12 word headline by letter, 1920x1080:\n  " + report.joined(separator: "\n  "))
    }
}
