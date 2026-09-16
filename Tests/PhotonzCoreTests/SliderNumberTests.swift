import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

@Suite("The number a slider's readout is typed as")
struct SliderNumberTests {

    // MARK: A length

    @Test("A length is typed in the app's one unit word, in whole points")
    func lengthIsWholePoints() {
        let length = SliderNumber.points
        #expect(length.suffix == DocumentUnit.word)
        #expect(length.wholeNumbers)
        #expect(length.shown(12) == 12)
        #expect(length.slid(12) == 12)
        #expect(length.spell(12) == "12")
        #expect(length.spell(12.6) == "13")
    }

    // MARK: A strength

    @Test("A strength slides nought to one and is typed nought to a hundred")
    func strengthIsTypedAsAPercentage() {
        let strength = SliderNumber.percent
        #expect(strength.suffix == "%")
        #expect(strength.shown(0.35) == 35)
        #expect(strength.slid(35) == 0.35)
        #expect(strength.spell(strength.shown(0.35)) == "35")
    }

    @Test("The ends of a strength's slider are the ends of its box")
    func strengthEndsMatch() {
        let strength = SliderNumber.percent
        #expect(strength.shown(0) == 0)
        #expect(strength.shown(1) == 100)
    }

    // MARK: A turn

    @Test("A turn is whole degrees")
    func turnIsWholeDegrees() {
        #expect(SliderNumber.degrees.suffix == "\u{00B0}")
        #expect(SliderNumber.degrees.wholeNumbers)
        #expect(SliderNumber.degrees.spell(89.5) == "90")
    }

    // MARK: A multiple

    @Test("A multiple keeps one decimal place and wears its sign in front")
    func multipleKeepsOneDecimal() {
        let times = SliderNumber.times
        #expect(times.leading == "\u{00D7}")
        #expect(times.suffix == nil)
        #expect(!times.wholeNumbers)
        #expect(times.spell(1.5) == "1.5")
        #expect(times.spell(2) == "2.0")
        #expect(times.shown(2.5) == 2.5)
        #expect(times.slid(2.5) == 2.5)
    }

    // MARK: What a person reads

    @Test("What a person reads is the number and the unit beside it")
    func readoutPutsTheNumberAndItsUnitBackTogether() {
        #expect(SliderNumber.points.readout(12) == "12 \(DocumentUnit.word)")
        #expect(SliderNumber.percent.readout(35) == "35 %")
        #expect(SliderNumber.degrees.readout(45) == "45 \u{00B0}")
        #expect(SliderNumber.times.readout(1.5) == "\u{00D7}1.5")
    }

    // MARK: Round tripping

    @Test("What is shown goes back to what the slider holds")
    func showingAndSlidingAreOpposites() {
        for number in [SliderNumber.points, .percent, .degrees, .times] {
            for value in [CGFloat(0), 0.5, 1, 12.25, 40] {
                #expect(abs(number.slid(number.shown(value)) - value) < 0.0001)
            }
        }
    }
}
