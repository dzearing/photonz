import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **⌥-drag on a clip leaves a copy behind**, the way Premiere and Final Cut
/// do it and the way the canvas already does: the copy goes where the hand
/// lets go and the original never moves. A piece of a cut clip copies as a
/// clip of its own, because to an editor every piece between two cuts is a
/// clip.
@Suite("Option dragging a clip leaves a copy behind")
struct ClipDragCopyTests {

    @Test("A copy of a whole clip reads the same recording, under the same name, on the same track")
    func copyOfAWholeClip() throws {
        let (doc, take, _, _) = ClipLandingTests.edit()
        let original = try #require(doc.layer(id: take))
        let copy = try #require(doc.clipDragCopy(of: take))
        #expect(copy.id != take)
        #expect(copy.name == original.name)
        #expect(copy.movie == original.movie)
        #expect(copy.time == original.time)
        #expect(copy.trackID == doc.trackID(ofClip: take))
        // Not in the document until it is let go of.
        #expect(doc.layer(id: copy.id) == nil)
    }

    @Test("Placing the copy later leaves the original exactly where it was")
    func placingLeavesTheOriginal() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let copy = try #require(doc.clipDragCopy(of: take))
        let ok1 = doc.placeClipCopy(copy, over: take, atInMS: 9000)
        #expect(ok1)
        #expect(doc.layer(id: take)?.time?.inMS == 0)
        #expect(doc.layer(id: take)?.time?.outMS == 8000)
        #expect(doc.layer(id: copy.id)?.time?.inMS == 9000)
        #expect(doc.layer(id: copy.id)?.time?.outMS == 17000)
        #expect(doc.trackID(ofClip: copy.id) == v1)
        #expect(doc.trackID(ofClip: take) == v1)
        // Two clips now read the one recording.
        let movie = doc.layer(id: take)?.movie
        #expect(doc.timelineClipLayers.filter { $0.movie == movie && movie != nil }.count == 2)
    }

    @Test("The copy brings its own sound, linked under it")
    func copyBringsItsSound() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let copy = try #require(doc.clipDragCopy(of: take))
        let ok2 = doc.placeClipCopy(copy, over: take, atInMS: 9000)
        #expect(ok2)
        #expect(doc.linkedSoundTrackID(ofClip: copy.id) != nil)
        #expect(doc.linkedSoundTrackID(ofClip: take) != nil)
    }

    @Test("A document that knows its length grows to hold a copy placed past its end")
    func documentGrows() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        doc.durationMS = 14000
        let copy = try #require(doc.clipDragCopy(of: take))
        let ok3 = doc.placeClipCopy(copy, over: take, atInMS: 12000)
        #expect(ok3)
        #expect(doc.durationMS == 20000)
    }

    @Test("Placing the same copy twice puts it in once, so a shown drag can be redrawn freely")
    func placingTwiceIsOnce() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let copy = try #require(doc.clipDragCopy(of: take))
        let before = doc.allLayers.count
        let ok4 = doc.placeClipCopy(copy, over: take, atInMS: 9000)
        #expect(ok4)
        doc.placeClipCopy(copy, over: take, atInMS: 9500)
        #expect(doc.allLayers.count == before + 1)
        #expect(doc.layer(id: copy.id)?.time?.inMS == 9500)
    }

    @Test("A copy of one piece of a cut clip is a clip of that piece alone, starting where the piece started")
    func copyOfOnePiece() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let ok5 = doc.splitClip(take, atMS: 3000)
        #expect(ok5)
        let pieces = try #require(doc.layer(id: take)?.clipPieces)
        let second = try #require(pieces.piece(at: 1))
        let copy = try #require(doc.clipDragCopy(of: take, piece: 1))
        let time = try #require(copy.time)
        #expect(time.inMS == 3000)
        #expect(time.lengthMS == 5000)
        #expect(copy.clipPieces?.count == 1)
        #expect(copy.clipPieces?.piece(at: 0)?.sourceInMS == second.sourceInMS)
        let ok6 = doc.placeClipCopy(copy, over: take, atInMS: 10000)
        #expect(ok6)
        // The cut clip is untouched: still two pieces, still eight seconds.
        #expect(doc.layer(id: take)?.clipPieces?.count == 2)
        #expect(doc.layer(id: take)?.time?.outMS == 8000)
        #expect(doc.layer(id: copy.id)?.time?.inMS == 10000)
        #expect(doc.layer(id: copy.id)?.time?.outMS == 15000)
    }

    @Test("A copy of the first piece of a cut clip keeps that piece's frames")
    func copyOfTheFirstPiece() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let ok7 = doc.splitClip(take, atMS: 3000)
        #expect(ok7)
        let copy = try #require(doc.clipDragCopy(of: take, piece: 0))
        #expect(copy.time?.inMS == 0)
        #expect(copy.time?.lengthMS == 3000)
        #expect(copy.clipPieces?.piece(at: 0)?.sourceInMS
                == doc.layer(id: take)?.clipPieces?.piece(at: 0)?.sourceInMS)
    }

    @Test("A piece that is not there, or a layer with no time, gives no copy")
    func nothingToCopy() throws {
        let (doc, take, _, _) = ClipLandingTests.edit()
        #expect(doc.clipDragCopy(of: take, piece: 4) == nil)
        #expect(doc.clipDragCopy(of: UUID()) == nil)
    }

    @Test("A clip on a locked track gives no copy, the way it gives no drag")
    func lockedTrackGivesNone() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        doc.materializeTracks()
        let v1 = try #require(doc.trackID(ofClip: take))
        doc.updateTrack(v1) { $0.isLocked = true }
        #expect(doc.clipDragCopy(of: take) == nil)
    }

    @Test("The copy, placed and then carried onto another track, is one edit")
    func copyThenNewTrack() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let copy = try #require(doc.clipDragCopy(of: take))
        let ok8 = doc.placeClipCopy(copy, over: take, atInMS: 2000)
        #expect(ok8)
        let made = doc.moveClipToNewTrack(copy.id, at: 0)
        #expect(made != nil)
        #expect(doc.trackID(ofClip: copy.id) != v1)
        #expect(doc.trackID(ofClip: take) == v1)
    }
}

extension ClipDragCopyTests {
    @Test("A copy dropped over the original's own stretch puts its sound on a track of its own")
    func overlappingCopySoundGoesElsewhere() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let copy = try #require(doc.clipDragCopy(of: take))
        let ok9 = doc.placeClipCopy(copy, over: take, atInMS: 2000)
        #expect(ok9)
        let mine = try #require(doc.linkedSoundTrackID(ofClip: copy.id))
        #expect(doc.linkedSoundTrackID(ofClip: take) != mine)
    }
}

extension ClipDragCopyTests {
    @Test("A copy let go over something on its own track goes onto a new track straight over it, as a paste does")
    func overlappingCopyGetsANewTrackOverItsOwn() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let copy = try #require(doc.clipDragCopy(of: take))
        let placed = doc.placeClipCopy(copy, over: take, atInMS: 2000)
        #expect(placed)
        doc.liftClipsOffOverlaps([copy.id])
        let track = try #require(doc.trackID(ofClip: copy.id))
        #expect(track != v1)
        let tracks = doc.timelineTracks
        let index = try #require(tracks.firstIndex { $0.id == track })
        #expect(tracks[index + 1].id == v1)
        #expect(doc.layer(id: copy.id)?.time?.inMS == 2000)
        #expect(doc.trackID(ofClip: take) == v1)
    }

    @Test("A copy let go where its own track is free stays on it")
    func freeCopyStaysOnItsTrack() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let v1 = try #require(doc.trackID(ofClip: take))
        let copy = try #require(doc.clipDragCopy(of: take))
        let placed = doc.placeClipCopy(copy, over: take, atInMS: 9000)
        #expect(placed)
        let count = doc.timelineTracks.count
        doc.liftClipsOffOverlaps([copy.id])
        #expect(doc.trackID(ofClip: copy.id) == v1)
        #expect(doc.timelineTracks.count == count)
    }

    @Test("Two copies off one track that both land over it share one new track where they fit side by side")
    func twoCopiesShareOneNewTrack() throws {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let split = doc.splitClip(take, atMS: 4000)
        #expect(split)
        let first = try #require(doc.clipDragCopy(of: take, piece: 0))
        let second = try #require(doc.clipDragCopy(of: take, piece: 1))
        let a = doc.placeClipCopy(first, over: take, atInMS: 1000)
        let b = doc.placeClipCopy(second, over: take, atInMS: 5000)
        #expect(a && b)
        let pictures = doc.timelineTracks.filter { $0.kind != .audio }.count
        doc.liftClipsOffOverlaps([first.id, second.id])
        #expect(doc.trackID(ofClip: first.id) == doc.trackID(ofClip: second.id))
        #expect(doc.trackID(ofClip: first.id) != doc.trackID(ofClip: take))
        #expect(doc.timelineTracks.filter { $0.kind != .audio }.count == pictures + 1)
    }
}

extension ClipDragCopyTests {
    @Test("Lifting the same copy in two goes makes the same track, so a carried copy keeps one row")
    func liftIsTheSameTrackEveryTime() throws {
        let (base, take, _, _) = ClipLandingTests.edit()
        let copy = try #require(base.clipDragCopy(of: take))
        var once = base, twice = base
        _ = once.placeClipCopy(copy, over: take, atInMS: 2000)
        once.liftClipsOffOverlaps([copy.id])
        _ = twice.placeClipCopy(copy, over: take, atInMS: 3000)
        twice.liftClipsOffOverlaps([copy.id])
        let a = try #require(once.trackID(ofClip: copy.id))
        #expect(a == twice.trackID(ofClip: copy.id))
        #expect(a != base.trackID(ofClip: take))
    }
}
