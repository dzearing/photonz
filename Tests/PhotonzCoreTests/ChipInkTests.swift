import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// One Color for the whole mark, any colour at all, and the chip's words stay
/// readable without a trip into Advanced (`docs/design/markup.md` sections 2,
/// 3 and 8).
@Suite("Any colour picked for an arrow keeps its chip's words readable")
struct ChipInkTests {

    private func captioned(_ hex: String = "#FF3B30", style: ChipStyle? = .solid) -> AnnotationContent {
        var a = AnnotationContent(shape: .arrow, colorHex: hex, start: .zero, end: CGPoint(x: 100, y: 0))
        a.caption = "Save button 48 pt"
        if let style { a.applyChipStyle(style) }
        return a
    }

    // MARK: One colour

    @Test("Picking a colour retints the line, the head and the chip at once")
    func oneColourTintsEverything() {
        var a = captioned("#FF3B30", style: .solid)
        a.setInk("#7FD18B")
        #expect(a.colorHex.uppercased() == "#7FD18B")
        #expect(a.headColorHex.uppercased() == "#7FD18B")
        let derived = ChipStyle.solid.parts(forInk: "#7FD18B")
        #expect(a.captionFill?.hex.uppercased() == derived.fill?.uppercased())
        #expect(a.captionTextHex.uppercased() == derived.text.uppercased())
    }

    @Test("A head painted apart from its line keeps its colour when the one Color changes")
    func headPaintedApartStays() {
        var a = captioned("#8E8E93")
        a.headColorHex = "#FF3B30"
        a.setInk("#0A84FF")
        #expect(a.colorHex.uppercased() == "#0A84FF")
        #expect(a.headColorHex.uppercased() == "#FF3B30")
    }

    @Test("A gradient line given one flat Color becomes that colour, head and all")
    func gradientBecomesFlat() {
        var a = captioned("#FF3B30")
        var ramp = Paint(hex: "#FF3B30")
        ramp.kind = .linear
        a.paint = ramp
        a.headPaint = ramp
        a.setInk("#5E5CE6")
        #expect(a.paint.kind == .solid)
        #expect(a.headPaint == a.paint)
    }

    @Test("The arrow layer takes the one Color and keeps its ends where they were")
    func layerKeepsItsEnds() throws {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = "Hello"
        content.applyChipStyle(.glass)
        let layer = AnnotationBuilder.layer(content: content, from: CGPoint(x: 40, y: 50), to: CGPoint(x: 240, y: 120))
        let inked = AnnotationBuilder.reinked(layer, "#3A2E8F")
        let a = try #require(inked.annotation)
        #expect(a.colorHex.uppercased() == "#3A2E8F")
        #expect(a.headColorHex.uppercased() == "#3A2E8F")
        #expect(inked.annotationEndpoint(.start) == layer.annotationEndpoint(.start))
        #expect(inked.annotationEndpoint(.end) == layer.annotationEndpoint(.end))
    }

    // MARK: Readable without Advanced

    @Test("Any of 5,472 colours reads at 4.5:1 in this chip style, with no warning",
          arguments: ChipStyle.allCases)
    func anyColourReads(style: ChipStyle) throws {
        // The design system's own sweep: every 5 degrees of hue, four
        // saturations, nineteen lightnesses (`Scripts/markup-plate-fixture.cjs`).
        let sweep = try ChipStyleTests.sweep().map { $0[0] }
        #expect(sweep.count == 5_472)
        var worst = (99.0, "")
        var a = captioned("#FF3B30", style: style)
        for ink in sweep {
            a.setInk(ink)
            let ratio = a.captionWordContrast ?? 0
            if ratio < worst.0 { worst = (ratio, ink) }
        }
        // The warning is this same reading under 4.5, so none fires.
        #expect(worst.0 >= 4.5, "\(style): worst \(worst.0) at \(worst.1)")
        a.setInk(worst.1)
        #expect(a.captionLegibilityNote == nil)
    }

    // MARK: A part painted by hand

    @Test("Words painted by hand that fall under 4.5:1 are called out, and one step puts the automatic colour back")
    func handPaintedWordsWarnAndRestore() {
        var a = captioned("#0A84FF", style: .solid)
        a.setCaptionPartByHand(.text, hex: "#4A90E2")
        #expect((a.captionWordContrast ?? 99) < 4.5)
        #expect(a.captionLegibilityNote != nil)
        #expect(a.canRestoreAutomaticChip)
        a.restoreAutomaticChip()
        #expect(a.captionPartsByHand.isEmpty)
        #expect(a.captionLegibilityNote == nil)
        #expect(a.captionTextHex.uppercased() == ChipStyle.solid.parts(forInk: "#0A84FF").text.uppercased())
    }

    @Test("A fill painted by hand on Glass that loses the words is called out")
    func glassFillByHand() {
        // Blue takes dark words on a lightened tint; a dark fill painted
        // under them loses them.
        var a = captioned("#0A84FF", style: .glass)
        #expect(a.captionLegibilityNote == nil)
        a.setCaptionPartByHand(.fill, hex: "#2C2C2E")
        #expect(a.captionLegibilityNote != nil)
    }

    @Test("The warning is short enough for a panel row")
    func warningIsALabel() {
        var a = captioned("#0A84FF", style: .solid)
        a.setCaptionPartByHand(.text, hex: "#0A84FF")
        let note = a.captionLegibilityNote ?? ""
        #expect(!note.isEmpty)
        #expect(note.count <= 40)
        #expect(!note.contains("\u{2014}"))
    }

    @Test("A pill from before chip styles with unreadable colours comes back readable in one step")
    func legacyPillRestores() {
        var a = captioned("#FF3B30", style: nil)
        a.captionFill = Paint(hex: "#FFFFFF")
        #expect(a.captionLegibilityNote != nil)
        #expect(a.canRestoreAutomaticChip)
        a.restoreAutomaticChip()
        #expect(a.captionLegibilityNote == nil)
        #expect(a.chipStyle == .today)
    }

    @Test("With its fill switched off the words are judged against nothing, so nothing is said")
    func noFillSaysNothing() {
        var a = captioned("#FF3B30", style: .solid)
        a.setCaptionPartByHand(.fill, hex: nil)
        #expect(a.captionWordContrast == nil)
        #expect(a.captionLegibilityNote == nil)
    }

    @Test("An automatic chip has nothing to restore")
    func automaticHasNothingToRestore() {
        #expect(!captioned("#30D158", style: .paper).canRestoreAutomaticChip)
    }
}
