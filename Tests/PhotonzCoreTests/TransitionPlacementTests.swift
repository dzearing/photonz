import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Where the overlap sits, and holding on black** (`video-transition-wt.html`,
/// `#rowAlign` and `#rowHold`).
///
/// Premiere's Alignment: a transition that needs an overlap can sit before the
/// cut, across it or after it, and each spends spare media only from the side
/// it borrows. A dip can hold on its colour, which is the one thing about a
/// transition that inserts real time and moves what comes after it.
@Suite("Where a transition sits, and a hold on black")
struct TransitionPlacementTests {

    typealias Fixture = EditPointTransitionTests

    /// The recording on V1 from 0 to 8s, two seconds spare after, and b-roll
    /// from 8s to 12s read from its very first frame: nothing to borrow before
    /// its in point, the case every freshly dropped clip is in.
    static func oneSided() throws -> (doc: PhotonzDocument, take: UUID, broll: UUID) {
        var doc = PhotonzDocument.recording(Fixture.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 10_000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(Fixture.broll.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: Fixture.broll.pixelSize))
        clip.movie = Fixture.broll
        clip.time = LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 6000)
        let landing = doc.clipLanding(kind: .video, lengthMS: 4000, atMS: 8000,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        return (doc, take, try #require(landed))
    }

    // MARK: - The written form

    @Test("A transition written before this reads back across the cut with no hold")
    func oldFilesReadBack() throws {
        let old = Data(#"{"kind":"dissolve","lengthMS":600}"#.utf8)
        let back = try JSONDecoder().decode(ClipTransition.self, from: old)
        #expect(back == ClipTransition(kind: .dissolve, lengthMS: 600))
        #expect(back.alignment == .across)
        #expect(back.holdMS == 0)
        // ...and one that sits across with no hold writes nothing new.
        let text = String(decoding: try JSONEncoder().encode(back), as: UTF8.self)
        #expect(!text.contains("alignment"))
        #expect(!text.contains("holdMS"))
        let placed = ClipTransition(kind: .push, lengthMS: 800, alignment: .after)
        let round = try JSONDecoder().decode(ClipTransition.self, from: try JSONEncoder().encode(placed))
        #expect(round == placed)
        let held = ClipTransition(kind: .dipToBlack, lengthMS: 1000, holdMS: 3000)
        let heldBack = try JSONDecoder().decode(ClipTransition.self, from: try JSONEncoder().encode(held))
        #expect(heldBack.holdMS == 3000)
    }

    @Test("Three places, in the words the panel uses")
    func titles() {
        #expect(ClipTransitionAlignment.allCases.map(\.title) == ["Before the cut", "Across it", "After it"])
    }

    // MARK: - How much of it falls either side

    @Test("Before the cut is all before, after it is all after, across is half each")
    func sides() {
        let before = ClipTransition(kind: .dissolve, lengthMS: 1000, alignment: .before)
        #expect(before.beforeMS == 1000 && before.afterMS == 0)
        let after = ClipTransition(kind: .dissolve, lengthMS: 1000, alignment: .after)
        #expect(after.beforeMS == 0 && after.afterMS == 1000)
        let across = ClipTransition(kind: .dissolve, lengthMS: 1000)
        #expect(across.beforeMS == 500 && across.afterMS == 500)
    }

    @Test("A dip is always across its cut and only a dip can hold")
    func dipsSitAcross() {
        let dip = ClipTransition(kind: .dipToBlack, lengthMS: 1000, alignment: .after, holdMS: 3000)
        #expect(dip.beforeMS == 500 && dip.afterMS == 500)
        #expect(dip.holdMS == 3000)
        #expect(dip.spanMS == 4000)
        let dissolve = ClipTransition(kind: .dissolve, lengthMS: 1000, holdMS: 3000)
        #expect(dissolve.holdMS == 0)
    }

    // MARK: - What each place can afford

    @Test("Each place spends spare only from the side it borrows")
    func eachPlaceSpendsItsOwnSide() throws {
        let (doc, take, broll) = try Fixture.edit()
        let cut = try #require(doc.documentCut(at: .edit(outgoing: take, incoming: broll))).cut
        // Two seconds after the take's out point, a second and a half before
        // b-roll's in point.
        #expect(cut.longestMS(of: .dissolve, aligned: .across) == 3000)
        // Before the cut, b-roll reads early: only its 1.5s before counts.
        #expect(cut.longestMS(of: .dissolve, aligned: .before) == 1500)
        // After it, the take runs on: its 2.0s, but no further than b-roll's
        // middle.
        #expect(cut.longestMS(of: .dissolve, aligned: .after) == 2000)
        #expect(cut.longestMS(of: .dissolve) == 3000)
    }

    @Test("A cut with spare on one side only can take a dissolve placed on that side")
    func oneSidedCut() throws {
        var (doc, take, broll) = try Self.oneSided()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.spareBeforeInMS == 0)
        #expect(cut.longestMS(of: .dissolve, aligned: .across) == 0)
        #expect(cut.longestMS(of: .dissolve, aligned: .before) == 0)
        #expect(cut.longestMS(of: .dissolve, aligned: .after) == 2000)
        #expect(cut.canAfford(.dissolve))
        // Across is refused, after is taken.
        let did1 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), at: place)
        #expect(did1 == false)
        let did2 = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000, alignment: .after), at: place)
        #expect(did2)
        // Nothing moved.
        #expect(doc.layer(id: broll)?.time?.inMS == 8000)
        // What the key and the tiles put on finds the side that can pay.
        let fitted = try #require(cut.fitted(.dissolve))
        #expect(fitted.alignment == .after)
        #expect(fitted.lengthMS == ClipTransition.defaultLengthMS)
    }

    @Test("The bill says which side pays")
    func paidWith() throws {
        var (doc, take, broll) = try Fixture.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000), at: place)
        var cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.spentFromOutgoingMS == 500 && cut.spentFromIncomingMS == 500)
        #expect(ClipTransitionCopy.paidWith(cut) == "0.5s + 0.5s of spare")
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000, alignment: .before), at: place)
        cut = try #require(doc.documentCut(at: place)).cut
        #expect(cut.spentFromOutgoingMS == 0 && cut.spentFromIncomingMS == 1000)
        #expect(ClipTransitionCopy.paidWith(cut) == "1.0s of spare before")
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000, alignment: .after), at: place)
        cut = try #require(doc.documentCut(at: place)).cut
        #expect(ClipTransitionCopy.paidWith(cut) == "1.0s of spare after")
    }

    // MARK: - What is on screen

    @Test("After the cut, nothing happens before it and the take runs on after it")
    func afterTheCutOnScreen() throws {
        var (doc, take, broll) = try Self.oneSided()
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000, alignment: .after),
                              at: .edit(outgoing: take, incoming: broll))
        // Before the cut the take plays alone.
        #expect(doc.drawn(atTimeMS: 7800).layers.filter(\.isVisible).count == 1)
        // A quarter of the way through, b-roll is a quarter up over the take,
        // which is reading on past its out point.
        let shown = doc.drawn(atTimeMS: 8250)
        #expect(shown.layers.filter(\.isVisible).count == 2)
        #expect(shown.layers.first { $0.id == broll }?.style.opacity == 0.25)
        let requests = doc.movieFrames(atTimeMS: 8250)
        #expect(requests.contains { $0.movie == Fixture.take && abs($0.sourceMS - 8250) < 40 })
        #expect(requests.contains { $0.movie == Fixture.broll && abs($0.sourceMS - 250) < 40 })
        // Done by 9s.
        #expect(doc.drawn(atTimeMS: 9050).layers.filter(\.isVisible).count == 1)
    }

    @Test("Before the cut, it is over at the cut")
    func beforeTheCutOnScreen() throws {
        var (doc, take, broll) = try Fixture.edit()
        _ = doc.setTransition(ClipTransition(kind: .dissolve, lengthMS: 1000, alignment: .before),
                              at: .edit(outgoing: take, incoming: broll))
        let shown = doc.drawn(atTimeMS: 7500)
        let partner = try #require(shown.layers.first { $0.id != take && $0.id != broll && $0.isVisible })
        #expect(partner.style.opacity == 0.5)
        #expect(doc.drawn(atTimeMS: 8050).layers.filter(\.isVisible).count == 1)
    }

    @Test("Inside one clip, a join takes a placement too")
    func joinPlacement() throws {
        let pieces = ClipPieces(pieces: [ClipPiece(sourceInMS: 0, lengthMS: 4000),
                                         ClipPiece(sourceInMS: 10_000, lengthMS: 4000)],
                                sourceLengthMS: 20_000)
        var placed = pieces
        let did3 = placed.setTransition(ClipTransition(kind: .wipe, lengthMS: 1000, alignment: .before), atCut: 1)
        #expect(did3)
        #expect(placed.transitionCut(atMS: 3500) != nil)
        #expect(placed.transitionCut(atMS: 4100) == nil)
        // No hold inside one clip: there is no gap to put black in.
        var held = pieces
        let did4 = held.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000, holdMS: 1000), atCut: 1)
        #expect(did4 == false)
    }

    // MARK: - Holding on black

    @Test("A hold on black inserts real time: the clips after it move along")
    func holdMovesWhatComesAfter() throws {
        var (doc, take, broll) = try Fixture.edit()
        let title = doc.addSound(SoundRef(durationMS: 1000), name: "later", atMS: 10_000)
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        let length = doc.documentDurationMS
        let did5 = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000), at: place)
        #expect(did5)
        let did6 = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000, holdMS: 3000), at: place)
        #expect(did6)
        #expect(doc.layer(id: take)?.time?.outMS == 8000)
        #expect(doc.layer(id: broll)?.time?.inMS == 11_000)
        #expect(doc.layer(id: title)?.time?.inMS == 13_000)
        #expect(doc.documentDurationMS == length + 3000)
        // Still one cut, at the take's out point, carrying the hold.
        let v1 = try #require(doc.trackID(ofClip: broll))
        #expect(doc.editPoints(onTrack: v1).map(\.atMS) == [8000])
        let cut = try #require(doc.documentCut(at: place))
        #expect(cut.atMS == 8000)
        #expect(cut.cut.transition?.holdMS == 3000)
        // Back to nothing, and everything slides back.
        let did7 = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000), at: place)
        #expect(did7)
        #expect(doc.layer(id: broll)?.time?.inMS == 8000)
        #expect(doc.layer(id: title)?.time?.inMS == 10_000)
        #expect(doc.documentDurationMS == length)
    }

    @Test("Black is on screen for the whole hold, with the fades either side of it")
    func holdIsBlack() throws {
        var (doc, take, broll) = try Fixture.edit()
        _ = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000, holdMS: 3000),
                              at: .edit(outgoing: take, incoming: broll))
        // Half way down.
        let fading = doc.drawn(atTimeMS: 7750).layers.filter(\.isVisible)
        #expect(fading.count == 2)
        #expect(fading.last?.style.opacity == 0.5)
        // In the middle of the hold neither clip is playing, and it is black.
        let held = doc.drawn(atTimeMS: 9500).layers.filter(\.isVisible)
        let panel = try #require(held.last)
        #expect(panel.style.opacity == 1)
        if case .annotation(let shape) = panel.content {
            #expect(shape.fillColorHex == "#000000")
        } else {
            Issue.record("the hold is not a panel of black")
        }
        #expect(doc.movieFrames(atTimeMS: 9500).count <= 1)
        // Half way back up over b-roll.
        let rising = doc.drawn(atTimeMS: 11_250).layers.filter(\.isVisible)
        #expect(rising.count == 2)
        #expect(rising.last?.style.opacity == 0.5)
        #expect(doc.drawn(atTimeMS: 11_600).layers.filter(\.isVisible).count == 1)
    }

    @Test("A hold is silent, and each side's sound fades where its picture does")
    func holdSound() {
        let dip = ClipTransition(kind: .dipToBlack, lengthMS: 1000, holdMS: 3000)
        #expect(dip.soundGain(atMS: 9000, cutAtMS: 8000, side: .outgoing) == 0)
        #expect(dip.soundGain(atMS: 9000, cutAtMS: 8000, side: .incoming) == 0)
        #expect(abs(dip.soundGain(atMS: 11_250, cutAtMS: 8000, side: .incoming) - 0.5) < 0.001)
        #expect(dip.soundGain(atMS: 11_500, cutAtMS: 8000, side: .incoming) == 1)
    }

    @Test("Changing a held dip to a dissolve, or taking it off, takes the black back out")
    func leavingTheDipTakesTheHoldOut() throws {
        var (doc, take, broll) = try Fixture.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        _ = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000, holdMS: 2000), at: place)
        #expect(doc.layer(id: broll)?.time?.inMS == 10_000)
        let cut = try #require(doc.documentCut(at: place)).cut
        let dissolve = try #require(cut.fitted(.dissolve))
        #expect(dissolve.holdMS == 0)
        let did8 = doc.setTransition(dissolve, at: place)
        #expect(did8)
        #expect(doc.layer(id: broll)?.time?.inMS == 8000)
        _ = doc.setTransition(ClipTransition(kind: .dipToWhite, lengthMS: 1000, holdMS: 1000), at: place)
        #expect(doc.layer(id: broll)?.time?.inMS == 9000)
        let did9 = doc.setTransition(nil, at: place)
        #expect(did9)
        #expect(doc.layer(id: broll)?.time?.inMS == 8000)
        #expect(doc.layer(id: broll)?.arrivalTransition == nil)
    }

    @Test("A held clip moved back against the other still has its cut, holding nothing")
    func buttedAgainHoldsNothing() throws {
        var (doc, take, broll) = try Fixture.edit()
        let place = TimelineCutPlace.edit(outgoing: take, incoming: broll)
        _ = doc.setTransition(ClipTransition(kind: .dipToBlack, lengthMS: 1000, holdMS: 2000), at: place)
        let did10 = doc.moveClip(broll, toInMS: 8000)
        #expect(did10)
        let cut = try #require(doc.documentCut(at: place))
        #expect(cut.cut.transition?.kind == .dipToBlack)
        #expect(cut.cut.transition?.holdMS == 0)
    }
}
