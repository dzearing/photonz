import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Q and W**: Premiere's Ripple Trim Previous Edit to Playhead and Ripple
/// Trim Next Edit to Playhead (`RippleTrim.swift`).
///
/// Tightening a talking recording in Premiere is parking the playhead where
/// the good part starts and pressing Q, then where it ends and pressing W. The
/// piece under the playhead loses everything from its start (or to its end)
/// and the gap closes on every track, so the sound and the captions stay with
/// the picture. Before this it was a cut, a click and a Delete.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("Q and W trim the clip under the playhead")
struct RippleTrimTests {

    static func movie(durationMS: Int = 12_000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                 pixelSize: CGSize(width: 1920, height: 1080),
                 durationMS: durationMS)
    }

    static func cue(_ text: String, _ inMS: Int, _ outMS: Int) -> CaptionCue {
        let words = text.split(separator: " ").map(String.init)
        let step = (outMS - inMS) / max(1, words.count)
        return CaptionCue(words: words.enumerated().map { index, word in
            TranscribedWord(word, startMS: inMS + index * step, endMS: inMS + (index + 1) * step)
        }, inMS: inMS, outMS: outMS)
    }

    /// A twelve second recording, uncut.
    static func talk() -> (doc: PhotonzDocument, clip: UUID) {
        var doc = PhotonzDocument.recording(movie(), name: "Talk")
        return (doc, doc.layers[0].id)
    }

    // MARK: Q

    @Test("Q two seconds into an uncut clip takes those two seconds off and the clip starts where it did")
    func qTrimsTheHead() throws {
        var (doc, clip) = Self.talk()
        let trimmed = doc.rippleTrim(clip: clip, atMS: 2000, .start)
        #expect(trimmed)
        let time = try #require(doc.layer(id: clip)?.time)
        #expect(time.inMS == 0)
        #expect(time.lengthMS == 10_000)
        // What plays first now is what played at 2.0s.
        #expect(doc.layer(id: clip)?.clipPieces?.sourceMS(atMS: 0) == 2000)
        #expect(doc.documentDurationMS == 10_000)
    }

    @Test("Q in a later piece trims from that piece's own start, not the clip's")
    func qTrimsFromThePiece() throws {
        var (doc, clip) = Self.talk()
        doc.splitClip(clip, atMS: 6000)
        doc.rippleTrim(clip: clip, atMS: 7500, .start)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        #expect(pieces.totalLengthMS == 10_500)
        #expect(pieces.count == 2)
        #expect(pieces.piece(at: 0)?.lengthMS == 6000)
        #expect(pieces.piece(at: 1)?.sourceInMS == 7500)
        #expect(pieces.piece(at: 1)?.lengthMS == 4500)
    }

    // MARK: W

    @Test("W takes everything from the playhead to the end of the piece and closes the gap")
    func wTrimsTheTail() throws {
        var (doc, clip) = Self.talk()
        doc.splitClip(clip, atMS: 6000)
        doc.rippleTrim(clip: clip, atMS: 4000, .end)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        #expect(pieces.totalLengthMS == 10_000)
        #expect(pieces.piece(at: 0)?.lengthMS == 4000)
        // The second piece plays straight after, from where it always did.
        #expect(pieces.piece(at: 1)?.sourceInMS == 6000)
        #expect(doc.layer(id: clip)?.time?.inMS == 0)
    }

    // MARK: Everything else keeps step

    @Test("A sound laid along the clip loses the same stretch, so it stays in sync")
    func soundKeepsStep() throws {
        var (doc, clip) = Self.talk()
        let voice = doc.addSound(SoundRef(durationMS: 12_000), name: "voice", atMS: 0)
        doc.rippleTrim(clip: clip, atMS: 2000, .start)
        let time = try #require(doc.layer(id: voice)?.time)
        #expect(time.inMS == 0)
        #expect(time.lengthMS == 10_000)
        #expect(doc.layer(id: voice)?.clipPieces?.sourceMS(atMS: 0) == 2000)
    }

    @Test("Captions after the trim slide back and one inside it goes")
    func captionsFollow() throws {
        var (doc, clip) = Self.talk()
        doc.landCaptions([Self.cue("gone", 500, 1500), Self.cue("kept later", 5000, 7000)])
        doc.rippleTrim(clip: clip, atMS: 2000, .start)
        let words = doc.captionLayers.compactMap { $0.captionWords?.first?.text }
        #expect(words == ["kept"])
        #expect(doc.captionLayers.first?.time?.inMS == 3000)
    }

    @Test("Markers after the trim move with the picture, and one inside lands on the join")
    func markersFollow() {
        var (doc, clip) = Self.talk()
        doc.addMarker(atMS: 1000)
        doc.addMarker(atMS: 5000)
        doc.setMarkIn(atMS: 6000)
        doc.rippleTrim(clip: clip, atMS: 2000, .start)
        #expect(doc.markers.map(\.atMS) == [0, 3000])
        #expect(doc.markInMS == 4000)
    }

    @Test("A clip on a locked track is not trimmed")
    func lockedTrack() throws {
        var (doc, clip) = Self.talk()
        doc.materializeTracks()
        let track = try #require(doc.trackID(ofClip: clip))
        doc.updateTrack(track) { $0.isLocked = true }
        let was = doc
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 2000, .start) == nil)
        let trimmed = doc.rippleTrim(clip: clip, atMS: 2000, .start)
        #expect(!trimmed)
        #expect(doc == was)
    }

    // MARK: Where there is nothing to trim

    @Test("On the piece's own edge there is nothing to take")
    func onTheEdge() {
        var (doc, clip) = Self.talk()
        doc.splitClip(clip, atMS: 6000)
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 6000, .start) == nil)
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 0, .start) == nil)
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 12_000, .end) == nil)
        // On a cut, W trims the piece that starts there: all of it would go,
        // which is a ripple delete, not a trim.
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 6000, .end) == nil)
    }

    @Test("A trim that would leave a sliver too short to hold is refused rather than taking the lot")
    func noSlivers() {
        let (doc, clip) = Self.talk()
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 11_995, .start) == nil)
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 5, .end) == nil)
        // A sliver is anything under a frame (`LayerTime.shortestMS`).
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 11_990, .start) == nil)
        let aFrameLeft = 12_000 - LayerTime.shortestMS
        #expect(doc.rippleTrimStretch(clip: clip, atMS: aFrameLeft, .start) == 0..<aFrameLeft)
    }

    @Test("A playhead outside the clip trims nothing")
    func outsideTheClip() {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Talk")
        let clip = doc.layers[0].id
        doc.moveClip(clip, toInMS: 2000)
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 1000, .start) == nil)
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 1000, .end) == nil)
        // Inside it, the stretch is on the document's clock.
        #expect(doc.rippleTrimStretch(clip: clip, atMS: 3000, .start) == 2000..<3000)
    }

    // MARK: Which clip

    @Test("The picked clip wins when the playhead is on it; otherwise the top clip under the playhead")
    func whichClip() {
        var (doc, clip) = Self.talk()
        let voice = doc.addSound(SoundRef(durationMS: 4000), name: "voice", atMS: 0)
        #expect(doc.rippleTrimClip(pickedLayerID: voice, atMS: 2000) == voice)
        // Picked, but the playhead is past it: the clip under the playhead.
        #expect(doc.rippleTrimClip(pickedLayerID: voice, atMS: 6000) == clip)
        #expect(doc.rippleTrimClip(pickedLayerID: nil, atMS: 6000) == clip)
        // Nothing with media under the playhead.
        #expect(doc.rippleTrimClip(pickedLayerID: nil, atMS: 20_000) == nil)
    }

    @Test("A caption or a title picked is not a clip to trim: the recording under it is")
    func captionPickedFallsThrough() throws {
        var (doc, clip) = Self.talk()
        doc.landCaptions([Self.cue("hello there", 1000, 3000)])
        let caption = try #require(doc.captionLayers.first?.id)
        #expect(doc.rippleTrimClip(pickedLayerID: caption, atMS: 2000) == clip)
    }
}
