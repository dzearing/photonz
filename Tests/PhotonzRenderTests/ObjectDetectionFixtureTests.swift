import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Size mode on buttons and cards (the user, 2026-10-13: "the size tool's edge
/// detection is great for text but hoooooorible for just objects. For example,
/// i select this button, and it will NOT measure the width /height of the
/// button. it just chooses whatever i select.").
///
/// Two fixtures:
///
/// - `download-pill-2x.png`, a crop of the user's own capture of the Photonz
///   download page (3456 x 2234 at 2x, cropped at 1000, 840). The pill's fill
///   runs x 492...1039, y 270...394 in the crop, measured pixel by pixel: 548 x
///   125 px, a purple gradient with a purple glow under it.
/// - `objects-1x.png` and `objects-2x.png`, drawn by
///   `Scripts/make-objects-fixture.swift` with known geometry, in points:
///
/// | specimen | rect (pt) | what makes it hard |
/// | --- | --- | --- |
/// | A gradient pill | 40, 40, 240 x 56 | wider than 160, a purple glow |
/// | B teal button | 60, 160, 200 x 40 | wider than 160 |
/// | C dark button | 20, 250, 280 x 48 | barely off a near black page |
/// | D red button | 380, 60, 200 x 40 | as bright as its grey page |
/// | E card | 360, 180, 240 x 100 | a soft drop shadow |
/// | F blue pill | 340, 320, 280 x 44 | a gradient and a blue glow |
///
/// Before this reader, hovering any of A, B, D, E or F read nothing or a piece
/// of it, and a rough box round the pill kept the box as drawn.
@Suite("Object detection on buttons, pills and cards")
struct ObjectDetectionFixtureTests {

    private static func analyze(_ name: String) -> EdgeMapAnalyzer.Analysis {
        guard let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data) else { return .empty }
        return EdgeMapAnalyzer.analyzeFully(image)
    }

    private static let pill = analyze("download-pill-2x")
    private static let objects1x = analyze("objects-1x")
    private static let objects2x = analyze("objects-2x")

    /// The pill's fill in the crop, in image px.
    static let pillRect = CGRect(x: 492, y: 270, width: 548, height: 125)

    /// The specimens, in points.
    static let specimens: [(name: String, rect: CGRect)] = [
        ("A gradient pill with a glow", CGRect(x: 40, y: 40, width: 240, height: 56)),
        ("B teal button", CGRect(x: 60, y: 160, width: 200, height: 40)),
        ("C dark button", CGRect(x: 20, y: 250, width: 280, height: 48)),
        ("D red button as bright as its page", CGRect(x: 380, y: 60, width: 200, height: 40)),
        ("E card with a shadow", CGRect(x: 360, y: 180, width: 240, height: 100)),
        ("F blue pill with a glow", CGRect(x: 340, y: 320, width: 280, height: 44)),
    ]

    /// The Size mode ladder at an image point, asked for as the app asks.
    static func ladder(_ p: CGPoint, in a: EdgeMapAnalyzer.Analysis, scale: Double) -> [CGRect] {
        ElementBounds.candidates(at: p, in: a.edges, luma: a.luma,
                                 minElement: max(10, 10 * scale), textGap: 8 * scale,
                                 readsShapes: true)
    }

    /// What a box snaps to, asked for as the app asks.
    static func snap(_ box: CGRect, in a: EdgeMapAnalyzer.Analysis, scale: Double) -> CGRect? {
        ObjectBounds.snap(box, field: a.luma, slack: 4 * scale, link: 4 * scale,
                          minElement: 4 * scale)
    }

    private func expectEdges(_ rect: CGRect?, _ expected: CGRect, within: CGFloat, _ what: String,
                             sourceLocation: SourceLocation = #_sourceLocation) {
        guard let rect else {
            Issue.record("\(what): expected \(expected), got nothing", sourceLocation: sourceLocation)
            return
        }
        let ok = abs(rect.minX - expected.minX) <= within && abs(rect.minY - expected.minY) <= within
            && abs(rect.maxX - expected.maxX) <= within && abs(rect.maxY - expected.maxY) <= within
        if !ok {
            Issue.record("\(what): expected \(expected), got \(rect)", sourceLocation: sourceLocation)
        }
    }

    private static func px(_ r: CGRect, _ s: Double) -> CGRect {
        CGRect(x: r.minX * s, y: r.minY * s, width: r.width * s, height: r.height * s)
    }

    @Test func theFixturesAreTheOnesTheseNumbersAreFor() {
        #expect(Self.pill.luma.width == 1560)
        #expect(Self.pill.luma.height == 600)
        #expect(Self.objects1x.luma.width == 640)
        #expect(Self.objects2x.luma.width == 1280)
    }

    // MARK: The user's pill

    @Test func hoveringTheUsersPillReadsThePillFromItsFill() {
        for p in [CGPoint(x: 520, y: 330), CGPoint(x: 1000, y: 300), CGPoint(x: 760, y: 385)] {
            expectEdges(Self.ladder(p, in: Self.pill, scale: 2).first, Self.pillRect, within: 2,
                        "hover at \(p)")
        }
    }

    @Test func hoveringThePillsLabelOffersThePill() {
        // On a letter of "Download for Mac".
        let ladder = Self.ladder(CGPoint(x: 690, y: 330), in: Self.pill, scale: 2)
        #expect(ladder.contains { abs($0.width - 548) <= 2 && abs($0.height - 125) <= 2 },
                "ladder \(ladder)")
    }

    @Test func onThePillsLabelThePillIsWhereTheLadderStartsAndTheLabelIsOneStepDown() {
        let a = Self.pill
        // On the fill between letters, and on a letter itself (the w).
        for p in [CGPoint(x: 700, y: 335), CGPoint(x: 640, y: 335)] {
            let at = ElementBounds.ladder(at: p, in: a.edges, luma: a.luma, minElement: 20, textGap: 16,
                                          readsShapes: true)
            expectEdges(at.rung(0), Self.pillRect, within: 2, "the pill from \(p): \(at)")
        }
        let found = ElementBounds.ladder(at: CGPoint(x: 690, y: 330), in: a.edges, luma: a.luma,
                                         minElement: 20, textGap: 16, readsShapes: true)
        expectEdges(found.rung(0), Self.pillRect, within: 2, "the pill")
        // One `[` down: the words "Download for Mac", inside the pill.
        guard let label = found.rung(-1) else {
            Issue.record("no label rung in \(found)")
            return
        }
        #expect(Self.pillRect.contains(label) && label.width < 400 && label.height < 60, "\(found)")
    }

    @Test func aRoughBoxRoundTheUsersPillSnapsToThePill() {
        // The box the user drew, 300 x 86 points, round the pill and over the
        // top of the line of small print under it.
        let box = CGRect(x: 462, y: 242, width: 600, height: 172)
        expectEdges(Self.snap(box, in: Self.pill, scale: 2), Self.pillRect, within: 2, "user's box")
        // A looser one that takes in the whole line of small print as well.
        let loose = CGRect(x: 440, y: 230, width: 650, height: 240)
        expectEdges(Self.snap(loose, in: Self.pill, scale: 2), Self.pillRect, within: 2, "loose box")
    }

    // MARK: Specimens, 1x and 2x

    @Test(arguments: [1, 2])
    func hoveringEachSpecimensFillReadsIt(scale: Int) {
        let a = scale == 1 ? Self.objects1x : Self.objects2x
        let s = Double(scale)
        for (name, rect) in Self.specimens {
            // Near its left end, clear of its label.
            let p = CGPoint(x: (rect.minX + 12) * s, y: rect.midY * s)
            expectEdges(Self.ladder(p, in: a, scale: s).first, Self.px(rect, s), within: CGFloat(scale),
                        "\(name) at \(scale)x")
        }
    }

    @Test(arguments: [1, 2])
    func aRoughBoxRoundEachSpecimenSnapsToIt(scale: Int) {
        let a = scale == 1 ? Self.objects1x : Self.objects2x
        let s = Double(scale)
        for (name, rect) in Self.specimens {
            let box = Self.px(rect.insetBy(dx: -12, dy: -10), s)
            expectEdges(Self.snap(box, in: a, scale: s), Self.px(rect, s), within: CGFloat(scale),
                        "\(name) at \(scale)x")
        }
    }
}
