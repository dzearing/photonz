import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The plate a label sits on when it has to be read over a picture nobody
/// chose: the measure chip's rule, now shared with the canvas name chips.
@Suite("Label plate")
struct LabelPlateTests {

    @Test("A plate is dark enough that white reads on it, whatever colour it came from")
    func whiteAlwaysReads() {
        // The colours that used to break a label: the component violet, the
        // starter Accent blue a button is painted in, a bright yellow accent,
        // and white itself.
        for hex in ["#9A5CFF", "#3B7DF5", "#FFD60A", "#FFFFFF", "#000000", "#FF3B30"] {
            let plate = LabelPlate.tone(from: RGBA(hex: hex)!)
            let reading = ContrastReading(of: RGBA(hex: LabelPlate.inkHex)!, on: plate)
            #expect(reading.ratio >= 4.5,
                    "white on the plate for \(hex) reads at \(reading.ratioText)")
        }
    }

    @Test("The component violet's plate reads comfortably above the body-text bar")
    func componentPlateRatio() {
        let plate = LabelPlate.tone(from: RGBA(hex: ComponentPaint.violetHex)!)
        let reading = ContrastReading(of: RGBA(hex: LabelPlate.inkHex)!, on: plate)
        // The number the audit quotes. Pinned so a nudge to either colour has
        // to face it.
        #expect(reading.ratio >= 9.0)
        #expect(reading.grade == .aaa)
    }

    @Test("A plate keeps the hue it came from, so it still says which kind of thing this is")
    func plateKeepsItsHue() {
        let violet = RGBA(hex: ComponentPaint.violetHex)!
        let plate = LabelPlate.tone(from: violet)
        #expect(abs(plate.hsl.hue - violet.hsl.hue) < 2)
        #expect(plate.relativeLuminance < violet.relativeLuminance)
    }

    @Test("The measure caption chip is the same rule, so the two labels stay one treatment")
    func captionChipUsesTheSameRule() {
        let arrow = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        #expect(arrow.captionChipColor.hexString == LabelPlate.tone(from: RGBA(hex: "#FF3B30")!).hexString)
    }
}
