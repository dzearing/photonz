import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A measurement's readout wears the same ten chip styles, the same one Color
/// and the same marker as an arrow's label (`docs/design/markup.md`), so a
/// redline is one system.
@Suite("A measurement's chip wears the arrow label's styles")
struct MeasureChipStyleTests {

    private func gap(_ ink: String = "#3774D5") -> MeasureContent {
        MeasureContent(start: CGPoint(x: 40, y: 100), end: CGPoint(x: 140, y: 100),
                       strokeWidth: 2, strokeColorHex: ink, chipColorHex: "#233963",
                       chipOpacity: 1, textColorHex: "#FFFFFF")
    }

    // MARK: Older documents

    @Test("A measurement saved before chip styles opens with no style and saves without one")
    func olderDocumentsAreUntouched() throws {
        let old = gap()
        let data = try JSONEncoder().encode(old)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("chipStyle"))
        #expect(!json.contains("chipMarker"))
        #expect(!json.contains("chipPartsByHand"))
        let back = try JSONDecoder().decode(MeasureContent.self, from: data)
        #expect(back.chipStyle == nil)
        #expect(back.chipLook == nil)
        #expect(back == old)
    }

    @Test("A style, a marker and a part painted by hand survive a save")
    func styleSurvivesASave() throws {
        var m = gap()
        m.applyChipStyle(.paper)
        m.chipMarker = .warning
        m.setChipPartByHand(.text, hex: "#112233")
        let back = try JSONDecoder().decode(MeasureContent.self, from: JSONEncoder().encode(m))
        #expect(back.chipStyle == .paper)
        #expect(back.chipMarker == .warning)
        #expect(back.chipPartsByHand == [.text])
        #expect(back == m)
    }

    // MARK: Painting from the ink

    @Test("Every style paints the chip from the caliper's ink", arguments: ChipStyle.allCases)
    func styleDerivesFromTheInk(style: ChipStyle) {
        var m = gap("#30D158")
        m.applyChipStyle(style)
        let parts = style.parts(forInk: "#30D158")
        #expect(m.chipStyle == style)
        #expect(m.strokeColorHex == "#30D158", "the caliper keeps the ink as picked")
        #expect(m.textColorHex.uppercased() == parts.text.uppercased())
        if let fill = parts.fill {
            #expect(m.chipColorHex.uppercased() == fill.uppercased())
            #expect(m.chipOpacity == 1)
        } else {
            #expect(!m.hasChipFill)
        }
        if let edge = parts.edge {
            #expect(m.hasChipBorder)
            #expect(m.chipBorderColorHex.uppercased() == edge.uppercased())
        } else {
            #expect(!m.hasChipBorder, "a style with no edge draws no ring")
        }
    }

    @Test("One Color retints the caliper and the chip together")
    func oneColourRetintsBoth() {
        var m = gap()
        m.applyChipStyle(.solid)
        m.setInk("#FF9F0A")
        let parts = ChipStyle.solid.parts(forInk: "#FF9F0A")
        #expect(m.strokeColorHex == "#FF9F0A")
        #expect(m.chipColorHex.uppercased() == parts.fill?.uppercased())
        #expect(m.textColorHex.uppercased() == parts.text.uppercased())
    }

    @Test("One Color on a chip from before styles puts it on Today, the look it already wears")
    func oneColourOnAnOldChip() {
        var m = gap()
        m.setInk("#BF5AF2")
        #expect(m.chipStyle == .today)
        let parts = ChipStyle.today.parts(forInk: "#BF5AF2")
        #expect(m.chipColorHex.uppercased() == parts.fill?.uppercased())
        #expect(m.chipBorderColorHex.uppercased() == parts.edge?.uppercased())
    }

    @Test("A part painted by hand keeps its colour through a style and a colour change")
    func handPaintedPartStays() {
        var m = gap()
        m.applyChipStyle(.solid)
        m.setChipPartByHand(.text, hex: "#FFD60A")
        m.applyChipStyle(.tag)
        m.setInk("#0A84FF")
        #expect(m.textColorHex == "#FFD60A")
        m.resetChipPartsByHand()
        #expect(m.textColorHex.uppercased() == ChipStyle.tag.parts(forInk: "#0A84FF").text.uppercased())
    }

    @Test("Painting a chip part on its row marks it as set by hand")
    func partRowMarksByHand() {
        var m = gap()
        m.applyChipStyle(.solid)
        var layer = MeasureBuilder.layer(content: m, from: m.start, to: m.end)
        layer.setColorHex("#123456", for: .chipText)
        #expect(layer.measure?.chipPartsByHand == [.text])
        layer.setColorHex("#00FF00", for: .caliper)
        #expect(layer.measure?.textColorHex == "#123456", "a part set by hand ignores the ink")
        #expect(layer.measure?.chipColorHex.uppercased()
                == ChipStyle.solid.parts(forInk: "#00FF00").fill?.uppercased(),
                "the rest of the chip follows the caliper's new ink")
    }

    // MARK: Legibility

    @Test("Every style keeps the words at 4.5:1 for every palette colour", arguments: ChipStyle.allCases)
    func everyStyleReads(style: ChipStyle) throws {
        for ink in InkPlate.palette {
            var m = gap(ink)
            m.applyChipStyle(style)
            let ratio = try #require(m.chipWordContrast)
            #expect(ratio >= 4.5, "\(style) in \(ink): \(ratio)")
            #expect(m.chipLegibilityNote == nil)
        }
    }

    @Test("Words painted by hand under 4.5:1 warn, and Reset Colors brings them back")
    func handPaintedWordsWarn() {
        var m = gap("#0A84FF")
        m.applyChipStyle(.solid)
        m.setChipPartByHand(.text, hex: "#4A90E2")
        #expect(m.chipLegibilityNote == "Words are hard to read on this chip")
        #expect(m.canRestoreAutomaticChip)
        m.restoreAutomaticChip()
        #expect(m.chipLegibilityNote == nil)
        #expect(m.chipPartsByHand.isEmpty)
    }

    // MARK: Shape and room

    @Test("The chip's corners are the style's own, and the line stops on that outline")
    func cornersAreTheStyles() {
        var m = gap()
        let size = CGSize(width: 80, height: 40)
        #expect(m.chipCornerRadius(for: size) == 20, "the pill from before styles is a capsule")
        m.applyChipStyle(.tag)
        #expect(abs(m.chipCornerRadius(for: size) - 20 * ChipStyle.tag.roundness) < 0.001)
        let plan = MeasurePlan.make(m, geometry: m.caliperGeometry(), chipSize: size)
        #expect(abs((plan.pill?.radius ?? 0) - 20 * ChipStyle.tag.roundness) < 0.001)
        m.applyChipStyle(.squircle)
        let squircle = MeasurePlan.make(m, geometry: m.caliperGeometry(), chipSize: size)
        #expect(squircle.pill?.continuous == true)
    }

    @Test("A marker makes room at the chip's front, in the reservation too")
    func markerMakesRoom() {
        var m = gap()
        m.applyChipStyle(.solid)
        m.chipMarker = .none
        let plain = m.estimatedLabelSize.width
        #expect(m.chipLeadWidth == 0)
        m.chipMarker = .warning
        #expect(m.chipLeadWidth > 0)
        #expect(m.estimatedLabelSize.width >= plain + m.chipLeadWidth - 1)
    }

    @Test("A style whose shadow reaches further reserves room for it")
    func shadowHasRoom() {
        var m = gap()
        let before = m.chipRenderPadding
        m.applyChipStyle(.paper)
        #expect(m.chipRenderPadding > before)
    }

    @Test("A styled chip sets its words semibold; the pill from before styles keeps regular ones")
    func weight() {
        var m = gap()
        #expect(m.chipFontWeight == .regular)
        m.applyChipStyle(.hairline)
        #expect(m.chipFontWeight == .semibold)
    }

    @Test("Only Glass frosts the picture behind it")
    func onlyGlassFrosts() {
        var m = gap()
        #expect(!m.drawsFrostedChip)
        #expect(!LayerContent.measure(m).readsBackdrop)
        m.applyChipStyle(.glass)
        #expect(m.drawsFrostedChip)
        #expect(LayerContent.measure(m).readsBackdrop)
    }

    // MARK: The next measurement

    @Test("The tool remembers a style and marker, and the next measurement wears them")
    func nextMeasurementWearsIt() throws {
        var styles = MeasureStyles()
        #expect(styles.chipStyle == nil)
        #expect(styles.content.chipStyle == nil, "until a style is picked, the look stays as it was")
        var picked = gap(styles.colors.strokeColorHex)
        picked.applyChipStyle(.paper)
        picked.chipMarker = .warning
        styles.absorb(picked)
        #expect(styles.chipStyle == .paper)
        #expect(styles.chipMarker == .warning)
        let next = styles.content(for: .spacing)
        #expect(next.chipStyle == .paper)
        #expect(next.chipMarker == .warning)
        #expect(next.chipColorHex.uppercased()
                == ChipStyle.paper.parts(forInk: styles.colors.strokeColorHex).fill?.uppercased())
        let back = try JSONDecoder().decode(MeasureStyles.self, from: JSONEncoder().encode(styles))
        #expect(back.chipStyle == .paper)
        #expect(back.chipMarker == .warning)
    }

    @Test("A remembered style from before chip styles reads as none")
    func olderMemory() throws {
        let data = try JSONEncoder().encode(MeasureStyles())
        var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "chipStyle")
        json.removeValue(forKey: "chipMarker")
        let back = try JSONDecoder().decode(MeasureStyles.self,
                                            from: JSONSerialization.data(withJSONObject: json))
        #expect(back.chipStyle == nil)
        #expect(back.chipMarker == .accent)
    }

    @Test("A style change keeps the feet where they were")
    func feetStay() throws {
        let m = gap()
        let layer = MeasureBuilder.layer(content: m, from: CGPoint(x: 40, y: 100), to: CGPoint(x: 140, y: 100))
        let styled = MeasureBuilder.rechipped(layer) { $0.applyChipStyle(.paper); $0.chipMarker = .warning }
        #expect(styled.measureEndpoint(.start) == layer.measureEndpoint(.start))
        #expect(styled.measureEndpoint(.end) == layer.measureEndpoint(.end))
        #expect(styled.measure?.chipStyle == .paper)
    }
}
