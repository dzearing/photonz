import CoreGraphics
import Foundation
import PhotonzCore
@testable import PhotonzRender
import Testing

/// Turning a separated run of text back into words, measured on a REAL
/// screenshot, because there is no other kind of test that can say whether the
/// face the app picked is the face in the picture.
///
/// The fixture is `Fixtures/settings-pane-2x.png`, the same 2x capture Separate
/// into Layers is pinned against. It carries the three cases the task named,
/// and all three are checked here:
///
/// | case | run |
/// | --- | --- |
/// | a heading | 0, "General", bold and large |
/// | a small caption | 1…6, six row labels on two cards |
/// | light on dark | 8, "Save Changes", WHITE on a solid blue button |
///
/// Full design: `docs/design/separate-into-layers.md`.
@Suite("Reading a separated run back into words, on a real capture")
struct ReadRunAsTextFixtureTests {

    private static let capture: CGImage? = {
        guard let url = Bundle.module.url(forResource: "Fixtures/settings-pane-2x",
                                          withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImageCodec.decode(data)
    }()

    private static let separated: LayerSeparator.Result? = {
        guard let capture else { return nil }
        return LayerSeparator.separateText(capture,
                                           luma: EdgeMapAnalyzer.analyzeFully(capture).luma)
    }()

    /// Every separated run, read back. The capture is 2x, so the type in it was
    /// set at half the pixel size, which is the size the face is identified at.
    private static let reads: [TextReader.Read] = {
        guard let separated else { return [] }
        return separated.runs.compactMap { $0.image }
            .map { TextReader.read($0, captureScale: 2) }
    }()

    private func reading(_ index: Int) throws -> TextReading.Reading {
        let refusal = Self.reads[index].outcome.refusal?.rawValue ?? "?"
        return try #require(Self.reads[index].outcome.reading,
                            "run \(index) was refused: \(refusal)")
    }

    // MARK: - The words

    @Test func everyRunInTheCaptureComesBackAsItsOwnWords() throws {
        #expect(Self.reads.count == 9)
        let words = try (0..<9).map { try reading($0).string }
        #expect(words == ["General", "Launch at login", "Show in menu bar",
                          "Play sound on capture", "Save captures to",
                          "File name prefix", "Copy to clipboard", "Reset",
                          "Save Changes"])
    }

    // MARK: - The face

    @Test func theHeadingComesBackBoldAndTheButtonLabelDoesNot() throws {
        // A heading is the one case where weight is unmistakable, and it is the
        // case a wrong answer would be most visible in.
        let heading = try reading(0)
        #expect(heading.face.fontName == "SF Pro")
        #expect(heading.face.weight == .bold)
        #expect(try reading(8).face.weight != .bold)
    }

    @Test func thePageComesBackInOneFamily() throws {
        // Nine runs of one screenshot, and the answer is the same family for
        // every one of them. That is the thing a person would actually notice
        // going wrong: three labels of one card in the system font and three in
        // something else is worse than all nine being wrong the same way.
        let families = Set(try (0..<9).map { try reading($0).face.fontName })
        #expect(families == ["SF Pro"])
    }

    @Test func mostOfThemAreAnAnswerRatherThanAFallback() throws {
        // A face that beat every other FAMILY by a clear margin is an answer,
        // and the audit is told which runs those were.
        let matched = try (0..<9).filter { try reading($0).provenance == .matched }
        #expect(matched.count >= 7)
    }

    @Test func aSerifAndAMonospaceAreNowhereNearTheAnswer() throws {
        // What makes the bar meaningful: the faces that are NOT in the picture
        // have to lose, and lose clearly, or refusing would never happen.
        for index in [0, 3, 8] {
            let best = try #require(Self.reads[index].scores.first)
            for wrong in Self.reads[index].scores
                where ["Georgia", "Times New Roman", "SF Mono"].contains(wrong.face.fontName) {
                #expect(wrong.agreement < best.agreement - TextReading.distinctMargin,
                        "\(wrong.face.displayName) was too close on run \(index)")
            }
        }
    }

    // MARK: - The size and the colour

    @Test func lightOnDarkComesBackWhiteAndDarkOnLightComesBackDark() throws {
        #expect(try reading(8).colorHex == "#FFFFFF")
        for index in 0..<8 {
            let hex = try reading(index).colorHex
            let color = try #require(RGBA(hex: hex))
            #expect(color.relativeLuminance < 0.25, "run \(index) came back \(hex)")
        }
    }

    @Test func aHeadingComesBackBiggerThanTheLabelsUnderIt() throws {
        let heading = try reading(0).fontSize
        for index in 1..<8 {
            #expect(try reading(index).fontSize < heading * 0.8)
        }
    }

    @Test func theRetypedWordsAreTheSizeTheOldOnesWere() throws {
        // The number this feature lives on. Set the words the app chose and
        // measure them: they have to cover the space the picture's ink covered,
        // or a label lands somewhere other than where it was.
        for index in 0..<9 {
            let reading = try reading(index)
            let ink = try #require(Self.reads[index].inkRect)
            let mask = try #require(TextReader.render(reading.string, in: reading.face,
                                                      size: reading.fontSize, scale: 1))
            let bounds = try #require(mask.inkBounds())
            #expect(abs(bounds.width - ink.width) <= 3,
                    "run \(index) came out \(bounds.width) px wide, was \(ink.width)")
            #expect(abs(bounds.height - ink.height) <= 3,
                    "run \(index) came out \(bounds.height) px tall, was \(ink.height)")
        }
    }

    @Test func theWordsLandWhereTheInkWas() throws {
        // The frame a text layer gets is not the picture's frame: the box holds
        // the ascent above the letters and the descent below. Setting the words
        // in that box has to put their ink back on the picture's ink.
        for index in [0, 3, 8] {
            let reading = try reading(index)
            let ink = try #require(Self.reads[index].inkRect)
            var text = TextContent(string: reading.string, fontName: reading.face.fontName,
                                   fontSize: reading.fontSize, colorHex: reading.colorHex,
                                   weight: reading.face.weight)
            text.staysOnOneLine = true
            let box = TextReader.frame(for: text, placingInkAt: ink)
            let mask = try #require(TextReader.render(reading.string, in: reading.face,
                                                      size: reading.fontSize, scale: 1))
            let inside = try #require(mask.inkBounds())
            #expect(abs(box.minX + inside.minX - ink.minX) < 0.51)
            #expect(abs(box.minY + inside.minY - ink.minY) < 0.51)
        }
    }

    // MARK: - What it refuses

    @Test func theWholeScreenshotSaysToSeparateItFirst() throws {
        // The footgun turned into a signpost. A person who tries this on a
        // whole page gets a sentence telling them what to do, rather than one
        // enormous label or a menu row that was never there.
        let capture = try #require(Self.capture)
        #expect(TextReader.read(capture, captureScale: 2).outcome.refusal == .moreThanOneRun)
    }

    @Test func aPieceOfFlatPanelIsNotWords() throws {
        // A crop with nothing in it: the case that must never come back as a
        // label, and the one a photograph's smooth sky would take.
        let capture = try #require(Self.capture)
        let flat = try #require(capture.cropping(to: CGRect(x: 600, y: 110,
                                                            width: 220, height: 40)))
        #expect(TextReader.read(flat, captureScale: 2).outcome.reading == nil)
    }

    @Test func aSwitchIsNotWords() throws {
        // A control, not text. The sweep already refuses to call it a run; this
        // is the other end of the same promise, for somebody who cropped one
        // out by hand and asked for its words.
        let capture = try #require(Self.capture)
        let toggle = try #require(capture.cropping(to: CGRect(x: 1250, y: 160,
                                                              width: 120, height: 60)))
        #expect(TextReader.read(toggle, captureScale: 2).outcome.reading == nil)
    }
}
