import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// How an arrow is DRAWN: the clean geometric arrow it has always been, or one
/// of the hand-made looks the user asked for on 2026-10-01 (a thin hand-drawn
/// line, a bold marker, a tapered brush stroke, a rough sketched outline).
@Suite("Arrow styles")
struct ArrowStyleTests {

    private func arrow(_ style: ArrowStyle, seed: UInt32 = 7, width: CGFloat = 4,
                       start: CGPoint = CGPoint(x: 40, y: 120),
                       end: CGPoint = CGPoint(x: 360, y: 60),
                       scale: CGFloat = 1) -> AnnotationContent {
        var a = AnnotationContent(shape: .arrow, strokeWidth: width, start: start, end: end,
                                  arrowheadScale: scale)
        a.arrowStyle = style
        a.styleSeed = seed
        return a
    }

    // MARK: - The set of styles

    @Test func fiveStylesInPickerOrder() {
        #expect(ArrowStyle.allCases == [.clean, .handDrawn, .marker, .brush, .sketch])
    }

    @Test func cleanIsTheDefaultAndTheOnlyOneNotHandMade() {
        #expect(ArrowStyle.standard == .clean)
        #expect(AnnotationContent(shape: .arrow).arrowStyle == .clean)
        #expect(!ArrowStyle.clean.isHandMade)
        for style in ArrowStyle.allCases where style != .clean {
            #expect(style.isHandMade)
        }
    }

    @Test func everyStyleHasAShortName() {
        for style in ArrowStyle.allCases {
            #expect(!style.title.isEmpty)
            #expect(style.title.count <= 12)
        }
        #expect(Set(ArrowStyle.allCases.map(\.title)).count == ArrowStyle.allCases.count)
    }

    // MARK: - On disk

    /// Every arrow saved before there were styles opens as the clean arrow it
    /// was drawn as.
    @Test func anArrowSavedBeforeStylesOpensClean() throws {
        let old = AnnotationContent(shape: .arrow, start: .zero, end: CGPoint(x: 100, y: 0))
        var json = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(old)) as? [String: Any])
        json.removeValue(forKey: "arrowStyle")
        json.removeValue(forKey: "styleSeed")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AnnotationContent.self, from: data)
        #expect(decoded.arrowStyle == .clean)
        #expect(decoded.styleSeed == 0)
    }

    @Test func styleAndSeedSurviveARoundTrip() throws {
        let drawn = arrow(.brush, seed: 123_456)
        let decoded = try JSONDecoder().decode(AnnotationContent.self,
                                               from: JSONEncoder().encode(drawn))
        #expect(decoded.arrowStyle == .brush)
        #expect(decoded.styleSeed == 123_456)
        #expect(decoded == drawn)
    }

    // MARK: - What the panel asks about

    /// A hand-made style draws its own head and its own tail, so the Ending
    /// picker and the tail's Ends row are Clean's alone. Head Size still sizes
    /// every head.
    @Test func handMadeStylesTakeTheEndingAndEndsRowsAway() {
        let clean = arrow(.clean)
        #expect(clean.settingRows.contains(.headStyle))
        #expect(clean.settingRows.contains(.lineEnds))
        for style in ArrowStyle.allCases where style.isHandMade {
            let rows = arrow(style).settingRows
            #expect(!rows.contains(.headStyle))
            #expect(!rows.contains(.lineEnds))
            #expect(rows.contains(.headSize))
            #expect(rows.contains(.thickness))
        }
    }

    /// A clean arrow that ends in nothing has no head, but a hand-made one
    /// always draws its own, whatever ending the clean style was left on.
    @Test func aHandMadeArrowAlwaysHasAHead() {
        var plain = arrow(.clean)
        plain.arrowheadStyle = .plain
        #expect(!plain.drawsArrowhead)
        var sketched = plain
        sketched.arrowStyle = .sketch
        #expect(sketched.drawsArrowhead)
        #expect(sketched.settingRows.contains(.headSize))
    }

    // MARK: - The drawing

    @Test func cleanHasNoHandMadeInk() {
        #expect(HandMadeArrow.inks(for: arrow(.clean)).isEmpty)
    }

    @Test func everyHandMadeStyleDrawsAShaftAndAHead() {
        for style in ArrowStyle.allCases where style.isHandMade {
            let inks = HandMadeArrow.inks(for: arrow(style))
            #expect(inks.contains { $0.part == .shaft }, "\(style) has no shaft")
            #expect(inks.contains { $0.part == .head }, "\(style) has no head")
        }
    }

    /// The same arrow is drawn the same way every time: on the canvas, after
    /// reopening, and in an export. Nothing about it wobbles between renders.
    @Test func theSameArrowAlwaysLooksTheSame() {
        for style in ArrowStyle.allCases where style.isHandMade {
            #expect(HandMadeArrow.inks(for: arrow(style)) == HandMadeArrow.inks(for: arrow(style)))
        }
    }

    /// ...and a new seed is a new hand: Reshuffle changes the drawing.
    @Test func aNewSeedDrawsItDifferently() {
        for style in ArrowStyle.allCases where style.isHandMade {
            #expect(HandMadeArrow.inks(for: arrow(style, seed: 1))
                    != HandMadeArrow.inks(for: arrow(style, seed: 2)), "\(style)")
        }
    }

    /// The tip of a hand-made arrow still lands on the point it marks: it is a
    /// pointer, however loose the hand that drew it.
    @Test func theHeadStillPointsAtTheEnd() {
        for style in ArrowStyle.allCases where style.isHandMade {
            let a = arrow(style)
            let head = HandMadeArrow.inks(for: a).filter { $0.part == .head }
            let nearest = head.flatMap(\.points)
                .map { hypot($0.x - a.end.x, $0.y - a.end.y) }.min() ?? .infinity
            #expect(nearest <= a.strokeWidth * 1.5, "\(style) head is \(nearest) from the tip")
        }
    }

    /// The shaft starts where the arrow starts.
    @Test func theShaftStartsAtTheTail() {
        for style in ArrowStyle.allCases where style.isHandMade {
            let a = arrow(style)
            let shaft = HandMadeArrow.inks(for: a).filter { $0.part == .shaft }
            let nearest = shaft.flatMap(\.points)
                .map { hypot($0.x - a.start.x, $0.y - a.start.y) }.min() ?? .infinity
            #expect(nearest <= a.strokeWidth * 2.5, "\(style) shaft is \(nearest) from the tail")
        }
    }

    /// Every bit of ink lands inside the frame the arrow is given, at every
    /// width, head size and direction, so nothing is ever clipped.
    @Test func theFrameHoldsEveryStyle() {
        let directions: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0)),
            (CGPoint(x: 300, y: 200), CGPoint(x: 0, y: 0)),
            (CGPoint(x: 0, y: 300), CGPoint(x: 10, y: 0)),
            (CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 30)),
        ]
        for style in ArrowStyle.allCases where style.isHandMade {
            for (start, end) in directions {
                for width in [CGFloat(1), 4, 12, 30] {
                    for scale in [CGFloat(0.5), 1, 2.2] {
                        for seed in [UInt32(1), 99, 40_000] {
                            var content = arrow(style, seed: seed, width: width,
                                                start: start, end: end, scale: scale)
                            let layer = AnnotationBuilder.layer(content: content, from: start, to: end)
                            guard let local = layer.annotation else { continue }
                            content = local
                            let ink = HandMadeArrow.inkBounds(for: content)
                            let frame = CGRect(origin: .zero, size: layer.frame.size)
                            #expect(frame.contains(ink),
                                    "\(style) w\(width) ×\(scale) seed \(seed): \(ink) outside \(frame)")
                        }
                    }
                }
            }
        }
    }

    /// Detail scales with the line: the same arrow drawn twice as big, twice
    /// as thick and with a head twice the size is the same drawing, twice the
    /// size. So a thick arrow is not a thin one's wobble on a fat line.
    @Test func detailScalesWithTheWidth() {
        for style in ArrowStyle.allCases where style.isHandMade {
            let small = arrow(style, width: 4, start: CGPoint(x: 10, y: 10),
                              end: CGPoint(x: 210, y: 90), scale: 1)
            let big = arrow(style, width: 8, start: CGPoint(x: 20, y: 20),
                            end: CGPoint(x: 420, y: 180), scale: 2)
            let a = HandMadeArrow.inks(for: small)
            let b = HandMadeArrow.inks(for: big)
            #expect(a.count == b.count, "\(style)")
            for (x, y) in zip(a, b) {
                #expect(x.points.count == y.points.count, "\(style)")
                for (p, q) in zip(x.points, y.points) {
                    #expect(abs(p.x * 2 - q.x) < 0.01 && abs(p.y * 2 - q.y) < 0.01, "\(style)")
                }
                #expect(abs(x.width * 2 - y.width) < 0.001, "\(style)")
            }
        }
    }

    /// A brush stroke starts as a point at the tail, swells through the body
    /// and narrows into the head.
    @Test func theBrushTapersAndSwells() {
        let a = arrow(.brush, width: 6, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 400, y: 100))
        let profile = HandMadeArrow.brushHalfWidths(for: a, at: [0, 0.1, 0.6, 0.97])
        #expect(profile[0] < 0.5)
        #expect(profile[1] < profile[2])
        #expect(profile[3] < profile[2])
        #expect(profile[2] >= a.strokeWidth)
    }

    /// The brush is a filled shape, the other three are lines.
    @Test func theBrushIsFilledAndTheLinesAreStroked() {
        #expect(HandMadeArrow.inks(for: arrow(.brush)).allSatisfy { $0.kind == .fill })
        for style in [ArrowStyle.handDrawn, .marker, .sketch] {
            #expect(HandMadeArrow.inks(for: arrow(style)).allSatisfy { $0.kind == .stroke }, "\(style)")
        }
    }

    /// A marker is bolder than a pen at the same Thickness setting.
    @Test func theMarkerIsBolderThanThePen() {
        let pen = HandMadeArrow.inks(for: arrow(.handDrawn)).map(\.width).max() ?? 0
        let marker = HandMadeArrow.inks(for: arrow(.marker)).map(\.width).max() ?? 0
        #expect(marker > pen * 1.3)
    }

    /// A sketch is drawn more than once over and broken in places, the way a
    /// dry marker leaves it: many short strokes, not one clean outline.
    @Test func theSketchIsDoubleStrokedAndBroken() {
        let inks = HandMadeArrow.inks(for: arrow(.sketch))
        #expect(inks.count >= 16)
        #expect(Set(inks.map(\.width)).count >= 2)
    }

    // MARK: - Following a curve

    /// The styles are drawn along a spine, so the day an arrow bends they
    /// follow it: the middle of the drawing sits on the curve, not on the
    /// straight line between the ends.
    @Test func everyStyleFollowsACurvedSpine() {
        let start = CGPoint(x: 0, y: 200)
        let end = CGPoint(x: 400, y: 200)
        let spine = ArrowSpine(start: start, control: CGPoint(x: 200, y: 0), end: end)
        let middle = spine.point(at: 0.5)
        for style in ArrowStyle.allCases where style.isHandMade {
            let inks = HandMadeArrow.inks(for: arrow(style, start: start, end: end), along: spine)
            let shaft = inks.filter { $0.part == .shaft }.flatMap(\.points)
            let nearest = shaft.map { hypot($0.x - middle.x, $0.y - middle.y) }.min() ?? .infinity
            #expect(nearest < 30, "\(style) is \(nearest) from the curve's middle")
        }
    }

    @Test func aStraightSpineIsEvenlySampled() {
        let spine = ArrowSpine(start: .zero, end: CGPoint(x: 100, y: 0))
        #expect(abs(spine.length - 100) < 0.01)
        let stations = spine.stations(count: 5)
        #expect(stations.map { ($0.point.x * 100).rounded() / 100 } == [0, 25, 50, 75, 100])
        #expect(stations.allSatisfy { abs($0.direction.dx - 1) < 1e-6 })
    }

    @Test func aCurvedSpineIsEvenlySampledAlongItsLength() {
        let spine = ArrowSpine(start: .zero, control: CGPoint(x: 50, y: 80), end: CGPoint(x: 100, y: 0))
        let stations = spine.stations(count: 9)
        var gaps: [CGFloat] = []
        for (a, b) in zip(stations, stations.dropFirst()) {
            gaps.append(hypot(b.point.x - a.point.x, b.point.y - a.point.y))
        }
        let spread = (gaps.max() ?? 0) - (gaps.min() ?? 0)
        #expect(spread < 0.5)
        #expect(spine.length > 100)
    }

    // MARK: - Restyling

    /// Switching style keeps where the arrow is, what it is painted and how
    /// thick it is.
    @Test func switchingStyleKeepsThePathColourAndWidth() {
        var content = arrow(.clean)
        content.colorHex = "#0A84FF"
        let layer = AnnotationBuilder.layer(content: content, from: CGPoint(x: 10, y: 50),
                                            to: CGPoint(x: 300, y: 200))
        let restyled = AnnotationBuilder.restyled(layer, arrowStyle: .sketch)
        #expect(restyled.annotation?.arrowStyle == .sketch)
        #expect(restyled.annotationEndpoint(.start) == layer.annotationEndpoint(.start))
        #expect(restyled.annotationEndpoint(.end) == layer.annotationEndpoint(.end))
        #expect(restyled.annotation?.colorHex == "#0A84FF")
        #expect(restyled.annotation?.strokeWidth == layer.annotation?.strokeWidth)
    }

    /// Reshuffling picks a new hand and nothing else.
    @Test func reshufflingChangesOnlyTheSeed() {
        let layer = AnnotationBuilder.layer(content: arrow(.handDrawn, seed: 5),
                                            from: CGPoint(x: 10, y: 50), to: CGPoint(x: 300, y: 200))
        let shuffled = AnnotationBuilder.restyled(layer, styleSeed: 6)
        #expect(shuffled.annotation?.styleSeed == 6)
        #expect(shuffled.annotation?.arrowStyle == .handDrawn)
        #expect(shuffled.annotationEndpoint(.start) == layer.annotationEndpoint(.start))
        #expect(shuffled.annotationEndpoint(.end) == layer.annotationEndpoint(.end))
    }

    /// The next seed is never the one just used, and is never zero (the seed
    /// an arrow from before styles has).
    @Test func theNextSeedIsAlwaysANewOne() {
        var seen: Set<UInt32> = []
        var seed: UInt32 = 0
        for _ in 0..<200 {
            seed = HandMadeArrow.seed(after: seed)
            #expect(seed != 0)
            seen.insert(seed)
        }
        #expect(seen.count == 200)
    }

    // MARK: - The tool remembers

    @Test func theLastUsedStyleSticksForTheNextArrow() throws {
        var styles = AnnotationStyles()
        #expect(styles.arrowStyle(forShape: .arrow) == .clean)
        styles.setArrowStyle(.marker, forShape: .arrow)
        #expect(styles.content(for: .arrow)?.arrowStyle == .marker)
        let decoded = try JSONDecoder().decode(AnnotationStyles.self,
                                               from: JSONEncoder().encode(styles))
        #expect(decoded.arrowStyle(forShape: .arrow) == .marker)
    }

    @Test func prefsFromBeforeStylesMeanClean() throws {
        let defaults = ShapeDefaults(colorHex: "#FF3B30", strokeWidth: 4, arrowheadScale: 1)
        var json = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(defaults)) as? [String: Any])
        json.removeValue(forKey: "arrowStyle")
        let decoded = try JSONDecoder().decode(ShapeDefaults.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.arrowStyle == .clean)
    }

    // MARK: - Export

    /// An SVG of a hand-made arrow carries the hand-made drawing, not the
    /// clean line underneath it.
    @Test func svgCarriesTheHandMadeDrawing() {
        let layer = AnnotationBuilder.layer(content: arrow(.brush), from: CGPoint(x: 10, y: 50),
                                            to: CGPoint(x: 300, y: 200))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [layer])
        let svg = SVGExport.write(doc).text
        #expect(!svg.contains("<line"))
        #expect(svg.contains("<path"))
    }
}
