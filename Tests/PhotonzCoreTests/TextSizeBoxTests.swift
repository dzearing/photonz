import CoreGraphics
import Testing
@testable import PhotonzCore

/// The Size box in the Text section: a number you type or nudge, with the
/// preset sizes one click away on the same box.
@Suite("Text size box")
struct TextSizeBoxTests {

    @Test func oneSizeShowsAsAWholeNumberWithNoUnit() {
        // The mock's box reads "28", the unit is not part of what you type.
        #expect(TextStyles.sizeShowing(StyleReading(value: 28, isMixed: false)) == .number("28"))
        #expect(TextStyles.sizeShowing(StyleReading(value: 24.6, isMixed: false)) == .number("25"))
    }

    @Test func sizesThatDisagreeShowTheWordMixed() {
        let showing = TextStyles.sizeShowing(StyleReading(value: 24, isMixed: true))
        #expect(showing == .standIn(MixedValue.text))
        #expect(showing.isMixed)
    }

    @Test func nothingPickedShowsAnEmptyBox() {
        #expect(TextStyles.sizeShowing(StyleReading<CGFloat>(value: nil, isMixed: false)) == .nothing)
    }

    @Test func aTypedSizeLandsAsTyped() {
        let landing = NumberBox.landing(draft: "37", showing: .number("24"), canClear: false,
                                        floor: TextStyles.smallestSize,
                                        ceiling: TextStyles.largestSize, wholeNumbers: true)
        #expect(landing == .land(37))
    }

    @Test func aTypedSizeIsHeldInsideWhatTypeCanBe() {
        let tooBig = NumberBox.landing(draft: "5000", showing: .number("24"), canClear: false,
                                       floor: TextStyles.smallestSize,
                                       ceiling: TextStyles.largestSize, wholeNumbers: true)
        #expect(tooBig == .land(TextStyles.largestSize))
        let nought = NumberBox.landing(draft: "0", showing: .number("24"), canClear: false,
                                       floor: TextStyles.smallestSize,
                                       ceiling: TextStyles.largestSize, wholeNumbers: true)
        #expect(nought == .land(TextStyles.smallestSize))
    }

    @Test func theLimitsHoldEveryPresetAndAThreeDigitSize() {
        for size in TextStyles.fontSizes + [TextStyles.threeDigitSizeForPlaytest] {
            #expect((TextStyles.smallestSize...TextStyles.largestSize).contains(size))
        }
        // Three digits at most, so the box never has to grow for a fourth.
        #expect(TextStyles.largestSize < 1000)
    }

    @Test func emptyingTheBoxPutsTheSizeBack() {
        let landing = NumberBox.landing(draft: "", showing: .number("24"), canClear: false,
                                        floor: TextStyles.smallestSize,
                                        ceiling: TextStyles.largestSize, wholeNumbers: true)
        #expect(landing == .putBack)
    }

    @Test func thePresetListIsThePresetsWhenThePickWearsOne() {
        #expect(TextStyles.sizeOptions(picked: [24]) == TextStyles.fontSizes)
        #expect(TextStyles.sizeOptions(picked: []) == TextStyles.fontSizes)
    }

    @Test func aSizeOffTheListJoinsItInOrderSoItCanBeTicked() {
        let options = TextStyles.sizeOptions(picked: [37, 24, 128])
        #expect(options == [14, 18, 24, 32, 37, 48, 64, 96, 128])
    }
}
