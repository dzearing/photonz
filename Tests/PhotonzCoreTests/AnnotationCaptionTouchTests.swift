import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The tail must RUN INTO the caption pill: whatever spot the planner picks,
/// the tail is the middle of the pill's near edge and there is no space
/// between the two. Reported by the user on 2026-09-05 with a screenshot of a
/// short label whose pill floated above and to the right of the tail.
@Suite("A captioned arrow's tail meets its pill")
struct AnnotationCaptionTouchTests {

    private let canvas = CGSize(width: 1440, height: 960)

    private func arrow(_ caption: String, from tail: CGPoint, to head: CGPoint,
                       canvas: CGSize) -> Layer {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = caption
        return AnnotationBuilder.planningCaption(
            AnnotationBuilder.layer(content: content, from: tail, to: head), canvas: canvas)
    }

    /// The pill as it lands, in document space, at whatever size is passed —
    /// the estimate by default, a measured pill when a caller has one.
    private func pill(_ layer: Layer, size: CGSize? = nil) -> CGRect {
        let a = layer.annotation!
        let size = size ?? a.estimatedCaptionSize
        let center = a.captionPillCenter(forPillSize: size)
        return CGRect(x: layer.frame.minX + center.x - size.width / 2,
                      y: layer.frame.minY + center.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The point on the pill's near edge the tail should land on: the middle of
    /// whichever of the four edges faces the tail.
    private func nearEdgeMidpoint(of pill: CGRect, growth: CGSize) -> CGPoint {
        if growth.width > 0 { return CGPoint(x: pill.minX, y: pill.midY) }
        if growth.width < 0 { return CGPoint(x: pill.maxX, y: pill.midY) }
        if growth.height > 0 { return CGPoint(x: pill.midX, y: pill.minY) }
        return CGPoint(x: pill.midX, y: pill.maxY)
    }

    private func expectTailTouchesPill(_ layer: Layer, size: CGSize? = nil,
                                       _ label: Comment) {
        let a = layer.annotation!
        let tail = layer.annotationEndpoint(.start)!
        let box = pill(layer, size: size)
        let meeting = nearEdgeMidpoint(of: box, growth: a.captionGrowthDirection())
        #expect(abs(meeting.x - tail.x) < 0.001, label)
        #expect(abs(meeting.y - tail.y) < 0.001, label)
    }

    /// Eight directions, three label lengths, room on every side: the pill sits
    /// behind the tail and its near edge starts exactly there.
    @Test func inOpenSpaceTheTailIsTheMiddleOfThePillsNearEdge() {
        let center = CGPoint(x: 720, y: 480)
        let captions = ["ok", "Primary action", "a much longer caption than anyone should write"]
        for step in 0..<8 {
            let angle = CGFloat(step) * .pi / 4
            let head = CGPoint(x: center.x + cos(angle) * 240, y: center.y + sin(angle) * 240)
            for caption in captions {
                let layer = arrow(caption, from: center, to: head, canvas: canvas)
                expectTailTouchesPill(layer, "angle \(step) caption \(caption)")
            }
        }
    }

    /// The same promise for a pill measured smaller than the estimate: the
    /// attachment is a point on the tail, so the real pill hangs off it too.
    @Test func aMeasuredPillTouchesTheTailJustAsTheEstimateDoes() {
        let layer = arrow("ok", from: CGPoint(x: 400, y: 400),
                          to: CGPoint(x: 700, y: 620), canvas: canvas)
        expectTailTouchesPill(layer, size: CGSize(width: 44, height: 46), "measured pill")
    }

    /// Near an edge the planner has to move the pill. It may choose any side,
    /// but it may not let go of the tail: every spot it can pick still meets it.
    @Test func aTailNearEveryEdgeStillHoldsItsPill() {
        let spots: [(String, CGPoint, CGPoint)] = [
            ("left margin", CGPoint(x: 40, y: 480), CGPoint(x: 600, y: 480)),
            ("right margin", CGPoint(x: 1400, y: 480), CGPoint(x: 800, y: 480)),
            ("top margin", CGPoint(x: 720, y: 30), CGPoint(x: 720, y: 600)),
            ("bottom margin", CGPoint(x: 720, y: 930), CGPoint(x: 720, y: 300)),
            ("top left corner", CGPoint(x: 40, y: 40), CGPoint(x: 600, y: 600)),
            ("bottom right corner", CGPoint(x: 1400, y: 920), CGPoint(x: 700, y: 300)),
        ]
        for (name, tail, head) in spots {
            for caption in ["ok", "Primary action"] {
                let layer = arrow(caption, from: tail, to: head, canvas: canvas)
                expectTailTouchesPill(layer, "\(name) / \(caption)")
            }
        }
    }

    /// A nearly round pill in a corner used to slide back onto the picture and
    /// swallow the tail. It must sit beside it, never on it.
    @Test func aShortLabelInACornerDoesNotCoverTheTail() {
        let layer = arrow("ok", from: CGPoint(x: 40, y: 40),
                          to: CGPoint(x: 600, y: 600), canvas: canvas)
        let tail = layer.annotationEndpoint(.start)!
        let box = pill(layer)
        #expect(!box.insetBy(dx: 0.5, dy: 0.5).contains(tail))
    }

    /// A hand-placed pill is the person's choice, so it keeps the spot it was
    /// dropped at even though it no longer touches the tail.
    @Test func aPinnedPillKeepsItsOwnSpot() {
        var layer = arrow("ok", from: CGPoint(x: 700, y: 500),
                          to: CGPoint(x: 900, y: 600), canvas: canvas)
        layer = AnnotationBuilder.placingCaption(layer, at: CGPoint(x: 500, y: 300),
                                                 canvas: canvas)
        let before = layer.annotation!.captionOffset
        layer = AnnotationBuilder.planningCaption(layer, canvas: canvas)
        #expect(layer.annotation!.captionOffset == before)
    }
}

/// What a selection outline should hug: the ink the layer actually puts down,
/// not the padded box the rasterizer needs.
@Suite("Drawn bounds hug the ink")
struct DrawnBoundsTests {

    private let canvas = CGSize(width: 1440, height: 960)

    @Test func aPlainArrowsDrawnBoxIsMuchSmallerThanItsFrame() {
        let content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 200, y: 200),
                                            to: CGPoint(x: 400, y: 200))
        let drawn = layer.drawnBounds()
        // The tip is a point, so the ink stops exactly where the arrow points;
        // the tail is a round cap, so it reaches half a stroke back.
        #expect(abs(drawn.minX - (200 - 2)) < 0.01)
        #expect(abs(drawn.maxX - 400) < 0.01)
        #expect(drawn.width < layer.frame.width)
        #expect(abs(drawn.midY - 200) < 0.01)
        #expect(layer.frame.contains(drawn.insetBy(dx: 0.01, dy: 0.01)))
    }

    /// A diagonal arrow's ink is a thin band, so its box is far tighter than
    /// the frame's square padding on all four sides.
    @Test func aDiagonalArrowsDrawnBoxDropsThePaddingItDoesNotUse() {
        let content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        let layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 200, y: 200),
                                            to: CGPoint(x: 400, y: 340))
        let drawn = layer.drawnBounds()
        #expect(drawn.width < layer.frame.width)
        #expect(drawn.height < layer.frame.height)
        // The tail is a round cap, so the box reaches half a stroke past it.
        #expect(abs(drawn.minX - (200 - 2)) < 0.5)
        #expect(abs(drawn.maxX - 400) < 0.01)
    }

    @Test func aCaptionedArrowsDrawnBoxIsTheArrowAndTheMeasuredPill() {
        var content = AnnotationContent(shape: .arrow, strokeWidth: 4, colorHex: "#FF3B30")
        content.caption = "a much longer caption than anyone should write"
        var layer = AnnotationBuilder.layer(content: content,
                                            from: CGPoint(x: 700, y: 400),
                                            to: CGPoint(x: 900, y: 560))
        layer = AnnotationBuilder.planningCaption(layer, canvas: canvas)
        // The pill really measures far less than the generous estimate; the
        // outline must believe the measurement.
        let measured = CGSize(width: 260, height: 46)
        let tight = layer.drawnBounds(captionPillSize: measured)
        let generous = layer.drawnBounds()
        #expect(tight.width < generous.width)
        #expect(tight.width < layer.frame.width)
        #expect(tight.height < layer.frame.height)
        // Both the head and the pill are inside it (the tip sits exactly on
        // the edge, which CGRect.contains counts as outside).
        #expect(tight.insetBy(dx: -0.01, dy: -0.01).contains(CGPoint(x: 900, y: 560)))
        let a = layer.annotation!
        let center = a.captionPillCenter(forPillSize: measured)
        let pill = CGRect(x: layer.frame.minX + center.x - measured.width / 2,
                          y: layer.frame.minY + center.y - measured.height / 2,
                          width: measured.width, height: measured.height)
        #expect(tight.insetBy(dx: -0.01, dy: -0.01).contains(pill))
    }

    /// Everything that is not an open stroke keeps the box it always had.
    @Test func otherContentKeepsItsOwnFrame() {
        let rect = Layer(name: "Rectangle",
                         content: .annotation(AnnotationContent(shape: .rectangle, strokeWidth: 2,
                                                                colorHex: "#FF3B30")),
                         frame: CGRect(x: 10, y: 20, width: 100, height: 50))
        #expect(rect.drawnBounds() == rect.frame)
    }
}
