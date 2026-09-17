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

    // MARK: - The weight a page sets one kind of label in

    /// A ballot: the size the page's family fits this run's ink at, the colour
    /// of the ink, and how each weight did.
    private func ballot(_ size: CGFloat, _ hex: String,
                        _ agreement: [TextWeight: Double]) -> TextReading.WeightBallot {
        TextReading.WeightBallot(size: size, color: RGBA(hex: hex) ?? RGBA(r: 0, g: 0, b: 0),
                                 agreement: agreement)
    }

    /// The row labels of the settings pane fixture, with the numbers the
    /// reader actually produced on them (`ReadRunAsTextFixtureTests`). Two of
    /// the six say Medium and say it confidently, by more than
    /// `distinctMargin`, and all six are the same weight in the picture.
    private var sixRowLabels: [TextReading.WeightBallot] {
        [ballot(12.85, "#111111", [.regular: 0.720, .medium: 0.795, .semibold: 0.733, .bold: 0.5]),
         ballot(13.17, "#111111", [.regular: 0.660, .medium: 0.719, .semibold: 0.697, .bold: 0.5]),
         ballot(13.03, "#111111", [.regular: 0.903, .medium: 0.806, .semibold: 0.605, .bold: 0.4]),
         ballot(13.00, "#111111", [.regular: 0.866, .medium: 0.787, .semibold: 0.704, .bold: 0.4]),
         ballot(12.85, "#111111", [.regular: 0.722, .medium: 0.681, .semibold: 0.650, .bold: 0.4]),
         ballot(12.85, "#111111", [.regular: 0.718, .medium: 0.652, .semibold: 0.676, .bold: 0.4])]
    }

    @Test func sixRowLabelsOfOnePaneComeBackAtOneWeight() throws {
        // The bug, in numbers: read one at a time these come back four Regular
        // and two Medium, and they are identical on screen.
        let settled = TextReading.pageWeights(of: sixRowLabels.map { $0 })
        #expect(settled == [TextWeight](repeating: .regular, count: 6).map { $0 })
    }

    @Test func aHeadingOverItsRowsIsNotDraggedDownToThem() throws {
        // The thing a page-wide vote would break. The heading is half again
        // the size of the rows, so it is not a label of their kind and its own
        // answer stands.
        let heading = ballot(23.63, "#111111",
                             [.regular: 0.60, .medium: 0.782, .semibold: 0.836, .bold: 0.920])
        let settled = TextReading.pageWeights(of: ([heading] + sixRowLabels).map { $0 })
        #expect(settled.first == .bold)
        #expect(settled.dropFirst().allSatisfy { $0 == .regular })
    }

    @Test func aSectionLabelIsNotDraggedDownToTheRowsUnderIt() throws {
        // The app's own Effects panel, measured: "Corner Radius", "Border 1"
        // and "Border 2" are white and the Style/Color/Position rows under
        // them are grey, at the same size. Ink colour is what tells a person
        // they are not the same kind of label, and it is what tells the app.
        let sections = [
            ballot(10.37, "#EAEAEB", [.regular: 0.60, .medium: 0.693, .semibold: 0.723]),
            ballot(10.55, "#EAEAEB", [.regular: 0.691, .medium: 0.715, .semibold: 0.652]),
            ballot(10.37, "#EAEAEB", [.regular: 0.683, .medium: 0.732, .semibold: 0.708]),
        ]
        // Every grey row of the two Border sections, with the numbers the
        // reader produced: five say Regular, four say Medium and two say
        // Semibold, and they are one weight on screen.
        let rows = [
            ballot(10.00, "#7C7C7C", [.regular: 0.779, .medium: 0.725, .semibold: 0.608]),
            ballot(10.00, "#7C7C7C", [.regular: 0.779, .medium: 0.725, .semibold: 0.608]),
            ballot(10.37, "#7C7C7C", [.regular: 0.691, .medium: 0.602, .semibold: 0.517]),
            ballot(10.37, "#7C7C7C", [.regular: 0.690, .medium: 0.602, .semibold: 0.517]),
            ballot(9.93, "#7C7C7C", [.regular: 0.703, .medium: 0.738, .semibold: 0.656]),
            ballot(9.93, "#7C7C7C", [.regular: 0.703, .medium: 0.738, .semibold: 0.656]),
            ballot(9.93, "#7C7C7C", [.regular: 0.724, .medium: 0.772, .semibold: 0.745]),
            ballot(10.37, "#7C7C7C", [.regular: 0.660, .medium: 0.570, .semibold: 0.468]),
            ballot(9.90, "#7C7C7C", [.regular: 0.768, .medium: 0.771, .semibold: 0.808]),
            ballot(10.29, "#7C7C7C", [.regular: 0.690, .medium: 0.701, .semibold: 0.737]),
            ballot(10.29, "#7C7C7C", [.regular: 0.809, .medium: 0.821, .semibold: 0.820]),
        ]
        let settled = TextReading.pageWeights(of: (sections + rows).map { $0 })
        // Each group settles, and they settle on DIFFERENT weights: the
        // section labels stay heavier than their rows.
        #expect(Set(settled.prefix(3)).count == 1)
        #expect(Set(settled.dropFirst(3)).count == 1)
        #expect(settled.first != settled.last)
    }

    @Test func aColourAPixelOrTwoOffIsTheSameColour() throws {
        // Ink colour is a median of sampled pixels, so one label reads #EAEAEB
        // and the identical one beside it #E8E8E8. Those are one colour.
        let a = ballot(10.40, "#EAEAEB", [.regular: 0.60, .medium: 0.70])
        let b = ballot(10.40, "#E8E8E8", [.regular: 0.68, .medium: 0.60])
        let settled = TextReading.pageWeights(of: [a, b])
        #expect(settled[0] == settled[1])
    }

    @Test func aRunWithNothingLikeItKeepsItsOwnAnswer() throws {
        // One label of its size and colour on the whole page: there is no
        // second opinion to have, so the run's own reading stands.
        let lone = ballot(30, "#0000FF", [.regular: 0.64, .medium: 0.70, .bold: 0.81])
        let settled = TextReading.pageWeights(of: (sixRowLabels + [lone]).map { $0 })
        #expect(settled.last == .bold)
    }

    @Test func aRunNobodyCouldReadCastsNoVoteAndGetsNoAnswer() throws {
        var ballots: [TextReading.WeightBallot?] = sixRowLabels.map { $0 }
        ballots.insert(nil, at: 2)
        let settled = TextReading.pageWeights(of: ballots)
        #expect(settled.count == 7)
        #expect(settled[2] == nil)
        #expect(settled.compactMap { $0 }.allSatisfy { $0 == .regular })
    }

    @Test func theCohortIsTheOneWithTheMostAgreementNotTheMostHands() throws {
        // Three runs. Two of them pick Medium by a whisker and the third picks
        // Regular by a mile, and Regular is what the three of them agree on
        // best. A show of hands would throw that away.
        let ballots = [
            ballot(12, "#000000", [.regular: 0.700, .medium: 0.705]),
            ballot(12, "#000000", [.regular: 0.700, .medium: 0.706]),
            ballot(12, "#000000", [.regular: 0.900, .medium: 0.600]),
        ]
        #expect(TextReading.pageWeights(of: ballots.map { $0 })
            == [TextWeight.regular, .regular, .regular])
    }

    @Test func labelsOfEverySizeOnAPageDoNotBecomeOneCohort() throws {
        // Sizes stepping up a little at a time, from a row label to a title.
        // Each is close to its neighbour, and a rule that only looked at
        // neighbours would chain the whole page into one cohort and set a
        // title in body weight.
        let ballots = (0..<12).map { step in
            ballot(10 * pow(1.03, CGFloat(step)), "#111111",
                   [.regular: step < 6 ? 0.9 : 0.5, .medium: 0.6,
                    .bold: step < 6 ? 0.5 : 0.9])
        }
        let settled = TextReading.pageWeights(of: ballots.map { $0 })
        #expect(settled.first == .regular)
        #expect(settled.last == .bold)
    }

    @Test func aWeightOnlySomeOfThemCouldBeSetInDoesNotWinOnTheirScoresAlone() throws {
        // Only a weight every run in the cohort was scored against can be the
        // answer, or a weight two runs of six happen to do well in takes the
        // page on two numbers.
        let ballots = [
            ballot(12, "#000000", [.regular: 0.70, .medium: 0.65]),
            ballot(12, "#000000", [.regular: 0.70, .medium: 0.65]),
            ballot(12, "#000000", [.regular: 0.60, .medium: 0.65, .bold: 0.99]),
        ]
        #expect(TextReading.pageWeights(of: ballots.map { $0 })
            == [TextWeight.regular, .regular, .regular])
    }

    @Test func nobodyOnThePageMeansNobodyToAnswerFor() throws {
        #expect(TextReading.pageWeights(of: []).isEmpty)
        #expect(TextReading.pageWeights(of: [nil, nil]) == [nil, nil])
    }

    // MARK: - Setting a run at the weight its kind of label is in

    @Test func theRunTakesItsCohortsWeightEvenWhenAnotherScoredHigher() throws {
        // "Launch at login" on the settings pane: on its own it says Medium
        // 0.795 against Regular's 0.720, and the five labels beside it, which
        // are the same weight on screen, say Regular.
        let regular = TextReading.Face(fontName: "SF Pro", weight: .regular)
        let outcome = TextReading.decide(
            string: "Launch at login",
            scores: [TextReading.Scored(face: sfMedium, fontSize: 12.7, agreement: 0.795),
                     TextReading.Scored(face: regular, fontSize: 12.85, agreement: 0.720)],
            color: RGBA(r: 0, g: 0, b: 0), preferring: "SF Pro", at: .regular)
        let reading = try #require(outcome.reading)
        #expect(reading.face == regular)
        // The page answered, not the run, and the audit is told which.
        #expect(reading.provenance == .fallback)
    }

    @Test func aRunAlreadyInItsCohortsWeightIsUnchangedByBeingHeldToIt() throws {
        let regular = TextReading.Face(fontName: "SF Pro", weight: .regular)
        let outcome = TextReading.decide(
            string: "Reset",
            scores: [TextReading.Scored(face: regular, fontSize: 13, agreement: 0.923),
                     TextReading.Scored(face: sfMedium, fontSize: 12.8, agreement: 0.846)],
            color: RGBA(r: 0, g: 0, b: 0), preferring: "SF Pro", at: .regular)
        #expect(outcome.reading?.face == regular)
        #expect(outcome.reading?.provenance == .matched)
    }

    @Test func aRunItsCohortsWeightCannotAccountForRefusesRatherThanGuessing() throws {
        let regular = TextReading.Face(fontName: "SF Pro", weight: .regular)
        let outcome = TextReading.decide(
            string: "Border 1",
            scores: [TextReading.Scored(face: sfSemibold, fontSize: 10, agreement: 0.80),
                     TextReading.Scored(face: regular, fontSize: 10.4, agreement: 0.31)],
            color: RGBA(r: 0, g: 0, b: 0), preferring: "SF Pro", at: .regular)
        #expect(outcome.refusal == .noFaceMatches)
    }
}
