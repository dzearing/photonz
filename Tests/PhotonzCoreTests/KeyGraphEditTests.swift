import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// The value graph takes points you add and segments you pick (task
/// `the-value-graph-lets-you-add-points-pick-the-seg`). Written before the
/// model: a point added on the line keeps the curve's shape, a picked segment
/// takes a curve from the shared list, and a point drags in time and value.
@Suite("Key graph edits")
struct KeyGraphEditTests {

    typealias Lanes = KeyLanesTests

    static func scaleLane(_ doc: PhotonzDocument, _ id: UUID) throws -> KeyLane {
        try #require(Lanes.lane(doc, id, .scale))
    }

    // MARK: - Splitting a curve

    @Test func aCurveSplitInTwoPlaysExactlyAsTheWholeDid() throws {
        let curves: [EasingCurve] = [.linear, .easeInOut, .easeIn, .easeOut, .easeOutQuint,
                                     .custom(x1: 0.7, y1: 0.1, x2: 0.3, y2: 0.95)]
        for curve in curves {
            for at in [0.25, 0.5, 0.8] {
                let (left, right) = curve.split(at: at)
                let middle = curve.value(at: at)
                for u in stride(from: 0.0, through: 1.0, by: 0.1) {
                    let whole = curve.value(at: u * at)
                    let half = middle * left.value(at: u)
                    #expect(abs(whole - half) < 0.002, "left half of \(curve.title) split at \(at), u \(u)")
                    let wholeAfter = curve.value(at: at + u * (1 - at))
                    let halfAfter = middle + (1 - middle) * right.value(at: u)
                    #expect(abs(wholeAfter - halfAfter) < 0.002,
                            "right half of \(curve.title) split at \(at), u \(u)")
                }
            }
        }
    }

    @Test func linearSplitsIntoLinear() {
        let (left, right) = EasingCurve.linear.split(at: 0.3)
        #expect(left == .linear && right == .linear)
    }

    @Test func aCurveNoBezierCanDrawKeepsItselfOnBothHalves() {
        let (left, right) = EasingCurve.easeOutElastic.split(at: 0.4)
        #expect(left == .easeOutElastic && right == .easeOutElastic)
        let (heldLeft, heldRight) = EasingCurve.steps(1).split(at: 0.4)
        #expect(heldLeft == .steps(1) && heldRight == .steps(1))
    }

    // MARK: - Adding a point on the line

    @Test func aPointAddedOnTheLineTakesTheValueTheLineHasThere() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try Self.scaleLane(doc, id)
        let before = (3000...6000).map { Lanes.value(doc, id, .scale, $0) ?? -1 }
        let made = doc.addKeyOnCurve(layerID: id, motionID: lane.motionID, atDocumentMS: 4000)
        let ref = try #require(made)
        let after = try Self.scaleLane(doc, id)
        #expect(after.keys.map(\.documentMS) == [3000, 4000, 6000])
        #expect(after.keys.map(\.ref).contains(ref))
        // The shape does not change anywhere along the stretch.
        let now = (3000...6000).map { Lanes.value(doc, id, .scale, $0) ?? -1 }
        for (old, new) in zip(before, now) { #expect(abs(old - new) < 0.05) }
    }

    @Test func aPointAddedOnAPickedCurveKeepsThatCurve() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try Self.scaleLane(doc, id)
        let first = try #require(lane.keys.first?.ref)
        let curvedExpo = doc.curveStretches(layerID: id, [first], .easeOutExpo)
        #expect(curvedExpo)
        let before = stride(from: 3000, through: 6000, by: 50).map { Lanes.value(doc, id, .scale, $0) ?? -1 }
        let added = doc.addKeyOnCurve(layerID: id, motionID: lane.motionID, atDocumentMS: 3600)
        _ = try #require(added)
        let now = stride(from: 3000, through: 6000, by: 50).map { Lanes.value(doc, id, .scale, $0) ?? -1 }
        for (old, new) in zip(before, now) { #expect(abs(old - new) < 0.1) }
    }

    @Test func aPointAddedPastTheLastKeyHoldsTheLastValue() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try Self.scaleLane(doc, id)
        let added = doc.addKeyOnCurve(layerID: id, motionID: lane.motionID, atDocumentMS: 7000)
        _ = try #require(added)
        let after = try Self.scaleLane(doc, id)
        #expect(after.keys.map(\.documentMS) == [3000, 6000, 7000])
        #expect(Lanes.value(doc, id, .scale, 7000) == 200)
        #expect(Lanes.value(doc, id, .scale, 6500) == 200)
    }

    @Test func aPointAddedOnAKeyAddsNothing() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try Self.scaleLane(doc, id)
        let addedOnAKey = doc.addKeyOnCurve(layerID: id, motionID: lane.motionID, atDocumentMS: 3000)
        #expect(addedOnAKey == nil)
        #expect(try Self.scaleLane(doc, id).keys.count == 2)
    }

    // MARK: - A picked segment's curve

    @Test func aPickedSegmentTakesACurveAndTheOthersKeepTheirs() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try Self.scaleLane(doc, id)
        let added = doc.addKeyOnCurve(layerID: id, motionID: lane.motionID, atDocumentMS: 4500)
        _ = try #require(added)
        let keys = try Self.scaleLane(doc, id).keys
        let secondHalf = (4500...6000).map { Lanes.value(doc, id, .scale, $0) ?? -1 }
        let curvedFirst = doc.curveStretches(layerID: id, [keys[0].ref], .easeOut)
        #expect(curvedFirst)
        #expect(doc.stretchesCurve(layerID: id, [keys[0].ref]) == .easeOut)
        // Ease out, CSS's meaning: fast off the first key, settling into the second.
        let from = try #require(Lanes.value(doc, id, .scale, 3000))
        let to = try #require(Lanes.value(doc, id, .scale, 4500))
        for fraction in [0.25, 0.5, 0.75] {
            let ms = 3000 + Int(1500 * fraction)
            let wanted = from + (to - from) * EasingCurve.easeOut.value(at: fraction)
            #expect(abs((Lanes.value(doc, id, .scale, ms) ?? -1) - wanted) < 0.2)
        }
        let after = (4500...6000).map { Lanes.value(doc, id, .scale, $0) ?? -1 }
        for (old, new) in zip(secondHalf, after) { #expect(abs(old - new) < 0.05) }
    }

    @Test func segmentsThatDisagreeReadAsNoOneCurve() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try Self.scaleLane(doc, id)
        let added = doc.addKeyOnCurve(layerID: id, motionID: lane.motionID, atDocumentMS: 4500)
        _ = try #require(added)
        let keys = try Self.scaleLane(doc, id).keys
        let easedIn = doc.curveStretches(layerID: id, [keys[0].ref], .easeIn)
        #expect(easedIn)
        let linearised = doc.curveStretches(layerID: id, [keys[1].ref], .linear)
        #expect(linearised)
        #expect(doc.stretchesCurve(layerID: id, [keys[0].ref, keys[1].ref]) == nil)
        let heldBoth = doc.curveStretches(layerID: id, [keys[0].ref, keys[1].ref], .steps(1))
        #expect(heldBoth)
        #expect(doc.stretchesCurve(layerID: id, [keys[0].ref, keys[1].ref]) == .steps(1))
        // Held: the value stays put until the next key.
        #expect(Lanes.value(doc, id, .scale, 4400) == 100)
    }

    @Test func theLastKeyStartsNoSegment() throws {
        var (doc, id) = Lanes.keyed()
        let keys = try Self.scaleLane(doc, id).keys
        let refusedLast = doc.curveStretches(layerID: id, [keys[1].ref], .easeIn)
        #expect(!refusedLast)
        #expect(doc.stretchesCurve(layerID: id, [keys[1].ref]) == nil)
    }

    // MARK: - Points and segments picked together

    // The timeline bar's Easing "names the curve and sets it for everything
    // picked" (`video-animate.html`, Pick): a picked point counts as the
    // segment it starts, the way the mock's key carries the curve leaving it.

    @Test func aPickedPointCountsAsTheSegmentItStarts() throws {
        var (doc, id) = Lanes.keyed()
        let lane = try Self.scaleLane(doc, id)
        let added = doc.addKeyOnCurve(layerID: id, motionID: lane.motionID, atDocumentMS: 4500)
        _ = try #require(added)
        let keys = try Self.scaleLane(doc, id).keys
        #expect(doc.segmentsInHand(layerID: id, points: [keys[1].ref], segments: []) == [keys[1].ref])
        #expect(doc.segmentsInHand(layerID: id, points: [keys[0].ref], segments: [keys[1].ref])
            == [keys[0].ref, keys[1].ref])
    }

    @Test func aPickedLastPointCountsAsTheSegmentArrivingAtIt() throws {
        let (doc, id) = Lanes.keyed()
        let keys = try Self.scaleLane(doc, id).keys
        #expect(doc.segmentsInHand(layerID: id, points: [keys[1].ref], segments: []) == [keys[0].ref])
    }

    @Test func aPointOnALoneKeyCountsAsNoSegment() throws {
        var (doc, id) = KeyLanesTests.withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        let only = try #require(Lanes.lane(doc, id, .scale)?.keys.first?.ref)
        #expect(doc.segmentsInHand(layerID: id, points: [only], segments: []).isEmpty)
    }

    @Test func pointsAndSegmentsPickedTogetherTakeOneCurveInOneChange() throws {
        var (doc, id) = Lanes.keyed()
        let scaleLane = try Self.scaleLane(doc, id)
        let added = doc.addKeyOnCurve(layerID: id, motionID: scaleLane.motionID, atDocumentMS: 4500)
        _ = try #require(added)
        let scale = try Self.scaleLane(doc, id).keys
        let opacity = try #require(Lanes.lane(doc, id, .opacity)).keys
        // A segment of Scale and the first point of Opacity, picked together.
        let inHand = doc.segmentsInHand(layerID: id, points: [opacity[0].ref], segments: [scale[1].ref])
        #expect(inHand == [scale[1].ref, opacity[0].ref])
        let curvedRight = doc.curveStretches(layerID: id, [scale[1].ref], .easeIn)
        #expect(curvedRight)
        #expect(doc.stretchesCurve(layerID: id, inHand) == nil)
        let curvedBoth = doc.curveStretches(layerID: id, inHand, .easeOutBack)
        #expect(curvedBoth)
        #expect(doc.stretchesCurve(layerID: id, inHand) == .easeOutBack)
        #expect(doc.stretchesCurve(layerID: id, [opacity[0].ref]) == .easeOutBack)
        // The segment nobody picked keeps the curve it had.
        #expect(doc.stretchesCurve(layerID: id, [scale[0].ref]) != .easeOutBack)
    }

    // MARK: - The graph names its segments

    @Test func theGraphDrawsEachSegmentOnItsOwn() throws {
        let (doc, id) = Lanes.keyed()
        let lane = try Self.scaleLane(doc, id)
        let graph = try #require(doc.keyGraph(layerID: id, motionID: lane.motionID))
        #expect(graph.stretches.count == 1)
        #expect(graph.stretches[0].first == CGPoint(x: 3000, y: 100))
        #expect(graph.stretches[0].last == CGPoint(x: 6000, y: 200))
        #expect(graph.before.first?.x == 2000)
        #expect(graph.after.last?.x == 8000)
    }

    // MARK: - Dragging a point

    @Test func aPointDragsInTimeAndValueAsOneChange() throws {
        var (doc, id) = Lanes.keyed()
        let first = try #require(try Self.scaleLane(doc, id).keys.first?.ref)
        let moved = doc.moveKeyOnGraph(layerID: id, first, byMS: 500, toValue: 140)
        _ = try #require(moved)
        let keys = try Self.scaleLane(doc, id).keys
        #expect(keys.map(\.documentMS) == [3500, 6000])
        #expect(keys.first?.ref == moved)
        #expect(Lanes.value(doc, id, .scale, 3500) == 140)
    }

    @Test func aPositionPointDragsInTimeOnly() throws {
        var (doc, id) = Lanes.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 400, y: 500)), layerID: id, .motion(.position),
                          atDocumentTimeMS: 5000)
        let lane = try #require(Lanes.lane(doc, id, .position))
        let last = try #require(lane.keys.last?.ref)
        let landed = doc.moveKeyOnGraph(layerID: id, last, byMS: 500, toValue: 9999)
        _ = try #require(landed)
        let keys = try #require(Lanes.lane(doc, id, .position)).keys
        #expect(keys.map(\.documentMS) == [3000, 5500])
        let at = doc.keyedValue(layerID: id, .motion(.position), atDocumentTimeMS: 5500)
        #expect(ClipKeyMarksTests.point(at) == CGPoint(x: 400, y: 500))
    }
}
