import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Dragging on the canvas with a row picked moves that whole animation
/// (`dragging-on-the-canvas-with-a-row-picked-moves-t`,
/// `docs/design/mocks/pages/video-animate.html`, the interaction table: "Drag
/// on the canvas, a row picked | Canvas | Moves every key of that row by the
/// same amount (for Position, the whole path), instead of keying the
/// playhead").
///
/// Written before the model. Pinned here: the hand's change to the picked
/// row's value at the playhead becomes the same change to every key of the
/// row; nothing is keyed at the playhead on that row; a change the row does
/// not hold keys at the playhead as it always did.
@Suite("Dragging with a row picked moves the whole row")
struct ShiftingAPickedRowTests {

    static func keyed(_ property: MotionProperty) -> (PhotonzDocument, UUID, UUID) {
        var (doc, id) = OnlyWhatIsAnimatedTests.drawn()
        doc.startKeying(layerID: id, .motion(property), atDocumentTimeMS: 1000)
        let motionID = doc.layer(id: id)?.motions?.first { $0.property == property }?.id ?? UUID()
        return (doc, id, motionID)
    }

    static func values(_ doc: PhotonzDocument, _ id: UUID, _ motionID: UUID) -> [MotionValue] {
        doc.layer(id: id)?.motions?.first { $0.id == motionID }?.keyframes.map(\.value) ?? []
    }

    static func moments(_ doc: PhotonzDocument, _ id: UUID, _ motionID: UUID) -> [Int] {
        doc.layer(id: id)?.motions?.first { $0.id == motionID }?.keyframes.map(\.atMS) ?? []
    }

    // MARK: - Position: the whole path moves

    @Test func aMoveWithPositionPickedMovesEveryKeyOfThePath() {
        var (doc, id, motionID) = Self.keyed(.position)
        guard let origin = doc.layer(id: id)?.frame.origin else { return }
        doc.setKeyedValue(.point(CGPoint(x: origin.x + 200, y: origin.y + 50)), layerID: id,
                          .motion(.position), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.point(CGPoint(x: origin.x + 400, y: origin.y)), layerID: id,
                          .motion(.position), atDocumentTimeMS: 5000)
        let before = Self.values(doc, id, motionID)
        let times = Self.moments(doc, id, motionID)
        #expect(before.count == 3)

        // The playhead sits between two keys, where a plain drag would key.
        doc.editShiftingRow(layerID: id, motionID: motionID, atDocumentTimeMS: 4000) { document in
            document.updateLayer(id: id) {
                $0.frame.origin.x += 30
                $0.frame.origin.y -= 20
            }
        }
        let after = Self.values(doc, id, motionID)
        #expect(Self.moments(doc, id, motionID) == times)
        #expect(after.count == before.count)
        for (old, new) in zip(before, after) {
            let was = OnlyWhatIsAnimatedTests.point(old)
            let now = OnlyWhatIsAnimatedTests.point(new)
            #expect(now?.x == (was?.x ?? 0) + 30)
            #expect(now?.y == (was?.y ?? 0) - 20)
        }
        // The stored layer stays put: the keys say where it is.
        #expect(doc.layer(id: id)?.frame.origin == origin)
    }

    @Test func aMoveWithPositionPickedOnAKeyMovesEveryKeyAndAddsNone() {
        var (doc, id, motionID) = Self.keyed(.position)
        guard let origin = doc.layer(id: id)?.frame.origin else { return }
        doc.setKeyedValue(.point(CGPoint(x: origin.x + 200, y: origin.y)), layerID: id,
                          .motion(.position), atDocumentTimeMS: 3000)
        doc.editShiftingRow(layerID: id, motionID: motionID, atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { $0.frame.origin.y += 40 }
        }
        let after = Self.values(doc, id, motionID).compactMap(OnlyWhatIsAnimatedTests.point)
        #expect(after == [CGPoint(x: origin.x, y: origin.y + 40), CGPoint(x: origin.x + 200, y: origin.y + 40)])
    }

    @Test func aBentPathKeepsItsBendWhenItMoves() {
        var (doc, id, motionID) = Self.keyed(.position)
        guard let origin = doc.layer(id: id)?.frame.origin else { return }
        doc.setKeyedValue(.point(CGPoint(x: origin.x + 200, y: origin.y)), layerID: id,
                          .motion(.position), atDocumentTimeMS: 3000)
        doc.updateLayer(id: id) { layer in
            layer.motions = layer.motions?.map { motion in
                var bent = motion
                bent.fromBend = CGPoint(x: 0, y: -60)
                return bent
            }
        }
        doc.editShiftingRow(layerID: id, motionID: motionID, atDocumentTimeMS: 2000) { document in
            document.updateLayer(id: id) { $0.frame.origin.x += 10 }
        }
        #expect(doc.layer(id: id)?.motions?.first { $0.id == motionID }?.fromBend == CGPoint(x: 0, y: -60))
    }

    // MARK: - Scale and Rotation: every key by the same amount

    @Test func aResizeWithScalePickedChangesEveryScaleKeyByTheSameAmount() {
        var (doc, id, motionID) = Self.keyed(.scale)
        doc.setKeyedValue(.number(150), layerID: id, .motion(.scale), atDocumentTimeMS: 3000)
        // At the first key, 100%: doubling the box is +100.
        doc.editShiftingRow(layerID: id, motionID: motionID, atDocumentTimeMS: 1000) { document in
            document.updateLayer(id: id) { layer in
                let box = layer.frame
                layer.frame = CGRect(x: box.midX - box.width, y: box.midY - box.height,
                                     width: box.width * 2, height: box.height * 2)
            }
        }
        let after = Self.values(doc, id, motionID).compactMap(OnlyWhatIsAnimatedTests.number)
        #expect(after == [200, 250])
    }

    @Test func aTurnWithRotationPickedTurnsEveryKeyByTheSameAmount() {
        var (doc, id, motionID) = Self.keyed(.rotation)
        doc.setKeyedValue(.number(90), layerID: id, .motion(.rotation), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(180), layerID: id, .motion(.rotation), atDocumentTimeMS: 5000)
        // At 3s the layer is drawn at 90; the hand turns it to 120.
        doc.editShiftingRow(layerID: id, motionID: motionID, atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { $0.transform.rotation = 120 * .pi / 180 }
        }
        let after = Self.values(doc, id, motionID).compactMap(OnlyWhatIsAnimatedTests.number)
        #expect(after.count == 3)
        for (got, want) in zip(after, [30.0, 120, 210]) {
            #expect(abs(got - want) < 0.001)
        }
    }

    // MARK: - What the row does not hold keys as it always did

    @Test func aMoveWithOpacityPickedKeysPositionAtThePlayheadAndLeavesOpacity() {
        var (doc, id, motionID) = Self.keyed(.opacity)
        doc.setKeyedValue(.number(40), layerID: id, .motion(.opacity), atDocumentTimeMS: 3000)
        let opacity = Self.values(doc, id, motionID)
        guard let origin = doc.layer(id: id)?.frame.origin else { return }
        doc.editShiftingRow(layerID: id, motionID: motionID, atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { $0.frame.origin.x += 100 }
        }
        #expect(Self.values(doc, id, motionID) == opacity)
        let end = OnlyWhatIsAnimatedTests.point(doc.keyedValue(layerID: id, .motion(.position),
                                                               atDocumentTimeMS: 3000))
        #expect(end?.x == origin.x + 100)
    }

    @Test func aResizeWithPositionPickedStillKeysScaleAtThePlayhead() {
        var (doc, id, motionID) = Self.keyed(.position)
        guard let origin = doc.layer(id: id)?.frame.origin else { return }
        doc.setKeyedValue(.point(CGPoint(x: origin.x + 200, y: origin.y)), layerID: id,
                          .motion(.position), atDocumentTimeMS: 3000)
        doc.editShiftingRow(layerID: id, motionID: motionID, atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { layer in
                let box = layer.frame
                layer.frame = CGRect(x: box.midX - box.width, y: box.midY - box.height,
                                     width: box.width * 2, height: box.height * 2)
            }
        }
        // The middle never moved, so the path stays where it was ...
        let path = Self.values(doc, id, motionID).compactMap(OnlyWhatIsAnimatedTests.point)
        #expect(path == [origin, CGPoint(x: origin.x + 200, y: origin.y)])
        // ... and the growth keys at the playhead.
        #expect(OnlyWhatIsAnimatedTests.number(doc.keyedValue(layerID: id, .motion(.scale),
                                                               atDocumentTimeMS: 3000)) == 200)
    }

    @Test func aRowThatIsGoneFallsBackToKeyingThePlayhead() {
        var (doc, id, _) = Self.keyed(.position)
        guard let origin = doc.layer(id: id)?.frame.origin else { return }
        doc.editShiftingRow(layerID: id, motionID: UUID(), atDocumentTimeMS: 3000) { document in
            document.updateLayer(id: id) { $0.frame.origin.x += 50 }
        }
        let start = OnlyWhatIsAnimatedTests.point(doc.keyedValue(layerID: id, .motion(.position),
                                                                 atDocumentTimeMS: 1000))
        let end = OnlyWhatIsAnimatedTests.point(doc.keyedValue(layerID: id, .motion(.position),
                                                               atDocumentTimeMS: 3000))
        #expect(start == origin)
        #expect(end?.x == origin.x + 50)
    }

    // MARK: - The shift itself

    @Test func aMotionShiftsItsEndsAndItsStopsAndNothingElse() {
        let motion = LayerMotion(property: .opacity, from: .number(10), to: .number(90),
                                 timing: MotionTiming(startMS: 0, durationMS: 1000))
        var stopped = motion
        stopped.stops = [MotionStop(atMS: 500, value: .number(50), ease: .hold)]
        let shifted = stopped.shiftingEveryKey(from: .number(50), to: .number(45))
        #expect(shifted?.keys.map(\.value) == [.number(5), .number(45), .number(85)])
        #expect(shifted?.stops?.first?.ease == .hold)
        #expect(shifted?.timing == motion.timing)
        // A colour has no amount to move by.
        let tint = LayerMotion(property: .opacity, from: .color("#000000"), to: .color("#FFFFFF"),
                               timing: MotionTiming(startMS: 0, durationMS: 1000))
        #expect(tint.shiftingEveryKey(from: .color("#000000"), to: .color("#111111")) == nil)
    }
}
