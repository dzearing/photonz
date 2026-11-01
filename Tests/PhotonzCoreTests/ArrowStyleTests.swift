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

    @Test func tenStylesInPickerOrder() {
        #expect(ArrowStyle.allCases == [.clean, .handDrawn, .marker, .brush, .sketch,
                                        .dashed, .block, .neon, .dotted, .elbow])
    }

    /// The four drawn from the user's own references have a hand that
    /// Reshuffle redraws; the five from the prototype are exact.
    @Test func onlyTheFourHandStylesHaveAHand() {
        #expect(ArrowStyle.allCases.filter(\.hasHand) == [.handDrawn, .marker, .brush, .sketch])
        #expect(ArrowStyle.allCases.filter(\.glows) == [.neon])
    }

    @Test func cleanIsTheDefaultAndTheOnlyOneNotHandMade() {
        #expect(ArrowStyle.standard == .clean)
        #expect(AnnotationContent(shape: .arrow).arrowStyle == .clean)
        #expect(!ArrowStyle.clean.drawsOwnInk)
        for style in ArrowStyle.allCases where style != .clean {
            #expect(style.drawsOwnInk)
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

    /// Every style, the five new ones included, is saved and opened as itself.
    @Test func everyStyleSurvivesARoundTrip() throws {
        for style in ArrowStyle.allCases {
            let drawn = arrow(style, seed: 9)
            let decoded = try JSONDecoder().decode(AnnotationContent.self,
                                                   from: JSONEncoder().encode(drawn))
            #expect(decoded.arrowStyle == style)
            #expect(HandMadeArrow.inks(for: decoded) == HandMadeArrow.inks(for: drawn), "\(style)")
        }
    }

    // MARK: - What the panel asks about

    /// A hand-made style draws its own head and its own tail, so the Ending
    /// picker and the tail's Ends row are Clean's alone. Head Size still sizes
    /// every head.
    @Test func handMadeStylesTakeTheEndingAndEndsRowsAway() {
        let clean = arrow(.clean)
        #expect(clean.settingRows.contains(.headStyle))
        #expect(clean.settingRows.contains(.lineEnds))
        for style in ArrowStyle.allCases where style.drawsOwnInk {
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
        for style in ArrowStyle.allCases where style.drawsOwnInk {
            let inks = HandMadeArrow.inks(for: arrow(style))
            #expect(inks.contains { $0.part == .shaft }, "\(style) has no shaft")
            #expect(inks.contains { $0.part == .head }, "\(style) has no head")
        }
    }

    /// The same arrow is drawn the same way every time: on the canvas, after
    /// reopening, and in an export. Nothing about it wobbles between renders.
    @Test func theSameArrowAlwaysLooksTheSame() {
        for style in ArrowStyle.allCases where style.drawsOwnInk {
            #expect(HandMadeArrow.inks(for: arrow(style)) == HandMadeArrow.inks(for: arrow(style)))
        }
    }

    /// ...and a new seed is a new hand: Reshuffle changes the drawing.
    @Test func aNewSeedDrawsItDifferently() {
        for style in ArrowStyle.allCases where style.hasHand {
            #expect(HandMadeArrow.inks(for: arrow(style, seed: 1))
                    != HandMadeArrow.inks(for: arrow(style, seed: 2)), "\(style)")
        }
    }

    /// ...and an exact style is the same drawing whatever its seed.
    @Test func anExactStyleIgnoresTheSeed() {
        for style in ArrowStyle.allCases where style.drawsOwnInk && !style.hasHand {
            #expect(HandMadeArrow.inks(for: arrow(style, seed: 1))
                    == HandMadeArrow.inks(for: arrow(style, seed: 2)), "\(style)")
        }
    }

    /// The tip of a hand-made arrow still lands on the point it marks: it is a
    /// pointer, however loose the hand that drew it.
    @Test func theHeadStillPointsAtTheEnd() {
        for style in ArrowStyle.allCases where style.drawsOwnInk {
            let a = arrow(style)
            let head = HandMadeArrow.inks(for: a).filter { $0.part == .head }
            let nearest = head.flatMap(\.points)
                .map { hypot($0.x - a.end.x, $0.y - a.end.y) }.min() ?? .infinity
            #expect(nearest <= a.strokeWidth * 1.5, "\(style) head is \(nearest) from the tip")
        }
    }

    /// The shaft starts where the arrow starts.
    @Test func theShaftStartsAtTheTail() {
        for style in ArrowStyle.allCases where style.drawsOwnInk {
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
        for style in ArrowStyle.allCases where style.drawsOwnInk {
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
        for style in ArrowStyle.allCases where style.drawsOwnInk {
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
        // Elbow is a right-angle connector: a bend picks its corner instead
        // (`anElbowsBendPicksItsCorner`).
        for style in ArrowStyle.allCases where style.drawsOwnInk && style != .elbow {
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

    // MARK: - The five exact styles (markup.md section 5)

    private func points(_ inks: [ArrowInk], _ part: ArrowInk.Part) -> [CGPoint] {
        inks.filter { $0.part == part }.flatMap(\.points)
    }

    private func distance(_ p: CGPoint, toLineFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        return abs((p.x - a.x) * dy - (p.y - a.y) * dx) / length
    }

    /// Dashed: the line is broken into many even dashes with square ends, and
    /// the head is one solid triangle whose point is the tip.
    @Test func dashedIsEvenDashesAndASolidHead() throws {
        let a = arrow(.dashed, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 400, y: 100))
        let inks = HandMadeArrow.inks(for: a)
        let dashes = inks.filter { $0.part == .shaft }
        #expect(dashes.count >= 12, "\(dashes.count) dashes")
        #expect(dashes.allSatisfy { $0.kind == .polygon })
        // Even: every dash is the same length along the line.
        let lengths = dashes.map { d in (d.points.map(\.x).max() ?? 0) - (d.points.map(\.x).min() ?? 0) }
        #expect((lengths.max() ?? 0) - (lengths.min() ?? 0) < 0.01)
        // ...and as thick as the line.
        let thick = (dashes[0].points.map(\.y).max() ?? 0) - (dashes[0].points.map(\.y).min() ?? 0)
        #expect(abs(thick - a.strokeWidth) < 0.01)
        let head = try #require(inks.first { $0.part == .head })
        #expect(head.kind == .polygon)
        #expect(head.points.count == 3)
        #expect(head.points.contains { hypot($0.x - a.end.x, $0.y - a.end.y) < 0.01 })
    }

    /// Block: one bold filled shape that widens from tail to head, and a head
    /// far wider than the shaft where they meet.
    @Test func blockWidensIntoABigHead() throws {
        let a = arrow(.block, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 400, y: 100))
        let inks = HandMadeArrow.inks(for: a)
        let body = try #require(inks.first { $0.part == .shaft })
        let head = try #require(inks.first { $0.part == .head })
        #expect(body.kind == .polygon && head.kind == .polygon)
        func halfWidth(atX x: CGFloat) -> CGFloat {
            // The body's outline either side of the line, nearest to x.
            let near = body.points.sorted { abs($0.x - x) < abs($1.x - x) }.prefix(2)
            return near.map { abs($0.y - 100) }.max() ?? 0
        }
        let tail = halfWidth(atX: 0)
        let late = halfWidth(atX: 300)
        #expect(tail >= a.strokeWidth / 2)
        #expect(late > tail * 2, "tail \(tail), near the head \(late)")
        let headHalf = (head.points.map { abs($0.y - 100) }.max() ?? 0)
        let bodyHalf = body.points.map { abs($0.y - 100) }.max() ?? 0
        #expect(headHalf > bodyHalf * 1.8)
        #expect(head.points.contains { hypot($0.x - a.end.x, $0.y - a.end.y) < 0.01 })
    }

    /// Neon: a line and an open chevron head, a bright core along both, and a
    /// glow that only Neon has.
    @Test func neonIsALineAnOpenHeadACoreAndAGlow() {
        let a = arrow(.neon, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 400, y: 100))
        let inks = HandMadeArrow.inks(for: a)
        #expect(inks.filter { $0.part != .core }.allSatisfy { $0.kind == .stroke })
        let core = inks.filter { $0.part == .core }
        #expect(!core.isEmpty)
        let line = inks.filter { $0.part != .core }.map(\.width).max() ?? 0
        #expect(core.allSatisfy { $0.width < line * 0.5 })
        // Open: the head is two strokes from the tip back to its wings.
        let head = inks.filter { $0.part == .head }
        #expect(head.count == 2)
        #expect(!HandMadeArrow.outlines(for: a).core.isEmpty)
        #expect(HandMadeArrow.glowRadii(for: a).count == 2)
        for style in ArrowStyle.allCases where style != .neon {
            #expect(HandMadeArrow.glowRadii(for: arrow(style)).isEmpty, "\(style)")
            #expect(HandMadeArrow.outlines(for: arrow(style)).core.isEmpty, "\(style)")
        }
    }

    /// The glow is part of what an arrow draws, so its frame makes room.
    @Test func theFrameMakesRoomForTheGlow() {
        let neon = arrow(.neon, width: 6)
        let glow = HandMadeArrow.glowRadii(for: neon).max() ?? 0
        #expect(neon.renderPadding >= glow * 3)
        #expect(neon.renderPadding > arrow(.clean, width: 6).renderPadding)
    }

    /// Dotted: evenly spaced round dots, a bigger one at the tail, and a
    /// chevron through the tip.
    @Test func dottedIsEvenDotsABigTailDotAndAChevron() throws {
        let a = arrow(.dotted, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 400, y: 100))
        let inks = HandMadeArrow.inks(for: a)
        let dots = inks.filter { $0.part == .shaft }
        #expect(dots.count >= 20, "\(dots.count) dots")
        #expect(dots.allSatisfy { $0.kind == .fill })
        let centres = dots.map { d in
            CGPoint(x: d.points.map(\.x).reduce(0, +) / CGFloat(d.points.count),
                    y: d.points.map(\.y).reduce(0, +) / CGFloat(d.points.count))
        }
        let radii = zip(dots, centres).map { d, c in d.points.map { hypot($0.x - c.x, $0.y - c.y) }.max() ?? 0 }
        let tailIndex = try #require(centres.indices.min { centres[$0].x < centres[$1].x })
        #expect(hypot(centres[tailIndex].x - a.start.x, centres[tailIndex].y - a.start.y) < 0.01)
        let others = radii.enumerated().filter { $0.offset != tailIndex }.map(\.element)
        #expect(radii[tailIndex] > (others.max() ?? 0) * 1.5)
        let xs = centres.enumerated().filter { $0.offset != tailIndex }.map(\.element.x).sorted()
        let gaps = zip(xs, xs.dropFirst()).map { $1 - $0 }
        #expect((gaps.max() ?? 0) - (gaps.min() ?? 0) < 0.01)
        #expect((gaps.min() ?? 0) > (others.max() ?? 0) * 2.5, "dots must not touch")
        let head = inks.filter { $0.part == .head }
        #expect(head.count == 2 && head.allSatisfy { $0.kind == .stroke })
    }

    /// Elbow: two straight legs at a right angle, joined by a rounded corner,
    /// a dot at the tail and a solid head pointing along the last leg.
    @Test func anElbowTurnsOneRightAngle() throws {
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 300, y: 200)
        let a = arrow(.elbow, start: start, end: end)
        let inks = HandMadeArrow.inks(for: a)
        let shaft = inks.filter { $0.part == .shaft }.flatMap(\.points)
        let corner = CGPoint(x: end.x, y: start.y)   // across first, then down
        let radius = a.strokeWidth * 4
        for p in shaft where hypot(p.x - corner.x, p.y - corner.y) > radius {
            let onAcross = abs(p.y - start.y) < a.strokeWidth * 1.6
            let onDown = abs(p.x - end.x) < a.strokeWidth * 1.6
            #expect(onAcross || onDown, "\(p) is on neither leg")
        }
        // It really does reach round the corner.
        #expect(shaft.contains { abs($0.x - end.x) < 0.01 && $0.y > 100 })
        let head = try #require(inks.first { $0.part == .head })
        #expect(head.kind == .polygon)
        // Pointing down the last leg: the wings sit level, above the tip.
        let wings = head.points.filter { hypot($0.x - end.x, $0.y - end.y) > 0.01 }
        #expect(wings.count == 2)
        #expect(abs(wings[0].y - wings[1].y) < 0.01 && wings[0].y < end.y)
        // The dot on the tail.
        #expect(inks.contains { $0.kind == .fill && $0.points.allSatisfy { hypot($0.x - start.x, $0.y - start.y) < a.strokeWidth * 1.5 } })
    }

    /// Ends that line up need no corner: the elbow is a straight connector.
    @Test func anElbowBetweenLevelEndsIsStraight() {
        let a = arrow(.elbow, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 400, y: 101))
        let shaft = HandMadeArrow.inks(for: a).filter { $0.part == .shaft }.flatMap(\.points)
        #expect(shaft.allSatisfy { distance($0, toLineFrom: a.start, to: a.end) < a.strokeWidth * 1.5 })
    }

    /// A short vertical leg cannot hold the head, so the elbow goes down first
    /// and the head points across.
    @Test func anElbowWithAShortDropTurnsTheOtherWay() throws {
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 300, y: 20)
        let a = arrow(.elbow, start: start, end: end)
        let head = try #require(HandMadeArrow.inks(for: a).first { $0.part == .head })
        let wings = head.points.filter { hypot($0.x - end.x, $0.y - end.y) > 0.01 }
        #expect(abs(wings[0].x - wings[1].x) < 0.01 && wings[0].x < end.x)
    }

    /// Dragging the bend handle towards a corner turns the elbow there.
    @Test func anElbowsBendPicksItsCorner() {
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 300, y: 200)
        let a = arrow(.elbow, start: start, end: end)
        let downFirst = ArrowSpine(start: start, control: CGPoint(x: 20, y: 190), end: end)
        let shaft = HandMadeArrow.inks(for: a, along: downFirst).filter { $0.part == .shaft }.flatMap(\.points)
        #expect(shaft.contains { abs($0.x - start.x) < 0.01 && $0.y > 100 })
        #expect(!shaft.contains { abs($0.y - start.y) < 0.01 && $0.x > 100 })
    }

    /// ...the same through the bend handle a person drags.
    @Test func anElbowBentByItsHandleTurnsAtThatCorner() throws {
        let start = CGPoint(x: 0, y: 0), end = CGPoint(x: 300, y: 200)
        let layer = AnnotationBuilder.layer(content: arrow(.elbow, start: start, end: end), from: start, to: end)
        let bent = AnnotationBuilder.bending(layer, through: CGPoint(x: 30, y: 180), straightWithin: 2)
        let a = try #require(bent.annotation)
        let shaft = HandMadeArrow.inks(for: a).filter { $0.part == .shaft }.flatMap(\.points)
            .map { CGPoint(x: $0.x + bent.frame.minX, y: $0.y + bent.frame.minY) }
        #expect(shaft.contains { abs($0.x - start.x) < 0.01 && $0.y > 100 })
        #expect(!shaft.contains { abs($0.y - start.y) < 0.01 && $0.x > 100 })
    }

    /// Every exact style keeps the arrow's own colour on the shaft and the head
    /// (no part is painted in some other colour), and lists its pieces in a
    /// part the renderer knows.
    @Test func switchingToAnExactStyleKeepsEverythingButTheLook() {
        for style in [ArrowStyle.dashed, .block, .neon, .dotted, .elbow] {
            var content = arrow(.clean)
            content.colorHex = "#0A84FF"
            content.arrowheadScale = 1.6
            let layer = AnnotationBuilder.layer(content: content, from: CGPoint(x: 10, y: 50),
                                                to: CGPoint(x: 300, y: 200))
            let restyled = AnnotationBuilder.restyled(layer, arrowStyle: style)
            #expect(restyled.annotationEndpoint(.start) == layer.annotationEndpoint(.start), "\(style)")
            #expect(restyled.annotationEndpoint(.end) == layer.annotationEndpoint(.end), "\(style)")
            #expect(restyled.annotation?.colorHex == "#0A84FF")
            #expect(restyled.annotation?.strokeWidth == layer.annotation?.strokeWidth)
            #expect(restyled.annotation?.arrowheadScale == 1.6)
            let back = AnnotationBuilder.restyled(restyled, arrowStyle: .clean)
            #expect(back.annotationEndpoint(.start) == layer.annotationEndpoint(.start), "\(style)")
            #expect(back.annotationEndpoint(.end) == layer.annotationEndpoint(.end), "\(style)")
        }
    }

    /// Head Size reaches every exact style's head.
    @Test func headSizeSizesEveryExactHead() {
        for style in [ArrowStyle.dashed, .block, .neon, .dotted, .elbow] {
            func headReach(_ scale: CGFloat) -> CGFloat {
                let a = arrow(style, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 400, y: 300), scale: scale)
                return points(HandMadeArrow.inks(for: a), .head)
                    .map { hypot($0.x - a.end.x, $0.y - a.end.y) }.max() ?? 0
            }
            #expect(headReach(2) > headReach(1) * 1.5, "\(style)")
        }
    }

    /// An SVG of a neon arrow carries its glow.
    @Test func svgCarriesTheNeonGlow() {
        let layer = AnnotationBuilder.layer(content: arrow(.neon), from: CGPoint(x: 10, y: 50),
                                            to: CGPoint(x: 300, y: 200))
        let doc = PhotonzDocument(canvasSize: CGSize(width: 400, height: 300), layers: [layer])
        let svg = SVGExport.write(doc).text
        #expect(svg.contains("feGaussianBlur"))
        #expect(svg.contains("filter=\"url(#"))
    }
}
