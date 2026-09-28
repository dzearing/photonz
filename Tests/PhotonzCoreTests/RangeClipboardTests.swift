import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Copy, cut and paste a range of time** (`RangeClipboard.swift`).
///
/// With a range drawn on the ruler, ⌘C takes that stretch of every track: the
/// parts of the clips, titles, sounds and captions inside it, cut to it and
/// counted from its start. ⌘X takes the same and closes the gap. ⌘V lays the
/// stretch back in at the playhead, each clip on the track it came from,
/// covering what was there, the way Final Cut pastes a range and Premiere
/// pastes in overwrite.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("Copy, cut and paste a range of time")
struct RangeClipboardTests {

    static func talk() -> (doc: PhotonzDocument, clip: UUID) {
        let (doc, clip, _) = MarkedStretchTests.talk()
        return (doc, clip)
    }

    static func cueSpans(_ doc: PhotonzDocument) -> [Range<Int>] {
        doc.captionLayers.compactMap { $0.time.map { $0.inMS..<$0.outMS } }
    }

    // MARK: Copy

    @Test("A copy is every clip's part inside the range, counted from the range's start")
    func copyTakesTheStretch() throws {
        let (doc, clip) = Self.talk()
        let copied = try #require(doc.copyRange(4000..<8000))
        #expect(copied.lengthMS == 4000)
        let picture = try #require(copied.clips.first { $0.clipPieces != nil })
        #expect(picture.time?.inMS == 0)
        #expect(picture.time?.lengthMS == 4000)
        // The first frame of the copy is the one that played at 4.0s.
        #expect(picture.clipPieces?.sourceMS(atMS: 0) == 4000)
        // It remembers the track it came off.
        #expect(picture.trackID == doc.trackID(ofClip: clip))
    }

    @Test("Captions in the range come along, cut to it: none from before or after")
    func copyTakesTheCaptions() throws {
        let (doc, _) = Self.talk()
        let copied = try #require(doc.copyRange(4000..<8000))
        let captions = try #require(copied.clips.first { $0.isCaptionsLayer })
        let spans = captions.children.compactMap { $0.time.map { $0.inMS..<$0.outMS } }
        #expect(spans == [0..<600, 1000..<3000, 3400..<4000])
    }

    @Test("Copying leaves the document as it was")
    func copyChangesNothing() {
        let (doc, _) = Self.talk()
        let before = doc
        _ = doc.copyRange(4000..<8000)
        #expect(doc == before)
    }

    @Test("A range with no length copies nothing")
    func emptyRangeCopiesNothing() {
        let (doc, _) = Self.talk()
        #expect(doc.copyRange(5000..<5000) == nil)
    }

    @Test("A clip on a locked track is not copied, the way it is not cut")
    func lockedTrackIsLeftOut() throws {
        var (doc, _) = Self.talk()
        let title = MarkedStretchTests.title("Locked", 5000, 6000)
        doc.addLayer(title)
        doc.materializeTracks()
        let track = try #require(doc.trackID(ofClip: title.id))
        doc.updateTrack(track) { $0.isLocked = true }
        let copied = try #require(doc.copyRange(4000..<8000))
        #expect(!copied.clips.contains { $0.name == "Locked" })
    }

    @Test("A copy survives the clipboard")
    func copyRoundTrips() throws {
        let (doc, _) = Self.talk()
        let copied = try #require(doc.copyRange(4000..<8000))
        let data = try JSONEncoder().encode(copied)
        #expect(try JSONDecoder().decode(CopiedRange.self, from: data) == copied)
    }

    // MARK: Paste

    @Test("Paste lays the stretch in at the playhead on the same track, covering what was there")
    func pasteOverwritesAtThePlayhead() throws {
        var (doc, clip) = Self.talk()
        let track = try #require(doc.trackID(ofClip: clip))
        let copied = try #require(doc.copyRange(0..<2000))
        let landed = doc.pasteRange(copied, atMS: 6000)
        #expect(!landed.isEmpty)
        #expect(!landed.contains(clip))
        let clips = doc.clipIDs(onTrack: track).compactMap { doc.layer(id: $0) }
            .filter { $0.clipPieces != nil }.sorted { ($0.time?.inMS ?? 0) < ($1.time?.inMS ?? 0) }
        #expect(clips.map { $0.time?.inMS } == [0, 6000, 8000])
        #expect(clips.map { $0.time?.outMS } == [6000, 8000, 12_000])
        // The pasted piece plays the first two seconds; the recording picks
        // up after it where it would have been.
        #expect(clips[1].clipPieces?.sourceMS(atMS: 0) == 0)
        #expect(clips[2].clipPieces?.sourceMS(atMS: 0) == 8000)
        #expect(doc.documentDurationMS == 12_000)
    }

    @Test("Pasted past the end, the document grows to hold it")
    func pastePastTheEnd() throws {
        var (doc, clip) = Self.talk()
        let copied = try #require(doc.copyRange(4000..<8000))
        doc.pasteRange(copied, atMS: 12_000)
        #expect(doc.documentDurationMS == 16_000)
        #expect(doc.layer(id: clip)?.time?.outMS == 12_000)
    }

    @Test("Pasted captions join the captions already there, covering the lines under them")
    func pasteCaptions() {
        var (doc, _) = Self.talk()
        guard let copied = doc.copyRange(4000..<8000) else { Issue.record("no copy"); return }
        doc.pasteRange(copied, atMS: 10_000)
        #expect(doc.captionsLayers.count == 1)
        let spans = Self.cueSpans(doc)
        // "after it" ran 9.5s to 11.0s: it keeps what played before the paste.
        #expect(spans.contains(9500..<10_000))
        #expect(spans.contains(10_000..<10_600))
        #expect(spans.contains(11_000..<13_000))
        #expect(spans.contains(13_400..<14_000))
        #expect(!spans.contains { $0.lowerBound == 9500 && $0.upperBound > 10_000 })
    }

    @Test("Each paste is new clips, so pasting twice leaves two copies")
    func pasteTwice() throws {
        var (doc, _) = Self.talk()
        let copied = try #require(doc.copyRange(4000..<8000))
        let first = doc.pasteRange(copied, atMS: 12_000)
        let second = doc.pasteRange(copied, atMS: 16_000)
        #expect(Set(first).isDisjoint(with: second))
        #expect(doc.documentDurationMS == 20_000)
    }

    @Test("A clip whose track has gone lands on a new track of its kind")
    func pasteOntoAMissingTrack() throws {
        var (doc, _) = Self.talk()
        let title = MarkedStretchTests.title("Hello", 5000, 6000)
        doc.addLayer(title)
        doc.materializeTracks()
        let copied = try #require(doc.copyRange(4000..<8000))
        let track = try #require(doc.trackID(ofClip: title.id))
        doc.deleteTrack(track)
        let landed = doc.pasteRange(copied, atMS: 12_000)
        let pasted = try #require(landed.compactMap { doc.layer(id: $0) }.first { $0.name.hasPrefix("Hello") })
        #expect(pasted.time?.inMS == 13_000)
        let newTrack = try #require(doc.trackID(ofClip: pasted.id))
        #expect(doc.track(id: newTrack)?.kind == .video)
    }

    // MARK: Cut

    @Test("Cut takes the stretch out and closes the gap, and hands back what it took")
    func cutClosesTheGap() throws {
        var (doc, clip) = Self.talk()
        doc.markRange(4000..<8000)
        let cut = doc.cutMarkedStretch()
        let copied = try #require(cut)
        #expect(copied.lengthMS == 4000)
        #expect(doc.layer(id: clip)?.time?.lengthMS == 8000)
        #expect(doc.markedRangeMS == nil)
        #expect(doc.documentDurationMS == 8000)
    }

    @Test("A title cut whole pastes back onto the track it was cut from")
    func cutThenPasteKeepsTheTrack() throws {
        var (doc, _) = Self.talk()
        let title = MarkedStretchTests.title("Hello", 5000, 6000)
        doc.addLayer(title)
        let track = try #require(doc.trackID(ofClip: title.id))
        doc.markRange(4000..<8000)
        let cut = doc.cutMarkedStretch()
        let copied = try #require(cut)
        #expect(doc.layer(id: title.id) == nil)
        let landed = doc.pasteRange(copied, atMS: 8000)
        let pasted = try #require(landed.compactMap { doc.layer(id: $0) }.first { $0.name == "Hello" })
        #expect(pasted.time?.inMS == 9000)
        #expect(doc.trackID(ofClip: pasted.id) == track)
    }

    @Test("Cut with nothing marked, or nothing under the marks, does nothing")
    func cutNothing() {
        var (doc, _) = Self.talk()
        let before = doc
        #expect(doc.cutMarkedStretch() == nil)
        #expect(doc == before)
    }
}
