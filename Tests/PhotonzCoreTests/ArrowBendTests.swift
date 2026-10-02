import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// An arrow can be curved: drag the handle in the middle of its shaft and the
/// shaft bends into a smooth arc through it, the head turning to follow, the
/// way Keynote, Skitch and Excalidraw arrows do (the user's hand-made arrow
/// references, 2026-10-01).
@Suite("Arrow bend")
struct ArrowBendTests {

    private let start = CGPoint(x: 0, y: 200)
    private let end = CGPoint(x: 400, y: 200)

    private func arrow(_ style: ArrowStyle = .clean, width: CGFloat = 4) -> AnnotationContent {
        var a = AnnotationContent(shape: .arrow, strokeWidth: width, start: start, end: end)
        a.arrowStyle = style
        a.styleSeed = 11
        return a
    }

    /// The same arrow bent so its middle passes through (200, 80).
    private func bent(_ style: ArrowStyle = .clean, width: CGFloat = 4) -> AnnotationContent {
        var a = arrow(style, width: width)
        a.bend = a.bend(through: CGPoint(x: 200, y: 80), straightWithin: 2)
        return a
    }

    private func close(_ a: CGPoint, _ b: CGPoint, _ within: CGFloat = 0.01) -> Bool {
        hypot(a.x - b.x, a.y - b.y) <= within
    }

    // MARK: - The model

    @Test func aNewArrowIsStraightWithItsHandleInTheMiddle() {
        let a = arrow()
        #expect(a.bend == nil)
        #expect(close(a.bendHandle, CGPoint(x: 200, y: 200)))
        #expect(close(a.spine.control, CGPoint(x: 200, y: 200)))
    }

    @Test func theCurvePassesThroughTheHandle() {
        let a = bent()
        #expect(a.bend != nil)
        #expect(close(a.bendHandle, CGPoint(x: 200, y: 80)))
        #expect(close(a.spine.point(at: 0.5), CGPoint(x: 200, y: 80)))
    }

    @Test func theHandleNeedNotSitHalfwayAlong() {
        var a = arrow()
        a.bend = a.bend(through: CGPoint(x: 120, y: 60), straightWithin: 2)
        #expect(close(a.spine.point(at: 0.5), CGPoint(x: 120, y: 60)))
    }

    @Test func aHandleBackOnTheStraightLineStraightensIt() {
        var a = bent()
        #expect(a.bend(through: CGPoint(x: 230, y: 201.5), straightWithin: 2) == nil)
        a.bend = a.bend(through: CGPoint(x: 230, y: 201.5), straightWithin: 2)
        #expect(a.bend == nil)
        // ...and just off the line it still bends.
        #expect(a.bend(through: CGPoint(x: 230, y: 205), straightWithin: 2) != nil)
    }

    @Test func aLineOrABoxNeverBends() {
        var line = AnnotationContent(shape: .line, strokeWidth: 4, start: start, end: end)
        #expect(line.bend(through: CGPoint(x: 200, y: 80), straightWithin: 2) == nil)
        line.bend = ArrowBend(along: 0.5, across: -0.3)
        #expect(close(line.spine.control, CGPoint(x: 200, y: 200)))
    }

    /// Moving an end keeps the curve's shape: the bend is stated against the
    /// line between the ends, so it turns and stretches with them.
    @Test func movingAnEndKeepsTheCurvesShape() {
        let a = bent()
        let layer = AnnotationBuilder.layer(content: a, from: start, to: end)
        // Twice as long, turned a quarter: the handle is turned and doubled too.
        let moved = AnnotationBuilder.updating(layer, start: start, end: CGPoint(x: 0, y: -600))
        let b = try! #require(moved.annotation)
        #expect(b.bend == a.bend)
        let handle = CGPoint(x: moved.frame.minX + b.bendHandle.x,
                             y: moved.frame.minY + b.bendHandle.y)
        // The handle sat 120 to the left of travel on a 400 long arrow, half way
        // along: on an 800 long arrow heading up it sits 240 to the left of
        // its middle.
        #expect(close(handle, CGPoint(x: -240, y: -200), 0.5))
    }

    // MARK: - Saving

    @Test func theBendSurvivesSavingAndReopening() throws {
        let a = bent(.brush)
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(AnnotationContent.self, from: data)
        #expect(back.bend == a.bend)
        #expect(back == a)
    }

    @Test func aStraightArrowWritesNoBendAtAll() throws {
        let data = try JSONEncoder().encode(arrow())
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("bend"))
    }

    @Test func anArrowFromBeforeBendsOpensStraight() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(arrow())) as? [String: Any] ?? [:]
        json["bend"] = nil
        let back = try JSONDecoder().decode(AnnotationContent.self,
                                            from: JSONSerialization.data(withJSONObject: json))
        #expect(back.bend == nil)
    }

    @Test func aBentLayerSurvivesACopy() throws {
        let layer = AnnotationBuilder.layer(content: bent(), from: start, to: end)
        let copy = try JSONDecoder().decode(Layer.self, from: JSONEncoder().encode(layer))
        #expect(copy.annotation?.bend == layer.annotation?.bend)
    }

    // MARK: - The head follows the curve

    @Test func theHeadPointsAlongTheCurveWhereItEnds() {
        let a = bent()
        let head = Geometry.arrowhead(start: a.headAim, end: a.end, strokeWidth: a.strokeWidth,
                                      scale: a.arrowheadScale, style: .triangle)
        let base = CGPoint(x: (head[1].x + head[2].x) / 2, y: (head[1].y + head[2].y) / 2)
        let heading = CGVector(dx: a.end.x - base.x, dy: a.end.y - base.y)
        let length = hypot(heading.dx, heading.dy)
        let tangent = a.spine.direction(at: 1)
        #expect(abs(heading.dx / length - tangent.dx) < 1e-6)
        #expect(abs(heading.dy / length - tangent.dy) < 1e-6)
        // Coming in from above-left, not straight along the line.
        #expect(tangent.dy > 0.3)
    }

    @Test func aStraightArrowAimsFromItsTailExactly() {
        let a = arrow()
        #expect(a.headAim == a.start)
    }

    @Test func theShaftStopsInsideTheHeadOnTheCurve() {
        let a = bent()
        let shaft = a.shaftSpine
        #expect(close(shaft.start, a.start))
        // The shaft's end is ON the curve, short of the tip.
        let stop = Geometry.arrowShaftEnd(start: a.headAim, end: a.end, strokeWidth: a.strokeWidth,
                                          scale: a.arrowheadScale, style: a.arrowheadStyle)
        let back = hypot(a.end.x - stop.x, a.end.y - stop.y)
        #expect(back > 1)
        #expect(a.spine.distance(to: shaft.end) < 0.5)
        #expect(abs(a.spine.length - shaft.length - back) < 0.5)
        // ...and it follows the same curve the whole way there.
        for t in stride(from: CGFloat(0), through: 1, by: 0.125) {
            #expect(a.spine.distance(to: shaft.point(at: t)) < 0.5)
        }
    }

    @Test func aStraightShaftIsALine() {
        let a = arrow()
        var elements = 0
        var curves = 0
        a.shaftPath.applyWithBlock { e in
            elements += 1
            if e.pointee.type == .addQuadCurveToPoint { curves += 1 }
        }
        #expect(curves == 0)
        #expect(elements == 2)
        var bentCurves = 0
        bent().shaftPath.applyWithBlock { e in
            if e.pointee.type == .addQuadCurveToPoint { bentCurves += 1 }
        }
        #expect(bentCurves == 1)
    }

    // MARK: - The frame and the hit

    @Test func theLayerFrameHoldsTheCurve() {
        for style in ArrowStyle.allCases {
            let a = bent(style, width: 8)
            let layer = AnnotationBuilder.layer(content: a, from: start, to: end)
            let peak = CGPoint(x: 200, y: 80)
            #expect(layer.frame.insetBy(dx: 4, dy: 4).contains(peak), "\(style)")
            // The ink box hugs the bow too: past it by no more than the same
            // style reaches past a straight arrow's line.
            let drawn = layer.drawnBounds()
            let straight = AnnotationBuilder.layer(content: arrow(style, width: 8),
                                                   from: start, to: end).drawnBounds()
            let overhang = 200 - straight.minY
            #expect(drawn.minY < 80, "\(style) drawn \(drawn)")
            #expect(drawn.minY > 80 - overhang - 6, "\(style) drawn \(drawn) overhang \(overhang)")
        }
    }

    @Test func theFrameDoesNotSwellOnTheFlatSide() {
        let layer = AnnotationBuilder.layer(content: bent(), from: start, to: end)
        // The bow is above the line; below it there is only the head and a cap.
        #expect(layer.frame.maxY < 230)
    }

    @Test func clickingTheCurvedShaftSelectsTheArrow() {
        for style in ArrowStyle.allCases {
            let layer = AnnotationBuilder.layer(content: bent(style), from: start, to: end)
            let onCurve = bent(style).spine.point(at: 0.3)
            #expect(layer.contains(canvasPoint: onCurve), "\(style)")
            // The straight line between the ends is empty air now.
            #expect(!layer.contains(canvasPoint: CGPoint(x: 200, y: 200)), "\(style)")
        }
    }

    @Test func theBendHandleIsFoundUnderThePointer() {
        let layer = AnnotationBuilder.layer(content: bent(), from: start, to: end)
        #expect(AnnotationEndpoints.bendHit(at: CGPoint(x: 203, y: 82), layer: layer, zoom: 1))
        #expect(!AnnotationEndpoints.bendHit(at: CGPoint(x: 230, y: 82), layer: layer, zoom: 1))
        let line = AnnotationBuilder.layer(
            content: AnnotationContent(shape: .line, strokeWidth: 4, start: start, end: end),
            from: start, to: end)
        #expect(!AnnotationEndpoints.bendHit(at: CGPoint(x: 200, y: 200), layer: line, zoom: 1))
    }

    @Test func bendingALayerThroughADocumentPointRebuildsItsFrame() {
        let layer = AnnotationBuilder.layer(content: arrow(), from: start, to: end)
        let bentLayer = AnnotationBuilder.bending(layer, through: CGPoint(x: 200, y: 80),
                                                  straightWithin: 2)
        let a = try! #require(bentLayer.annotation)
        #expect(a.bend != nil)
        #expect(close(CGPoint(x: bentLayer.frame.minX + a.bendHandle.x,
                              y: bentLayer.frame.minY + a.bendHandle.y),
                      CGPoint(x: 200, y: 80), 0.01))
        #expect(bentLayer.annotationEndpoint(.start).map { close($0, start) } == true)
        #expect(bentLayer.annotationEndpoint(.end).map { close($0, end) } == true)
        #expect(bentLayer.frame.minY < 80)
        #expect(bentLayer.id == layer.id)
        // ...and back onto the line straightens it, frame and all.
        let straight = AnnotationBuilder.bending(bentLayer, through: CGPoint(x: 200, y: 200),
                                                 straightWithin: 2)
        #expect(straight.annotation?.bend == nil)
        #expect(straight.frame == layer.frame)
    }

    // MARK: - Every style follows

    @Test func everyHandMadeStyleFollowsTheBend() {
        for style in ArrowStyle.allCases where style.isHandMade {
            let a = bent(style)
            let shaft = HandMadeArrow.inks(for: a).filter { $0.part == .shaft }.flatMap(\.points)
            let nearest = shaft.map { hypot($0.x - 200, $0.y - 80) }.min() ?? .infinity
            #expect(nearest < 12, "\(style) is \(nearest) from the bend")
            let onChord = shaft.map { hypot($0.x - 200, $0.y - 200) }.min() ?? .infinity
            #expect(onChord > 60, "\(style) still runs along the straight line")
        }
    }

    // MARK: - The caption

    @Test func aCaptionGrowsAwayFromTheTailAlongTheCurve() {
        var a = AnnotationContent(shape: .arrow, strokeWidth: 4, start: start,
                                  end: CGPoint(x: 400, y: 260))
        // Bent so the tail leaves heading straight up.
        a.bend = ArrowBend(along: 0, across: 0.6)
        let tail = a.spine.direction(at: 0)
        #expect(abs(tail.dx) < abs(tail.dy))
        let growth = a.captionGrowthDirection()
        #expect(growth.width == 0)
        #expect(growth.height == (tail.dy > 0 ? -1 : 1))
    }

    // MARK: - Export

    @Test func aBentCleanArrowExportsAsACurve() {
        let document = PhotonzDocument(canvasSize: CGSize(width: 480, height: 320), layers: [
            AnnotationBuilder.layer(content: bent(), from: start, to: end)
        ])
        let text = SVGExport.write(document).text
        #expect(!text.contains("<line"))
        #expect(text.contains(" Q"))
    }
}
