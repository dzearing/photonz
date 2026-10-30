import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A cut with no spare frames pays for an overlap by getting shorter**
/// (`video-transition-wt.html` step 10, "Or · Shorten the cut by 1.0s").
///
/// A second clip dropped at full length after a recording used to its last
/// frame leaves a cut with nothing either side to borrow, so every transition
/// that puts both shots on screen is refused. The mock's answer is one offered
/// edit: trim from the two clip ends exactly the frames the overlap needs, so
/// they become its spare, close the gap the way Extract does, and put the
/// transition on. One step to undo.
@Suite("Shortening a cut to pay for an overlap")
struct ShortenTheCutTests {

    /// Eight seconds recorded and all eight used: nothing spare after.
    static let take = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 8000)
    /// Four seconds recorded, read from its first frame: nothing spare before.
    static let broll = MovieRef(pixelSize: CGSize(width: 100, height: 60), durationMS: 4000)

    /// The recording on V1 from 0 to 8s, b-roll butted on from 8s to 12s at
    /// full length. `spareAfter` leaves that much of the recording unused.
    static func edit(spareAfter: Int = 0, brollLength: Int = 4000) throws
        -> (doc: PhotonzDocument, place: TimelineCutPlace, take: UUID, broll: UUID, v1: UUID) {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000 - spareAfter, sourceInMS: 0, sourceLengthMS: 8000)
        }
        let v1 = try #require(doc.timelineTracks.first { $0.name == "V1" }?.id)
        var clip = Layer(name: "b-roll", content: .image(Self.broll.frameRef(atSourceMS: 0)),
                         frame: CGRect(origin: .zero, size: Self.broll.pixelSize))
        clip.movie = Self.broll
        clip.time = LayerTime(inMS: 0, outMS: brollLength, sourceInMS: 0, sourceLengthMS: 4000)
        let landing = doc.clipLanding(kind: .video, lengthMS: brollLength, atMS: 8000 - spareAfter,
                                      over: .onto(v1), edit: .overwrite)
        let landed = doc.land(clip, at: landing)
        let broll = try #require(landed)
        return (doc, .edit(outgoing: take, incoming: broll), take, broll, v1)
    }

    // MARK: - The arithmetic

    @Test("A cut with nothing either side holds its edge frames for a dissolve, and shortening by its length plays real footage")
    func bothSidesEmpty() throws {
        let (doc, place, _, _, _) = try Self.edit()
        let cut = try #require(doc.documentCut(at: place)?.cut)
        #expect(cut.spareAfterOutMS == 0)
        #expect(cut.spareBeforeInMS == 0)
        #expect(cut.canAfford(.dissolve))
        // A dip needs no overlap, so it never asks for the cut to shorten.
        #expect(cut.canAfford(.dipToBlack))
        #expect(cut.shortening(for: .dipToBlack) == nil)

        let shortening = try #require(cut.shortening(for: .dissolve))
        // Across the cut, half from each side: 0.2s off the recording's end
        // and 0.2s off b-roll's start, the whole 0.4s of the dissolve.
        #expect(shortening.transition == ClipTransition(kind: .dissolve))
        #expect(shortening.fromOutgoingMS == 200)
        #expect(shortening.fromIncomingMS == 200)
        #expect(shortening.totalMS == 400)
        #expect(ClipTransitionCopy.shortenTheCut(shortening) == "Shorten the cut by 0.4s")
        #expect(ClipTransitionCopy.shorteningTip(shortening) == "Cross dissolve, 0.4s")
    }

    @Test("Spare one side has, too little to pay alone, is spent before anything is trimmed")
    func partSpare() throws {
        let (doc, place, _, _, _) = try Self.edit(spareAfter: 50)
        let cut = try #require(doc.documentCut(at: place)?.cut)
        #expect(cut.spareAfterOutMS == 50)
        #expect(cut.canAfford(.dissolve))
        let shortening = try #require(cut.shortening(for: .dissolve))
        #expect(shortening.fromOutgoingMS == 150)
        #expect(shortening.fromIncomingMS == 200)
        #expect(shortening.totalMS == 350)
    }

    @Test("A cut that can already pay is never offered a shortening")
    func affordableNeedsNone() throws {
        let (doc, place, _, _, _) = try Self.edit(spareAfter: 1000)
        let cut = try #require(doc.documentCut(at: place)?.cut)
        #expect(cut.canAfford(.dissolve))
        #expect(cut.shortening(for: .dissolve) == nil)
    }

    @Test("A clip too short to give up the frames and still hold the overlap is refused")
    func tooShort() throws {
        let (doc, place, _, _, _) = try Self.edit(brollLength: 500)
        let cut = try #require(doc.documentCut(at: place)?.cut)
        // 0.5s less 0.2s leaves 0.3s, shorter than the 0.4s dissolve.
        #expect(cut.shortening(for: .dissolve) == nil)
        #expect(doc.cutShortening(for: .dissolve, at: place) == nil)
    }

    @Test("A length asked for is the length shortened for")
    func askedLength() throws {
        let (doc, place, _, _, _) = try Self.edit()
        let cut = try #require(doc.documentCut(at: place)?.cut)
        let shortening = try #require(cut.shortening(for: .push, lengthMS: 1000))
        #expect(shortening.transition.lengthMS == 1000)
        #expect(shortening.transition.kind == .push)
        #expect(shortening.totalMS == 1000)
    }

    // MARK: - What it offers

    @Test("The offer is the transition on the cut, and only while it holds edge frames")
    func whichKind() throws {
        var (doc, place, _, _, _) = try Self.edit()
        var cut = try #require(doc.documentCut(at: place)?.cut)
        // A hard cut holds nothing, so there is nothing to offer.
        #expect(cut.shorteningOffer(defaultKind: .wipe) == nil)
        let wiped = doc.setTransition(ClipTransition(kind: .wipe), at: place)
        #expect(wiped)
        cut = try #require(doc.documentCut(at: place)?.cut)
        #expect(cut.holdsFrames)
        #expect(cut.shorteningOffer(defaultKind: .dissolve)?.transition.kind == .wipe)
        // A dip holds no frames: each clip fades inside the time it has.
        let dipped = doc.setTransition(ClipTransition(kind: .dipToBlack), at: place)
        #expect(dipped)
        cut = try #require(doc.documentCut(at: place)?.cut)
        #expect(cut.shorteningOffer(defaultKind: .dissolve) == nil)
    }

    // MARK: - Doing it

    @Test("Shortening trims both ends, closes the gap, and puts the dissolve on with the spare it made")
    func shortenAndPutOn() throws {
        var (doc, place, take, broll, _) = try Self.edit()
        let added = doc.addMarker(atMS: 10_000)
        let marker = try #require(added)
        let landed = doc.shortenCut(for: .dissolve, at: place)
        #expect(landed == place)
        #expect(doc.layer(id: take)?.time?.outMS == 7800)
        #expect(doc.layer(id: broll)?.time?.inMS == 7800)
        #expect(doc.layer(id: broll)?.time?.outMS == 11_600)
        #expect(doc.documentDurationMS == 11_600)
        // The marker went with the picture it was dropped on.
        #expect(doc.markers.first { $0.id == marker }?.atMS == 9600)

        let cut = try #require(doc.documentCut(at: place))
        #expect(cut.atMS == 7800)
        #expect(cut.cut.spareAfterOutMS == 200)
        #expect(cut.cut.spareBeforeInMS == 200)
        #expect(cut.cut.drawnTransition == ClipTransition(kind: .dissolve))
        #expect(cut.cut.spentFromOutgoingMS == 200)
        #expect(cut.cut.spentFromIncomingMS == 200)
        #expect(ClipTransitionCopy.paidWith(cut.cut) == "0.2s + 0.2s of spare")
        // Paid for, so nothing more is offered.
        #expect(cut.cut.shorteningOffer(defaultKind: .dissolve) == nil)
    }

    @Test("A dip on the cut is replaced by the dissolve the shortening paid for")
    func replacesTheDip() throws {
        var (doc, place, _, broll, _) = try Self.edit()
        let dipped = doc.setTransition(ClipTransition(kind: .dipToBlack), at: place)
        #expect(dipped)
        let landed = doc.shortenCut(for: .dissolve, at: place)
        #expect(landed == place)
        #expect(doc.layer(id: broll)?.arrivalTransition?.kind == .dissolve)
    }

    @Test("A clip on a locked track is not trimmed, so the cut is not shortened")
    func lockedTrack() throws {
        var (doc, place, take, _, v1) = try Self.edit()
        doc.updateTrack(v1) { $0.isLocked = true }
        #expect(doc.cutShortening(for: .dissolve, at: place) == nil)
        let before = doc
        let landed = doc.shortenCut(for: .dissolve, at: place)
        #expect(landed == nil)
        #expect(doc == before)
        #expect(doc.layer(id: take)?.time?.outMS == 8000)
    }

    @Test("Inside one clip, a join between two ends of the recording shortens the same way")
    func atAJoin() throws {
        var doc = PhotonzDocument.recording(Self.take, name: "take")
        let take = doc.layers[0].id
        doc.updateLayer(id: take) {
            $0.time = LayerTime(inMS: 0, outMS: 8000, sourceInMS: 0, sourceLengthMS: 8000)
        }
        // Cut at 4s and play the second half first: the piece going out ends
        // on the recording's last frame and the one coming in starts on its
        // first, so neither has anything to lend.
        let split = doc.splitClip(take, atMS: 4000)
        #expect(split)
        let moved = doc.moveClipPiece(take, from: 1, to: 0)
        #expect(moved)
        let place = TimelineCutPlace.join(clip: take, index: 1)
        let cut = try #require(doc.documentCut(at: place)?.cut)
        #expect(cut.footageMS(of: .dissolve, aligned: .across) == 0)
        let landed = doc.shortenCut(for: .dissolve, at: place)
        #expect(landed == place)
        #expect(doc.layer(id: take)?.time?.outMS == 7600)
        let after = try #require(doc.documentCut(at: place)?.cut)
        #expect(after.atMS == 3800)
        #expect(after.drawnTransition == ClipTransition(kind: .dissolve))
    }
}
