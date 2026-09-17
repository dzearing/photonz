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
/// Serialized, like the row-naming suite next door and for the same reason:
/// every test here waits on ONE lazily read capture, and a dozen of them
/// blocking on that at once holds a cooperative thread each while the reading
/// itself needs threads to finish. Run one at a time the whole suite is fifteen
/// seconds; run at once the suite deadlocked the full test run.
@Suite("Reading a separated run back into words, on a real capture", .serialized)
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

    private static let runImages: [CGImage] = separated?.runs.compactMap { $0.image } ?? []

    /// Every separated run, read back as a PAGE: the family the runs vote for
    /// is settled first, and then each of them is set in it. What the app does,
    /// and the only shape in which a label cannot come back heavier than the
    /// identical label beside it.
    ///
    /// The capture is 2x, so the type in it was set at half the pixel size,
    /// which is the size the face is identified at.
    private static let reads: [TextReader.Read] = TextReader.readPage(runImages,
                                                                      captureScale: 2)

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

    // MARK: - Every label at once (`next-read-every-label`)

    /// The same nine runs read the way the app reads them when somebody presses
    /// Read the Words: across the cores, because there are forty of these on a
    /// window capture and a hundred and forty on a page.
    private static let spread: [TextReader.Read] = TextReader.readPage(
        runImages, captureScale: 2, spreadingOverTheCores: true)

    @Test func readingThePageAcrossTheCoresAnswersExactlyAsOneAtATime() throws {
        // Spreading the work is a speed decision and must not be a correctness
        // one. Nine runs, same words, same faces, same sizes, whichever way
        // round they were read.
        #expect(Self.spread.count == Self.reads.count)
        for index in Self.reads.indices {
            #expect(Self.spread[index].outcome.reading?.string
                == Self.reads[index].outcome.reading?.string, "run \(index)")
            #expect(Self.spread[index].outcome.reading?.face
                == Self.reads[index].outcome.reading?.face, "run \(index)")
            #expect(Self.spread[index].outcome.reading?.fontSize
                == Self.reads[index].outcome.reading?.fontSize, "run \(index)")
        }
    }

    @Test func everyLabelOfOnePageComesBackAtOneWeightPerKindOfLabel() throws {
        // The other half of what reading the whole picture at once can do that
        // reading one label at a time never can: the six row labels are
        // compared with each other, so none of them comes back heavier than
        // the identical label beside it, and the heading over them keeps its
        // own weight.
        let rows = Self.spread[1...6].compactMap(\.outcome.reading?.face.weight)
        #expect(Set(rows) == [.regular])
        #expect(Self.spread[0].outcome.reading?.face.weight == .bold)
    }

    @Test func everyLabelOfOnePageComesBackInOneFamily() throws {
        // The thing reading the whole picture at once can do that reading one
        // label at a time never can: the labels are compared with each other,
        // so no label comes back in a family the page does not contain.
        let families = Set(Self.spread.compactMap(\.outcome.reading?.face.fontName))
        #expect(families == ["SF Pro"])
    }

    @Test func aPageWhoseFamilyIsAlreadySettledIsNotAskedAgain() throws {
        // A screenshot read in a batch and then one more label read on its own
        // must not end up with two answers. Told the family, every run is held
        // to it and nothing votes.
        let told = TextReader.readPage(Self.runImages, captureScale: 2, preferring: "SF Pro")
        let families = Set(told.compactMap(\.outcome.reading?.face.fontName))
        #expect(families == ["SF Pro"])
        #expect(told.compactMap(\.outcome.reading).count
            == Self.reads.compactMap(\.outcome.reading).count)
    }

    @Test func aPageHeldToAFamilyItIsNotInLosesReadingsRatherThanGainingWrongOnes() throws {
        // The safety net under the batch, the same one a single reading has:
        // held to a family this capture is plainly not set in, the labels stay
        // pictures. A page that genuinely mixes families gives up readings
        // rather than handing back labels in the wrong face.
        let wrong = TextReader.readPage(Self.runImages, captureScale: 2, preferring: "Georgia")
        #expect(!wrong.contains { $0.outcome.reading?.face.fontName == "SF Pro" })
        #expect(wrong.compactMap(\.outcome.reading).count < Self.reads.compactMap(\.outcome.reading).count)
    }

    @Test func aRunDrawnSmallerOnTheCanvasIsSetSmaller() throws {
        // Each run carries its own scale, because a label somebody resized
        // after separating has to cover the space it covers NOW. Read as a page
        // at half the size, the words come back at half the point size.
        let runs = Self.runImages.prefix(3).map { TextReader.PageRun(image: $0, layerScale: 2) }
        let smaller = TextReader.readPage(Array(runs), captureScale: 2)
        for index in runs.indices {
            guard let half = smaller[index].outcome.reading,
                  let whole = Self.reads[index].outcome.reading else { continue }
            #expect(half.fontSize < whole.fontSize, "run \(index)")
        }
    }

    @Test func theRunsOfThisCaptureVoteForTheSystemFont() throws {
        let readings = Self.reads.compactMap(\.outcome.reading)
        #expect(TextReading.pageFamily(of: readings) == "SF Pro")
    }

    @Test func aRunToldItsPageIsSomethingItIsNotStaysAPicture() throws {
        // The safety net under the vote. Told this label is Georgia when it is
        // plainly not, the app does not set it in Georgia: it refuses, and the
        // run stays the picture it was. So a page that genuinely mixes families
        // loses a reading rather than gaining a wrong face.
        let read = TextReader.read(try #require(Self.runImages.first), captureScale: 2,
                                   preferring: "Georgia")
        #expect(read.outcome.refusal == .noFaceMatches)
    }

    @Test func aRunToldItsOwnFamilyIsUnchangedByBeingTold() throws {
        let image = try #require(Self.runImages.first)
        let free = TextReader.read(image, captureScale: 2)
        let told = TextReader.read(image, captureScale: 2, preferring: "SF Pro")
        #expect(free.outcome.reading?.face == told.outcome.reading?.face)
        #expect(told.outcome.reading?.provenance == .matched)
    }

    @Test func oneRunOnItsOwnStillReadsWithNoPageToAsk() throws {
        // The whole point of keeping the per-run path: Turn into Text on a
        // single label, before anything has told the app what the page is.
        let read = TextReader.read(try #require(Self.runImages.first), captureScale: 2)
        #expect(read.outcome.reading?.string == "General")
    }

    @Test func mostOfThemAreAnAnswerRatherThanAFallback() throws {
        // A face that beat every other FAMILY and every other WEIGHT by a
        // clear margin is an answer, and the audit is told which runs those
        // were. Three of the nine are the page answering rather than the run:
        // one whose own best face is in a family this pane does not contain,
        // and the two row labels the page holds to Regular against their own
        // confident Medium.
        let matched = try (0..<9).filter { try reading($0).provenance == .matched }
        #expect(matched.count >= 6)
    }

    // MARK: - The weight

    /// Runs 1 to 6 are the six row labels of the two cards, and the picture
    /// says plainly that they are one weight. Run 0 is the heading over them.
    private static let rowLabels = 1...6

    @Test func theRowLabelsOfOnePaneComeBackAtOneWeight() throws {
        // The bug: read one at a time, "Launch at login" and "Show in menu
        // bar" come back Medium and the four under them come back Regular.
        let found = try Set(Self.rowLabels.map { try reading($0).face.weight })
        #expect(found == [.regular])
    }

    @Test func theHeadingIsNotDraggedDownToItsRows() throws {
        // What a page-wide vote would have broken. "General" is half again
        // the size of the labels under it, so it is not a label of their kind
        // and its own answer stands.
        #expect(try reading(0).face.weight == .bold)
    }

    @Test func settlingTheWeightNeverCostsAReading() throws {
        // A weight a shade off is a smaller harm than a label that stays a
        // picture, so the weight the page settled is never the reason one
        // does. Held to the family alone, exactly as many labels come back.
        let held = Self.runImages.map {
            TextReader.read($0, captureScale: 2, preferring: "SF Pro")
        }
        #expect(held.compactMap(\.outcome.reading).count
            == Self.reads.compactMap(\.outcome.reading).count)
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

    @Test func theRowLabelsOfOnePaneComeBackAtOneSize() throws {
        // The other half of the bug the weight vote fixed. Left to fit itself,
        // each of these six labels comes back at its own size — 27.6, 28.0,
        // 28.5, 28.0, 28.5, 28.4 — while every one of them is 13 points on
        // screen, so picking all six reads Mixed in the Size menu.
        let sizes = try Set(Self.rowLabels.map { try reading($0).fontSize })
        #expect(sizes.count == 1)
        // And it is a size out of what they measured, not a number from
        // somewhere else: they each fitted between 28.0 and 28.5.
        let one = try #require(sizes.first)
        #expect(one > 28 && one < 28.5)
    }

    @Test func theHeadingIsNotDraggedToTheSizeOfItsRows() throws {
        // What settling the size must never do, and the reason it is settled
        // per kind of label. "General" is half again the size of the labels
        // under it.
        let heading = try reading(0).fontSize
        let rows = try Self.rowLabels.map { try reading($0).fontSize }
        #expect(rows.allSatisfy { $0 < heading * 0.8 })
    }

    @Test func aButtonLabelOfItsOwnKindKeepsItsOwnSize() throws {
        // "Save Changes" is white on a blue button: nothing else on the pane
        // is that kind of label, so there is no second opinion to have and its
        // own size stands rather than being pulled onto the grey rows'.
        let button = try reading(8).fontSize
        let rows = try Self.rowLabels.map { try reading($0).fontSize }
        #expect(!rows.contains(button))
    }

    @Test func settlingTheSizeNeverCostsAReading() throws {
        // The same promise the weight makes. A label back at the size it
        // fitted itself is a smaller harm than a label that does not come back
        // at all, so a run whose ink its cohort's size cannot account for
        // keeps its own.
        let held = Self.runImages.map {
            TextReader.read($0, captureScale: 2, preferring: "SF Pro")
        }
        #expect(Self.reads.compactMap(\.outcome.reading).count
            == held.compactMap(\.outcome.reading).count)
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
