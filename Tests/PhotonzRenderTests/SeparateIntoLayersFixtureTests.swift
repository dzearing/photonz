import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Separate into Layers measured against a REAL screenshot, because that is the
/// only kind of test that can catch this heuristic going wrong. A drawn scene
/// contains exactly the shapes the code is looking for; a capture brings
/// antialiasing, rounded corners, a switch with a knob in it, hairline dividers
/// and a bold display heading — and every one of those broke an earlier version
/// of the sweep.
///
/// The fixture is `Fixtures/settings-pane-2x.png`, the same 2x capture element
/// detection is pinned against. It holds nine runs of text:
///
/// | run | what it is |
/// | --- | --- |
/// | 1 | "General", a bold display heading on the page |
/// | 2…4 | three row labels on a white card |
/// | 5…7 | three more row labels on the second card |
/// | 8 | "Reset", dark words on a light grey button |
/// | 9 | "Save Changes", WHITE words on a solid blue button |
///
/// …and three switches, two text fields and two buttons, none of which are text
/// and none of which may come out as a layer.
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Separate into Layers on a real capture")
struct SeparateIntoLayersFixtureTests {

    private static let capture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    private static let analysis: EdgeMapAnalyzer.Analysis = {
        guard let capture else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(capture)
    }()

    private static let separated: LayerSeparator.Result? = {
        guard let capture else { return nil }
        return LayerSeparator.separateText(capture, luma: analysis.luma)
    }()

    /// One pixel of a bitmap, unpremultiplied, in 0…255 per channel.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        guard let bytes = LayerSeparator.read(image), x >= 0, y >= 0,
              x < image.width, y < image.height else { return (-1, -1, -1, -1) }
        let i = (y * image.width + x) * 4
        let a = Int(bytes[i + 3])
        guard a > 0 else { return (0, 0, 0, 0) }
        return (Int(bytes[i]) * 255 / a, Int(bytes[i + 1]) * 255 / a, Int(bytes[i + 2]) * 255 / a, a)
    }

    // MARK: - What the sweep finds

    @Test func everyRunOfTextInTheCaptureComesOut() throws {
        let runs = TextRunSweep.sweep(in: Self.analysis.luma).runs
        #expect(runs.count == 9)
        // Down the page, then across — the order an eye reads them in. The
        // last two share a row (the Reset and Save Changes buttons sit side by
        // side), and on a shared row the left one comes first even though its
        // letters start a pixel lower.
        let tops = runs.dropLast().map { Int($0.minY) }
        #expect(tops == tops.sorted())
        // The heading first, then the six row labels, then the two buttons'
        // labels left to right.
        #expect(runs.first.map { Int($0.minX) } == 66)
        #expect(runs.dropLast().last.map { Int($0.minX) } == 104)
        #expect(runs.last.map { Int($0.minX) } == 272)
        #expect(runs.last.map { Int($0.minY) } == 776)
    }

    @Test func noSwitchAndNoButtonComesOutAsAPieceOfText() throws {
        let runs = TextRunSweep.sweep(in: Self.analysis.luma).runs
        // The three switches sit at the right edge of the cards, x past 1250.
        #expect(!runs.contains { $0.minX > 1200 })
        // The blue button is 262 wide and 46 tall; its LABEL is 170 by 25. If
        // the button itself had been taken, the label could not have been.
        #expect(!runs.contains { $0.width > 280 })
    }

    @Test func everyRunIsSeparatedAndNoneIsSkipped() throws {
        let result = try #require(Self.separated)
        #expect(result.pieces.count == 9)
        #expect(result.skipped == 0)
    }

    // MARK: - No holes

    @Test func whiteWordsOnASolidBlueButtonLeaveThatButtonOneFlatColour() throws {
        let result = try #require(Self.separated)
        let label = try #require(result.pieces.last).rect
        let patched = result.background

        // The button's own blue, read well away from where the words were.
        let button = pixel(patched, 250, 788)
        var worst = 0
        var readings: Set<String> = []
        guard let bytes = LayerSeparator.read(patched) else {
            Issue.record("the repaired picture could not be read back")
            return
        }
        for y in Int(label.minY)..<Int(label.maxY) {
            for x in Int(label.minX)..<Int(label.maxX) {
                let i = (y * patched.width + x) * 4
                let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                readings.insert("\(r),\(g),\(b)")
                worst = max(worst, max(abs(r - button.r), max(abs(g - button.g), abs(b - button.b))))
            }
        }
        print("PATCH the Save Changes label's \(Int(label.width))x\(Int(label.height)) box "
            + "reads \(readings.count) distinct colour(s); worst channel difference from the "
            + "button's own blue elsewhere: \(worst)/255")
        // Exact, not approximate: one colour across the whole box, and it is
        // the button's colour.
        #expect(readings.count == 1)
        #expect(worst == 0)
    }

    @Test func everyRunLeavesItsSpaceFlatAndMatchingWhatSurroundsIt() throws {
        let result = try #require(Self.separated)
        let patched = result.background
        let bytes = try #require(LayerSeparator.read(patched))
        var report: [String] = []
        for (index, piece) in result.pieces.enumerated() {
            let box = piece.rect
            // What is just outside the box, three pixels clear of it.
            let outside = pixel(patched, Int(box.minX) - 4, Int(box.midY))
            var worst = 0
            for y in Int(box.minY)..<Int(box.maxY) {
                for x in Int(box.minX)..<Int(box.maxX) {
                    let i = (y * patched.width + x) * 4
                    worst = max(worst, abs(Int(bytes[i]) - outside.r))
                    worst = max(worst, abs(Int(bytes[i + 1]) - outside.g))
                    worst = max(worst, abs(Int(bytes[i + 2]) - outside.b))
                }
            }
            report.append("Text \(index + 1): \(worst)")
            #expect(worst <= 1, "Text \(index + 1) does not match what surrounds it")
        }
        print("PATCH worst channel difference between the filled space and the pixel "
            + "4 px to its left, per run, out of 255 — \(report.joined(separator: ", "))")
    }

    @Test func runningItTwiceFindsNothingLeftToTake() throws {
        let result = try #require(Self.separated)
        let again = EdgeMapAnalyzer.analyzeFully(result.background)
        let runs = TextRunSweep.sweep(in: again.luma).runs
        print("TWICE the repaired picture offers \(runs.count) runs")
        #expect(runs.isEmpty)
    }

    // MARK: - What comes out is the letters

    @Test func aPieceIsTheLettersAndNotARectangleOfButton() throws {
        let result = try #require(Self.separated)
        let label = try #require(result.pieces.last)
        let piece = label.image
        // Its corners are the button, and the button did not come with it.
        for corner in [(0, 0), (piece.width - 1, 0), (0, piece.height - 1),
                       (piece.width - 1, piece.height - 1)] {
            #expect(pixel(piece, corner.0, corner.1).a == 0)
        }
        // And the letters did: somewhere in the middle is opaque and white.
        var opaque = 0, white = 0
        let bytes = try #require(LayerSeparator.read(piece))
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] == 255 {
            opaque += 1
            if bytes[i] > 240, bytes[i + 1] > 240, bytes[i + 2] > 240 { white += 1 }
        }
        let coverage = Double(opaque) / Double(piece.width * piece.height)
        print("CUT the Save Changes piece is \(piece.width)x\(piece.height); "
            + "\(Int(coverage * 100))% of it is solid ink and \(white) of those \(opaque) "
            + "pixels are white")
        #expect(opaque > 0)
        #expect(white == opaque)
        // Letters, not a tile: most of the box is see-through.
        #expect(coverage < 0.5)
    }

    @Test func aDarkLabelKeepsItsOwnColourWhenItComesOut() throws {
        let result = try #require(Self.separated)
        // Run 2 is "Launch at login": near black words on a white card.
        let piece = try #require(result.pieces.dropFirst().first).image
        let bytes = try #require(LayerSeparator.read(piece))
        var darkest = 255
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] == 255 {
            darkest = min(darkest, Int(bytes[i]))
        }
        #expect(darkest < 40)
    }

    // MARK: - What it refuses

    @Test func wordsOnAPhotographAreLeftInThePicture() throws {
        // Rule three. The ring round these words is neither one colour nor a
        // straight ramp, so there is no fill the app can justify: the run stays
        // in the picture and no layer is made of it.
        let w = 400, h = 240
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        // Smooth enough that it is not ink, curved enough that it is neither a
        // colour nor a ramp — the shape a photograph has behind a caption.
        for y in 0..<h {
            for x in 0..<w {
                let shade = 110 + 34 * sin(Double(x) / 11) * cos(Double(y) / 9)
                let i = (y * w + x) * 4
                bytes[i] = UInt8(shade)
                bytes[i + 1] = UInt8(shade * 0.8)
                bytes[i + 2] = UInt8(shade * 0.6)
                bytes[i + 3] = 255
            }
        }
        // White "letters" over it: ascenders, x height, and a descender, so the
        // sweep reads them as a run rather than as a box.
        for letter in 0..<14 {
            let x0 = 100 + letter * 8
            let top = (letter == 0 || letter == 3) ? 100 : 106
            let bottom = letter == 13 ? 130 : 124
            for y in top..<bottom {
                for x in x0..<(x0 + 3) {
                    let i = (y * w + x) * 4
                    bytes[i] = 255; bytes[i + 1] = 255; bytes[i + 2] = 255; bytes[i + 3] = 255
                }
            }
        }
        let image = try #require(LayerSeparator.makeImage(bytes, width: w, height: h))
        let analysis = EdgeMapAnalyzer.analyzeFully(image)
        let found = TextRunSweep.sweep(in: analysis.luma).runs
        let result = try #require(LayerSeparator.separateText(image, luma: analysis.luma))
        print("SKIP words on a photograph: \(found.count) run(s) found, "
            + "\(result.pieces.count) separated, \(result.skipped) left in the picture")
        #expect(!found.isEmpty)
        #expect(result.pieces.isEmpty)
        #expect(result.skipped == found.count)
        // And the picture came back untouched, since nothing was taken out of it.
        #expect(result.background === image)
    }

    // MARK: - How long it takes

    /// The fastest of three passes, since the first pays for a cold cache and
    /// what a person feels is the ordinary one.
    private func best(_ runs: Int = 3, _ work: () -> Void) -> TimeInterval {
        var quickest = TimeInterval.greatestFiniteMagnitude
        for _ in 0..<runs {
            let started = Date()
            work()
            quickest = min(quickest, Date().timeIntervalSince(started))
        }
        return quickest
    }

    @Test func separatingTheCaptureIsQuickEnoughToFeelLikeACommand() throws {
        let capture = try #require(Self.capture)
        let megapixels = Double(capture.width * capture.height) / 1_000_000
        let sweep = best { _ = TextRunSweep.sweep(in: Self.analysis.luma) }
        let whole = best { _ = LayerSeparator.separateText(capture, luma: Self.analysis.luma) }
        print(String(format: "PERF %.1f megapixels: sweep %.0f ms, sweep and cut %.0f ms "
                     + "(%.0f and %.0f ms per megapixel)",
                     megapixels, sweep * 1000, whole * 1000,
                     sweep * 1000 / megapixels, whole * 1000 / megapixels))
    }

    /// The number the perf note quotes, on a capture the size of a real retina
    /// screen. Off by default: it is seconds of work in a debug build, and the
    /// everyday suite runs debug. `PHOTONZ_PERF=1 Scripts/test.sh -c release
    /// --filter separatingATwelveMegapixel` is how it is read.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_PERF"] == "1"))
    func separatingATwelveMegapixelCaptureIsUnderASecond() throws {
        let capture = try #require(Self.capture)
        // The fixture tiled out to 4032 x 3024 — 12.2 megapixels, a 2x capture
        // of a 16 inch screen, with twelve times as much text in it as any real
        // screenshot would have.
        let w = 4032, h = 3024
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return }
        for row in 0..<4 {
            for column in 0..<3 {
                context.draw(capture, in: CGRect(x: column * capture.width,
                                                 y: row * capture.height,
                                                 width: capture.width, height: capture.height))
            }
        }
        let big = try #require(context.makeImage())
        // The brightness field itself, which is the one pass this shares with
        // the measure tool and pays for only once per picture.
        let reading = best(2) { _ = EdgeMapAnalyzer.analyzeFully(big) }
        let analysis = EdgeMapAnalyzer.analyzeFully(big)
        let sweep = best(2) { _ = TextRunSweep.sweep(in: analysis.luma) }
        let whole = best(2) { _ = LayerSeparator.separateText(big, luma: analysis.luma) }
        let result = try #require(LayerSeparator.separateText(big, luma: analysis.luma))
        print(String(format: "PERF12 %d x %d (%.1f megapixels), %d runs: reading the picture "
                     + "%.0f ms, sweep %.0f ms, sweep and cut %.0f ms", w, h,
                     Double(w * h) / 1_000_000, result.pieces.count,
                     reading * 1000, sweep * 1000, whole * 1000))
    }
}
