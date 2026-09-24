import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A layer's track opens into one lane per keyed value
/// (task `a-layer-s-track-opens-into-one-lane-per-keyed-va`).
///
/// Written before the model. The clip already carries one diamond per moment
/// (`ClipKeys.swift`); this is the lanes under it: one row per keyed value,
/// every key on it that a hand picks, drags, copies, deletes and eases, the
/// two new eases (Hold and Bezier), and the curve a lane opens into.
@Suite("Key lanes")
struct KeyLanesTests {

    // MARK: - Fixtures

    /// Ten seconds, with a title on screen from 2s to 8s.
    static func withTitle() -> (PhotonzDocument, UUID) {
        ClipKeyMarksTests.withTitle()
    }

    /// Scale keyed 100 at 3s and 200 at 6s, and opacity keyed 100 at 3s and
    /// 0 at 5s.
    static func keyed() -> (PhotonzDocument, UUID) {
        var (doc, id) = withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(200), layerID: id, .motion(.scale), atDocumentTimeMS: 6000)
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.opacity), atDocumentTimeMS: 5000)
        return (doc, id)
    }

    static func number(_ value: MotionValue?) -> Double? { ClipKeyMarksTests.number(value) }

    static func lane(_ doc: PhotonzDocument, _ id: UUID, _ property: MotionProperty) -> KeyLane? {
        doc.keyLanes(layerID: id).first { $0.property == property }
    }

    static func refs(_ doc: PhotonzDocument, _ id: UUID, _ property: MotionProperty,
                     at times: [Int]) -> Set<KeyRef> {
        let keys = lane(doc, id, property)?.keys ?? []
        return Set(keys.filter { times.contains($0.documentMS) }.map(\.ref))
    }

    static func value(_ doc: PhotonzDocument, _ id: UUID, _ property: MotionProperty, _ ms: Int) -> Double? {
        number(doc.keyedValue(layerID: id, .motion(property), atDocumentTimeMS: ms))
    }

    static func linear(from: Double = 0, to: Double = 100) -> LayerMotion {
        LayerMotion(property: .opacity, from: .number(from), to: .number(to),
                    timing: MotionTiming(startMS: 0, durationMS: 1000),
                    curve: .linear, repeats: .once)
    }

    // MARK: - The lanes

    @Test func aLayerHasOneLanePerKeyedValueInThePanelsOrder() {
        let (doc, id) = Self.keyed()
        let lanes = doc.keyLanes(layerID: id)
        #expect(lanes.map(\.property) == [.scale, .opacity])
        #expect(lanes.map(\.title) == ["Scale", "Opacity"])
        #expect(Self.lane(doc, id, .scale)?.keys.map(\.documentMS) == [3000, 6000])
        #expect(Self.lane(doc, id, .opacity)?.keys.map(\.documentMS) == [3000, 5000])
        #expect(Self.lane(doc, id, .scale)?.keys.map(\.reading) == ["100%", "200%"])
    }

    @Test func aLayerWithNothingKeyedHasNoLanes() {
        let (doc, id) = Self.withTitle()
        #expect(doc.keyLanes(layerID: id).isEmpty)
        #expect(!doc.hasKeyLanes(layerID: id))
        let (keyed, keyedID) = Self.keyed()
        #expect(keyed.hasKeyLanes(layerID: keyedID))
    }

    @Test func aKeyReadsWhatItsMotionsCurveDoesWhereNobodyEasedIt() {
        let (doc, id) = Self.keyed()
        // Keys set through the panel run on the panel's own curve.
        #expect(Self.lane(doc, id, .scale)?.keys.first?.ease == KeyEase(following: PropertyKeys.curve))
    }

    // MARK: - Hold and Bezier

    @Test func holdKeepsTheValueUntilTheNextKey() {
        let motion = Self.linear().easing(key: 0, .hold)
        #expect(motion.keys.first?.ease == .hold)
        #expect(Self.number(motion.value(atMS: 500, cycleMS: 10_000)) == 0)
        #expect(Self.number(motion.value(atMS: 999, cycleMS: 10_000)) == 0)
        #expect(Self.number(motion.value(atMS: 1000, cycleMS: 10_000)) == 100)
    }

    @Test func holdIsNotAnEaseInOrOut() {
        #expect(!KeyEase.hold.easesIn && !KeyEase.hold.easesOut)
        #expect(KeyEase.allCases.map(\.title)
                == ["Linear", "Ease In", "Ease Out", "Ease In and Out", "Hold", "Bezier"])
    }

    @Test func choosingBezierKeepsTheShapeTheKeyAlreadyHad() {
        let eased = Self.linear().easing(key: 0, .easeOut).easing(key: 1, .easeIn)
        let before = Self.number(eased.value(atMS: 300, cycleMS: 10_000)) ?? 0
        let bezier = eased.easing(key: 0, .bezier).easing(key: 1, .bezier)
        #expect(bezier.keys.map(\.ease) == [.bezier, .bezier])
        #expect(bezier.keys[0].handles != nil)
        let after = Self.number(bezier.value(atMS: 300, cycleMS: 10_000)) ?? -1
        #expect(abs(before - after) < 0.001)
    }

    @Test func bezierHandlesShapeTheStretchBetweenTwoKeys() {
        var motion = Self.linear().easing(key: 0, .bezier).easing(key: 1, .bezier)
        // Linear stays linear with its handles on the diagonal.
        #expect(abs((Self.number(motion.value(atMS: 250, cycleMS: 10_000)) ?? 0) - 25) < 0.5)
        motion = motion.settingHandle(key: 0, .leaving, to: CGPoint(x: 0.9, y: 0))
        motion = motion.settingHandle(key: 1, .arriving, to: CGPoint(x: 0.9, y: 1))
        // Both handles pulled late: the move barely starts before half way.
        let early = Self.number(motion.value(atMS: 250, cycleMS: 10_000)) ?? 100
        #expect(early < 10)
        #expect(Self.number(motion.value(atMS: 1000, cycleMS: 10_000)) == 100)
    }

    @Test func aHandleCannotLeaveItsStretchInTime() {
        let motion = Self.linear().settingHandle(key: 0, .leaving, to: CGPoint(x: 1.7, y: 0.5))
        #expect(motion.keys[0].handles?.leaving.x == 1)
        #expect(motion.keys[0].ease == .bezier)
    }

    @Test func handlesSurviveEncodingAndKeysWithoutThemEncodeNothingNew() throws {
        let plain = Self.linear()
        let plainJSON = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!plainJSON.contains("Handles"))
        let shaped = plain.settingHandle(key: 0, .leaving, to: CGPoint(x: 0.3, y: 0.8))
        let back = try JSONDecoder().decode(LayerMotion.self, from: JSONEncoder().encode(shaped))
        #expect(back == shaped)
        #expect(back.keys[0].handles?.leaving == CGPoint(x: 0.3, y: 0.8))
    }

    @Test func handlesAndHoldTravelWhenKeysAreMovedOrRetimed() {
        let three = Self.linear().settingKey(atMS: 500, value: .number(20))
            .easing(key: 1, .hold)
            .settingHandle(key: 0, .leaving, to: CGPoint(x: 0.2, y: 0.9))
        let retimed = three.retimed(to: MotionTiming(startMS: 0, durationMS: 2000))
        #expect(retimed.keys.map(\.ease) == three.keys.map(\.ease))
        #expect(retimed.keys[0].handles == three.keys[0].handles)
        #expect(retimed.keys[1].handles == three.keys[1].handles)
    }

    // MARK: - Moving keys

    @Test func movingPickedKeysCarriesThemTogether() {
        var (doc, id) = Self.keyed()
        let picked = Self.refs(doc, id, .scale, at: [3000]).union(Self.refs(doc, id, .opacity, at: [3000]))
        let moved = doc.moveKeys(layerID: id, picked, byMS: 500, copying: false)
        #expect(moved.count == 2)
        #expect(Self.lane(doc, id, .scale)?.keys.map(\.documentMS) == [3500, 6000])
        #expect(Self.lane(doc, id, .opacity)?.keys.map(\.documentMS) == [3500, 5000])
        // What moved is what is picked afterwards.
        let after = Set((Self.lane(doc, id, .scale)?.keys ?? []).filter { $0.documentMS == 3500 }.map(\.ref))
        #expect(after.isSubset(of: moved))
    }

    @Test func movedKeysKeepTheirValuesAndEases() {
        var (doc, id) = Self.keyed()
        _ = doc.easeKeys(layerID: id, Self.refs(doc, id, .scale, at: [6000]), .hold)
        _ = doc.moveKeys(layerID: id, Self.refs(doc, id, .scale, at: [6000]), byMS: 1000, copying: false)
        let keys = Self.lane(doc, id, .scale)?.keys ?? []
        #expect(keys.map(\.documentMS) == [3000, 7000])
        #expect(keys.last?.reading == "200%")
        #expect(keys.last?.ease == .hold)
    }

    @Test func aKeyDraggedPastAnotherOnTheSameLaneTakesItsPlaceInOrder() {
        var (doc, id) = Self.keyed()
        _ = doc.moveKeys(layerID: id, Self.refs(doc, id, .scale, at: [3000]), byMS: 4000, copying: false)
        let keys = Self.lane(doc, id, .scale)?.keys ?? []
        #expect(keys.map(\.documentMS) == [6000, 7000])
        #expect(keys.map(\.reading) == ["200%", "100%"])
    }

    @Test func aKeyLandingOnAnotherReplacesIt() {
        var (doc, id) = Self.keyed()
        _ = doc.moveKeys(layerID: id, Self.refs(doc, id, .scale, at: [3000]), byMS: 3000, copying: false)
        let keys = Self.lane(doc, id, .scale)?.keys ?? []
        #expect(keys.map(\.documentMS) == [6000])
        #expect(keys.map(\.reading) == ["100%"])
    }

    @Test func keysStayOnTheClip() {
        var (doc, id) = Self.keyed()
        let all = Self.refs(doc, id, .scale, at: [3000, 6000])
        _ = doc.moveKeys(layerID: id, all, byMS: 9000, copying: false)
        // The title ends at 8s: the pair stops with the later key on its end.
        #expect(Self.lane(doc, id, .scale)?.keys.map(\.documentMS) == [5000, 8000])
        _ = doc.moveKeys(layerID: id, Set(Self.lane(doc, id, .scale)?.keys.map(\.ref) ?? []),
                         byMS: -9000, copying: false)
        #expect(Self.lane(doc, id, .scale)?.keys.map(\.documentMS) == [2000, 5000])
    }

    @Test func optionDragCopiesAndLeavesTheOriginals() {
        var (doc, id) = Self.keyed()
        let copies = doc.moveKeys(layerID: id, Self.refs(doc, id, .scale, at: [3000, 6000]),
                                  byMS: 1000, copying: true)
        let keys = Self.lane(doc, id, .scale)?.keys ?? []
        // Both originals stay; their copies land a second later.
        #expect(keys.map(\.documentMS) == [3000, 4000, 6000, 7000])
        #expect(keys.map(\.reading) == ["100%", "100%", "200%", "200%"])
        #expect(copies.count == 2)
        let copyTimes = Set(keys.filter { copies.contains($0.ref) }.map(\.documentMS))
        #expect(copyTimes == [4000, 7000])
    }

    @Test func aCopyThatGoesNowhereChangesNothing() {
        var (doc, id) = Self.keyed()
        let before = doc
        _ = doc.moveKeys(layerID: id, Self.refs(doc, id, .scale, at: [3000]), byMS: 5, copying: true)
        #expect(doc == before)
    }

    // MARK: - Deleting and easing

    @Test func deletingPickedKeysAcrossLanes() {
        var (doc, id) = Self.keyed()
        let picked = Self.refs(doc, id, .scale, at: [6000]).union(Self.refs(doc, id, .opacity, at: [5000]))
        let done = doc.removeKeys(layerID: id, picked)
        #expect(done)
        #expect(Self.lane(doc, id, .scale)?.keys.map(\.documentMS) == [3000])
        #expect(Self.lane(doc, id, .opacity)?.keys.map(\.documentMS) == [3000])
    }

    @Test func deletingEveryKeyOfAValueStopsKeyingItAndKeepsAValue() {
        var (doc, id) = Self.keyed()
        let done = doc.removeKeys(layerID: id, Self.refs(doc, id, .opacity, at: [3000, 5000]))
        #expect(done)
        #expect(Self.lane(doc, id, .opacity) == nil)
        #expect(doc.keyLanes(layerID: id).map(\.property) == [.scale])
        #expect(doc.layer(id: id)?.style.opacity == 1)
    }

    @Test func easingPickedKeysAndReadingWhatTheyAgreeOn() {
        var (doc, id) = Self.keyed()
        let picked = Self.refs(doc, id, .scale, at: [3000]).union(Self.refs(doc, id, .opacity, at: [3000]))
        let done = doc.easeKeys(layerID: id, picked, .linear)
        #expect(done)
        #expect(doc.keysEase(layerID: id, picked) == .linear)
        _ = doc.easeKeys(layerID: id, Self.refs(doc, id, .scale, at: [3000]), .hold)
        #expect(doc.keysEase(layerID: id, picked) == nil)
        // Hold plays: the scale sits at 100 until the key at 6s.
        #expect(Self.value(doc, id, .scale, 5900) == 100)
    }

    // MARK: - The curve

    @Test func theGraphFollowsWhatPlays() throws {
        let (doc, id) = Self.keyed()
        let scale = try #require(Self.lane(doc, id, .scale))
        let graph = try #require(doc.keyGraph(layerID: id, motionID: scale.motionID))
        #expect(graph.low == 100 && graph.high == 200)
        #expect(graph.keys.map(\.documentMS) == [3000, 6000])
        #expect(graph.keys.map(\.value) == [100, 200])
        // Every sample is what the picture is at that moment.
        for sample in graph.points where sample.x >= 3000 && sample.x <= 6000 {
            let playing = Self.value(doc, id, .scale, Int(sample.x.rounded())) ?? -1
            #expect(abs(playing - Double(sample.y)) < 1.5)
        }
        // Flat before the first key and after the last, out to the clip's ends.
        #expect(graph.points.first?.x == 2000 && graph.points.first?.y == 100)
        #expect(graph.points.last?.x == 8000 && graph.points.last?.y == 200)
    }

    @Test func aHeldStretchIsDrawnAsAStep() throws {
        var (doc, id) = Self.keyed()
        _ = doc.easeKeys(layerID: id, Self.refs(doc, id, .scale, at: [3000]), .hold)
        let scale = try #require(Self.lane(doc, id, .scale))
        let graph = try #require(doc.keyGraph(layerID: id, motionID: scale.motionID))
        let inside = graph.points.filter { $0.x > 3000 && $0.x < 6000 }
        #expect(inside.allSatisfy { $0.y == 100 })
        #expect(graph.points.contains(CGPoint(x: 6000, y: 100)))
        #expect(graph.points.contains(CGPoint(x: 6000, y: 200)))
    }

    @Test func aColourHasNoGraph() throws {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.color), atDocumentTimeMS: 3000)
        let colour = try #require(Self.lane(doc, id, .color))
        #expect(doc.keyGraph(layerID: id, motionID: colour.motionID) == nil)
    }

    @Test func positionIsGraphedAsDistanceTravelled() throws {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: 400, y: 500)), layerID: id, .motion(.position),
                          atDocumentTimeMS: 5000)
        let lane = try #require(Self.lane(doc, id, .position))
        let graph = try #require(doc.keyGraph(layerID: id, motionID: lane.motionID))
        // From (100,100) to (400,500) is 500 points.
        #expect(graph.keys.map(\.value) == [0, 500])
    }

    @Test func handlesSitInTheGraphWhereTheyShapeTheCurve() throws {
        var (doc, id) = Self.keyed()
        let scale = try #require(Self.lane(doc, id, .scale))
        let first = try #require(scale.keys.first?.ref)
        let done = doc.setKeyHandle(layerID: id, first, .leaving,
                                 toGraphPoint: CGPoint(x: 4500, y: 100))
        #expect(done)
        let graph = try #require(doc.keyGraph(layerID: id, motionID: scale.motionID))
        let key = try #require(graph.keys.first)
        #expect(key.ease == .bezier)
        // Half way along the three seconds, level with the key.
        #expect(key.leaving.map { abs($0.x - 4500) < 1 && abs($0.y - 100) < 0.01 } == true)
        #expect(key.arriving == nil)
        // The second key has an arriving handle but nothing leaves it.
        #expect(graph.keys.last?.leaving == nil)
        #expect(graph.keys.last?.arriving != nil)
    }

    @Test func aHandleDraggedOnAFlatStretchKeepsItsHeight() throws {
        var (doc, id) = Self.withTitle()
        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(100), layerID: id, .motion(.scale), atDocumentTimeMS: 6000)
        let scale = try #require(Self.lane(doc, id, .scale))
        let first = try #require(scale.keys.first?.ref)
        let done = doc.setKeyHandle(layerID: id, first, .leaving, toGraphPoint: CGPoint(x: 4500, y: 180))
        #expect(done)
        let motion = try #require(doc.layer(id: id)?.keyedMotion(.scale))
        #expect(motion.keys[0].handles?.leaving.x == 0.5)
        #expect(Self.value(doc, id, .scale, 4000) == 100)
    }
}
