import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Measure tool modes")
struct MeasureToolModeTests {

    @Test func distanceIsTheOnlyModeThatDrawsNothingUnderThePointer() {
        // The whole reason Distance is the default: with the tool picked up and
        // the pointer moving, the canvas stays untouched until you act.
        #expect(!MeasureToolMode.distance.previewsUnderPointer)
        #expect(MeasureToolMode.size.previewsUnderPointer)
        #expect(MeasureToolMode.gap.previewsUnderPointer)
        #expect(!MeasureToolMode.alignment.previewsUnderPointer)
    }

    @Test func sizeAndGapCommitOnASingleClick() {
        #expect(MeasureToolMode.size.commitsOnClick)
        #expect(MeasureToolMode.gap.commitsOnClick)
        #expect(!MeasureToolMode.distance.commitsOnClick)
        #expect(!MeasureToolMode.alignment.commitsOnClick)
    }

    @Test func onlySizePicksAmongCandidates() {
        #expect(MeasureToolMode.size.picksAmongCandidates)
        #expect(!MeasureToolMode.gap.picksAmongCandidates)
        #expect(!MeasureToolMode.distance.picksAmongCandidates)
    }

    // MARK: The tool button owns its modes (D15)

    @Test func everyModeHasItsOwnGlyphSoTheToolButtonCanSayWhatItWillDo() {
        // The bar shows the live mode as a glyph and nothing else, so two modes
        // sharing a symbol would make the button lie about what a click does.
        let symbols = MeasureToolMode.allCases.map(\.symbol)
        #expect(Set(symbols).count == MeasureToolMode.allCases.count)
        #expect(symbols.allSatisfy { !$0.isEmpty })
        // Distance keeps the ruler: it is the tool's own identity and the default.
        #expect(MeasureToolMode.distance.symbol == "ruler")
    }

    @Test func theToolKeyCyclesForwardThroughTheOfferedModes() {
        #expect(MeasureToolMode.distance.cycled(alignmentEnabled: false) == .size)
        #expect(MeasureToolMode.size.cycled(alignmentEnabled: false) == .gap)
        #expect(MeasureToolMode.gap.cycled(alignmentEnabled: false) == .distance)
    }

    @Test func cyclingReachesAlignmentOnlyWhenItIsOffered() {
        #expect(MeasureToolMode.gap.cycled(alignmentEnabled: true) == .alignment)
        #expect(MeasureToolMode.alignment.cycled(alignmentEnabled: true) == .distance)
    }

    @Test func cyclingOutOfAModeThatIsNoLongerOfferedLandsOnTheDefault() {
        // Alignment can be switched off underneath a session that is sitting in
        // it. The key must still do something sane rather than stick.
        #expect(MeasureToolMode.alignment.cycled(alignmentEnabled: false) == .distance)
    }

    @Test func thePickerAlwaysOffersTheThreeMeasuringModes() {
        // The current mode has to be visible at all times, so the three real
        // measuring modes are never behind a flag. Alignment checks rather than
        // measures, and stays gated on its own.
        #expect(MeasureToolMode.available(alignmentEnabled: false) == [.distance, .size, .gap])
        #expect(MeasureToolMode.available(alignmentEnabled: true)
                == [.distance, .size, .gap, .alignment])
    }

    @Test func distanceIsFirstSoItReadsAsTheDefault() {
        #expect(MeasureToolMode.available(alignmentEnabled: true).first == .distance)
    }

    @Test func everyModeSaysWhatAClickDoes() {
        for mode in MeasureToolMode.allCases {
            #expect(!mode.title.isEmpty)
            #expect(mode.help.hasPrefix(mode.title))
            #expect(!mode.hint.isEmpty)
            // No em dashes in user-facing copy.
            #expect(!mode.help.contains("—"))
            #expect(!mode.hint.contains("—"))
        }
    }

    @Test func aGapPreviewCanBorrowTheSpacingInkWithoutChangingTheRememberedRole() {
        // Gap mode commits a Spacing callout, so its preview has to be drawn in
        // Spacing ink — but picking up the Gap mode must not rewrite what the
        // NEXT plain caliper starts from.
        var styles = MeasureStyles()
        styles.role = .size
        let spacing = styles.content(for: .spacing)
        #expect(spacing.role == .spacing)
        #expect(spacing.strokeColorHex == styles.colors(for: .spacing).strokeColorHex)
        #expect(styles.role == .size)
        #expect(styles.content.role == .size)
    }

    @Test func aModePlacedCaliperStandsOffFarEnoughForItsReadoutToClear() {
        // A 24 px gap with a 90 px readout parked on it tells you nothing about
        // which gap you measured, so the modes that place their own calipers
        // reach past half the chip before drawing the head line.
        var content = MeasureContent(mode: .horizontal, decimals: 0)
        content.start = CGPoint(x: 100, y: 200)
        content.end = CGPoint(x: 124, y: 200)
        let reach = MeasureBuilder.clearingHeadOffset(content: content,
                                                      from: content.start, to: content.end)
        #expect(reach >= content.estimatedLabelSize.height / 2)
        #expect(reach > MeasureContent.defaultHeadOffset)

        // A vertical caliper clears the chip's WIDTH, which is the bigger of the
        // two, so it stands off further.
        var vertical = content
        vertical.mode = .vertical
        vertical.start = CGPoint(x: 100, y: 200)
        vertical.end = CGPoint(x: 100, y: 224)
        let verticalReach = MeasureBuilder.clearingHeadOffset(content: vertical,
                                                              from: vertical.start, to: vertical.end)
        #expect(verticalReach >= vertical.estimatedLabelSize.width / 2)
        #expect(verticalReach > reach)
    }

    @Test func theReachNeverDropsBelowTheStandardOne() {
        // A tiny label must not pull the head in tighter than a hand-placed
        // caliper's default reach, or mode-made measurements would look
        // different from the ones you draw yourself.
        var content = MeasureContent(mode: .horizontal, labelScale: 0.5)
        content.start = .zero
        content.end = CGPoint(x: 4, y: 0)
        #expect(MeasureBuilder.clearingHeadOffset(content: content,
                                                  from: content.start, to: content.end)
                >= MeasureContent.defaultHeadOffset)
    }

    /// The margin outside an element is where a redliner expects the number,
    /// so a head that cannot reach its full standoff shortens to fit rather
    /// than doubling back over the thing it is measuring.
    @Test func aHeadShortReachesIntoTheMarginBeforeItGivesUpAndFlips() {
        var content = MeasureContent(mode: .vertical, decimals: 0)
        // The settings capture: a card edge at x 1376 on a 1440 wide image, so
        // there are 64 px of margin — not the full standoff, but enough.
        let feet = (CGPoint(x: 1376, y: 148), CGPoint(x: 1376, y: 236))
        content.start = feet.0
        content.end = feet.1
        let canvas = CGSize(width: 1440, height: 960)
        let offset = MeasureBuilder.clearingHeadOffset(content: content, from: feet.0, to: feet.1,
                                                       canvas: canvas)
        #expect(offset > 0, "the head stayed outward instead of flipping over the element")
        var placed = content
        placed.headOffset = offset
        let chip = placed.labelRect(chipSize: placed.estimatedLabelSize)
        #expect(CGRect(origin: .zero, size: canvas).contains(chip),
                "the readout hangs off the canvas: \(chip)")
    }

    /// The same on the bottom edge, where a width caliper reaches down.
    @Test func aBottomEdgeHeadShortensToKeepTheReadoutOnTheImage() {
        var content = MeasureContent(mode: .horizontal, decimals: 0)
        let feet = (CGPoint(x: 600, y: 900), CGPoint(x: 800, y: 900))
        content.start = feet.0
        content.end = feet.1
        let canvas = CGSize(width: 1440, height: 960)
        let offset = MeasureBuilder.clearingHeadOffset(content: content, from: feet.0, to: feet.1,
                                                       canvas: canvas)
        #expect(offset > 0)
        var placed = content
        placed.headOffset = offset
        #expect(CGRect(origin: .zero, size: canvas)
            .contains(placed.labelRect(chipSize: placed.estimatedLabelSize)))
    }

    /// A shortened head is still a head: it never collapses onto the feet, or
    /// the caliper stops reading as a caliper.
    @Test func aShortenedHeadStaysFarEnoughOutToReadAsACaliper() {
        var content = MeasureContent(mode: .vertical, decimals: 0)
        let feet = (CGPoint(x: 1376, y: 148), CGPoint(x: 1376, y: 236))
        content.start = feet.0
        content.end = feet.1
        let offset = MeasureBuilder.clearingHeadOffset(content: content, from: feet.0, to: feet.1,
                                                       canvas: CGSize(width: 1440, height: 960))
        #expect(abs(offset) >= MeasureBuilder.minimumClearingReach)
    }

    @Test func theHeadFlipsRatherThanHangTheReadoutOffTheCanvas() {
        // An element hard against the right edge: reaching right would put the
        // readout half outside the image, so it goes left instead.
        var content = MeasureContent(mode: .vertical, decimals: 0)
        let feet = (CGPoint(x: 990, y: 100), CGPoint(x: 990, y: 160))
        content.start = feet.0
        content.end = feet.1
        let canvas = CGSize(width: 1000, height: 800)
        let offset = MeasureBuilder.clearingHeadOffset(content: content, from: feet.0, to: feet.1,
                                                       canvas: canvas)
        #expect(offset < 0)
        // With room on the right it reaches outward as usual.
        let roomy = (CGPoint(x: 400, y: 100), CGPoint(x: 400, y: 160))
        #expect(MeasureBuilder.clearingHeadOffset(content: content, from: roomy.0, to: roomy.1,
                                                  canvas: canvas) > 0)
    }
}
