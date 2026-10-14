import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A layer's track shows only what is animated
/// (`a-layer-s-track-shows-only-what-is-animated-and`,
/// `docs/design/mocks/pages/video-animate.html`, "A track lists only what is
/// animated").
///
/// The user's words (2026-10-12): "When I add a 'key' to a video, it adds all
/// of the animatable properties below it. ... we really should only show the
/// properties being animated." Their answer on the card (2026-10-13): on a
/// layer that has keys, any change keys itself.
///
/// Written before the model. Pinned here: Add Key on a layer with nothing
/// keyed is one hollow moment and no rows; a change on a layer with keys joins
/// that property with its old value held at the layer's other key moments;
/// Animate adds one property with one key; Remove Key takes a hollow moment.
@Suite("A track lists only what is animated")
struct OnlyWhatIsAnimatedTests {

    // MARK: - Fixtures

    /// An eight second recording with a rectangle drawn at one second that
    /// runs to six.
    static func drawn() -> (PhotonzDocument, UUID) {
        var doc = PhotonzDocument.recording(HeldFrameTests.movie(), name: "Take 1")
        let shape = DrawnOnTheTimelineTests.rectangle()
        doc.addLayerDrawn(shape, atTimeMS: 1000, placingInTime: true)
        _ = doc.moveLayerEnd(shape.id, toMS: 6000)
        return (doc, shape.id)
    }

    static func number(_ value: MotionValue?) -> Double? {
        if case let .number(number)? = value { return number }
        return nil
    }

    static func point(_ value: MotionValue?) -> CGPoint? {
        if case let .point(point)? = value { return point }
        return nil
    }

    // MARK: - Add Key on a layer with nothing keyed

    @Test func addKeyOnALayerWithNothingKeyedIsOneHollowMomentAndNoRows() {
        var (doc, id) = Self.drawn()
        let did = doc.addKeyMoment(layerID: id, atDocumentTimeMS: 2000)
        #expect(did)
        #expect(doc.keyLanes(layerID: id).isEmpty)
        #expect(doc.layer(id: id)?.hasMotion == false)
        let marks = doc.clipKeyMarks(layerID: id)
        #expect(marks.count == 1)
        #expect(marks.first?.documentMS == 2000)
        #expect(marks.first?.isHollow == true)
        #expect(doc.isAnimating(layerID: id))
        #expect(doc.keyMomentDiamond(layerID: id, atDocumentTimeMS: 2000) == .onKey)
        #expect(doc.keyMomentDiamond(layerID: id, atDocumentTimeMS: 3000) == .betweenKeys)
    }

    @Test func aLayerWithNoKeysAndNoMomentsIsNotAnimating() {
        let (doc, id) = Self.drawn()
        #expect(!doc.isAnimating(layerID: id))
        #expect(doc.keyMomentDiamond(layerID: id, atDocumentTimeMS: 2000) == .dormant)
    }

    @Test func addKeyOnALayerWithKeysKeysEveryAnimatedValueThereAndNothingElse() {
        var (doc, id) = Self.drawn()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(40), layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 3000)
        #expect(doc.keyLanes(layerID: id).map(\.property) == [.opacity])
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 2)
        #expect(doc.clipKeyMarks(layerID: id).allSatisfy { !$0.isHollow })
    }

    @Test func removeKeyMomentTakesTheHollowMomentAndEveryKeyThere() {
        var (doc, id) = Self.drawn()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 2000)
        let did1 = doc.removeKeyMoment(layerID: id, atDocumentTimeMS: 2000)
        #expect(did1)
        #expect(doc.clipKeyMarks(layerID: id).isEmpty)
        #expect(!doc.isAnimating(layerID: id))

        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)
        let did2 = doc.removeKeyMoment(layerID: id, atDocumentTimeMS: 1000)
        #expect(did2)
        #expect(doc.keyLanes(layerID: id).isEmpty)
    }

    @Test func toggleKeyMomentAddsWhereThereIsNoneAndRemovesWhereThereIsOne() {
        var (doc, id) = Self.drawn()
        doc.toggleKeyMoment(layerID: id, atDocumentTimeMS: 2000)
        #expect(doc.clipKeyMarks(layerID: id).count == 1)
        doc.toggleKeyMoment(layerID: id, atDocumentTimeMS: 2000)
        #expect(doc.clipKeyMarks(layerID: id).isEmpty)
    }

    @Test func aHollowMomentDraggedAlongMovesInTime() {
        var (doc, id) = Self.drawn()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 2000)
        let did3 = doc.moveClipKeys(layerID: id, fromMS: 2000, toMS: 3500)
        #expect(did3)
        #expect(doc.clipKeyMarks(layerID: id).map(\.documentMS) == [3500])
    }

    // MARK: - A change on a layer with keys keys itself

    @Test func aPanelChangeAfterAddKeyJoinsWithItsOldValueHeldAtTheHollowMoment() {
        var (doc, id) = Self.drawn()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(40), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        #expect(doc.keyLanes(layerID: id).map(\.property) == [.opacity])
        #expect(doc.keyCount(layerID: id, .motion(.opacity)) == 2)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)) == 100)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)) == 40)
        // The hollow moment is a real key now: nothing hollow is left.
        #expect(doc.clipKeyMarks(layerID: id).allSatisfy { !$0.isHollow })
        #expect(doc.clipKeyMarks(layerID: id).map(\.documentMS) == [1000, 3000])
    }

    @Test func aChangeOnAHollowMomentKeysThereAloneAndTheMomentStopsBeingHollow() {
        var (doc, id) = Self.drawn()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 2000)
        doc.setKeyedValue(.number(15), layerID: id, .motion(.rotation), atDocumentTimeMS: 2000)
        #expect(doc.keyCount(layerID: id, .motion(.rotation)) == 1)
        #expect(doc.clipKeyMarks(layerID: id).map(\.isHollow) == [false])
    }

    @Test func aPropertyJoiningKeepsItsOldValueAtTheKeyMomentsEitherSide() {
        var (doc, id) = Self.drawn()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.opacity), atDocumentTimeMS: 5000)
        // Rotation changes at three seconds, between the two opacity keys.
        doc.setKeyedValue(.number(30), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        #expect(doc.keyCount(layerID: id, .motion(.rotation)) == 3)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)) == 0)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)) == 30)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.rotation), atDocumentTimeMS: 5000)) == 0)
        #expect(doc.keyLanes(layerID: id).map(\.property) == [.rotation, .opacity])
    }

    @Test func aChangeOnALayerWithNoKeysJustChangesIt() {
        var (doc, id) = Self.drawn()
        doc.setKeyedValue(.number(30), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        #expect(doc.keyLanes(layerID: id).isEmpty)
        #expect(abs((Self.number(doc.keyedValue(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)) ?? 0) - 30) < 0.001)
    }

    @Test func theAppearanceSliderOnALayerWithKeysJoinsOpacity() {
        var (doc, id) = Self.drawn()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 1000)
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 3000) { document in
            _ = document.updateLayerStyles(layerIDs: [id]) { $0.opacity = 0.4 }
        }
        #expect(doc.keyLanes(layerID: id).map(\.property) == [.opacity])
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)) == 100)
        #expect(abs((Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)) ?? 0) - 40) < 0.001)
        // The layer's own opacity is what it was: the keys say where it goes.
        #expect(doc.layer(id: id)?.style.opacity == 1)
    }

    @Test func theAppearanceSliderOnALayerWithNoKeysJustChangesIt() {
        var (doc, id) = Self.drawn()
        doc.editLooks(layerIDs: [id], atDocumentTimeMS: 3000) { document in
            _ = document.updateLayerStyles(layerIDs: [id]) { $0.opacity = 0.4 }
        }
        #expect(doc.keyLanes(layerID: id).isEmpty)
        #expect(doc.layer(id: id)?.style.opacity == 0.4)
    }

    @Test func aDragOnTheCanvasAtAKeyMomentAddsPositionByItself() {
        var (doc, id) = Self.drawn()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        guard let before = doc.layer(id: id) else { return }
        doc.editPosedForCanvas(layerID: id, atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { $0.frame.origin.x += 300 }
        }
        #expect(doc.keyLanes(layerID: id).map(\.property) == [.position, .opacity])
        let start = Self.point(doc.keyedValue(layerID: id, .motion(.position), atDocumentTimeMS: 1000))
        let end = Self.point(doc.keyedValue(layerID: id, .motion(.position), atDocumentTimeMS: 3000))
        #expect(start == before.frame.origin)
        #expect(end?.x == before.frame.origin.x + 300)
        // The stored layer stays where it was: the keys say where it goes.
        #expect(doc.layer(id: id)?.frame.origin == before.frame.origin)
    }

    @Test func aResizeOnTheCanvasOfALayerWithKeysAddsScale() {
        var (doc, id) = Self.drawn()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 1000)
        guard let before = doc.layer(id: id) else { return }
        doc.editPosedForCanvas(layerID: id, atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { layer in
                let box = layer.frame
                layer.frame = CGRect(x: box.midX - box.width, y: box.midY - box.height,
                                     width: box.width * 2, height: box.height * 2)
            }
        }
        #expect(doc.keyLanes(layerID: id).map(\.property).contains(.scale))
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 1000)) == 100)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)) == 200)
        #expect(doc.layer(id: id)?.frame.size == before.frame.size)
    }

    @Test func aTurnInSpaceOnALayerWithAnyKeyJoins() {
        var (doc, id) = Self.drawn()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.setSpaceValue(.rotationY, 25, layerIDs: [id], atDocumentTimeMS: 3000)
        #expect(doc.keyLanes(layerID: id).map(\.property).contains(.rotationY))
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.rotationY), atDocumentTimeMS: 1000)) == 0)
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.rotationY), atDocumentTimeMS: 3000)) == 25)
    }

    // MARK: - Leaving and coming back

    @Test func stopAnimatingTakesEveryKeyAndKeepsTheValueAtThePlayhead() {
        var (doc, id) = Self.drawn()
        doc.startKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)
        doc.setKeyedValue(.number(0), layerID: id, .motion(.opacity), atDocumentTimeMS: 5000)
        doc.startKeying(layerID: id, .motion(.rotation), atDocumentTimeMS: 1000)
        let here = Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000))
        let did4 = doc.stopKeying(layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        #expect(did4)
        #expect(doc.keyLanes(layerID: id).map(\.property) == [.rotation])
        #expect(Self.number(doc.keyedValue(layerID: id, .motion(.opacity), atDocumentTimeMS: 1000)) == here)
    }

    @Test func animateAddsOneKeyAtThePlayheadForThatPropertyAlone() {
        var (doc, id) = Self.drawn()
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 1000)
        let did5 = doc.animate(layerID: id, .motion(.scale), atDocumentTimeMS: 2000)
        #expect(did5)
        #expect(doc.keyLanes(layerID: id).map(\.property) == [.scale])
        #expect(doc.keyCount(layerID: id, .motion(.scale)) == 1)
        // Already animating, it is not offered and not keyed again.
        let did6 = doc.animate(layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        #expect(!did6)
    }

    @Test func theAnimateListIsGroupedAsThePanelIsAndLeavesOutWhatIsAnimating() {
        var (doc, id) = Self.drawn()
        guard let layer = doc.layer(id: id) else { return }
        let groups = layer.animateGroups(excluding: [])
        #expect(groups.map(\.group) == [.transform, .space, .look, .effects])
        #expect(groups.first?.properties.prefix(3) == [.motion(.position), .motion(.scale), .motion(.rotation)])
        #expect(groups.first { $0.group == .look }?.properties.first == .motion(.opacity))
        #expect(AnimateGroup.allCases.map(\.title) == ["Transform", "3D", "Look", "Effects"])

        doc.startKeying(layerID: id, .motion(.scale), atDocumentTimeMS: 1000)
        let animating = Set(doc.keyLanes(layerID: id).map { KeyedProperty.motion($0.property, effect: $0.effect) })
        let after = doc.layer(id: id)?.animateGroups(excluding: animating) ?? []
        #expect(!(after.first?.properties.contains(.motion(.scale)) ?? true))
    }

    // MARK: - Saved and opened

    @Test func aHollowMomentSavesAndOpensAndAnOldDocumentOpensWithNone() throws {
        var (doc, id) = Self.drawn()
        let old = try JSONEncoder().encode(doc)
        #expect(!String(decoding: old, as: UTF8.self).contains("hollowKeyMoments"))
        doc.addKeyMoment(layerID: id, atDocumentTimeMS: 2000)
        let data = try JSONEncoder().encode(doc)
        let opened = try JSONDecoder().decode(PhotonzDocument.self, from: data)
        #expect(opened.clipKeyMarks(layerID: id).map(\.isHollow) == [true])
        let reopened = try JSONDecoder().decode(PhotonzDocument.self, from: old)
        #expect(reopened.clipKeyMarks(layerID: id).isEmpty)
    }
}
