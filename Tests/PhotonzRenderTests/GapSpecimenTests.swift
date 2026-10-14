import CoreGraphics
import Foundation
import PhotonzCore
import PhotonzRender
import Testing

/// Gap mode measured against pictures whose answer is known.
///
/// The specimens (`Scripts/make-gap-specimens.swift`) are the shapes a redliner
/// points between every day: two lines of a display heading, three lines of
/// body copy, stacked cards, two buttons side by side, an icon beside its
/// label, a row of chips and a label over a divider, each rendered at 1x and
/// 2x. `gap-specimens.json` boxes every element in image pixels: a shape where
/// it was drawn, a line of text by its ink, read off its own pixels. Every
/// probe below sits in the space between two of them, and the reading has to
/// run ACROSS the pointer from one to the other, within 1 px at 1x and 2 px at
/// 2x.
///
/// The one the user hit (2026-10-13): pointing into the dark band between
/// "Screenshots" and "recordings" read a few pixels sideways between letter
/// edges that are not level with the pointer at all.
@Suite("Gap mode on the specimen set")
struct GapSpecimenTests {

    private struct Specimen {
        var analysis: EdgeMapAnalyzer.Analysis
        var boxes: [String: CGRect]
        var scale: Double
    }

    private static let manifest: [String: [String: [Int]]] = {
        guard let url = Bundle.module.url(forResource: "Fixtures/gap-specimens", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: [Int]]].self, from: data)
        else { return [:] }
        return decoded
    }()

    private static func load(_ name: String, scale: Int) -> Specimen? {
        let key = "\(name)-\(scale)x"
        guard let url = Bundle.module.url(forResource: "Fixtures/\(key)", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let image = ImageCodec.decode(data),
              let raw = manifest[key] else { return nil }
        let boxes = raw.mapValues { CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3]) }
        return Specimen(analysis: EdgeMapAnalyzer.analyzeFully(image), boxes: boxes, scale: Double(scale))
    }

    /// The reading Gap mode would give with the pointer at `point` (in POINTS),
    /// with the same text gap the canvas hands it.
    private static func reading(_ s: Specimen, at point: CGPoint) -> GapMeasurement? {
        ElementBounds.gap(at: CGPoint(x: point.x * s.scale, y: point.y * s.scale),
                          luma: s.analysis.luma,
                          textGap: Double(AlignmentScan.visibleGap) * s.scale)
    }

    /// Checks one specimen: every probe reads `from`'s far side to `to`'s near
    /// side along `axis`, running through the pointer.
    private static func check(_ name: String, from: String, to: String, axis: MeasureMode,
                              probes: [(Double, Double)],
                              sourceLocation: SourceLocation = #_sourceLocation) {
        for scale in [1, 2] {
            guard let s = load(name, scale: scale), let a = s.boxes[from], let b = s.boxes[to] else {
                Issue.record("missing specimen \(name) at \(scale)x", sourceLocation: sourceLocation)
                continue
            }
            let tolerance = CGFloat(scale)
            for (x, y) in probes {
                let point = CGPoint(x: x * s.scale, y: y * s.scale)
                guard let gap = reading(s, at: CGPoint(x: x, y: y)) else {
                    Issue.record("\(name) \(scale)x at (\(x), \(y)): no reading", sourceLocation: sourceLocation)
                    continue
                }
                let want: (CGFloat, CGFloat) = axis == .vertical ? (a.maxY, b.minY) : (a.maxX, b.minX)
                let got: (CGFloat, CGFloat) = axis == .vertical ? (gap.start.y, gap.end.y) : (gap.start.x, gap.end.x)
                let across = axis == .vertical ? gap.start.x == point.x : gap.start.y == point.y
                let ok = gap.axis == axis && across
                    && abs(got.0 - want.0) <= tolerance && abs(got.1 - want.1) <= tolerance
                #expect(ok, "\(name) \(scale)x at (\(x), \(y)): want \(axis) \(want.0)...\(want.1), got \(gap.axis) \(gap.start)...\(gap.end)",
                        sourceLocation: sourceLocation)
            }
        }
    }

    @Test func betweenTwoLinesOfADisplayHeadingReadsLineToLine() {
        Self.check("gap-heading-lines", from: "upper", to: "lower", axis: .vertical,
                   probes: [(100, 90), (200, 76), (300, 100), (150, 105), (250, 85), (70, 95), (320, 80)])
    }

    @Test func betweenLinesOfBodyCopyReadsLineToLine() {
        Self.check("gap-body-lines", from: "line1", to: "line2", axis: .vertical,
                   probes: [(30, 37), (60, 37), (100, 38), (140, 36), (160, 37)])
        Self.check("gap-body-lines", from: "line2", to: "line3", axis: .vertical,
                   probes: [(40, 59), (90, 59), (130, 60), (25, 58), (110, 59)])
    }

    @Test func betweenStackedCardsReadsCardToCard() {
        Self.check("gap-cards", from: "cardA", to: "cardB", axis: .vertical,
                   probes: [(40, 106), (100, 106), (170, 105), (250, 107), (300, 106)])
    }

    @Test func betweenATitleAndItsBodyInsideACardReadsLineToLine() {
        Self.check("gap-cards", from: "titleA", to: "bodyA", axis: .vertical,
                   probes: [(60, 54), (100, 52), (80, 56), (45, 55), (120, 54)])
    }

    @Test func betweenSideBySideButtonsReadsButtonToButton() {
        Self.check("gap-buttons", from: "cancel", to: "save", axis: .horizontal,
                   probes: [(136, 38), (136, 42), (136, 45), (134, 48), (138, 52)])
    }

    @Test func betweenAnIconAndItsLabelReadsIconToLabel() {
        Self.check("gap-icon-label", from: "icon", to: "label", axis: .horizontal,
                   probes: [(51, 32), (51, 34), (49, 35), (53, 36), (51, 38)])
    }

    @Test func betweenChipsReadsChipToChip() {
        Self.check("gap-chips", from: "chip1", to: "chip2", axis: .horizontal,
                   probes: [(90, 31), (90, 33), (89, 34), (91, 35), (90, 37)])
        Self.check("gap-chips", from: "chip2", to: "chip3", axis: .horizontal,
                   probes: [(162, 33), (162, 35)])
        Self.check("gap-chips", from: "chip3", to: "chip4", axis: .horizontal,
                   probes: [(246, 33), (246, 35)])
    }

    @Test func betweenALabelAndTheDividerUnderItReadsLabelToDivider() {
        Self.check("gap-divider", from: "above", to: "divider", axis: .vertical,
                   probes: [(30, 39.5), (60, 39.5), (100, 40), (130, 39), (90, 41)])
        Self.check("gap-divider", from: "divider", to: "below", axis: .vertical,
                   probes: [(30, 51), (80, 51), (120, 50), (150, 52), (60, 53)])
    }
}
