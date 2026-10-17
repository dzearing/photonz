import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **⌘ on an edge**: Premiere's ripple trim by hand (`RippleEdgeDrag.swift`).
///
/// A plain drag on a clip's end leaves a gap for the next clip to sit across;
/// in Premiere, ⌘ held over the edit point with the Selection tool turns the
/// same drag into a ripple trim, and everything after the edit slides along
/// with the edge on every track, so tightening a cut by eye is one gesture.
/// Shortening takes the stretch out of every unlocked track the way Q and W
/// do; lengthening puts the time in the way a hold that pushes everything
/// does.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("⌘ dragging a clip's edge ripple trims")
struct RippleEdgeDragTests {

    static func movie(durationMS: Int) -> MovieRef {
        MovieRef(id: UUID(), pixelSize: CGSize(width: 1920, height: 1080), durationMS: durationMS)
    }

    static func cue(_ text: String, _ inMS: Int, _ outMS: Int) -> CaptionCue {
        let words = text.split(separator: " ").map(String.init)
        let step = (outMS - inMS) / max(1, words.count)
        return CaptionCue(words: words.enumerated().map { index, word in
            TranscribedWord(word, startMS: inMS + index * step, endMS: inMS + (index + 1) * step)
        }, inMS: inMS, outMS: outMS)
    }

    /// A twelve second talk trimmed to its first eight, so there are four
    /// seconds of spare behind its end; a five second clip straight after it;
    /// music under both; a marker one second into the second clip.
    static func edit() -> (doc: PhotonzDocument, talk: UUID, next: UUID, music: UUID) {
        var doc = PhotonzDocument.recording(movie(durationMS: 12_000), name: "Talk")
        let talk = doc.layers[0].id
        doc.trimClipEnd(talk, ofPiece: 0, byMS: -4000)
        let next = doc.addClip(movie(durationMS: 5000), name: "Next", atMS: 8000,
                               frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let music = doc.addSound(SoundRef(durationMS: 13_000), name: "music", atMS: 0)
        doc.addMarker(atMS: 9000)
        return (doc, talk, next, music)
    }

    // MARK: The end edge

    @Test("Pulling the end in two seconds brings the next clip, the marker and the music's later part in with it")
    func endInRipples() throws {
        var (doc, talk, next, music) = Self.edit()
        let did1 = doc.rippleTrimClipEdge(talk, .seam(after: 0), byMS: -2000)
        #expect(did1)
        #expect(doc.layer(id: talk)?.time?.lengthMS == 6000)
        #expect(doc.layer(id: next)?.time?.inMS == 6000)
        #expect(doc.markers.map(\.atMS) == [7000])
        // The music lost the same two seconds, so what played under the next
        // clip's first frame still does.
        let musicTime = try #require(doc.layer(id: music)?.time)
        #expect(musicTime.lengthMS == 11_000)
        #expect(doc.layer(id: music)?.clipPieces?.sourceMS(atMS: 6000) == 8000)
        #expect(doc.documentDurationMS == 11_000)
    }

    @Test("Pulling the end out a second and a half pushes everything after it later")
    func endOutRipples() throws {
        var (doc, talk, next, music) = Self.edit()
        let did2 = doc.rippleTrimClipEdge(talk, .seam(after: 0), byMS: 1500)
        #expect(did2)
        #expect(doc.layer(id: talk)?.time?.lengthMS == 9500)
        #expect(doc.layer(id: next)?.time?.inMS == 9500)
        #expect(doc.markers.map(\.atMS) == [10_500])
        // The music under the edit waits for the new time and then carries on
        // from where it was, so it is still in step with the next clip.
        let pieces = try #require(doc.layer(id: music)?.clipPieces)
        #expect(pieces.totalLengthMS == 14_500)
        #expect(pieces.sourceMS(atMS: 9500) == 8000)
    }

    @Test("A plain trim of the same edge leaves the next clip where it was")
    func plainTrimStillLeavesAGap() {
        var (doc, talk, next, _) = Self.edit()
        doc.trimClipEnd(talk, ofPiece: 0, byMS: -2000)
        #expect(doc.layer(id: next)?.time?.inMS == 8000)
        #expect(doc.markers.map(\.atMS) == [9000])
    }

    @Test("A join inside the clip ripples too: the clip's own later piece and everything after it follow")
    func interiorJoin() throws {
        var (doc, talk, next, _) = Self.edit()
        doc.splitClip(talk, atMS: 4000)
        let did3 = doc.rippleTrimClipEdge(talk, .seam(after: 0), byMS: -1000)
        #expect(did3)
        let pieces = try #require(doc.layer(id: talk)?.clipPieces)
        #expect(pieces.piece(at: 0)?.lengthMS == 3000)
        #expect(pieces.piece(at: 1)?.sourceInMS == 4000)
        #expect(doc.layer(id: next)?.time?.inMS == 7000)
    }

    @Test("A caption after the edit keeps its words on the picture they were heard over, either way")
    func captionWordsFollow() throws {
        var (doc, talk, _, _) = Self.edit()
        doc.landCaptions([Self.cue("later on", 9000, 10_000)])
        var shorter = doc
        shorter.rippleTrimClipEdge(talk, .seam(after: 0), byMS: -2000)
        #expect(shorter.captionLayers.first?.time?.inMS == 7000)
        #expect(shorter.captionLayers.first?.captionWords?.first?.startMS == 7000)
        doc.rippleTrimClipEdge(talk, .seam(after: 0), byMS: 1500)
        #expect(doc.captionLayers.first?.time?.inMS == 10_500)
        #expect(doc.captionLayers.first?.captionWords?.first?.startMS == 10_500)
    }

    // MARK: The start edge

    @Test("Pulling the start in trims the head, the clip keeps its place, and everything after it comes in")
    func startInRipples() throws {
        var (doc, talk, next, _) = Self.edit()
        let did4 = doc.rippleTrimClipEdge(talk, .clipStart, byMS: 2000)
        #expect(did4)
        let time = try #require(doc.layer(id: talk)?.time)
        #expect(time.inMS == 0)
        #expect(time.lengthMS == 6000)
        #expect(doc.layer(id: talk)?.clipPieces?.sourceMS(atMS: 0) == 2000)
        #expect(doc.layer(id: next)?.time?.inMS == 6000)
        #expect(doc.markers.map(\.atMS) == [7000])
    }

    @Test("Pulling the start back out gives the head back and pushes everything after it later")
    func startOutRipples() throws {
        var (doc, talk, next, _) = Self.edit()
        doc.trimClipStart(talk, ofPiece: 0, byMS: 2000)
        // A plain head trim leaves the next clip where it was.
        #expect(doc.layer(id: next)?.time?.inMS == 8000)
        let did5 = doc.rippleTrimClipEdge(talk, .clipStart, byMS: -1000)
        #expect(did5)
        #expect(doc.layer(id: talk)?.time?.lengthMS == 7000)
        #expect(doc.layer(id: talk)?.clipPieces?.sourceMS(atMS: 0) == 1000)
        #expect(doc.layer(id: next)?.time?.inMS == 9000)
    }

    // MARK: Locks and refusals

    @Test("A locked track stays exactly where it was")
    func lockedTrackStays() throws {
        var (doc, talk, next, music) = Self.edit()
        doc.materializeTracks()
        let track = try #require(doc.trackID(ofClip: music))
        doc.updateTrack(track) { $0.isLocked = true }
        let musicWas = doc.layer(id: music)
        let did6 = doc.rippleTrimClipEdge(talk, .seam(after: 0), byMS: -2000)
        #expect(did6)
        #expect(doc.layer(id: music) == musicWas)
        #expect(doc.layer(id: next)?.time?.inMS == 6000)
        var longer = doc
        let did7 = longer.rippleTrimClipEdge(talk, .seam(after: 0), byMS: 1000)
        #expect(did7)
        #expect(longer.layer(id: music) == musicWas)
    }

    @Test("A clip on a locked track does not ripple at all")
    func lockedClipRefused() throws {
        var (doc, talk, _, _) = Self.edit()
        doc.materializeTracks()
        let track = try #require(doc.trackID(ofClip: talk))
        doc.updateTrack(track) { $0.isLocked = true }
        let was = doc
        let did8 = doc.rippleTrimClipEdge(talk, .seam(after: 0), byMS: -2000)
        #expect(!did8)
        #expect(doc == was)
    }

    @Test("Nothing moved, a grab that is not an edge, or an edge past its spare, changes nothing")
    func refusals() {
        var (doc, talk, _, _) = Self.edit()
        let was = doc
        let did9 = doc.rippleTrimClipEdge(talk, .seam(after: 0), byMS: 0)
        #expect(!did9)
        let did10 = doc.rippleTrimClipEdge(talk, .body, byMS: 1000)
        #expect(!did10)
        let did11 = doc.rippleTrimClipEdge(talk, .carry(piece: 0), byMS: 1000)
        #expect(!did11)
        // Only four seconds of spare behind the end.
        let did12 = doc.rippleTrimClipEdge(talk, .seam(after: 0), byMS: 5000)
        #expect(!did12)
        #expect(doc == was)
    }

    @Test("Which grabs a held ⌘ turns into a ripple: an edge with frames behind it, never a title's free start")
    func whichGrabsRipple() {
        let pieces = ClipPieces(single: LayerTime(inMS: 0, outMS: 4000, sourceInMS: 0, sourceLengthMS: 4000))
        #expect(ClipBarDrag(grab: .seam(after: 0), pieces: pieces, clipStartMS: 0).ripples)
        #expect(ClipBarDrag(grab: .clipStart, pieces: pieces, clipStartMS: 0).ripples)
        #expect(!ClipBarDrag(grab: .clipStart, pieces: pieces, clipStartMS: 0, startIsFree: true).ripples)
        #expect(!ClipBarDrag(grab: .body, pieces: pieces, clipStartMS: 0).ripples)
        #expect(!ClipBarDrag(grab: .carry(piece: 0), pieces: pieces, clipStartMS: 0).ripples)
    }
}
