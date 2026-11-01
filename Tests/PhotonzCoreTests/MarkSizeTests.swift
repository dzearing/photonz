import CoreGraphics
import Testing
@testable import PhotonzCore

/// S, M and L for an arrow's or a measurement's chip (markup.md section 7):
/// the chip's type size and padding, and an arrow's line weight unless its
/// Thickness was set by hand.
@Suite struct MarkSizeTests {

    @Test func typeSizesAreTheSpecimensAtTheirScale() {
        #expect(MarkSize.small.specimenPoints == 10.5)
        #expect(MarkSize.medium.specimenPoints == 12)
        #expect(MarkSize.large.specimenPoints == 14)
        #expect(MarkSize.medium.typeScale == 1)
        #expect(abs(MarkSize.small.typeScale - 10.5 / 12) < 0.0001)
        #expect(abs(MarkSize.large.typeScale - 14.0 / 12) < 0.0001)
        #expect(MarkSize.allCases.map(\.title) == ["S", "M", "L"])
    }

    @Test func aNewArrowIsMedium() {
        let a = AnnotationContent(shape: .arrow, caption: "Save")
        #expect(a.markSize == .medium)
        #expect(a.thicknessFollowsSize)
        #expect(!a.headSizeByHand)
    }

    @Test func sizeSetsTheChipTypeAndPaddingAndTheLine() {
        var a = AnnotationContent(shape: .arrow, caption: "Save")
        let mediumPadding = a.captionPadding
        a.applyMarkSize(.large)
        #expect(a.markSize == .large)
        #expect(abs(a.captionFontSize - AnnotationContent.captionFontSizeDefault * 14 / 12) < 0.0001)
        #expect(a.captionPadding > mediumPadding)
        #expect(a.strokeWidth == MarkSize.large.arrowThickness)
        a.applyMarkSize(.small)
        #expect(a.markSize == .small)
        #expect(a.strokeWidth == MarkSize.small.arrowThickness)
        #expect(a.captionPadding < mediumPadding)
    }

    @Test func thicknessSetByHandOverridesSize() {
        var a = AnnotationContent(shape: .arrow, caption: "Save")
        a.strokeWidth = 9
        #expect(!a.thicknessFollowsSize)
        a.applyMarkSize(.large)
        #expect(a.strokeWidth == 9)
        #expect(a.markSize == .large)
        a.resetThicknessToSize()
        #expect(a.strokeWidth == MarkSize.large.arrowThickness)
        #expect(a.thicknessFollowsSize)
    }

    @Test func headSizeSetByHandIsKeptAndResets() {
        var a = AnnotationContent(shape: .arrow)
        a.arrowheadScale = 2
        #expect(a.headSizeByHand)
        a.applyMarkSize(.small)
        #expect(a.arrowheadScale == 2)
        a.resetHeadSize()
        #expect(!a.headSizeByHand)
    }

    @Test func aChipTypedAtAnOddSizeShowsNoSize() {
        var a = AnnotationContent(shape: .arrow, caption: "Save")
        a.captionFontSize = 31
        #expect(a.markSize == nil)
        // With no size lit, a thickness that is one of the three still counts
        // as following, so the first S, M or L moves it.
        #expect(a.thicknessFollowsSize)
    }

    @Test func theHeadFollowsTheLineUntilPaintedApart() {
        var a = AnnotationContent(shape: .arrow, caption: "Save")
        #expect(!a.headByHand)
        a.setInk("#0A84FF")
        #expect(a.headColorHex == "#0A84FF")
        a.headColorHex = "#30D158"
        #expect(a.headByHand)
        a.setInk("#BF5AF2")
        #expect(a.headColorHex == "#30D158")
        a.resetHeadToLine()
        #expect(!a.headByHand)
        #expect(a.headColorHex == "#BF5AF2")
        a.setInk("#FF9F0A")
        #expect(a.headColorHex == "#FF9F0A")
    }

    @Test func eachChipPartSaysWhetherItWasSetByHand() {
        var a = AnnotationContent(shape: .arrow, caption: "Save")
        a.applyChipStyle(.solid)
        #expect(a.captionPartsByHand.isEmpty)
        a.setCaptionPartByHand(.fill, hex: "#000000")
        a.setInk("#0A84FF")
        #expect(a.captionFill?.hex == "#000000")
        #expect(a.captionPartsByHand == [.fill])
        a.resetCaptionPartsByHand([.fill])
        #expect(a.captionPartsByHand.isEmpty)
        #expect(a.captionFill?.hex != "#000000")
    }

    @Test func aMeasurementTakesTheSameSizesOnItsChipAlone() {
        var m = MeasureContent(start: .zero, end: CGPoint(x: 100, y: 0), mode: .horizontal)
        #expect(m.markSize == .medium)
        let width = m.strokeWidth
        m.applyMarkSize(.large)
        #expect(m.markSize == .large)
        #expect(abs(m.labelScale - 14.0 / 12) < 0.0001)
        #expect(abs(m.labelPointSize - MeasureContent.labelFontSize * 14 / 12) < 0.0001)
        // A redline's hairline stays the hairline it was.
        #expect(m.strokeWidth == width)
        m.labelScale = 2
        #expect(m.markSize == nil)
    }

    @Test func aMeasurementChipPartPaintedByHandIsKnownEvenOnThePillFromBeforeStyles() {
        let look = MeasureContent(start: .zero, end: CGPoint(x: 100, y: 0), mode: .horizontal)
        var m = look
        #expect(m.chipStyle == nil)
        m.setChipPartByHand(.fill, hex: "#FF0000")
        #expect(m.chipPartsByHand == [.fill])
        #expect(m.chipColorHex.uppercased() == "#FF0000")
        // The pill keeps its look: painting one part does not restyle it.
        #expect(m.chipStyle == nil)
        #expect(m.textColorHex == look.textColorHex)
        m.resetChipPart(.fill, toLookOf: look)
        #expect(m.chipPartsByHand.isEmpty)
        #expect(m.chipColorHex == look.chipColorHex)
        #expect(m.chipOpacity == look.chipOpacity)
    }

    @Test func aStyledMeasurementChipPartResetsToTheStyle() {
        var m = MeasureContent(start: .zero, end: CGPoint(x: 100, y: 0), mode: .horizontal)
        m.applyChipStyle(.solid)
        let derived = m.textColorHex
        m.setChipPartByHand(.text, hex: "#00FF00")
        #expect(m.chipPartsByHand == [.text])
        m.resetChipPart(.text, toLookOf: MeasureContent())
        #expect(m.chipPartsByHand.isEmpty)
        #expect(m.textColorHex == derived)
    }
}
