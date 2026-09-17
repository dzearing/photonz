import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The deciding half of "a separated run of text becomes text you can retype".
///
/// What is pinned here is the JUDGEMENT, not the reading: whether two shapes of
/// ink agree, what colour the ink is, and when the app is willing to hand a
/// person words instead of pixels. The half that runs Vision and sets the words
/// in a real face is measured against a real screenshot in
/// `PhotonzRenderTests/ReadRunAsTextFixtureTests.swift`.
@Suite("Reading a run of text back into words")
struct TextReadingTests {

    /// A mask with `rects` filled solid, on a `width` x `height` field.
    private func mask(_ width: Int, _ height: Int, _ rects: [CGRect],
                      ink: Double = 1) -> TextReading.Mask {
        var coverage = [Double](repeating: 0, count: width * height)
        for rect in rects {
            for y in Int(rect.minY)..<Int(rect.maxY) where y >= 0 && y < height {
                for x in Int(rect.minX)..<Int(rect.maxX) where x >= 0 && x < width {
                    coverage[y * width + x] = ink
                }
            }
        }
        return TextReading.Mask(width: width, height: height, coverage: coverage)
    }

    // MARK: - Ink

    @Test func inkBoundsIsTheTightBoxRoundTheLetters() throws {
        let m = mask(20, 10, [CGRect(x: 3, y: 2, width: 4, height: 5)])
        #expect(m.inkBounds() == CGRect(x: 3, y: 2, width: 4, height: 5))
        #expect(m.inkTotal == 20)
    }

    @Test func anAntialiasedRimIsNotPartOfTheBox() throws {
        // A stroke with a one pixel haze round it. The box is the stroke: a box
        // drawn round the last pixel above zero is a box round the rim, and
        // every size this measures would come out a size too big.
        var coverage = [Double](repeating: 0, count: 20 * 10)
        for y in 2..<7 { for x in 3..<7 { coverage[y * 20 + x] = 1 } }
        for y in 1..<8 { coverage[y * 20 + 2] = 0.04; coverage[y * 20 + 7] = 0.04 }
        let m = TextReading.Mask(width: 20, height: 10, coverage: coverage)
        #expect(m.inkBounds() == CGRect(x: 3, y: 2, width: 4, height: 5))
    }

    @Test func nothingInkedHasNoBox() throws {
        #expect(mask(8, 8, []).inkBounds() == nil)
    }

    // MARK: - Agreement

    @Test func aMaskAgreesPerfectlyWithItself() throws {
        let m = mask(30, 12, [CGRect(x: 2, y: 3, width: 6, height: 6),
                              CGRect(x: 12, y: 3, width: 6, height: 6)])
        #expect(TextReading.agreement(m, m) == 1)
    }

    @Test func theSameInkPlacedDifferentlyStillAgrees() throws {
        // The two are laid ink box on ink box before anything is scored, so the
        // same words in the same face score 1 wherever they sit in their
        // pictures. Without that, a run cut one pixel wider would look like a
        // different face.
        let a = mask(30, 12, [CGRect(x: 2, y: 2, width: 8, height: 7)])
        let b = mask(40, 20, [CGRect(x: 21, y: 11, width: 8, height: 7)])
        #expect(TextReading.agreement(a, b) == 1)
    }

    @Test func inkTheSameHeightAndTheWrongWidthLosesBadly() throws {
        // The case the whole feature turns on: a face whose letters are the
        // right height and set a quarter wider. Strokes are what a word is made
        // of, so every one of them past the first lands in the gap the other
        // face left, and the score cannot be argued back up.
        func strokes(_ pitch: Int) -> TextReading.Mask {
            mask(80, 12, (0..<5).map {
                CGRect(x: 2 + $0 * pitch, y: 2, width: 3, height: 8)
            })
        }
        let score = TextReading.agreement(strokes(8), strokes(10))
        #expect(score < 0.45)
        #expect(score < TextReading.agreementBar)
    }

    @Test func nudgingIsBoundedSoAWrongFaceCannotSlideIntoPlace() throws {
        // Two strokes a long way apart in one mask and close together in the
        // other. Aligning their ink boxes lines the first stroke up; the slack
        // is nowhere near enough to bring the second one over too.
        let a = mask(60, 12, [CGRect(x: 2, y: 2, width: 4, height: 8),
                              CGRect(x: 40, y: 2, width: 4, height: 8)])
        let b = mask(60, 12, [CGRect(x: 2, y: 2, width: 4, height: 8),
                              CGRect(x: 12, y: 2, width: 4, height: 8)])
        #expect(TextReading.agreement(a, b) < 0.55)
    }

    @Test func nothingToCompareAgainstScoresNothing() throws {
        let m = mask(10, 10, [CGRect(x: 1, y: 1, width: 3, height: 3)])
        #expect(TextReading.agreement(m, mask(10, 10, [])) == 0)
    }

    @Test func aFaintRimAgreesWithTheStrokeItSurrounds() throws {
        // Coverage is compared, not colour, so an antialiased edge that is 40%
        // ink in one and 60% in the other costs a fifth of those pixels rather
        // than all of them.
        let solid = mask(20, 10, [CGRect(x: 4, y: 2, width: 6, height: 6)])
        let faint = mask(20, 10, [CGRect(x: 4, y: 2, width: 6, height: 6)], ink: 0.8)
        let score = TextReading.agreement(solid, faint)
        #expect(score > 0.75 && score < 0.85)
    }

    // MARK: - Colour

    @Test func theInkColourIsTheMiddleSampleNotTheAverage() throws {
        // One stray pixel of something else caught inside the run — a coloured
        // bullet, a caret — must not drag the whole label off its colour.
        let white = RGBA(r: 1, g: 1, b: 1)
        let samples = [white, white, white, white, RGBA(r: 1, g: 0, b: 0)]
        #expect(TextReading.inkColor(samples)?.hexString == "#FFFFFF")
    }

    @Test func nothingSolidEnoughToSampleHasNoColour() throws {
        #expect(TextReading.inkColor([]) == nil)
    }

    // MARK: - The verdict

    private let sfSemibold = TextReading.Face(fontName: "SF Pro", weight: .semibold)
    private let georgia = TextReading.Face(fontName: "Georgia", weight: .regular)

    @Test func aClearWinnerIsAMatchedFace() throws {
        let outcome = TextReading.decide(
            string: "Save Changes",
            scores: [TextReading.Scored(face: sfSemibold, fontSize: 15, agreement: 0.78),
                     TextReading.Scored(face: georgia, fontSize: 15, agreement: 0.41)],
            color: RGBA(r: 1, g: 1, b: 1))
        let reading = try #require(outcome.reading)
        #expect(reading.string == "Save Changes")
        #expect(reading.face == sfSemibold)
        #expect(reading.provenance == .matched)
        #expect(reading.colorHex == "#FFFFFF")
    }

    @Test func twoFamiliesNeckAndNeckMakeTheWinnerAStatedFallback() throws {
        // The picture did not say which family it is. The words are still set
        // in the best of them, and the audit is told this is a fallback rather
        // than an answer.
        let outcome = TextReading.decide(
            string: "General",
            scores: [TextReading.Scored(face: sfSemibold, fontSize: 20, agreement: 0.71),
                     TextReading.Scored(face: georgia, fontSize: 20, agreement: 0.70)],
            color: RGBA(r: 0, g: 0, b: 0))
        #expect(outcome.reading?.provenance == .fallback)
        #expect(outcome.reading?.face == sfSemibold)
    }

    @Test func twoWeightsOfOneFamilyAreOneAnswerNotATie() throws {
        let medium = TextReading.Face(fontName: "SF Pro", weight: .medium)
        let outcome = TextReading.decide(
            string: "Reset",
            scores: [TextReading.Scored(face: sfSemibold, fontSize: 13, agreement: 0.75),
                     TextReading.Scored(face: medium, fontSize: 13, agreement: 0.74),
                     TextReading.Scored(face: georgia, fontSize: 13, agreement: 0.40)],
            color: RGBA(r: 0, g: 0, b: 0))
        #expect(outcome.reading?.provenance == .matched)
    }

    @Test func nothingAgreeingWellEnoughStaysAPicture() throws {
        let outcome = TextReading.decide(
            string: "Save Changes",
            scores: [TextReading.Scored(face: sfSemibold, fontSize: 15, agreement: 0.55),
                     TextReading.Scored(face: georgia, fontSize: 15, agreement: 0.44)],
            color: RGBA(r: 1, g: 1, b: 1))
        #expect(outcome.refusal == .noFaceMatches)
    }

    @Test func noWordsAndNoColourEachHaveTheirOwnRefusal() throws {
        let scored = [TextReading.Scored(face: sfSemibold, fontSize: 15, agreement: 0.9)]
        #expect(TextReading.decide(string: "   ", scores: scored,
                                   color: RGBA(r: 0, g: 0, b: 0)).refusal == .noWords)
        #expect(TextReading.decide(string: "Reset", scores: scored,
                                   color: nil).refusal == .tooFaint)
        #expect(TextReading.decide(string: "Reset", scores: [],
                                   color: RGBA(r: 0, g: 0, b: 0)).refusal == .noFaceMatches)
    }

    // MARK: - The family the page is set in

    private let sfMedium = TextReading.Face(fontName: "SF Pro", weight: .medium)
    private let helvetica = TextReading.Face(fontName: "Helvetica Neue", weight: .bold)

    private func reading(_ face: TextReading.Face) -> TextReading.Reading {
        TextReading.Reading(string: "Border 1", face: face, fontSize: 13,
                            colorHex: "#000000", agreement: 0.7, provenance: .matched)
    }

    @Test func thePageIsSetInTheFamilyMostOfItsRunsCameBackIn() throws {
        let readings = [reading(sfSemibold), reading(sfMedium), reading(helvetica)]
        #expect(TextReading.pageFamily(of: readings) == "SF Pro")
    }

    @Test func aPageNobodyReadHasNoFamily() throws {
        #expect(TextReading.pageFamily(of: []) == nil)
    }

    @Test func aPageThatIsGenuinelySomethingElseSaysSo() throws {
        let readings = [reading(helvetica), reading(helvetica), reading(sfMedium)]
        #expect(TextReading.pageFamily(of: readings) == "Helvetica Neue")
    }

    @Test func aTieGoesToTheSystemFont() throws {
        // Two runs, one each, and nothing to tell them apart. The same reason
        // `fallbackFamily` exists: on a Mac screenshot the system font is the
        // one to reach for when the picture does not say.
        let readings = [reading(helvetica), reading(sfMedium)]
        #expect(TextReading.pageFamily(of: readings) == "SF Pro")
    }

    // MARK: - Setting a run in the family the page voted for

    @Test func theRunTakesThePagesFamilyEvenWhenAnotherScoredHigher() throws {
        // The measured bug: "Border 1" alone says Helvetica Neue 0.78 against
        // SF Pro's 0.72, on a window with no Helvetica Neue in it.
        let outcome = TextReading.decide(
            string: "Border 1",
            scores: [TextReading.Scored(face: helvetica, fontSize: 13, agreement: 0.78),
                     TextReading.Scored(face: sfMedium, fontSize: 13, agreement: 0.72)],
            color: RGBA(r: 0, g: 0, b: 0), preferring: "SF Pro")
        let reading = try #require(outcome.reading)
        #expect(reading.face == sfMedium)
        // The page answered, not the run, and the audit is told which.
        #expect(reading.provenance == .fallback)
    }

    @Test func aRunThePagesFamilyCannotAccountForStaysAPicture() throws {
        // "Width" on this app's own window: SF Pro's best is 0.578, under the
        // bar. Losing the reading is the right outcome — a picture is honest
        // and a wrong face is not.
        let outcome = TextReading.decide(
            string: "Width",
            scores: [TextReading.Scored(face: helvetica, fontSize: 13, agreement: 0.73),
                     TextReading.Scored(face: sfMedium, fontSize: 13, agreement: 0.58)],
            color: RGBA(r: 0, g: 0, b: 0), preferring: "SF Pro")
        #expect(outcome.refusal == .noFaceMatches)
    }

    @Test func aRunThatAlreadyAgreedWithThePageIsStillAnAnswer() throws {
        let outcome = TextReading.decide(
            string: "Border 2",
            scores: [TextReading.Scored(face: sfMedium, fontSize: 13, agreement: 0.72),
                     TextReading.Scored(face: helvetica, fontSize: 13, agreement: 0.50)],
            color: RGBA(r: 0, g: 0, b: 0), preferring: "SF Pro")
        #expect(outcome.reading?.face == sfMedium)
        #expect(outcome.reading?.provenance == .matched)
    }

    @Test func noFamilyPreferredIsTheAnswerTheRunGivesOnItsOwn() throws {
        // Turn into Text on one label, with no page to vote: unchanged.
        let scores = [TextReading.Scored(face: helvetica, fontSize: 13, agreement: 0.78),
                      TextReading.Scored(face: sfMedium, fontSize: 13, agreement: 0.72)]
        let outcome = TextReading.decide(string: "Border 1", scores: scores,
                                         color: RGBA(r: 0, g: 0, b: 0), preferring: nil)
        #expect(outcome.reading?.face == helvetica)
        #expect(outcome.reading?.provenance == .matched)
    }

    @Test func aPreferredFamilyNoFaceWasTriedInStaysAPicture() throws {
        let outcome = TextReading.decide(
            string: "Border 1",
            scores: [TextReading.Scored(face: helvetica, fontSize: 13, agreement: 0.78)],
            color: RGBA(r: 0, g: 0, b: 0), preferring: "Georgia")
        #expect(outcome.refusal == .noFaceMatches)
    }

    // MARK: - The name

    @Test func theNewLayerIsCalledTheWords() throws {
        #expect(TextReading.layerName(for: "Save Changes") == "Save Changes")
        #expect(TextReading.layerName(for: "  Reset\n") == "Reset")
    }

    @Test func aRunTooLongForTheListIsCutAtAWord() throws {
        let long = "Automatically check for updates every week"
        let name = TextReading.layerName(for: long)
        #expect(name == "Automatically check for updates\u{2026}")
        #expect(name.count <= TextReading.nameLimit + 1)
    }

    @Test func aSingleEnormousWordIsStillCut() throws {
        let name = TextReading.layerName(for: String(repeating: "x", count: 60))
        #expect(name.count == TextReading.nameLimit + 1)
    }

    @Test func aFaceSaysItsWeightOutLoudUnlessItIsTheOrdinaryOne() throws {
        #expect(sfSemibold.displayName == "SF Pro Semibold")
        #expect(TextReading.Face(fontName: "SF Pro", weight: .regular).displayName == "SF Pro")
    }
}
