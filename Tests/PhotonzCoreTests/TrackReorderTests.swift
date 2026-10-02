import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **Tracks carried up and down the timeline by their headers**
/// (`DocumentTracks.swift` `moveTrack`, `TrackRowDrag.swift`).
///
/// The user asked on 2026-09-30 for the layers list's lifting drag on the
/// timeline's track headers too: the track lifts, the others slide aside, and
/// the gap they open is where it lands. Where it lands is read in halves, the
/// same rule as the layers list: the top half of a row puts it above that row,
/// the bottom half below, and the bottom half of an open group's heading puts it
/// inside the group, first.
@Suite("Reordering tracks")
struct TrackReorderTests {

    static let movie = MovieRef(pixelSize: CGSize(width: 100, height: 100),
                                durationMS: 6000, hasSound: true)

    /// A recording at the bottom, a title over it, and some music.
    static func cut() -> (doc: PhotonzDocument, recording: UUID, title: UUID, music: UUID) {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let recording = doc.layers[0].id
        var title = Layer(name: "Hello", content: .text(TextContent(string: "Hello")),
                          frame: CGRect(x: 0, y: 0, width: 40, height: 20))
        title.time = LayerTime(inMS: 1000, outMS: 3000)
        doc.addLayer(title)
        let music = doc.addSound(SoundRef(durationMS: 5000), name: "music", atMS: 0)
        return (doc, recording, title.id, music)
    }

    // MARK: - The document

    @Test("A track carried above another lands there, and the stack follows: higher is further forward")
    func moveAbove() throws {
        var (doc, recording, title, _) = Self.cut()
        let ids = doc.timelineTracks.map(\.id)
        // Title, V1, Audio, Audio 2: V1 carried above Title.
        do { let moved = doc.moveTrack(ids[1], .above(ids[0])); #expect(moved) }
        #expect(doc.timelineTracks.map(\.id) == [ids[1], ids[0], ids[2], ids[3]])
        // The layers list tells the same story: the recording is now in front.
        let order = doc.layers.map(\.id)
        let r = try #require(order.firstIndex(of: recording))
        let t = try #require(order.firstIndex(of: title))
        #expect(r > t)
    }

    @Test("A track carried below another lands under it")
    func moveBelow() {
        var (doc, _, _, _) = Self.cut()
        let ids = doc.timelineTracks.map(\.id)
        do { let moved = doc.moveTrack(ids[0], .below(ids[1])); #expect(moved) }
        #expect(doc.timelineTracks.map(\.id) == [ids[1], ids[0], ids[2], ids[3]])
    }

    @Test("Letting go where it came from changes nothing")
    func moveNowhere() {
        var (doc, _, _, _) = Self.cut()
        let ids = doc.timelineTracks.map(\.id)
        let before = doc
        do { let moved = doc.moveTrack(ids[1], .below(ids[0])); #expect(!moved) }
        do { let moved = doc.moveTrack(ids[1], .above(ids[2])); #expect(!moved) }
        #expect(doc == before)
    }

    @Test("A locked track stays where it is")
    func lockedStays() {
        var (doc, _, _, _) = Self.cut()
        let ids = doc.timelineTracks.map(\.id)
        doc.updateTrack(ids[1]) { $0.isLocked = true }
        let before = doc
        #expect(!doc.canMoveTrack(ids[1]))
        do { let moved = doc.moveTrack(ids[1], .above(ids[0])); #expect(!moved) }
        #expect(doc == before)
    }

    @Test("Reordering the sound tracks carries each clip's own sound with its track")
    func linkedSoundRidesItsTrack() throws {
        var (doc, recording, _, music) = Self.cut()
        let ids = doc.timelineTracks.map(\.id)
        let audio = ids[2], audio2 = ids[3]
        #expect(doc.linkedSoundClipIDs(onTrack: audio) == [recording])
        #expect(doc.clipIDs(onTrack: audio2) == [music])
        // The music's track carried above the recording's sound.
        do { let moved = doc.moveTrack(audio2, .above(audio)); #expect(moved) }
        let tracks = doc.timelineTracks
        #expect(tracks.map(\.id) == [ids[0], ids[1], audio2, audio])
        // Each track kept what was on it: the headers did not just swap names
        // over sound that stayed put.
        #expect(doc.clipIDs(onTrack: audio2) == [music])
        #expect(doc.linkedSoundClipIDs(onTrack: audio) == [recording])
        #expect(doc.linkedSoundTrackID(ofClip: recording) == audio)
    }

    @Test("Two clips' own sounds on two tracks swap places with their tracks")
    func twoLinkedSoundsSwap() throws {
        var doc = PhotonzDocument.recording(Self.movie, name: "take")
        let first = doc.layers[0].id
        let second = doc.addClip(Self.movie, name: "take 2", atMS: 0,
                                 frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        // Both recordings speak, and at the same moments, so their sounds sit
        // on two tracks.
        #expect(doc.layer(id: first)?.hasLinkedSound == true)
        #expect(doc.layer(id: second)?.hasLinkedSound == true)
        let tracks = doc.timelineTracks
        let audio = tracks.filter { $0.kind == .audio }.map(\.id)
        #expect(audio.count == 2)
        let onFirst = doc.linkedSoundClipIDs(onTrack: audio[0])
        let onSecond = doc.linkedSoundClipIDs(onTrack: audio[1])
        do { let moved = doc.moveTrack(audio[1], .above(audio[0])); #expect(moved) }
        #expect(doc.timelineTracks.filter { $0.kind == .audio }.map(\.id) == [audio[1], audio[0]])
        #expect(doc.linkedSoundClipIDs(onTrack: audio[0]) == onFirst)
        #expect(doc.linkedSoundClipIDs(onTrack: audio[1]) == onSecond)
    }

    @Test("A track carried in among a group's tracks joins it; carried out, it leaves; an emptied group goes")
    func groups() throws {
        var (doc, _, _, _) = Self.cut()
        let ids = doc.timelineTracks.map(\.id)
        let grouped = doc.groupTracks([ids[0], ids[1]])
        let group = try #require(grouped)
        // Above a grouped track: in the group.
        do { let moved = doc.moveTrack(ids[2], .above(ids[1])); #expect(moved) }
        #expect(doc.timelineTracks.map(\.id) == [ids[0], ids[2], ids[1], ids[3]])
        #expect(doc.track(id: ids[2])?.groupID == group)
        // Below the group, by its heading: out of it, under its last track.
        do { let moved = doc.moveTrack(ids[0], .below(group)); #expect(moved) }
        #expect(doc.timelineTracks.map(\.id) == [ids[2], ids[1], ids[0], ids[3]])
        #expect(doc.track(id: ids[0])?.groupID == nil)
        // Above the heading: out of it, over its first track.
        do { let moved = doc.moveTrack(ids[3], .above(group)); #expect(moved) }
        #expect(doc.timelineTracks.map(\.id) == [ids[3], ids[2], ids[1], ids[0]])
        #expect(doc.track(id: ids[3])?.groupID == nil)
        // Inside the heading: its first slot.
        do { let moved = doc.moveTrack(ids[0], .inside(group)); #expect(moved) }
        #expect(doc.timelineTracks.map(\.id) == [ids[3], ids[0], ids[2], ids[1]])
        #expect(doc.track(id: ids[0])?.groupID == group)
        // Every track carried out of it: the group goes with the last one.
        do { let moved = doc.moveTrack(ids[0], .above(ids[3])); #expect(moved) }
        do { let moved = doc.moveTrack(ids[2], .above(ids[3])); #expect(moved) }
        do { let moved = doc.moveTrack(ids[1], .above(ids[3])); #expect(moved) }
        #expect(doc.trackGroups.isEmpty)
    }

    // MARK: - The drag

    typealias Row = TrackRowDrag.Row

    /// Four ungrouped tracks, 30 tall with 4 between, the first at y 4.
    static func plainRows(_ ids: [UUID], heights: [CGFloat]? = nil) -> [Row] {
        var top: CGFloat = 4
        return ids.enumerated().map { index, id in
            let height = heights?[index] ?? 30
            defer { top += height + 4 }
            return Row(id: id, top: top, height: height, kind: .track(group: nil))
        }
    }

    @Test("Picked up, the track rides the pointer and nothing moves yet")
    func pickUp() throws {
        let ids = (0..<4).map { _ in UUID() }
        let rows = Self.plainRows(ids)
        let drag = try #require(TrackRowDrag(grabbing: ids[1], rows: rows, spacing: 4, pointerY: 50))
        #expect(drag.liftedTop == 38)
        #expect(drag.gapTop == 38)
        #expect(drag.landing == nil)
        for id in ids { #expect(drag.offset(of: id) == 0) }
    }

    @Test("Past the middle of the row under it, the track swaps with it once and stays swapped")
    func swapDown() throws {
        let ids = (0..<4).map { _ in UUID() }
        var drag = try #require(TrackRowDrag(grabbing: ids[1], rows: Self.plainRows(ids),
                                             spacing: 4, pointerY: 50))
        // Into the top half of the row under it: that is where it already is.
        drag.move(pointerY: 76)
        #expect(drag.offset(of: ids[2]) == 0)
        // Its bottom half: below it. That row moves up into the old slot.
        drag.move(pointerY: 92)
        #expect(drag.landing == .below(ids[2]))
        #expect(drag.offset(of: ids[2]) == -34)
        #expect(drag.gapTop == 72)
        // The pointer is over the gap now, and a pointer over the gap changes
        // nothing however it wobbles.
        drag.move(pointerY: 80)
        drag.move(pointerY: 95)
        #expect(drag.landing == .below(ids[2]))
        #expect(drag.offset(of: ids[2]) == -34)
    }

    @Test("Rows of different heights: the gap is the carried track's height, and only rows it passes move")
    func mixedHeights() throws {
        let ids = (0..<3).map { _ in UUID() }
        // A sound track is taller.
        let rows = Self.plainRows(ids, heights: [30, 44, 30])
        var drag = try #require(TrackRowDrag(grabbing: ids[0], rows: rows, spacing: 4, pointerY: 10))
        // Down into the bottom half of the 44 tall row (it starts at 38).
        drag.move(pointerY: 38 + 30)
        #expect(drag.landing == .below(ids[1]))
        // It moves up by the carried row and its spacing; the last row stays.
        #expect(drag.offset(of: ids[1]) == -34)
        #expect(drag.offset(of: ids[2]) == 0)
        #expect(drag.gapTop == 52)
        #expect(drag.gapHeight == 30)
    }

    @Test("Above the first row is the very top; past the last is the very bottom")
    func ends() throws {
        let ids = (0..<3).map { _ in UUID() }
        var drag = try #require(TrackRowDrag(grabbing: ids[1], rows: Self.plainRows(ids),
                                             spacing: 4, pointerY: 50))
        drag.move(pointerY: -20)
        #expect(drag.landing == .above(ids[0]))
        #expect(drag.gapTop == 4)
        #expect(drag.liftedTop == 4)
        drag.move(pointerY: 400)
        #expect(drag.landing == .below(ids[2]))
        // Never drawn past the last place a row could stand.
        #expect(drag.liftedTop == 72)
    }

    @Test("Escape puts the gap back where the track came from, and letting go then changes nothing")
    func returnHome() throws {
        let ids = (0..<3).map { _ in UUID() }
        var drag = try #require(TrackRowDrag(grabbing: ids[0], rows: Self.plainRows(ids),
                                             spacing: 4, pointerY: 10))
        drag.move(pointerY: 70)
        #expect(drag.landing != nil)
        drag.returnHome()
        #expect(drag.landing == nil)
        #expect(drag.gapTop == 4)
        for id in ids { #expect(drag.offset(of: id) == 0) }
    }

    @Test("A group's heading: its top half is above the group, its bottom half the group's first slot")
    func headingHalves() throws {
        let loose = UUID(), group = UUID(), a = UUID(), b = UUID()
        let rows = [Row(id: loose, top: 4, height: 30, kind: .track(group: nil)),
                    Row(id: group, top: 38, height: 22, kind: .heading(isOpen: true)),
                    Row(id: a, top: 64, height: 30, kind: .track(group: group)),
                    Row(id: b, top: 98, height: 30, kind: .track(group: group))]
        var drag = try #require(TrackRowDrag(grabbing: loose, rows: rows, spacing: 4, pointerY: 10))
        // The heading's bottom half.
        drag.move(pointerY: 38 + 18)
        #expect(drag.landing == .inside(group))
        #expect(drag.gapGroup == group)
        // The bottom half of the group's last track keeps it inside...
        drag.move(pointerY: 98 + 25)
        #expect(drag.landing == .below(b))
        #expect(drag.gapGroup == group)
        // ...and past the end, it is out below the group.
        drag.move(pointerY: 300)
        #expect(drag.landing == .below(group))
        #expect(drag.gapGroup == nil)
    }

    @Test("A folded group's heading: its bottom half is below the whole group")
    func foldedHeading() throws {
        let group = UUID(), loose = UUID(), last = UUID()
        let rows = [Row(id: loose, top: 4, height: 30, kind: .track(group: nil)),
                    Row(id: group, top: 38, height: 14, kind: .heading(isOpen: false)),
                    Row(id: last, top: 56, height: 30, kind: .track(group: nil))]
        var drag = try #require(TrackRowDrag(grabbing: loose, rows: rows, spacing: 4, pointerY: 10))
        drag.move(pointerY: 38 + 12)
        #expect(drag.landing == .below(group))
        #expect(drag.gapGroup == nil)
    }

    @Test("Nothing to carry it past: no drag")
    func alone() {
        let id = UUID()
        #expect(TrackRowDrag(grabbing: id, rows: Self.plainRows([id]), spacing: 4, pointerY: 10) == nil)
        #expect(TrackRowDrag(grabbing: UUID(), rows: Self.plainRows([id, UUID()]), spacing: 4,
                             pointerY: 10) == nil)
    }
}
