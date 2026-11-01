import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// The finish of the four chip styles a blind judge scored under the
/// professional bar on 2026-10-31 (Glass 4, Spec badge 6, Lit tag 6,
/// Highlighter 4), held to what each was reworked to fix. The judge's words
/// are on each test; the look itself is `docs/design/markup.md` section 4.
@Suite("Chip style finish")
struct ChipStyleFinishTests {

    private func look(_ style: ChipStyle, _ ink: String = "#ff375f",
                      marker: ChipMarker = .accent) -> ChipLook {
        ChipLook.resolve(style: style, ink: ink, marker: marker)
    }

    // MARK: Glass: "muddy over light pictures, the photo shows through"

    @Test("Glass is lit like glass: a rim bright at the top and catching light again at the bottom, and a sheen along its top")
    func glassLit() throws {
        let rim = try #require(look(.glass).rim)
        #expect(!rim.diagonal)
        let top = try #require(rim.stops.first), bottom = try #require(rim.stops.last)
        let middle = rim.stops.map(\.alpha).min() ?? 1
        #expect(top.alpha >= 0.5)
        #expect(bottom.alpha >= 0.2 && bottom.alpha > middle)
        #expect(look(.glass).sheen >= 0.1)
    }

    @Test("Glass is light frosted glass on every picture: see-through, lifted, dark words")
    func glassSeeThrough() throws {
        for ink in InkPlate.palette {
            let glass = look(.glass, ink)
            #expect((glass.fillTop?.a ?? 1) <= 0.5, "\(ink)")
            let frost = try #require(glass.frost)
            #expect(frost.lifts && frost.veil(0) >= 0.7 && frost.blur > 0, "\(ink)")
            #expect(glass.text.hexString.uppercased() == InkPlate.darkWordsHex, "\(ink)")
        }
        #expect(look(.solid).frost == nil)
    }

    @Test("Glass holds its edge on a white picture with a hairline ring, so it never smears into it")
    func glassRinged() {
        #expect(look(.glass).ringAlpha >= 0.1)
    }

    // MARK: Spec badge: "monospace reads like a terminal, nearly vanishes on dark UI"

    @Test("Spec badge sets its words in the system face, full size, not monospaced")
    func specProportional() {
        var a = AnnotationContent(shape: .arrow, colorHex: "#0A84FF", start: .zero, end: CGPoint(x: 100, y: 0))
        a.caption = "12 pt"
        a.applyChipStyle(.spec)
        #expect(a.captionFontName == "SF Pro")
        #expect(a.captionTypeSize == a.captionFontSize)
        #expect(a.captionFontWeight == .semibold)
    }

    @Test("Spec badge's light inner edge goes all the way round, so it stands off a dark window")
    func specEdgeAllRound() throws {
        let rim = try #require(look(.spec).rim)
        #expect(rim.stops.allSatisfy { $0.alpha >= 0.12 }, "\(rim.stops)")
        // Its graphite is a step lighter than a dark window's own rows (#2C2C2E).
        let plate = try #require(look(.spec).fillBottom)
        let row = RGBA(hex: "#2C2C2E")!
        #expect(InkPlate.contrast(plate, row) >= 1.15)
    }

    // MARK: Lit tag: kept as approved (a bevel and a glow both judged worse)

    @Test("Lit tag keeps the approved look: a lit fill, small square corners, a grey shadow, no glow")
    func tagAsApproved() {
        let tag = look(.tag)
        #expect(tag.fillTop != tag.fillBottom)
        #expect(tag.innerHighlight > 0 && tag.edge == nil)
        #expect(ChipStyle.allCases.allSatisfy { style in look(style).shadows.allSatisfy { $0.color == nil } })
        #expect(ChipStyle.tag.roundness < ChipStyle.squircle.roundness)
    }

    // MARK: Highlighter: "the band reads as misaligned"

    @Test("Highlighter's band is level and covers the whole line of words, a hair past each end, inside the plate")
    func highlightLevel() throws {
        let hl = look(.highlight)
        let rect = CGRect(x: 100, y: 50, width: 160, height: 26)
        let layout = hl.layout(in: rect, fontSize: 12, padding: 7)
        let swipe = try #require(layout.swipe)
        #expect(swipe.count == 4)
        #expect(swipe[0].y == swipe[1].y && swipe[2].y == swipe[3].y)
        #expect(swipe[0].x == swipe[3].x && swipe[1].x == swipe[2].x)
        // Words run from the padding to the padding; the band overhangs them
        // by a hair, and stays inside the plate.
        #expect(swipe[0].x < rect.minX + 7 && swipe[0].x > rect.minX)
        #expect(swipe[1].x > rect.maxX - 7 && swipe[1].x < rect.maxX)
        // From above the capitals to below the descenders: the whole line.
        #expect(swipe[2].y - swipe[0].y >= 12 * 1.05)
        #expect(swipe[0].y > rect.minY && swipe[2].y < rect.maxY)
        #expect(abs((swipe[0].y + swipe[2].y) / 2 - rect.midY) < 0.01)
    }

    // MARK: Still readable

    @Test("The reworked styles keep every palette ink at 4.5:1 or better over white and black")
    func stillLegible() {
        let white = RGBA(r: 1, g: 1, b: 1), black = RGBA(r: 0, g: 0, b: 0)
        for style in [ChipStyle.glass, .spec, .tag, .highlight] {
            for ink in InkPlate.palette {
                let l = look(style, ink)
                #expect(l.wordContrast(over: white) >= 4.5, "\(style) \(ink) over white")
                #expect(l.wordContrast(over: black) >= 4.5, "\(style) \(ink) over black")
            }
        }
    }
}
