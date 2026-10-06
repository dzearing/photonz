import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **X, Shift-I and Shift-O**: Premiere's Mark Clip, Go to In and Go to Out
/// (`TimelineMarks.swift`, `TimelineKeys.swift`).
///
/// Marking a piece to extract it used to take two trips with the playhead, one
/// to its start for I and one to its end for O. Premiere does it in one key: X
/// puts the In and the Out round the clip under the playhead. Shift-I and
/// Shift-O take the playhead back to either mark.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("X marks the clip under the playhead")
struct MarkClipTests {

    static func movie(durationMS: Int = 12_000) -> MovieRef {
        MovieRef(id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
                 pixelSize: CGSize(width: 1920, height: 1080),
                 durationMS: durationMS)
    }

    /// A twelve second recording, uncut.
    static func talk() -> (doc: PhotonzDocument, clip: UUID) {
        let doc = PhotonzDocument.recording(movie(), name: "Talk")
        return (doc, doc.layers[0].id)
    }

    @Test("X on an uncut recording marks the whole of it")
    func wholeClip() {
        var (doc, _) = Self.talk()
        #expect(doc.markClipRangeMS(pickedLayerID: nil, atMS: 5000) == 0..<12_000)
        let changed1 = doc.markClip(pickedLayerID: nil, atMS: 5000)
        #expect(changed1)
        #expect(doc.markInMS == 0)
        #expect(doc.markOutMS == 12_000)
    }

    @Test("Cut with B at two and four seconds, X at three marks just the piece between the cuts")
    func pieceBetweenCuts() {
        var (doc, clip) = Self.talk()
        doc.splitClip(clip, atMS: 2000)
        doc.splitClip(clip, atMS: 4000)
        let changed2 = doc.markClip(pickedLayerID: nil, atMS: 3000)
        #expect(changed2)
        #expect(doc.markInMS == 2000)
        #expect(doc.markOutMS == 4000)
        // Then ' takes exactly that piece out and closes the gap.
        let changed3 = doc.extractMarkedStretch()
        #expect(changed3)
        #expect(doc.documentDurationMS == 10_000)
    }

    @Test("On a cut the playhead belongs to the piece that starts there")
    func onTheCut() {
        var (doc, clip) = Self.talk()
        doc.splitClip(clip, atMS: 4000)
        #expect(doc.markClipRangeMS(pickedLayerID: nil, atMS: 4000) == 4000..<12_000)
    }

    @Test("X replaces marks already set, both at once")
    func replacesMarks() {
        var (doc, clip) = Self.talk()
        doc.splitClip(clip, atMS: 6000)
        doc.setMarkIn(atMS: 8000)
        doc.setMarkOut(atMS: 9000)
        doc.markClip(pickedLayerID: nil, atMS: 1000)
        #expect(doc.markInMS == 0)
        #expect(doc.markOutMS == 6000)
    }

    @Test("A clip placed later in the video is marked on the video's clock")
    func laterClip() {
        var (doc, _) = Self.talk()
        let later = doc.addClip(Self.movie(durationMS: 3000), name: "B-roll", atMS: 5000,
                                frame: CGRect(x: 0, y: 0, width: 640, height: 360))
        #expect(doc.markClipRangeMS(pickedLayerID: nil, atMS: 6000) == 5000..<8000)
        // The clip on top wins over the recording under it.
        #expect(doc.markClipTarget(pickedLayerID: nil, atMS: 6000) == later)
    }

    @Test("The topmost picture wins over a sound on top of it; a picked clip under the playhead wins over both")
    func whichClip() {
        var (doc, clip) = Self.talk()
        let voice = doc.addSound(SoundRef(durationMS: 4000), name: "voice", atMS: 1000)
        #expect(doc.markClipTarget(pickedLayerID: nil, atMS: 2000) == clip)
        #expect(doc.markClipTarget(pickedLayerID: voice, atMS: 2000) == voice)
        #expect(doc.markClipRangeMS(pickedLayerID: voice, atMS: 2000) == 1000..<5000)
        // Picked, but the playhead is past it: the picture under the playhead.
        #expect(doc.markClipTarget(pickedLayerID: voice, atMS: 8000) == clip)
    }

    @Test("A sound alone under the playhead is still a clip to mark")
    func soundAlone() {
        var doc = PhotonzDocument.recording(Self.movie(durationMS: 4000), name: "Talk")
        doc.addSound(SoundRef(durationMS: 4000), name: "music", atMS: 6000)
        #expect(doc.markClipRangeMS(pickedLayerID: nil, atMS: 7000) == 6000..<10_000)
    }

    @Test("Nothing under the playhead: X marks nothing and leaves the marks alone")
    func nothingThere() {
        var doc = PhotonzDocument.recording(Self.movie(durationMS: 4000), name: "Talk")
        doc.addSound(SoundRef(durationMS: 2000), name: "music", atMS: 8000)
        doc.setMarkIn(atMS: 1000)
        #expect(doc.markClipRangeMS(pickedLayerID: nil, atMS: 6000) == nil)
        let changed4 = doc.markClip(pickedLayerID: nil, atMS: 6000)
        #expect(!changed4)
        #expect(doc.markInMS == 1000)
        #expect(doc.markOutMS == nil)
    }

    @Test("X twice on the same clip changes nothing the second time")
    func againIsNothing() {
        var (doc, _) = Self.talk()
        let changed5 = doc.markClip(pickedLayerID: nil, atMS: 5000)
        #expect(changed5)
        let changed6 = doc.markClip(pickedLayerID: nil, atMS: 5000)
        #expect(!changed6)
    }
}
