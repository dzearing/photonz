import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Motion blur on titles that move fast, as drawn (task
/// `motion-blur-on-titles-that-move-fast`).
///
/// Written before the renderer. A part under a motion blur that moved while
/// the shutter was open is drawn as the average of its own picture over the
/// places it was: smeared along the way it went and nowhere else. A part
/// holding still is drawn exactly as it is without motion blur.
@Suite("Motion blur, as drawn", .serialized)
struct MotionBlurRenderTests {

    static let canvas = CGSize(width: 1920, height: 1080)

    static func backdrop() -> Layer {
        var back = Layer(name: "Back", content: .annotation(AnnotationContent(
            shape: .rectangle, strokeWidth: 0, colorHex: "#101318",
            start: .zero, end: CGPoint(x: canvas.width, y: canvas.height), fillColorHex: "#101318")),
            frame: CGRect(origin: .zero, size: canvas))
        back.time = LayerTime(inMS: 0, outMS: 4_000)
        return back
    }

    /// A white box 200pt square sliding 1600pt right between 1000ms and
    /// 1500ms, in a straight line: 3.2pt a millisecond.
    static func slide(_ blur: MotionBlurEffect?) -> PhotonzDocument {
        var box = Layer(name: "Box", content: .annotation(AnnotationContent(
            shape: .rectangle, strokeWidth: 0, colorHex: "#FFFFFF",
            start: .zero, end: CGPoint(x: 200, y: 200), fillColorHex: "#FFFFFF")),
            frame: CGRect(x: 0, y: 400, width: 200, height: 200))
        box.time = LayerTime(inMS: 0, outMS: 4_000)
        box.motions = [LayerMotion(property: .position, from: .point(CGPoint(x: 0, y: 400)),
                                   to: .point(CGPoint(x: 1600, y: 400)),
                                   timing: MotionTiming(startMS: 1_000, durationMS: 500),
                                   curve: .linear, repeats: .once)]
        if let blur { box.style.effects = [.motionBlur(blur)] }
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.layers = [backdrop(), box]
        doc.durationMS = 4_000
        return doc
    }

    /// A twelve word headline rising in a word at a time, under a title's
    /// motion blur or not.
    static func headline(_ blur: MotionBlurEffect?) -> PhotonzDocument {
        var text = TextContent(string: TextRevealRenderTests.headline, fontSize: 96, colorHex: "#FFFFFF",
                               weight: .bold)
        text.reveal = TextReveal(style: .riseAndFade, unit: .word, amount: 120, curve: .easeOutExpo)
        let words = Layer(name: "Headline", content: .text(text),
                          frame: CGRect(x: 120, y: 330, width: 1680, height: 420))
        var title = Layer(name: "Title", content: .group(GroupContent(children: [words])),
                          frame: CGRect(origin: .zero, size: .zero))
        title.time = LayerTime(inMS: 1_000, outMS: 4_000)
        if let blur { title.style.effects = [.motionBlur(blur)] }
        var doc = PhotonzDocument(canvasSize: canvas)
        doc.layers = [backdrop(), title]
        doc.durationMS = 4_000
        return doc
    }

    static func render(_ doc: PhotonzDocument, atMS ms: Int, with renderer: DocumentRenderer = DocumentRenderer())
        -> CGImage? {
        renderer.render(doc.drawn(atTimeMS: ms), store: ImageStore())
    }

    /// The grey level along one row of the picture, top-left counted.
    static func row(_ image: CGImage, y: Int) -> [UInt8] {
        let bytes = TextRevealRenderTests.bytes(image)
        return (0..<image.width).map { bytes[(y * image.width + $0) * 4] }
    }

    /// The grey level down one column.
    static func column(_ image: CGImage, x: Int) -> [UInt8] {
        let bytes = TextRevealRenderTests.bytes(image)
        return (0..<image.height).map { bytes[($0 * image.width + x) * 4] }
    }

    /// How many pixels are neither the backdrop nor the box: the soft part.
    static func soft(_ line: [UInt8]) -> Int {
        line.filter { $0 > 40 && $0 < 230 }.count
    }

    @Test("Mid slide, the box is smeared along the way it goes and its top and bottom stay hard")
    func midSlideIsSmearedAlongTheWay() throws {
        let sharp = try #require(Self.render(Self.slide(nil), atMS: 1_250))
        let blurred = try #require(Self.render(Self.slide(MotionBlurEffect()), atMS: 1_250))
        // Across the box: hard edges plain, about 53pt of ramp at each end
        // blurred (3.2pt a millisecond for 16.5ms).
        let plainRow = Self.row(sharp, y: 500), blurRow = Self.row(blurred, y: 500)
        #expect(Self.soft(plainRow) <= 4, "plain \(Self.soft(plainRow))")
        #expect(Self.soft(blurRow) > 70, "blurred \(Self.soft(blurRow))")
        // The same light, spread out, never more or less of it: counted as
        // light, since the copies are averaged as light rather than as the
        // numbers a picture file stores.
        func light(_ line: [UInt8]) -> Double {
            line.reduce(0) { sum, value in
                let v = Double(value) / 255
                return sum + (v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4))
            }
        }
        let plainInk = light(plainRow), blurInk = light(blurRow)
        #expect(abs(plainInk - blurInk) < plainInk / 50, "\(plainInk) then \(blurInk)")
        // Down the middle of the box it is still a hard-edged 200pt band.
        let down = Self.column(blurred, x: 900)
        #expect(Self.soft(down) <= 4, "down \(Self.soft(down))")
    }

    @Test("Held still, a part is pixel for pixel the same with motion blur on and off")
    func heldFramesAreIdentical() throws {
        for ms in [500, 2_000] {
            let sharp = try #require(Self.render(Self.slide(nil), atMS: ms))
            let blurred = try #require(Self.render(Self.slide(MotionBlurEffect(shutterAngle: 360)), atMS: ms))
            #expect(TextRevealRenderTests.bytes(sharp) == TextRevealRenderTests.bytes(blurred), "at \(ms)")
        }
        // ...and a title whose words are all home.
        let home = try #require(Self.render(Self.headline(nil), atMS: 3_500))
        let homeBlurred = try #require(Self.render(Self.headline(MotionBlurEffect()), atMS: 3_500))
        #expect(TextRevealRenderTests.bytes(home) == TextRevealRenderTests.bytes(homeBlurred))
    }

    @Test("Words rising in one at a time are each smeared up and down, not across")
    func revealPiecesAreSmeared() throws {
        let sharp = try #require(Self.render(Self.headline(nil), atMS: 1_150))
        let blurred = try #require(Self.render(Self.headline(MotionBlurEffect(shutterAngle: 360)), atMS: 1_150))
        #expect(TextRevealRenderTests.bytes(sharp) != TextRevealRenderTests.bytes(blurred))
        // Down the first word's middle the ramp is longer with the smear.
        var plainSoft = 0, blurSoft = 0
        for x in stride(from: 140, to: 400, by: 4) {
            plainSoft += Self.soft(Self.column(sharp, x: x))
            blurSoft += Self.soft(Self.column(blurred, x: x))
        }
        #expect(blurSoft > plainSoft + plainSoft / 4, "\(plainSoft) then \(blurSoft)")
    }

    /// Playback runs every frame in order through one renderer; a scrub jumps
    /// about through another; an export makes a fresh one. All three agree.
    @Test("Playback, scrubbing and export draw the same smear at three moments")
    func playbackScrubExportAgree() throws {
        let doc = Self.headline(MotionBlurEffect())
        var slide = Self.slide(MotionBlurEffect())
        slide.layers.append(contentsOf: doc.layers.dropFirst())
        let moments = [1_080, 1_240, 1_400]
        let playback = DocumentRenderer()
        var played: [Int: [UInt8]] = [:]
        for ms in stride(from: 1_000, through: 1_480, by: 40) {
            let image = try #require(Self.render(slide, atMS: ms, with: playback))
            if moments.contains(ms) { played[ms] = TextRevealRenderTests.bytes(image) }
        }
        let scrub = DocumentRenderer()
        for ms in moments.reversed() + [1_300, 1_040] {
            _ = Self.render(slide, atMS: ms, with: scrub)
        }
        for ms in moments {
            let scrubbed = try #require(Self.render(slide, atMS: ms, with: scrub))
            let exported = try #require(DocumentRenderer().render(slide.drawn(atTimeMS: ms), store: ImageStore(),
                                                                 scale: 1))
            #expect(played[ms] == TextRevealRenderTests.bytes(scrubbed), "scrub differs at \(ms)")
            #expect(played[ms] == TextRevealRenderTests.bytes(exported), "export differs at \(ms)")
        }
    }

    /// The perf note for the composite path: a word stagger and a full-frame
    /// slide at 1080p, through the canvas's own render.
    @Test("A word stagger and a full-frame slide with motion blur draw inside a frame at 1080p")
    func insideAFrame() throws {
        let store = ImageStore()
        var report: [String] = []
        // A whole 1920x1080 panel sliding in from the left on an expo ease.
        var panel = Layer(name: "Panel", content: .annotation(AnnotationContent(
            shape: .rectangle, strokeWidth: 0, colorHex: "#3A6FF7",
            start: .zero, end: CGPoint(x: Self.canvas.width, y: Self.canvas.height), fillColorHex: "#3A6FF7")),
            frame: CGRect(origin: .zero, size: Self.canvas))
        panel.time = LayerTime(inMS: 0, outMS: 4_000)
        panel.motions = [LayerMotion(property: .position, from: .point(CGPoint(x: -1920, y: 0)),
                                     to: .point(.zero), timing: MotionTiming(startMS: 1_000, durationMS: 600),
                                     curve: .easeOutExpo, repeats: .once)]
        func fullFrame(_ blur: MotionBlurEffect?) -> PhotonzDocument {
            var doc = PhotonzDocument(canvasSize: Self.canvas)
            var moving = panel
            if let blur { moving.style.effects = [.motionBlur(blur)] }
            doc.layers = [Self.backdrop(), moving]
            doc.durationMS = 4_000
            return doc
        }
        let cases: [(String, PhotonzDocument)] = [
            ("word stagger, plain", Self.headline(nil)),
            ("word stagger, 180", Self.headline(MotionBlurEffect())),
            ("word stagger, 360", Self.headline(MotionBlurEffect(shutterAngle: 360))),
            ("full-frame slide, plain", fullFrame(nil)),
            ("full-frame slide, 180", fullFrame(MotionBlurEffect())),
            ("full-frame slide, 360", fullFrame(MotionBlurEffect(shutterAngle: 360))),
        ]
        for (name, doc) in cases {
            let renderer = DocumentRenderer()
            _ = renderer.renderInteractive(doc.drawn(atTimeMS: 1_000), store: store)
            var samples: [Double] = []
            for ms in stride(from: 1_016, to: 1_900, by: 16) {
                let began = ContinuousClock.now
                let shown = doc.drawn(atTimeMS: ms)
                _ = renderer.renderInteractive(shown, store: store)
                let took = ContinuousClock.now - began
                samples.append(Double(took.components.attoseconds) / 1e15 + Double(took.components.seconds) * 1000)
            }
            let median = samples.sorted()[samples.count / 2]
            let worst = samples.max() ?? 0
            report.append(String(format: "%@: median %.1fms, worst %.1fms over %d frames",
                                 name, median, worst, samples.count))
            #expect(median < 16, "\(name) median \(median)ms")
        }
        print("[perf] motion blur at 1920x1080 (drawn + renderInteractive):\n  " + report.joined(separator: "\n  "))
    }
}
