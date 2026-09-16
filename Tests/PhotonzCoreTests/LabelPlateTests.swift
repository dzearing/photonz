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

    @Test("A screen's plate reads white at least as well as a component's")
    func screenPlateRatio() {
        let ink = RGBA(hex: LabelPlate.inkHex)!
        let screen = ContrastReading(of: ink, on: LabelPlate.tone(from: RGBA(hex: ScreenPaint.greyHex)!))
        let component = ContrastReading(
            of: ink, on: LabelPlate.tone(from: RGBA(hex: ComponentPaint.violetHex)!))
        // The number the component chip's audit quotes. A screen's name sits
        // beside a component's on the same canvas, so it may not be the
        // shabbier of the two.
        #expect(screen.ratio >= 9.9, "white on a screen's plate reads at \(screen.ratioText)")
        #expect(screen.ratio >= component.ratio)
        #expect(screen.grade == .aaa)
    }

    @Test("A screen's plate is grey, so it never reads as a component")
    func screenPlateIsGrey() {
        let plate = LabelPlate.tone(from: RGBA(hex: ScreenPaint.greyHex)!)
        // A screen has no colour of its own; the one thing its plate must not
        // do is borrow a hue somebody could mistake for the component violet.
        #expect(plate.hsl.saturation < 0.08)
    }

    @Test("The screen plate and the component plate are the same weight of chip")
    func bothPlatesReadAsOneFamily() {
        let screen = LabelPlate.tone(from: RGBA(hex: ScreenPaint.greyHex)!)
        let component = LabelPlate.tone(from: RGBA(hex: ComponentPaint.violetHex)!)
        // Two pills on one canvas, one grey and one violet: they say different
        // things by hue, never by one of them being visibly heavier.
        #expect(abs(screen.wcagLuminance - component.wcagLuminance) < 0.02)
    }
}
