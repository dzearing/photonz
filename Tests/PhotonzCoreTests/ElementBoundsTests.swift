import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A painted screenshot, in brightness only. Element detection reads BOTH the
/// edge map and the pixels behind it, so a test scene has to be a picture rather
/// than a set of hand-placed gradient responses: the gradients are derived from
/// the paint the same way `EdgeMapAnalyzer` derives them from a real capture, so
/// what these tests exercise is the shipping path.
private struct Capture {
    var w: Int, h: Int
    /// Brightness 0…255, top-left row order.
    var pixels: [UInt8]

    init(w: Int, h: Int, background: UInt8 = 242) {
        self.w = w
        self.h = h
        pixels = [UInt8](repeating: background, count: w * h)
    }

    mutating func fill(_ rect: CGRect, _ tone: UInt8) {
        for y in Int(rect.minY)..<Int(rect.maxY) where y >= 0 && y < h {
            for x in Int(rect.minX)..<Int(rect.maxX) where x >= 0 && x < w {
                pixels[y * w + x] = tone
            }
        }
    }

    /// A bordered element: `width` px of `border` tone around an `inside` fill.
    mutating func box(_ rect: CGRect, border: UInt8, inside: UInt8 = 255, width: Int = 2) {
        fill(rect, border)
        fill(rect.insetBy(dx: CGFloat(width), dy: CGFloat(width)), inside)
    }

    /// A horizontal rule of `thickness` px whose TOP is `y` — a settings-row
    /// divider, which has no left or right edge of its own.
    mutating func rule(y: Int, x0: Int, x1: Int, tone: UInt8, thickness: Int = 2) {
        fill(CGRect(x: x0, y: y, width: x1 - x0, height: thickness), tone)
    }

    /// Stand-in text: a run of dark strokes on a shared baseline, the thing that
    /// used to win every directional walk inside a button.
    mutating func text(x: Int, y: Int, glyphs: Int, tone: UInt8 = 40,
                       glyphWidth: Int = 4, gap: Int = 4, height: Int = 14) {
        for i in 0..<glyphs {
            let left = x + i * (glyphWidth + gap)
            fill(CGRect(x: left, y: y, width: glyphWidth, height: height), tone)
        }
    }

    var luma: LumaField { LumaField(width: w, height: h, samples: pixels) }

    /// The same Sobel pass `EdgeMapAnalyzer` runs, on 0…1 brightness so the
    /// map's absolute floor means what it means on a real capture.
    var map: EdgeMap {
        var gx = [Double](repeating: 0, count: w * h)
        var gy = [Double](repeating: 0, count: w * h)
        func at(_ x: Int, _ y: Int) -> Double {
            let cx = min(max(x, 0), w - 1), cy = min(max(y, 0), h - 1)
            return Double(pixels[cy * w + cx]) / 255
        }
        for y in 0..<h {
            for x in 0..<w {
                let sx = -at(x - 1, y - 1) + at(x + 1, y - 1)
                    - 2 * at(x - 1, y) + 2 * at(x + 1, y)
                    - at(x - 1, y + 1) + at(x + 1, y + 1)
                let sy = -at(x - 1, y - 1) - 2 * at(x, y - 1) - at(x + 1, y - 1)
                    + at(x - 1, y + 1) + 2 * at(x, y + 1) + at(x + 1, y + 1)
                gx[y * w + x] = abs(sx)
                gy[y * w + x] = abs(sy)
            }
        }
        var flat = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) { flat[i] = Double(pixels[i]) / 255 }
        return EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy, luma: flat)
    }
}

/// Whether a detected rect is the element these scenes painted. What these tests
/// are for is WHICH element gets picked — the button rather than a letter inside
/// it, the switch rather than its knob, the row rather than its card — so they
/// allow a few pixels: a 2 px painted border has two flanks and the gradient peak
/// can name either. The exact numbers a person reads are pinned separately,
/// against a real screenshot, in `ElementDetectionFixtureTests`.
private func expectRect(_ rect: CGRect?, _ expected: CGRect, slack: CGFloat = 3,
                        sourceLocation: SourceLocation = #_sourceLocation) {
    guard let rect else {
        Issue.record("expected \(expected), got nothing", sourceLocation: sourceLocation)
        return
    }
    let matches = abs(rect.minX - expected.minX) <= slack
        && abs(rect.minY - expected.minY) <= slack
        && abs(rect.width - expected.width) <= slack * 2
        && abs(rect.height - expected.height) <= slack * 2
    if !matches {
        Issue.record("expected \(expected), got \(rect)", sourceLocation: sourceLocation)
    }
}

@Suite("ElementBounds hover detection")
struct ElementBoundsTests {

    // MARK: The pick

    @Test func findsTheBoxAroundTheProbe() {
        var c = Capture(w: 400, h: 300)
        let button = CGRect(x: 60, y: 50, width: 140, height: 70)
        c.box(button, border: 90)
        expectRect(ElementBounds.detect(at: CGPoint(x: 130, y: 80), in: c.map, luma: c.luma),
                   button)
    }

    @Test func aProbeOverTextStillReadsTheButton() {
        // The exact failure the audit of 2026-08-23 measured: glyph strokes
        // inside a button won the nearest-edge walk, so the readout was a sliver
        // of a letter — or, when the walks disagreed, nothing at all.
        var c = Capture(w: 400, h: 300)
        let button = CGRect(x: 60, y: 50, width: 200, height: 60)
        c.box(button, border: 90)
        c.text(x: 100, y: 72, glyphs: 8)
        expectRect(ElementBounds.detect(at: CGPoint(x: 130, y: 80), in: c.map, luma: c.luma),
                   button)
        // And the pick does not change as the pointer crosses the letters.
        expectRect(ElementBounds.detect(at: CGPoint(x: 170, y: 80), in: c.map, luma: c.luma),
                   button)
    }

    @Test func aRowWithNoSidesReadsAsWideAsItsDivider() {
        // A settings row has no left or right border at all: its width is only
        // knowable from how far the hairline under it runs, which is the whole
        // reason detection reads pixels. The card around it is 30 px wider.
        var c = Capture(w: 700, h: 400)
        c.box(CGRect(x: 40, y: 40, width: 620, height: 264), border: 200, width: 1)
        c.rule(y: 128, x0: 70, x1: 630, tone: 220)
        c.rule(y: 216, x0: 70, x1: 630, tone: 220)
        expectRect(ElementBounds.detect(at: CGPoint(x: 350, y: 170), in: c.map, luma: c.luma),
                   CGRect(x: 70, y: 128, width: 560, height: 88))
    }

    @Test func aSwitchReadsTheSwitchNotTheKnobUnderThePointer() {
        // A knob sits inside a switch, and the middle of the switch lands on it.
        // The knob is a real element; nobody pointing at the middle of a switch
        // means the knob.
        var c = Capture(w: 300, h: 200)
        let track = CGRect(x: 100, y: 88, width: 84, height: 48)
        c.fill(track, 120)
        c.fill(CGRect(x: 140, y: 92, width: 40, height: 40), 250) // knob, right-hand end
        expectRect(ElementBounds.detect(at: CGPoint(x: 142, y: 112), in: c.map, luma: c.luma),
                   track)
    }

    @Test func flatRegionShowsNothing() {
        let c = Capture(w: 400, h: 300)
        #expect(ElementBounds.detect(at: CGPoint(x: 200, y: 150), in: c.map, luma: c.luma) == nil)
    }

    @Test func aBoxMissingASideIsStillReadableFromItsRuns() {
        // Two rules and no vertical borders anywhere: the pair still describes a
        // band, and its width is the stretch they share.
        var c = Capture(w: 400, h: 300)
        c.rule(y: 80, x0: 50, x1: 350, tone: 90)
        c.rule(y: 160, x0: 50, x1: 350, tone: 90)
        expectRect(ElementBounds.detect(at: CGPoint(x: 200, y: 120), in: c.map, luma: c.luma),
                   CGRect(x: 50, y: 80, width: 300, height: 80))
    }

    @Test func sidesBeyondMaxRadiusDoNotCount() {
        var c = Capture(w: 1200, h: 400)
        c.box(CGRect(x: 10, y: 40, width: 1090, height: 300), border: 90)
        let probe = CGPoint(x: 550, y: 190)
        #expect(ElementBounds.detect(at: probe, in: c.map, luma: c.luma) != nil)
        #expect(ElementBounds.detect(at: probe, in: c.map, luma: c.luma, maxRadius: 100) == nil)
    }

    @Test func anElementSmallerThanTheFloorIsNotOffered() {
        // The band between a word's cap height and its baseline looks exactly
        // like a wide, short box. Nothing that small is something anyone means
        // to measure.
        var c = Capture(w: 400, h: 300)
        c.box(CGRect(x: 60, y: 50, width: 200, height: 60), border: 90)
        c.text(x: 100, y: 72, glyphs: 8)
        let ladder = ElementBounds.candidates(at: CGPoint(x: 130, y: 80),
                                              in: c.map, luma: c.luma)
        #expect(ladder.allSatisfy { $0.height >= ElementBounds.defaultMinElement })
    }

    @Test func emptyMapMissesQuietly() {
        #expect(ElementBounds.detect(at: CGPoint(x: 50, y: 50), in: .empty, luma: .empty) == nil)
    }

    @Test func anUnanalyzedImageMissesQuietly() {
        // The edge map and the brightness field come from one pass, so a map
        // without pixels only happens before analysis lands. Quiet, not wrong.
        var c = Capture(w: 400, h: 300)
        c.box(CGRect(x: 60, y: 50, width: 140, height: 70), border: 90)
        #expect(ElementBounds.detect(at: CGPoint(x: 130, y: 80), in: c.map, luma: .empty) == nil)
    }

    @Test func detectionStaysWellInsideTheMouseMoveBudget() {
        // Spec budget: under 1 ms per mouse move on a 12-megapixel document.
        // Tests build unoptimized, so this is asserted with generous slack; the
        // real measurement lives in the render-side fixture test, which pins the
        // cost against the edge-map query it rides on.
        var c = Capture(w: 2000, h: 1500)
        c.box(CGRect(x: 900, y: 700, width: 400, height: 200), border: 90)
        let map = c.map
        let luma = c.luma
        let start = ContinuousClock.now
        for i in 0..<100 {
            _ = ElementBounds.detect(at: CGPoint(x: 1000 + i % 50, y: 800), in: map, luma: luma)
        }
        #expect((ContinuousClock.now - start) / 100 < .milliseconds(10))
    }

    // MARK: The neighbours (what a readout has to steer around)

    /// Three settings rows stacked in a card. Measuring the middle row, the
    /// rows touching it above and below are what a readout must not park on.
    @Test func neighborsFindTheRowsTouchingTheOneMeasured() {
        var c = Capture(w: 700, h: 400)
        c.box(CGRect(x: 40, y: 40, width: 620, height: 264), border: 200, width: 1)
        c.rule(y: 128, x0: 70, x1: 630, tone: 220)
        c.rule(y: 216, x0: 70, x1: 630, tone: 220)
        let middle = CGRect(x: 70, y: 128, width: 560, height: 88)
        let found = ElementBounds.neighbors(of: middle, in: c.map, luma: c.luma)
        #expect(found.contains { abs($0.minY - 216) <= 4 }, "no row below in \(found)")
        #expect(found.contains { abs($0.maxY - 128) <= 4 }, "no row above in \(found)")
    }

    /// The card AROUND the row is not a neighbour: a readout cannot steer out
    /// of a box it is standing inside, and treating it as one would only push
    /// the number somewhere arbitrary.
    @Test func neighborsIgnoreTheContainerTheElementSitsIn() {
        var c = Capture(w: 700, h: 400)
        c.box(CGRect(x: 40, y: 40, width: 620, height: 264), border: 200, width: 1)
        c.rule(y: 128, x0: 70, x1: 630, tone: 220)
        c.rule(y: 216, x0: 70, x1: 630, tone: 220)
        let middle = CGRect(x: 70, y: 128, width: 560, height: 88)
        let found = ElementBounds.neighbors(of: middle, in: c.map, luma: c.luma)
        #expect(found.allSatisfy { !$0.contains(middle) }, "a container came back: \(found)")
    }

    @Test func neighborsOfSomethingAloneInTheOpenAreEmpty() {
        var c = Capture(w: 400, h: 300)
        let button = CGRect(x: 60, y: 50, width: 140, height: 70)
        c.box(button, border: 90)
        #expect(ElementBounds.neighbors(of: button, in: c.map, luma: c.luma).isEmpty)
    }

    /// Neighbours are read while the pointer moves, so they ride the same
    /// budget the pick does: eight probes, and only when the pick changes.
    @Test func readingTheNeighboursStaysInsideTheMouseMoveBudget() {
        var c = Capture(w: 2000, h: 1500)
        c.box(CGRect(x: 900, y: 700, width: 400, height: 200), border: 90)
        c.box(CGRect(x: 900, y: 900, width: 400, height: 200), border: 90)
        let map = c.map
        let luma = c.luma
        let element = CGRect(x: 900, y: 700, width: 400, height: 200)
        let start = ContinuousClock.now
        for _ in 0..<20 {
            _ = ElementBounds.neighbors(of: element, in: map, luma: luma,
                                        reaches: [ElementBounds.neighborProbeReach, 90])
        }
        // 29 ms unoptimized for eight probes on a 3-megapixel scene, and only
        // when the pick changes (the canvas keeps the last answer), so a
        // release build stays well under a mouse move.
        #expect((ContinuousClock.now - start) / 20 < .milliseconds(50))
    }

    @Test func neighborsOfAnUnanalyzedImageAreEmpty() {
        #expect(ElementBounds.neighbors(of: CGRect(x: 10, y: 10, width: 40, height: 40),
                                        in: .empty, luma: .empty).isEmpty)
    }

    // MARK: The ladder ([ and ] grow and shrink the pick)

    @Test func candidatesGrowOutwardFromTheInnermost() {
        var c = Capture(w: 600, h: 500)
        let card = CGRect(x: 20, y: 20, width: 540, height: 440)
        let button = CGRect(x: 120, y: 120, width: 200, height: 100)
        c.box(card, border: 180, width: 1)
        c.box(button, border: 90)
        let list = ElementBounds.candidates(at: CGPoint(x: 200, y: 170), in: c.map, luma: c.luma)
        expectRect(list.first, button)
        #expect(list.contains { abs($0.width - card.width) <= 3 && abs($0.height - card.height) <= 3 })
        // Strictly nested, innermost first: that is what makes it a ladder.
        for (inner, outer) in zip(list, list.dropFirst()) {
            #expect(outer.insetBy(dx: -1, dy: -1).contains(inner))
        }
    }

    @Test func detectIsTheFirstCandidate() {
        var c = Capture(w: 600, h: 500)
        c.box(CGRect(x: 20, y: 20, width: 540, height: 440), border: 180, width: 1)
        c.box(CGRect(x: 120, y: 120, width: 200, height: 100), border: 90)
        let probe = CGPoint(x: 200, y: 170)
        #expect(ElementBounds.detect(at: probe, in: c.map, luma: c.luma)
                == ElementBounds.candidates(at: probe, in: c.map, luma: c.luma).first)
    }

    @Test func flatBackgroundOffersNoCandidates() {
        let c = Capture(w: 400, h: 300)
        #expect(ElementBounds.candidates(at: CGPoint(x: 200, y: 150),
                                         in: c.map, luma: c.luma).isEmpty)
    }

    @Test func candidateListStaysShort() {
        var c = Capture(w: 900, h: 900)
        for i in 0..<12 {
            let inset = CGFloat(i) * 30
            c.box(CGRect(x: 20 + inset, y: 20 + inset,
                         width: 860 - inset * 2, height: 860 - inset * 2),
                  border: UInt8(60 + i * 12), inside: 250, width: 2)
        }
        let list = ElementBounds.candidates(at: CGPoint(x: 450, y: 450), in: c.map, luma: c.luma)
        #expect(!list.isEmpty)
        #expect(list.count <= ElementBounds.candidateLimit)
    }
}

/// Gap mode measures WHITESPACE, so it reads to the clean background hugging
/// each element and needs only the one axis it measures. Its scenes are built
/// straight from gradient responses: what is under test is the edge map's
/// landings, not how far a boundary runs.
private struct GapScene {
    var w: Int, h: Int
    var gx: [Double]
    var gy: [Double]

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        gx = [Double](repeating: 0, count: w * h)
        gy = [Double](repeating: 0, count: w * h)
    }

    mutating func addHorizontalEdge(row: Int, x0: Int, x1: Int, magnitude: Double = 2.0) {
        for x in max(0, x0)...min(w - 1, x1) { gy[row * w + x] = magnitude }
    }

    mutating func addVerticalEdge(col: Int, y0: Int, y1: Int, magnitude: Double = 2.0) {
        for y in max(0, y0)...min(h - 1, y1) { gx[y * w + col] = magnitude }
    }

    mutating func addBox(_ r: CGRect, magnitude: Double = 2.0) {
        addHorizontalEdge(row: Int(r.minY), x0: Int(r.minX), x1: Int(r.maxX), magnitude: magnitude)
        addHorizontalEdge(row: Int(r.maxY), x0: Int(r.minX), x1: Int(r.maxX), magnitude: magnitude)
        addVerticalEdge(col: Int(r.minX), y0: Int(r.minY), y1: Int(r.maxY), magnitude: magnitude)
        addVerticalEdge(col: Int(r.maxX), y0: Int(r.minY), y1: Int(r.maxY), magnitude: magnitude)
    }

    var map: EdgeMap { EdgeMap(width: w, height: h, gxMagnitude: gx, gyMagnitude: gy) }
}

@Suite("ElementBounds gap mode")
struct ElementGapTests {

    @Test func gapReadsTheShorterSpanThroughTheClick() {
        // Two buttons side by side inside a tall card: clicking between them
        // must measure the 40 px horizontal gap, not the card's height.
        var s = GapScene(w: 600, h: 500)
        s.addBox(CGRect(x: 20, y: 20, width: 560, height: 440))
        s.addBox(CGRect(x: 100, y: 150, width: 120, height: 60))
        s.addBox(CGRect(x: 260, y: 150, width: 120, height: 60))
        let gap = ElementBounds.gap(at: CGPoint(x: 240, y: 180), in: s.map)
        #expect(gap?.axis == .horizontal)
        #expect(gap?.length == 40)
        #expect(gap?.start == CGPoint(x: 220, y: 180))
        #expect(gap?.end == CGPoint(x: 260, y: 180))
    }

    @Test func gapReadsAVerticalStackToo() {
        var s = GapScene(w: 600, h: 500)
        s.addBox(CGRect(x: 20, y: 20, width: 560, height: 440))
        s.addBox(CGRect(x: 100, y: 100, width: 400, height: 60))
        s.addBox(CGRect(x: 100, y: 184, width: 400, height: 60))
        let gap = ElementBounds.gap(at: CGPoint(x: 300, y: 172), in: s.map)
        #expect(gap?.axis == .vertical)
        #expect(gap?.length == 24)
        #expect(gap?.start == CGPoint(x: 300, y: 160))
        #expect(gap?.end == CGPoint(x: 300, y: 184))
    }

    @Test func gapOnFlatBackgroundIsAQuietMiss() {
        let s = GapScene(w: 400, h: 300)
        #expect(ElementBounds.gap(at: CGPoint(x: 200, y: 150), in: s.map) == nil)
    }

    @Test func gapNeedsOnlyTheAxisItMeasures() {
        // Two stacked cards with nothing to their left or right: the space
        // between them has a top and a bottom and no sides at all. Refusing to
        // measure it would fail the most ordinary gap there is.
        var s = GapScene(w: 600, h: 500)
        s.addHorizontalEdge(row: 200, x0: 0, x1: 599)
        s.addHorizontalEdge(row: 240, x0: 0, x1: 599)
        let gap = ElementBounds.gap(at: CGPoint(x: 300, y: 220), in: s.map)
        #expect(gap?.axis == .vertical)
        #expect(gap?.length == 40)
    }
}

/// What a hand-drawn caliper is ABOUT: the elements its two feet landed on.
/// A foot carries only a point, so the element is read back off the picture at
/// placement time, and the readout planner is told to stay off it the way it
/// already stays off the element Size mode measured.
@Suite("ElementBounds subjects of a caliper")
struct ElementBoundsSubjectTests {

    private func subjects(_ c: Capture, from start: CGPoint, to end: CGPoint,
                          mode: MeasureMode) -> [CGRect] {
        ElementBounds.subjects(from: start, to: end, mode: mode, in: c.map, luma: c.luma)
    }

    @Test func aCaliperBetweenTwoButtonsKnowsBothButtons() {
        var c = Capture(w: 500, h: 200)
        let left = CGRect(x: 60, y: 50, width: 140, height: 70)
        let right = CGRect(x: 260, y: 50, width: 140, height: 70)
        c.box(left, border: 90)
        c.box(right, border: 90)
        let found = subjects(c, from: CGPoint(x: 200, y: 85), to: CGPoint(x: 260, y: 85),
                             mode: .horizontal)
        #expect(found.count == 2, "\(found)")
        expectRect(found.first { $0.midX < 230 }, left)
        expectRect(found.first { $0.midX > 230 }, right)
    }

    @Test func aCaliperBetweenTwoStackedCardsKnowsBothCards() {
        var c = Capture(w: 600, h: 400)
        let top = CGRect(x: 100, y: 100, width: 400, height: 60)
        let bottom = CGRect(x: 100, y: 184, width: 400, height: 60)
        c.box(top, border: 90)
        c.box(bottom, border: 90)
        // Feet the way a foot drag lands them: on the clean background hugging
        // each element, a pixel or two off the painted edge.
        let found = subjects(c, from: CGPoint(x: 300, y: 161), to: CGPoint(x: 300, y: 183),
                             mode: .vertical)
        expectRect(found.first { $0.maxY <= 170 }, top)
        expectRect(found.first { $0.minY >= 170 }, bottom)
        // Two bordered cards also bound the strip of whitespace between them,
        // which reads as a band of its own. That band is the gap being
        // measured, so it is a fine thing for the number to stay off, but it
        // is the only other thing that may come back.
        let extra = found.filter { $0.maxY > 170 && $0.minY < 170 }
        #expect(found.count - extra.count == 2, "\(found)")
        #expect(extra.allSatisfy { $0.minY >= 155 && $0.maxY <= 190 }, "\(extra)")
    }

    @Test func theSameGapReadsTheSameSubjectsFromEitherDirection() {
        var c = Capture(w: 500, h: 200)
        c.box(CGRect(x: 60, y: 50, width: 140, height: 70), border: 90)
        c.box(CGRect(x: 260, y: 50, width: 140, height: 70), border: 90)
        let forward = subjects(c, from: CGPoint(x: 200, y: 85), to: CGPoint(x: 260, y: 85),
                               mode: .horizontal)
        let backward = subjects(c, from: CGPoint(x: 260, y: 85), to: CGPoint(x: 200, y: 85),
                                mode: .horizontal)
        #expect(Set(forward.map { "\($0)" }) == Set(backward.map { "\($0)" }))
    }

    /// Measuring one element edge to edge by hand is Size mode drawn slowly, and
    /// it gets the same subject: that element, once.
    @Test func anElementMeasuredEdgeToEdgeIsItsOwnSubjectOnce() {
        var c = Capture(w: 400, h: 300)
        let button = CGRect(x: 60, y: 50, width: 140, height: 70)
        c.box(button, border: 90)
        let found = subjects(c, from: CGPoint(x: 60, y: 85), to: CGPoint(x: 200, y: 85),
                             mode: .horizontal)
        #expect(found.count == 1, "\(found)")
        expectRect(found.first, button)
    }

    /// A caliper from a card's edge to a button inside it runs INSIDE the card.
    /// The number cannot steer out of a box it is standing in, so the card is
    /// not a subject; the button is.
    @Test func aContainerTheCaliperRunsInsideIsNotASubject() {
        var c = Capture(w: 600, h: 500)
        let card = CGRect(x: 20, y: 20, width: 540, height: 440)
        let button = CGRect(x: 120, y: 120, width: 200, height: 100)
        c.box(card, border: 180, width: 1)
        c.box(button, border: 90)
        let found = subjects(c, from: CGPoint(x: 20, y: 170), to: CGPoint(x: 120, y: 170),
                             mode: .horizontal)
        #expect(found.count == 1, "\(found)")
        expectRect(found.first, button)
    }

    @Test func aFootOnOpenBackgroundContributesNothing() {
        var c = Capture(w: 500, h: 200)
        let button = CGRect(x: 60, y: 50, width: 140, height: 70)
        c.box(button, border: 90)
        #expect(subjects(c, from: CGPoint(x: 300, y: 85), to: CGPoint(x: 400, y: 85),
                         mode: .horizontal).isEmpty)
        let half = subjects(c, from: CGPoint(x: 200, y: 85), to: CGPoint(x: 400, y: 85),
                            mode: .horizontal)
        #expect(half.count == 1, "\(half)")
        expectRect(half.first, button)
    }

    /// A foot dropped in the MIDDLE of a button did not snap to its edge, so
    /// the button is not what the caliper is describing.
    @Test func aFootInsideAnElementIsNotOnItsEdge() {
        var c = Capture(w: 500, h: 200)
        c.box(CGRect(x: 60, y: 50, width: 140, height: 70), border: 90)
        #expect(subjects(c, from: CGPoint(x: 130, y: 85), to: CGPoint(x: 400, y: 85),
                         mode: .horizontal).isEmpty)
    }

    /// The measuring line runs beside the element, not through it: nothing to
    /// stand on, nothing read.
    @Test func aLineDrawnPastAnElementDoesNotReadIt() {
        var c = Capture(w: 500, h: 300)
        c.box(CGRect(x: 60, y: 50, width: 140, height: 70), border: 90)
        #expect(subjects(c, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 300, y: 200),
                         mode: .horizontal).isEmpty)
    }

    @Test func subjectsOfAnUnanalyzedImageAreEmpty() {
        #expect(ElementBounds.subjects(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10),
                                       mode: .horizontal, in: .empty, luma: .empty).isEmpty)
    }

    /// Two probes per foot, once per placement: nothing here runs per mouse
    /// move, but it still has to be cheap enough to never be felt on a click.
    @Test func readingTheSubjectsCostsFourProbes() {
        var c = Capture(w: 2000, h: 1500)
        c.box(CGRect(x: 900, y: 700, width: 400, height: 200), border: 90)
        c.box(CGRect(x: 900, y: 1000, width: 400, height: 200), border: 90)
        let map = c.map
        let luma = c.luma
        let start = ContinuousClock.now
        for _ in 0..<20 {
            _ = ElementBounds.subjects(from: CGPoint(x: 1100, y: 900), to: CGPoint(x: 1100, y: 1000),
                                       mode: .vertical, in: map, luma: luma)
        }
        #expect((ContinuousClock.now - start) / 20 < .milliseconds(30))
    }
}
