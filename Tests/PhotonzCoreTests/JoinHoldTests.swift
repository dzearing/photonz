import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Holding on black at a blade cut inside one clip**
/// (task `a-dip-on-a-blade-cut-inside-one-clip-can-hold-on`).
///
/// Between two clips a hold is the gap between them. Inside one clip the
/// pieces butt, so asking for a hold there cuts the clip in two at the join,
/// the way Premiere's blade leaves two clips, and the hold is the gap that
/// opens between them. One edit, so one undo takes it all back.
@Suite("A dip on a blade cut inside one clip holds on black")
struct JoinHoldTests {

    typealias Fixture = EditPointTransitionTests

    /// The recording on V1 from 0 to 8s, cut with the blade at 4s, a dip on
    /// that cut, and a sound further along on its own track at 9s.
    static func bladed() throws -> (doc: PhotonzDocument, take: UUID, sound: UUID) {
        var doc = PhotonzDocument.recording(Fixture.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let sound = doc.addSound(SoundRef(durationMS: 1000), name: "later", atMS: 9000)
        let did1 = doc.splitClip(take, atMS: 4000)
        #expect(did1)
        let did2 = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000),
                                  at: .join(clip: take, index: 1))
        #expect(did2)
        return (doc, take, sound)
    }

    @Test("A dip on a join can hold; a dissolve cannot")
    func whoCanHold() throws {
        var (doc, take, _) = try Self.bladed()
        #expect(doc.canHoldOnColour(at: .join(clip: take, index: 1)))
        let cut = try #require(doc.documentCut(at: .join(clip: take, index: 1))).cut
        let dissolve = try #require(cut.fitted(.dissolve))
        let did3 = doc.setTransition(dissolve, at: .join(clip: take, index: 1))
        #expect(did3)
        #expect(!doc.canHoldOnColour(at: .join(clip: take, index: 1)))
        // Still no hold written inside one clip's pieces.
        var pieces = try #require(doc.layer(id: take)?.clipPieces)
        let did4 = pieces.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000, holdMS: 1000), atCut: 1)
        #expect(!did4)
    }

    @Test("A hold on a join puts that much black in and moves everything after it along")
    func holdInsertsBlack() throws {
        var (doc, take, sound) = try Self.bladed()
        let length = doc.documentDurationMS
        let heldAt = doc.holdOnColour(2000, at: .join(clip: take, index: 1))
        let place = try #require(heldAt)
        guard case let .edit(outgoing, incoming) = place else {
            Issue.record("the held cut is not between two clips")
            return
        }
        #expect(outgoing == take)
        #expect(incoming != take)
        // The first half stays where it was.
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: take)?.time?.outMS == 4000)
        // The second half starts two seconds later, reading on where it did.
        let tail = try #require(doc.layer(id: incoming))
        #expect(tail.time?.inMS == 6000)
        #expect(tail.time?.outMS == 10_000)
        #expect(tail.clipMoment(atTimeMS: 7000)?.sourceMS == 5000)
        #expect(tail.name == "take")
        #expect(tail.movie?.id == Fixture.take.id)
        // Everything after it on another track moved along too.
        #expect(doc.layer(id: sound)?.time?.inMS == 11_000)
        #expect(doc.documentDurationMS == length + 2000)
        // One cut, carrying the dip and its hold, on the same track.
        let cut = try #require(doc.documentCut(at: place))
        #expect(cut.atMS == 4000)
        #expect(cut.cut.transition?.kind == .dipToBlack)
        #expect(cut.cut.transition?.lengthMS == 1000)
        #expect(cut.cut.transition?.holdMS == 2000)
        #expect(doc.trackID(ofClip: take) == doc.trackID(ofClip: incoming))
        // Black on screen in the middle of the hold.
        let held = doc.drawn(atTimeMS: 5000).layers.filter(\.isVisible)
        let panel = try #require(held.last)
        #expect(panel.style.opacity == 1)
        if case .annotation(let shape) = panel.content {
            #expect(shape.fillColorHex == "#000000")
        } else {
            Issue.record("the hold is not a panel of black")
        }
    }

    @Test("The hold grows, shrinks and comes back out at the cut it now lives on")
    func holdChanges() throws {
        var (doc, take, sound) = try Self.bladed()
        let heldAt = doc.holdOnColour(2000, at: .join(clip: take, index: 1))
        let place = try #require(heldAt)
        let did5 = doc.holdOnColour(3000, at: place)
        #expect(did5 == place)
        #expect(doc.layer(id: sound)?.time?.inMS == 12_000)
        let did6 = doc.holdOnColour(0, at: place)
        #expect(did6 == place)
        #expect(doc.layer(id: sound)?.time?.inMS == 9000)
        guard case let .edit(_, incoming) = place else { return }
        #expect(doc.layer(id: incoming)?.time?.inMS == 4000)
        #expect(doc.documentCut(at: place)?.cut.transition?.kind == .dipToBlack)
        // Asking for the hold it already has changes nothing.
        let did7 = doc.holdOnColour(0, at: place)
        #expect(did7 == nil)
    }

    @Test("Other cuts in the clip keep their transitions, on the half they fall in")
    func otherJoinsTravel() throws {
        var (doc, take, _) = try Self.bladed()
        let did8 = doc.splitClip(take, atMS: 2000)
        #expect(did8)
        let did9 = doc.splitClip(take, atMS: 6000)
        #expect(did9)
        // Pieces: 0-2, 2-4, 4-6, 6-8. The dip is on join 2 now.
        #expect(doc.documentCut(at: .join(clip: take, index: 2))?.cut.transition?.kind == .dipToBlack)
        let did10 = doc.setTransition(ClipTransition(kind: .dipToWhite, lengthMS: 400),
                                  at: .join(clip: take, index: 1))
        #expect(did10)
        let did11 = doc.setTransition(ClipTransition(kind: .dipToWhite, lengthMS: 600),
                                  at: .join(clip: take, index: 3))
        #expect(did11)
        let heldAt = doc.holdOnColour(1000, at: .join(clip: take, index: 2))
        let place = try #require(heldAt)
        guard case let .edit(_, incoming) = place else { return }
        #expect(doc.layer(id: take)?.clipPieces?.count == 2)
        #expect(doc.layer(id: take)?.clipPieces?.transition(atCut: 1)?.lengthMS == 400)
        #expect(doc.layer(id: incoming)?.clipPieces?.count == 2)
        #expect(doc.layer(id: incoming)?.clipPieces?.transition(atCut: 1)?.lengthMS == 600)
        #expect(doc.layer(id: incoming)?.time?.inMS == 5000)
    }

    @Test("A hard cut or a dissolve is refused a hold, and nothing changes")
    func refused() throws {
        var (doc, take, _) = try Self.bladed()
        let did12 = doc.setTransition(nil, at: .join(clip: take, index: 1))
        #expect(did12)
        let before = doc
        let did13 = doc.holdOnColour(1000, at: .join(clip: take, index: 1))
        #expect(did13 == nil)
        #expect(doc == before)
        #expect(!doc.canHoldOnColour(at: .join(clip: take, index: 1)))
    }
}
