import AppKit
import CoreGraphics
import CoreText
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Reading a separated run for its WORDS ALONE, which is what a row in the
/// layers list needs and all it needs.
///
/// The full reading (`TextReader.read`) also identifies the face and the size,
/// by setting the words again in every face the app knows, at several sizes
/// each, and laying each one over the picture's own ink. A row wants none of
/// that. It wants the characters, so it can say "Save Changes" instead of
/// "Text 57".
///
/// Two things follow, and both are checked here: it is never the dearer of the
/// two and on a dense page about half, and it answers on pictures the full
/// reading refuses — a page set in a face the app cannot match still has words
/// a person can read and search.
@Suite("The words in a run, for a row to wear")
struct RunWordsForARowTests {

    private static let capture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    private static let runs: [CGImage] = {
        guard let capture,
              let separated = LayerSeparator.separateText(
                capture, luma: EdgeMapAnalyzer.analyzeFully(capture).luma)
        else { return [] }
        return separated.runs.compactMap(\.image)
    }()

    private static let expected = ["General", "Launch at login", "Show in menu bar",
                                   "Play sound on capture", "Save captures to",
                                   "File name prefix", "Copy to clipboard", "Reset",
                                   "Save Changes"]

    // MARK: - The words

    @Test func everyRunHandsOverTheWordsInIt() throws {
        #expect(Self.runs.count == 9)
        #expect(Self.runs.map { TextReader.words(in: $0) } == Self.expected)
    }

    @Test func aPictureWithNoWordsInItHandsBackNothing() throws {
        // The case a row must never wear: a control or a patch of flat panel
        // has no words, so its row keeps the name the app gave it.
        let capture = try #require(Self.capture)
        let flat = try #require(capture.cropping(to: CGRect(x: 600, y: 110,
                                                            width: 220, height: 40)))
        #expect(TextReader.words(in: flat) == nil)
    }

    // MARK: - What it costs

    /// Off unless asked for, like every other timing here: an ordinary test run
    /// has several hundred Vision passes going at once and the clock says
    /// nothing about either reading.
    ///
    /// ```
    /// PHOTONZ_STUDY=1 Scripts/test.sh -c release --filter RunWordsForARow
    /// ```
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PHOTONZ_STUDY"] == "1"))
    func theWordsAloneNeverCostMoreThanTheWholeReading() throws {
        // Measured rather than assumed, because the obvious guess is wrong. In
        // a DEBUG build the words are a fiftieth of the whole reading, which
        // makes the face matching look free to skip; optimised, the recogniser
        // is nearly all of the cost and the saving is much smaller — 276 ms
        // against 358 ms for this pane, so about a quarter, and about half on
        // the dense page, whose runs are small and many (1650 ms for its 142
        // runs, against 3643 ms to read them whole).
        //
        // So speed is not why a row reads this way. A row reads this way
        // because the face is the half that is wrong often enough to matter
        // (`docs/design/separate-reads-the-words.md`) and a name does not need
        // it. What this test holds is the floor: reading for words alone is
        // never the slower of the two, and one run costs a fraction of a
        // second, which is what makes a background pass over a whole page
        // finish while somebody is still looking at the pill.
        let runs = Self.runs
        #expect(!runs.isEmpty)
        // The recogniser loads its model on first use, and whichever of the two
        // goes first pays for it. Warmed up, they can be compared.
        _ = TextReader.words(in: runs[0])
        var t0 = Date()
        for run in runs { _ = TextReader.words(in: run) }
        let wordsMS = Date().timeIntervalSince(t0) * 1000
        t0 = Date()
        for run in runs { _ = TextReader.read(run, captureScale: 2) }
        let wholeMS = Date().timeIntervalSince(t0) * 1000
        print("words alone \(Int(wordsMS)) ms · the whole reading \(Int(wholeMS)) ms "
              + "for \(runs.count) runs")
        #expect(wordsMS < wholeMS * 1.05,
                "words alone took \(Int(wordsMS)) ms against \(Int(wholeMS)) ms")
        #expect(wordsMS / Double(runs.count) < 200)
    }

    // MARK: - Where the full reading gives up

    @Test func afaceTheAppCannotMatchStillHasWordsInIt() throws {
        // Sixty of the dense page's hundred and forty two runs are refused for
        // having no matching face, and every one of them is still a label a
        // person can read and would search for. A row says its words whether or
        // not the app could say what they are SET in.
        let picture = try #require(Self.picture(of: "Recommended", face: "Chalkduster",
                                                size: 34))
        #expect(TextReader.read(picture, captureScale: 1).outcome.reading == nil)
        #expect(TextReader.words(in: picture) == "Recommended")
    }

    /// A run of text drawn the way a screenshot holds one: dark words on a
    /// light panel, with a margin of panel round them.
    private static func picture(of words: String, face: String, size: CGFloat) -> CGImage? {
        let font = CTFontCreateWithName(face as CFString, size, nil)
        let attributed = NSAttributedString(string: words, attributes: [
            .font: font, .foregroundColor: CGColor(gray: 0.1, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let w = Int(bounds.width.rounded(.up)) + 24, h = Int(bounds.height.rounded(.up)) + 24
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(gray: 0.97, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        context.textPosition = CGPoint(x: 12, y: 12 - bounds.minY)
        CTLineDraw(line, context)
        return context.makeImage()
    }
}
