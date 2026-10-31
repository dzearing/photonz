import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The chip an arrow's caption sits on: ten premade styles, one colour that
/// tints it, a marker, and a plate that is always derived so the words read.
/// The rules are `docs/design/markup.md`; the design system's
/// `markup.js` (`PZ.markup.plateFor`) computes the same plate, and the two
/// must agree to the hex digit.
@Suite("Chip styles")
struct ChipStyleTests {

    // MARK: The plate rule, against markup.md's table

    @Test("The plate for every palette ink matches markup.md to the hex digit",
          arguments: [
              ("#ff375f", "#D62E50", "#FFFFFF", 4.8),
              ("#0a84ff", "#0970D9", "#FFFFFF", 4.8),
              ("#bf5af2", "#9F4BC9", "#FFFFFF", 4.9),
              ("#ff9f0a", "#FF9F0A", "#1D1D1F", 8.2),
              ("#30d158", "#30D158", "#1D1D1F", 8.3),
              ("#ffd60a", "#FFD60A", "#1D1D1F", 11.9),
              ("#ffffff", "#FFFFFF", "#1D1D1F", 16.8),
              ("#1d1d1f", "#1D1D1F", "#FFFFFF", 16.8),
          ])
    func plateTable(ink: String, plate: String, words: String, contrast: Double) {
        let reading = InkPlate.reading(forInk: ink)
        #expect(reading.plateHex == plate)
        #expect(reading.onPlateHex == words)
        #expect((reading.contrast * 10).rounded() / 10 == contrast)
    }

    @Test("Ink-coloured words on a white plate reach 4.5:1 for every palette ink")
    func inkTextOnWhite() {
        for ink in InkPlate.palette {
            let reading = InkPlate.reading(forInk: ink)
            let words = RGBA(hex: reading.inkTextHex)!
            #expect(InkPlate.contrast(words, RGBA(r: 1, g: 1, b: 1)) >= 4.5, "\(ink)")
        }
    }

    // MARK: The set

    @Test("Ten styles with the ids the design system uses, all with names")
    func tenStyles() {
        #expect(ChipStyle.allCases.map(\.rawValue) == [
            "today", "solid", "squircle", "hairline", "glass",
            "paper", "spec", "tag", "twotone", "highlight",
        ])
        #expect(Set(ChipStyle.allCases.map(\.title)).count == 10)
        #expect(ChipStyle.allCases.allSatisfy { !$0.help.isEmpty && $0.help.count <= 60 })
        #expect(ChipMarker.allCases.map(\.rawValue) == ["none", "accent", "error", "warning", "success", "info"])
    }

    @Test("No two styles draw the same chip: each differs in shape, plate, edge or finish")
    func stylesAreDistinct() {
        let looks = ChipStyle.allCases.map { style in
            ChipLook.resolve(style: style, ink: "#ff375f", marker: .accent)
        }
        for i in looks.indices {
            for j in looks.indices where j > i {
                #expect(looks[i].signature != looks[j].signature,
                        "\(ChipStyle.allCases[i]) and \(ChipStyle.allCases[j]) draw alike")
            }
        }
    }

    // MARK: Legibility

    /// The four backdrops the acceptance names: white, black, a busy photo
    /// (its brightest, darkest and two mid tones) and a saturated colour.
    static let backdrops: [(String, RGBA)] = [
        ("white", RGBA(r: 1, g: 1, b: 1)),
        ("black", RGBA(r: 0, g: 0, b: 0)),
        ("photo light", RGBA(hex: "#E8DCC8")!),
        ("photo mid", RGBA(hex: "#7A8C6E")!),
        ("photo dark", RGBA(hex: "#2B2F36")!),
        ("saturated", RGBA(hex: "#00C2FF")!),
        ("saturated red", RGBA(hex: "#FF2D2D")!),
    ]

    @Test("Every style's words read at 4.5:1 or better on its plate, for every ink and every backdrop")
    func everyStyleReads() {
        for style in ChipStyle.allCases {
            for ink in InkPlate.palette {
                let look = ChipLook.resolve(style: style, ink: ink, marker: .accent)
                for (name, back) in Self.backdrops {
                    let ratio = look.wordContrast(over: back)
                    #expect(ratio >= 4.5, "\(style) \(ink) over \(name): \(ratio)")
                }
            }
        }
    }

    // MARK: Markers

    @Test("A status marker keeps its meaning colour: a white disc on an ink plate, a coloured disc elsewhere")
    func markerColours() {
        let solid = ChipLook.resolve(style: .solid, ink: "#0a84ff", marker: .error)
        #expect(solid.marker?.disc.hexString == "#FFFFFF")
        #expect(solid.marker?.glyph.hexString == "#FF3B30")
        let paper = ChipLook.resolve(style: .paper, ink: "#0a84ff", marker: .warning)
        #expect(paper.marker?.disc.hexString == "#FFCC00")
        #expect(paper.marker?.glyph.hexString == "#1D1D1F")
        let onSolidWarning = ChipLook.resolve(style: .solid, ink: "#0a84ff", marker: .warning)
        #expect(onSolidWarning.marker?.glyph.hexString == "#FF9500")
        // A marker other than Accent takes the stripe or dot away.
        #expect(paper.accent == nil)
        #expect(ChipLook.resolve(style: .paper, ink: "#0a84ff", marker: .accent).accent != nil)
        #expect(ChipLook.resolve(style: .paper, ink: "#0a84ff", marker: .none).accent == nil)
        // None and Accent draw no icon.
        #expect(ChipLook.resolve(style: .solid, ink: "#0a84ff", marker: .none).marker == nil)
        #expect(ChipLook.resolve(style: .solid, ink: "#0a84ff", marker: .accent).marker == nil)
    }

    @Test("A marker or accent makes room for itself at the front of the chip")
    func markerLead() {
        #expect(ChipLook.resolve(style: .solid, ink: "#0a84ff", marker: .accent).lead == 0)
        #expect(ChipLook.resolve(style: .solid, ink: "#0a84ff", marker: .info).lead > 0)
        #expect(ChipLook.resolve(style: .spec, ink: "#0a84ff", marker: .accent).lead > 0)
        #expect(ChipLook.resolve(style: .twotone, ink: "#0a84ff", marker: .none).lead == 0)
        #expect(ChipLook.resolve(style: .twotone, ink: "#0a84ff", marker: .none).tab == nil)
    }

    // MARK: On the arrow

    private func captioned(_ hex: String = "#FF3B30") -> AnnotationContent {
        var a = AnnotationContent(shape: .arrow, colorHex: hex,
                                  start: .zero, end: CGPoint(x: 100, y: 0))
        a.caption = "Hello"
        return a
    }

    @Test("An arrow captioned before chip styles opens with no style and draws exactly its stored colours")
    func olderDocumentKeepsItsPill() throws {
        var a = captioned()
        a.captionFill = Paint(hex: "#123456")
        let data = try JSONEncoder().encode(a)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("chipStyle"))
        let back = try JSONDecoder().decode(AnnotationContent.self, from: data)
        #expect(back.chipStyle == nil)
        #expect(back.chipMarker == .accent)
        #expect(back.captionFill?.hex == "#123456")
        // Recolouring a legacy arrow leaves its pill alone, as it always has.
        var recoloured = back
        recoloured.colorHex = "#0A84FF"
        #expect(recoloured.captionFill?.hex == "#123456")
    }

    @Test("Picking a style paints the chip from the arrow's colour, saves, and reopens the same")
    func pickAndRoundTrip() throws {
        var a = captioned("#0a84ff")
        a.applyChipStyle(.paper)
        #expect(a.chipStyle == .paper)
        #expect(a.captionFill?.hex == "#FFFFFD")
        #expect(a.captionTextHex == "#1D1D1F")
        #expect(a.captionBorder == nil)
        a.chipMarker = .warning
        let back = try JSONDecoder().decode(AnnotationContent.self, from: JSONEncoder().encode(a))
        #expect(back == a)
        // The words and colour are untouched by a style change.
        a.applyChipStyle(.solid)
        #expect(a.caption == "Hello")
        #expect(a.colorHex.uppercased() == "#0A84FF")
        #expect(a.captionFill?.hex == "#0970D9")
    }

    @Test("One colour tints the chip: recolouring a styled arrow re-derives its plate")
    func colourTintsTheChip() {
        var a = captioned("#ff375f")
        a.applyChipStyle(.solid)
        #expect(a.captionFill?.hex == "#D62E50")
        a.colorHex = "#30d158"
        #expect(a.captionFill?.hex == "#30D158")
        #expect(a.captionTextHex == "#1D1D1F")
    }

    @Test("A chip part set by hand stays set through a style or colour change until it is reset")
    func byHandStays() {
        var a = captioned("#ff375f")
        a.applyChipStyle(.solid)
        a.setCaptionPartByHand(.fill, hex: "#222222")
        a.colorHex = "#0a84ff"
        #expect(a.captionFill?.hex == "#222222")
        a.applyChipStyle(.squircle)
        #expect(a.captionFill?.hex == "#222222")
        a.resetCaptionPartsByHand()
        #expect(a.captionFill?.hex == "#0970D9")
    }

    @Test("A style sets the chip's corner, and a legacy pill picking a style keeps parts it had changed")
    func legacyPick() {
        var a = captioned("#ff375f")
        a.captionTextColorHex = "#FFEE00"   // changed by hand before styles existed
        a.applyChipStyle(.squircle)
        #expect(a.captionTextHex == "#FFEE00")
        #expect(a.captionPartsByHand == [.text])
        #expect(abs(a.captionRoundness - ChipStyle.squircle.roundness) < 0.001)
    }

    @Test("A style with a bigger shadow reserves more room round the chip, so it never clips")
    func shadowSlack() {
        var a = captioned()
        #expect(a.captionShadowSlack == AnnotationContent.captionShadowPadding)
        a.applyChipStyle(.paper)
        #expect(a.captionShadowSlack >= AnnotationContent.captionShadowPadding)
        a.applyChipStyle(.squircle)
        #expect(a.captionShadowSlack == AnnotationContent.captionShadowPadding)
    }

    @Test("The pill grows by the marker's room, and the words move over by the same")
    func pillMakesRoomForTheMarker() {
        var a = captioned()
        a.applyChipStyle(.solid)
        let plain = a.captionPillSize(forTextSize: CGSize(width: 80, height: 24))
        a.chipMarker = .info
        let marked = a.captionPillSize(forTextSize: CGSize(width: 80, height: 24))
        #expect(marked.width > plain.width)
        #expect(marked.height == plain.height)
        #expect(a.estimatedCaptionSize.width >= marked.width)
    }

    @Test("Restyling a built arrow's chip repaints its label and rebuilds its frame")
    func rechippedLayer() throws {
        var content = AnnotationContent(shape: .arrow, colorHex: "#FF3B30")
        content.caption = "Save button 48 pt"
        content.applyChipStyle(.solid)
        let layer = AnnotationBuilder.layer(content: content, from: CGPoint(x: 600, y: 600),
                                            to: CGPoint(x: 900, y: 400))
        let paper = AnnotationBuilder.rechipped(layer, style: .paper)
        #expect(paper.annotation?.chipStyle == .paper)
        #expect(paper.annotation?.captionFill?.hex == "#FFFFFD")
        let marked = AnnotationBuilder.rechipped(paper, marker: .warning)
        #expect(marked.annotation?.chipMarker == .warning)
        #expect(marked.frame.width >= paper.frame.width)
    }

    // MARK: Any colour, against the design system's own answers

    /// markup.js's answers for 5,472 colours (every 5 degrees of hue, four
    /// saturations, nineteen lightnesses), written by
    /// `Scripts/markup-plate-fixture.cjs`.
    static func sweep() throws -> [[String]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/design/markup-plate-sweep.tsv")
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n").dropFirst().map { $0.split(separator: "\t").map(String.init) }
    }

    @Test("The plate, its words, ink text and Glass tint agree with markup.js to the hex digit for 5,472 colours")
    func sweepAgreesWithTheDesignSystem() throws {
        let rows = try Self.sweep()
        #expect(rows.count == 5_472)
        var disagreements: [String] = []
        for row in rows where row.count == 6 {
            let r = InkPlate.reading(forInk: row[0])
            let mine = [r.plateHex, r.onPlateHex, r.inkTextHex, r.glassHex, r.onGlassHex]
            if mine != row[1...].map({ $0.uppercased() }) { disagreements.append("\(row) vs \(mine)") }
        }
        #expect(disagreements.isEmpty, "\(disagreements.count): \(disagreements.prefix(3))")
    }

    @Test("Every chip style keeps its words at 4.5:1 or better for all 5,472 colours, over white and black")
    func sweepIsLegibleInEveryStyle() throws {
        let rows = try Self.sweep()
        let backs = [RGBA(r: 1, g: 1, b: 1), RGBA(r: 0, g: 0, b: 0)]
        var worst: [ChipStyle: Double] = [:]
        for row in rows {
            let reading = InkPlate.reading(forInk: row[0])
            for style in ChipStyle.allCases {
                let look = ChipLook.resolve(style: style, ink: row[0], marker: .accent, reading: reading)
                let ratio = backs.map { look.wordContrast(over: $0) }.min() ?? 0
                worst[style] = min(worst[style] ?? 99, ratio)
            }
        }
        for style in ChipStyle.allCases {
            #expect((worst[style] ?? 0) >= 4.5, "\(style): worst \(worst[style] ?? 0)")
        }
    }

    @Test("Glass's tint for the palette is the design system's")
    func glassPalette() {
        #expect(InkPlate.reading(forInk: "#ff375f").glassHex == "#AD2541")
        #expect(InkPlate.reading(forInk: "#0a84ff").glassHex == "#5BADFF")
        #expect(InkPlate.reading(forInk: "#0a84ff").onGlassHex == "#1D1D1F")
        #expect(InkPlate.reading(forInk: "#bf5af2").glassHex == "#D28CF6")
    }
}
