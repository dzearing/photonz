import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A moving layer draws its path on the canvas, and dragging the path bends it
/// into an arc (task `a-moving-layer-draws-its-path-on-the-canvas-and`,
/// `docs/design/mocks/pages/video-move-wt.html` steps 5, 7 and 8).
///
/// Written before the model. Two position keys are a straight run; the handle
/// in the middle of that run is a point ON the path, and dragging it bends the
/// run so it passes through where the handle was let go. The keys stay the
/// same keys: what changes is how the value gets from one to the other, so the
/// render, the export and the Properties readout all follow the arc because
/// they all ask the motion where it is.
@Suite("Motion path")
struct MotionPathTests {

    // MARK: - Fixtures

    /// A 100 x 50 graphic keyed at (100, 500) at 0s and (700, 500) at 4s.
    static func keyedAcross() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var art = Layer(name: "Sparkle",
                        content: .annotation(AnnotationContent(shape: .rectangle, colorHex: "#FFD36B")),
                        frame: CGRect(x: 100, y: 500, width: 100, height: 50))
        art.time = LayerTime(inMS: 0, outMS: 10_000)
        var motion = LayerMotion.keyed(.position, atMS: 0, value: .point(CGPoint(x: 100, y: 500)))
        motion = motion.settingKey(atMS: 4000, value: .point(CGPoint(x: 700, y: 500)))
        art.motions = [motion]
        doc.layers = [art]
        doc.durationMS = 10_000
        return (doc, art.id)
    }

    static func point(_ value: MotionValue?) -> CGPoint? {
        if case let .point(point) = value { return point }
        return nil
    }

    static func near(_ a: CGPoint?, _ b: CGPoint, within: CGFloat = 0.5) -> Bool {
        guard let a else { return false }
        return abs(a.x - b.x) <= within && abs(a.y - b.y) <= within
    }

    // MARK: - The segment

    @Test func aStraightSegmentHasItsHandleHalfWayAlongTheLine() {
        let run = MotionPathSegment(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 40))
        #expect(!run.isCurved)
        #expect(Self.near(run.middle, CGPoint(x: 50, y: 20)))
        #expect(Self.near(run.point(atFraction: 0.25), CGPoint(x: 25, y: 10)))
    }

    @Test func bendingThroughAPointPutsTheMiddleOfTheCurveExactlyThere() {
        let start = CGPoint(x: 0, y: 100)
        let end = CGPoint(x: 200, y: 100)
        let target = CGPoint(x: 90, y: 20)
        let bent = MotionPathSegment(start: start, end: end,
                                     bend: MotionPathSegment.bend(from: start, to: end, throughMiddle: target))
        #expect(bent.isCurved)
        #expect(Self.near(bent.middle, target))
        #expect(Self.near(bent.point(atParameter: 0.5), target))
        #expect(Self.near(bent.point(atFraction: 0), start))
        #expect(Self.near(bent.point(atFraction: 1), end))
    }

    /// Linear means a flat rate along the ARC, not along the curve's own
    /// parameter: "an arc can still run at a flat rate" (the mock's note).
    @Test func anArcRunsAtAFlatRateAlongItsLength() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 300, y: 0)
        // Lopsided on purpose: the control point far to one side makes the
        // curve's own parameter bunch up at one end.
        let bent = MotionPathSegment(start: start, end: end, bend: CGPoint(x: 120, y: -200))
        var samples: [CGPoint] = []
        for step in 0...10 { samples.append(bent.point(atFraction: Double(step) / 10)) }
        let gaps = zip(samples, samples.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let shortest = gaps.min() ?? 0
        let longest = gaps.max() ?? 0
        #expect(shortest > 0)
        #expect(longest / shortest < 1.1)
    }

    // MARK: - The motion's path

    @Test func twoPositionKeysMakeOneStraightSegment() {
        let (doc, id) = Self.keyedAcross()
        let motion = doc.layer(id: id)?.keyedMotion(.position)
        #expect(motion?.pathSegments.count == 1)
        #expect(motion?.pathShape == .straight)
    }

    @Test func aPropertyThatIsNotWhereHasNoPath() {
        let scale = LayerMotion.keyed(.scale, atMS: 0, value: .number(100))
            .settingKey(atMS: 1000, value: .number(150))
        #expect(scale.pathSegments.isEmpty)
    }

    @Test func oneKeyHasNoPath() {
        let one = LayerMotion.keyed(.position, atMS: 0, value: .point(.zero))
        #expect(one.pathSegments.isEmpty)
    }

    @Test func bendingASegmentMakesThePathCurvedAndLeavesTheKeysAlone() throws {
        let (doc, id) = Self.keyedAcross()
        let motion = try #require(doc.layer(id: id)?.keyedMotion(.position))
        let bent = motion.bending(segment: 0, throughMiddle: CGPoint(x: 400, y: 300))
        #expect(bent.pathShape == .curved)
        #expect(bent.keyframes.map(\.atMS) == motion.keyframes.map(\.atMS))
        #expect(bent.keyframes.map(\.value) == motion.keyframes.map(\.value))
        #expect(Self.near(bent.pathSegments.first?.middle, CGPoint(x: 400, y: 300)))
    }

    @Test func theLayerFollowsTheArcWhenPlayed() throws {
        let (doc, id) = Self.keyedAcross()
        let motion = try #require(doc.layer(id: id)?.keyedMotion(.position))
        var linear = motion.bending(segment: 0, throughMiddle: CGPoint(x: 400, y: 300))
        linear = linear.easing(key: 0, .linear).easing(key: 1, .linear)
        // Half way through the time, half way along the arc: its middle.
        let halfway = Self.point(linear.value(atMS: 2000, cycleMS: 10_000))
        #expect(Self.near(halfway, CGPoint(x: 400, y: 300), within: 1))
        // A straight run would sit on y = 500 the whole way.
        let quarter = try #require(Self.point(linear.value(atMS: 1000, cycleMS: 10_000)))
        #expect(quarter.y < 450)
        // And it still lands on its keys.
        #expect(Self.near(Self.point(linear.value(atMS: 0, cycleMS: 10_000)), CGPoint(x: 100, y: 500)))
        #expect(Self.near(Self.point(linear.value(atMS: 4000, cycleMS: 10_000)), CGPoint(x: 700, y: 500)))
    }

    @Test func theDocumentPoseFollowsTheArcSoExportAndCanvasAgree() throws {
        var (doc, id) = Self.keyedAcross()
        doc.updateLayer(id: id) { layer in
            // Linear keys, so half the time is half the way: the default ease
            // is the design language's standard curve, which is lopsided.
            layer.motions = layer.motions?.map {
                $0.easing(key: 0, .linear).easing(key: 1, .linear)
                    .bending(segment: 0, throughMiddle: CGPoint(x: 400, y: 300))
            }
        }
        let value = Self.point(doc.keyedValue(layerID: id, .motion(.position), atDocumentTimeMS: 2000))
        #expect(Self.near(value, CGPoint(x: 400, y: 300), within: 1))
        let posed = doc.posedForCanvas(atTimeMS: 2000).layer(id: id)?.frame.origin
        #expect(Self.near(posed, CGPoint(x: 400, y: 300), within: 1))
    }

    @Test func settingStraightPutsItBack() throws {
        let (doc, id) = Self.keyedAcross()
        let motion = try #require(doc.layer(id: id)?.keyedMotion(.position))
        let back = motion.bending(segment: 0, throughMiddle: CGPoint(x: 400, y: 300)).shapingPath(.straight)
        #expect(back.pathShape == .straight)
        #expect(back == motion)
    }

    @Test func settingCurvedOnAStraightPathBendsItUpward() throws {
        let (doc, id) = Self.keyedAcross()
        let motion = try #require(doc.layer(id: id)?.keyedMotion(.position))
        let curved = motion.shapingPath(.curved)
        #expect(curved.pathShape == .curved)
        let middle = try #require(curved.pathSegments.first?.middle)
        // Up the screen, which is smaller y: an arc over, as the mock draws.
        #expect(middle.y < 500)
        #expect(abs(middle.x - 400) < 1)
        // Asking again for what it already is changes nothing.
        #expect(curved.shapingPath(.curved) == curved)
    }

    @Test func aSegmentDraggedBackOntoTheLineIsStraightAgain() throws {
        let (doc, id) = Self.keyedAcross()
        let motion = try #require(doc.layer(id: id)?.keyedMotion(.position))
        let bent = motion.bending(segment: 0, throughMiddle: CGPoint(x: 400, y: 300))
        #expect(bent.straightening(segment: 0) == motion)
    }

    // MARK: - More keys

    @Test func eachSegmentBendsOnItsOwn() throws {
        let (doc, id) = Self.keyedAcross()
        var motion = try #require(doc.layer(id: id)?.keyedMotion(.position))
        motion = motion.settingKey(atMS: 8000, value: .point(CGPoint(x: 700, y: 900)))
        #expect(motion.pathSegments.count == 2)
        let bent = motion.bending(segment: 1, throughMiddle: CGPoint(x: 900, y: 700))
        #expect(bent.pathSegments[0].isCurved == false)
        #expect(bent.pathSegments[1].isCurved)
        // The first stretch is untouched by the second's bend.
        #expect(Self.point(bent.value(atMS: 2000, cycleMS: 10_000)) == Self.point(motion.value(atMS: 2000, cycleMS: 10_000)))
    }

    /// A key written part way along an arc (the key button, with the layer
    /// sitting on the arc) splits the arc rather than flattening it: both
    /// halves keep the curve they were part of.
    @Test func aKeyAddedPartWayAlongAnArcKeepsTheArc() throws {
        let (doc, id) = Self.keyedAcross()
        var motion = try #require(doc.layer(id: id)?.keyedMotion(.position))
        motion = motion.easing(key: 0, .linear).easing(key: 1, .linear)
        let bent = motion.bending(segment: 0, throughMiddle: CGPoint(x: 400, y: 300))
        let onArc = try #require(Self.point(bent.value(atMS: 1000, cycleMS: 10_000)))
        let split = bent.settingKey(atMS: 1000, value: .point(onArc))
        #expect(split.pathSegments.count == 2)
        #expect(split.pathSegments.allSatisfy { $0.isCurved })
        // The top of the arc is still where it was.
        let top = try #require(bent.pathSegments.first?.point(atParameter: 0.5))
        let near = split.pathSegments[1].point(atParameter: split.pathSegments[1].parameter(nearest: top))
        #expect(Self.near(near, top, within: 1.5))
    }

    // MARK: - Saving

    @Test func aBendSurvivesSavingAndAStraightPathWritesNothingNew() throws {
        let (doc, id) = Self.keyedAcross()
        let motion = try #require(doc.layer(id: id)?.keyedMotion(.position))
        let straight = String(decoding: try JSONEncoder().encode(motion), as: UTF8.self)
        #expect(!straight.contains("bend"))
        let bent = motion.bending(segment: 0, throughMiddle: CGPoint(x: 400, y: 300))
        let data = try JSONEncoder().encode(bent)
        let read = try JSONDecoder().decode(LayerMotion.self, from: data)
        #expect(read == bent)
    }

    // MARK: - On the canvas

    /// The path the canvas draws runs through the MIDDLE of the layer, which
    /// is where the eye reads a graphic as being, in canvas points.
    @Test func theCanvasPathRunsThroughTheMiddleOfTheLayer() throws {
        let (doc, id) = Self.keyedAcross()
        let path = try #require(doc.motionPath(layerID: id))
        #expect(path.segments.count == 1)
        #expect(Self.near(path.segments[0].start, CGPoint(x: 150, y: 525)))
        #expect(Self.near(path.segments[0].end, CGPoint(x: 750, y: 525)))
        #expect(Self.near(path.segments[0].middle, CGPoint(x: 450, y: 525)))
    }

    @Test func aHandleDraggedOnTheCanvasBendsThePathThroughIt() throws {
        var (doc, id) = Self.keyedAcross()
        doc.bendMotionPath(layerID: id, segment: 0, throughCanvasPoint: CGPoint(x: 450, y: 325))
        let path = try #require(doc.motionPath(layerID: id))
        #expect(Self.near(path.segments[0].middle, CGPoint(x: 450, y: 325)))
        #expect(doc.layer(id: id)?.keyedMotion(.position)?.pathShape == .curved)
    }

    @Test func aLayerWithOneKeyOrNoMoveHasNoCanvasPath() {
        let (doc, id) = PropertyKeysTestsFixtures.titleOnly()
        #expect(doc.motionPath(layerID: id) == nil)
    }
}

enum PropertyKeysTestsFixtures {
    static func titleOnly() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 1920, height: 1080))
        var title = Layer(name: "Hello",
                          content: .text(TextContent(string: "Hello", fontSize: 48)),
                          frame: CGRect(x: 100, y: 100, width: 400, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        title.motions = [LayerMotion.keyed(.position, atMS: 0, value: .point(CGPoint(x: 100, y: 100)))]
        doc.layers = [title]
        doc.durationMS = 10_000
        return (doc, title.id)
    }
}
