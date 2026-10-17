import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// Freeze Frame asks how long, and by default freezes the clip's own track
/// (the user, 2026-10-17: "by default we'd just freeze THAT track, not every
/// track"). The clips after the freeze on that track move along by its length,
/// every other track carries on, and "Freeze every track" pushes every
/// unlocked one.
@Suite("A freeze moves its own track, or every unlocked track")
struct FreezeOnItsTrackTests {

    static let movie = MovieRef(id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                                pixelSize: CGSize(width: 1920, height: 1080), durationMS: 6000)

    /// Two clips end to end on V1 (0-3s and 3-9s) and a voice under both on
    /// its own track, starting at 0 and running 10s.
    static func twoOnV1WithVoice() throws -> (doc: PhotonzDocument, first: UUID, second: UUID, voice: UUID) {
        var (doc, first, second, _) = try ClipsAcrossTracksTests.twoOnV1()
        let voice = doc.addSound(SoundRef(durationMS: 10_000), name: "voice over", atMS: 0)
        return (doc, first, second, voice)
    }

    static func time(_ doc: PhotonzDocument, _ id: UUID) -> LayerTime? { doc.layer(id: id)?.time }

    @Test("A freeze nobody chose a push for moves only its own track")
    func theDefaultIsThisTrack() {
        #expect(HoldPush.whenNobodySays == .thisTrack)
        #expect(HoldPush.thisTrack.title == "This track")
        #expect(HoldPush.everything.title == "Every track")
    }

    @Test("A freeze of this track moves the next clip on the track and leaves the voice alone")
    func thisTrackRipplesItsTrack() throws {
        var (doc, first, second, voice) = try Self.twoOnV1WithVoice()
        let voiceBefore = try #require(Self.time(doc, voice))
        let did = doc.holdFrame(first, atMS: 1000, forMS: 10_000, push: .thisTrack)
        #expect(did)
        #expect(Self.time(doc, first)?.outMS == 13_000)
        // The next clip on V1 was butted up at 3s and still is, at 13s.
        #expect(Self.time(doc, second)?.inMS == 13_000)
        // The voice on its own track runs straight on under the frozen frame.
        #expect(Self.time(doc, voice) == voiceBefore)
        #expect(doc.layer(id: voice)?.clipPieces?.count == 1)
    }

    @Test("A freeze of every track moves both, and pauses the voice")
    func everyTrackRipplesEverything() throws {
        var (doc, first, second, voice) = try Self.twoOnV1WithVoice()
        let did = doc.holdFrame(first, atMS: 1000, forMS: 2000, push: .everything)
        #expect(did)
        #expect(Self.time(doc, second)?.inMS == 5000)
        #expect(Self.time(doc, voice)?.outMS == 12_000)
        #expect(doc.layer(id: voice)?.clipPieces?.piece(at: 1)?.isHeld == true)
    }

    @Test("Every track spares a locked one")
    func everyTrackSparesALockedTrack() throws {
        var (doc, first, _, voice) = try Self.twoOnV1WithVoice()
        doc.materializeTracks()
        let voiceTrack = try #require(doc.trackID(ofClip: voice))
        doc.updateTrack(voiceTrack) { $0.isLocked = true }
        let voiceBefore = try #require(Self.time(doc, voice))
        let did = doc.holdFrame(first, atMS: 1000, forMS: 2000, push: .everything)
        #expect(did)
        #expect(Self.time(doc, voice) == voiceBefore)
        #expect(doc.layer(id: voice)?.clipPieces?.count == 1)
    }

    @Test("Making a freeze of this track longer or shorter carries the next clip on the track with it")
    func resizingCarriesTheTrack() throws {
        var (doc, first, second, voice) = try Self.twoOnV1WithVoice()
        let voiceBefore = try #require(Self.time(doc, voice))
        _ = doc.holdFrame(first, atMS: 1000, forMS: 10_000, push: .thisTrack)
        let shorter = doc.setHoldLength(first, ofPiece: 1, toMS: 4000)
        #expect(shorter)
        #expect(Self.time(doc, first)?.outMS == 7000)
        #expect(Self.time(doc, second)?.inMS == 7000)
        let longer = doc.setHoldLength(first, ofPiece: 1, toMS: 6000)
        #expect(longer)
        #expect(Self.time(doc, second)?.inMS == 9000)
        #expect(Self.time(doc, voice) == voiceBefore)
    }

    @Test("Throwing a freeze of this track away closes the gap on its track only")
    func deletingClosesItsTrack() throws {
        var (doc, first, second, voice) = try Self.twoOnV1WithVoice()
        let before = doc
        _ = doc.holdFrame(first, atMS: 1000, forMS: 4000, push: .thisTrack)
        let gone = doc.rippleDeleteClipPiece(first, at: 1)
        #expect(gone)
        #expect(Self.time(doc, first)?.outMS == 3000)
        #expect(Self.time(doc, second)?.inMS == 3000)
        #expect(Self.time(doc, voice) == Self.time(before, voice))
        // The two halves either side close back into the one piece they were.
        #expect(doc.layer(id: first)?.clipPieces?.count == 1)
    }

    @Test("Switching a freeze between this track and every track lands where making it that way would")
    func switchingLandsTheSame() throws {
        var madeThatWay = try Self.twoOnV1WithVoice()
        _ = madeThatWay.doc.holdFrame(madeThatWay.first, atMS: 1000, forMS: 2000, push: .everything)

        var (doc, first, _, _) = try Self.twoOnV1WithVoice()
        let fresh = doc
        _ = doc.holdFrame(first, atMS: 1000, forMS: 2000, push: .thisTrack)
        let thisTrack = doc
        let switched = doc.setHoldPush(first, ofPiece: 1, to: .everything)
        #expect(switched)
        #expect(doc.allLayers.map(\.time) == madeThatWay.doc.allLayers.map(\.time))
        let back = doc.setHoldPush(first, ofPiece: 1, to: .thisTrack)
        #expect(back)
        #expect(doc == thisTrack)
        #expect(doc != fresh)
    }

    // MARK: - What is typed

    @Test("A length is read the ways an editor types one", arguments: [
        ("10", 10_000), ("10s", 10_000), ("10 s", 10_000), ("2.5", 2500), ("2.5 sec", 2500),
        ("1:30", 90_000), ("0:02.5", 2500), ("48f", 1600), ("48 frames", 1600), ("500ms", 500),
        (" 4 seconds ", 4000), ("3S", 3000),
    ])
    func typedLengths(_ typed: String, _ ms: Int) {
        #expect(FreezeLength.parse(typed) == ms)
    }

    @Test("Anything that is not a length is not read as one", arguments: [
        "", "abc", "0", "-2", "2x", "1:75", "s", "10 minutes", "99999",
    ])
    func notLengths(_ typed: String) {
        #expect(FreezeLength.parse(typed) == nil)
    }

    @Test("The field opens on two seconds, written the way the timeline writes it")
    func theFieldOpensOnTwoSeconds() {
        #expect(FreezeLength.text(FreezeLength.defaultMS) == "2s")
        #expect(FreezeLength.parse(FreezeLength.text(FreezeLength.defaultMS)) == 2000)
    }
}
