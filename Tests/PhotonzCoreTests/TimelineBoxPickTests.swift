import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **A box over the timeline picks everything it touches**
/// (`TimelineBoxPick.swift`, task `dragging-a-box-on-the-timeline-picks-everything`).
///
/// A box drawn over the tracks has always picked the clips and pieces it
/// touches (`TrackRangeTests`). It now picks the zoom bars and the keys it
/// touches too, so a person can box a stretch of an edit and move or delete
/// the lot, the way Premiere and Final Cut marquee selection works. A zoom or a
/// key on a clip that is itself picked rides with the clip and is never moved
/// or taken twice.
///
/// Written before the code, which is the rule for `PhotonzCore`.
@Suite("A box picks zooms and keys too")
struct TimelineBoxPickTests {

    static func movie() -> MovieRef {
        MovieRef(pixelSize: CGSize(width: 1920, height: 1080), durationMS: 12_000)
    }

    /// A twelve second recording with zooms at 2s and 7s, and a title from 2s
    /// to 8s with scale keyed at 3s and 6s.
    static func edit() throws -> (doc: PhotonzDocument, clip: UUID, early: UUID, late: UUID, title: UUID) {
        var doc = PhotonzDocument.recording(movie(), name: "Talk")
        let clip = doc.layers[0].id
        let made = doc.addZoom(toClip: clip, atTimeMS: 2000, around: nil)
        let early = try #require(made).id
        let madeLate = doc.addZoom(toClip: clip, atTimeMS: 7000, around: nil)
        let late = try #require(madeLate).id
        var title = Layer(name: "Title", content: .text(TextContent(string: "Hi", fontSize: 48)),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        doc.layers.append(title)
        doc.startKeying(layerID: title.id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(200), layerID: title.id, .motion(.scale), atDocumentTimeMS: 6000)
        doc.materializeTracks()
        return (doc, clip, early, late, title.id)
    }

    static func span(_ doc: PhotonzDocument, _ clip: UUID, _ zoom: UUID) -> (start: Int, end: Int)? {
        doc.layer(id: clip)?.timelineSpanMS(of: zoom)
    }

    static func keyTimes(_ doc: PhotonzDocument, _ id: UUID) -> [Int] {
        doc.keyLanes(layerID: id).flatMap(\.keys).map(\.documentMS).sorted()
    }

    // MARK: Which rows a box reaches

    @Test("A box reaches a row it overlaps, and not one it only nears")
    func reachesRows() {
        #expect(TimelineMarquee.reaches(10...20, minY: 15, maxY: 30))
        #expect(TimelineMarquee.reaches(10...20, minY: 0, maxY: 10))
        #expect(!TimelineMarquee.reaches(10...20, minY: 21, maxY: 40))
        #expect(!TimelineMarquee.reaches(10...20, minY: 0, maxY: 9.5))
    }

    // MARK: What a box touches

    @Test("A box picks the zoom bars it overlaps, not one it only meets")
    func zoomsTouched() throws {
        let (doc, clip, early, late, _) = try Self.edit()
        let first = try #require(Self.span(doc, clip, early))
        let second = try #require(Self.span(doc, clip, late))
        #expect(doc.marqueeZooms(within: first.start..<(first.start + 10), onClip: clip) == [early])
        #expect(Set(doc.marqueeZooms(within: 0..<12_000, onClip: clip)) == [early, late])
        #expect(doc.marqueeZooms(within: first.end..<second.start, onClip: clip).isEmpty)
        #expect(doc.marqueeZooms(within: 0..<12_000, onClip: UUID()).isEmpty)
    }

    @Test("Nothing on a locked clip is picked")
    func lockedClipsKeepTheirZoomsAndKeys() throws {
        var (doc, clip, _, _, title) = try Self.edit()
        doc.updateLayer(id: clip) { $0.isLocked = true }
        doc.updateLayer(id: title) { $0.isLocked = true }
        #expect(doc.marqueeZooms(within: 0..<12_000, onClip: clip).isEmpty)
        let lanes = Set(doc.keyLanes(layerID: title).map(\.motionID))
        #expect(doc.marqueeKeys(within: 0..<12_000, layerID: title, motionIDs: lanes).isEmpty)
    }

    @Test("A box picks the keys inside it on the lanes it crosses, its edges included")
    func keysTouched() throws {
        let (doc, _, _, _, title) = try Self.edit()
        let lanes = Set(doc.keyLanes(layerID: title).map(\.motionID))
        #expect(lanes.count == 1)
        #expect(doc.marqueeKeys(within: 2500..<3500, layerID: title, motionIDs: lanes).count == 1)
        #expect(doc.marqueeKeys(within: 3000..<6000, layerID: title, motionIDs: lanes).count == 2)
        #expect(doc.marqueeKeys(within: 0..<12_000, layerID: title, motionIDs: lanes).count == 2)
        #expect(doc.marqueeKeys(within: 4000..<5000, layerID: title, motionIDs: lanes).isEmpty)
        #expect(doc.marqueeKeys(within: 0..<12_000, layerID: title, motionIDs: []).isEmpty)
    }

    // MARK: Counting

    @Test("Extras count their zooms and keys, and are empty with neither")
    func counts() throws {
        let (doc, clip, early, late, title) = try Self.edit()
        let lanes = Set(doc.keyLanes(layerID: title).map(\.motionID))
        let keys = doc.marqueeKeys(within: 0..<12_000, layerID: title, motionIDs: lanes)
        var extras = TimelineBoxExtras()
        #expect(extras.isEmpty)
        extras.zooms[clip] = [early, late]
        extras.keys[title] = keys
        #expect(!extras.isEmpty)
        #expect(extras.zoomCount == 2)
        #expect(extras.keyCount == 2)
        // A zoom or key on a clip that is itself picked rides with it.
        let besides = extras.besides([clip])
        #expect(besides.zoomCount == 0)
        #expect(besides.keyCount == 2)
    }

    // MARK: Moving

    @Test("Moving the extras moves each zoom and key by the same time")
    func shiftMovesZoomsAndKeys() throws {
        var (doc, clip, early, late, title) = try Self.edit()
        let before = try #require(Self.span(doc, clip, early))
        let laterBefore = try #require(Self.span(doc, clip, late))
        let lanes = Set(doc.keyLanes(layerID: title).map(\.motionID))
        var extras = TimelineBoxExtras()
        extras.zooms[clip] = [early, late]
        extras.keys[title] = doc.marqueeKeys(within: 0..<12_000, layerID: title, motionIDs: lanes)
        let landed = doc.shiftBoxExtras(extras, byMS: 500)
        #expect(landed.zoomCount == 2)
        #expect(landed.keyCount == 2)
        #expect(Self.span(doc, clip, early)?.start == before.start + 500)
        #expect(Self.span(doc, clip, early)?.end == before.end + 500)
        #expect(Self.span(doc, clip, late)?.start == laterBefore.start + 500)
        #expect(Self.keyTimes(doc, title) == [3500, 6500])
        // And back again, earliest first so nothing stops against its neighbour.
        doc.shiftBoxExtras(landed, byMS: -500)
        #expect(Self.span(doc, clip, early)?.start == before.start)
        #expect(Self.keyTimes(doc, title) == [3000, 6000])
    }

    @Test("Zooms side by side all move when they move toward each other's room")
    func neighboursMoveTogether() throws {
        var doc = PhotonzDocument.recording(Self.movie(), name: "Talk")
        let clip = doc.layers[0].id
        let madeA = doc.addZoom(toClip: clip, atTimeMS: 2000, around: nil)
        let a = try #require(madeA).id
        let aSpan = try #require(Self.span(doc, clip, a))
        // The second starts right where the first ends.
        let madeB = doc.addZoom(toClip: clip, atTimeMS: aSpan.end, around: nil)
        let b = try #require(madeB).id
        let bSpan = try #require(Self.span(doc, clip, b))
        var extras = TimelineBoxExtras()
        extras.zooms[clip] = [a, b]
        doc.shiftBoxExtras(extras, byMS: 300)
        #expect(Self.span(doc, clip, a)?.start == aSpan.start + 300)
        #expect(Self.span(doc, clip, b)?.start == bSpan.start + 300)
        doc.shiftBoxExtras(extras, byMS: -300)
        #expect(Self.span(doc, clip, a)?.start == aSpan.start)
        #expect(Self.span(doc, clip, b)?.start == bSpan.start)
    }

    @Test("A group stops where any zoom or key in it runs out of room")
    func roomIsTheTightest() throws {
        let (doc, clip, early, late, title) = try Self.edit()
        let first = try #require(Self.span(doc, clip, early))
        let second = try #require(Self.span(doc, clip, late))
        // Nothing to hold back: no limit either way.
        #expect(doc.boxExtrasRoom(TimelineBoxExtras()) == Int.min...Int.max)
        // The later zoom alone: back to where the earlier one ends, on to the
        // clip's end.
        var extras = TimelineBoxExtras()
        extras.zooms[clip] = [late]
        #expect(doc.boxExtrasRoom(extras) == (first.end - second.start)...(12_000 - second.end))
        // Both together: the earlier one meets the clip's start, the later the end.
        extras.zooms[clip] = [early, late]
        #expect(doc.boxExtrasRoom(extras) == (0 - first.start)...(12_000 - second.end))
        // Keys keep inside their layer: the title runs 2s to 8s, keys at 3s and 6s.
        let lanes = Set(doc.keyLanes(layerID: title).map(\.motionID))
        let keys = TimelineBoxExtras(keys: [title: doc.marqueeKeys(within: 0..<12_000, layerID: title,
                                                                   motionIDs: lanes)])
        #expect(doc.boxExtrasRoom(keys) == -1000...2000)
    }

    // MARK: Deleting

    @Test("Removing the extras takes every zoom and key it holds")
    func removeTakesThem() throws {
        var (doc, clip, early, late, title) = try Self.edit()
        let lanes = Set(doc.keyLanes(layerID: title).map(\.motionID))
        var extras = TimelineBoxExtras()
        extras.zooms[clip] = [early]
        extras.keys[title] = doc.marqueeKeys(within: 2500..<3500, layerID: title, motionIDs: lanes)
        let removed = doc.removeBoxExtras(extras)
        #expect(removed)
        #expect(doc.layer(id: clip)?.zooms?.map(\.id) == [late])
        #expect(Self.keyTimes(doc, title).count == 1)
        let nothing = doc.removeBoxExtras(TimelineBoxExtras())
        #expect(!nothing)
    }

    @Test("Ripple deleting a box's pick takes its clips, closes their gap and takes the zooms and keys beside them")
    func rippleDeleteTakesTheWholePick() throws {
        var (doc, clip, early, late, title) = try Self.edit()
        let lanes = Set(doc.keyLanes(layerID: title).map(\.motionID))
        var extras = TimelineBoxExtras()
        // The recording's own zoom rides with it; the title's keys are beside it.
        extras.zooms[clip] = [early]
        extras.keys[title] = doc.marqueeKeys(within: 0..<12_000, layerID: title, motionIDs: lanes)
        let changed = doc.rippleDeleteBoxPick([TimelinePick(layerID: clip, piece: nil)], extras: extras)
        #expect(changed)
        #expect(doc.layer(id: clip) == nil)
        #expect(doc.layer(id: title) != nil)
        #expect(Self.keyTimes(doc, title).isEmpty)
        _ = late
    }

    @Test("Ripple deleting a title picked with a zoom on a recording left in place takes the zoom too")
    func rippleDeleteTakesZoomsOnClipsLeftBehind() throws {
        var (doc, clip, early, late, title) = try Self.edit()
        var extras = TimelineBoxExtras()
        extras.zooms[clip] = [early]
        let changed = doc.rippleDeleteBoxPick([TimelinePick(layerID: title, piece: nil)], extras: extras)
        #expect(changed)
        #expect(doc.layer(id: title) == nil)
        #expect(doc.layer(id: clip)?.zooms?.map(\.id) == [late])
        // Nothing picked at all changes nothing.
        let nothing = doc.rippleDeleteBoxPick([], extras: TimelineBoxExtras())
        #expect(!nothing)
    }
}

/// **Option drag on a box's pick copies all of it**
/// (task `a-box-pick-on-the-timeline-is-copied-and-ripple`).
///
/// Option drag on a picked clip leaves a copy of every picked clip behind
/// the hand; the zooms and keys a box picked beside them on clips that stay
/// put are copied by the same time, onto the clips they are on. Zooms on one
/// clip never overlap, so the copies land only where every one of them fits,
/// and the hand stops at the nearest such spot, as a move stops where a zoom
/// runs out of room.
@Suite("Option drag copies a box's zooms and keys")
struct TimelineBoxCopyTests {

    /// A twenty second recording with a zoom from 2s to 5s, and a title from
    /// 2s to 8s with scale keyed at 3s and 6s.
    static func edit() throws -> (doc: PhotonzDocument, clip: UUID, zoom: UUID, title: UUID) {
        var doc = PhotonzDocument.recording(MovieRef(pixelSize: CGSize(width: 1920, height: 1080),
                                                     durationMS: 20_000), name: "Talk")
        let clip = doc.layers[0].id
        let made = doc.addZoom(toClip: clip, atTimeMS: 2000, around: nil)
        let zoom = try #require(made).id
        var title = Layer(name: "Title", content: .text(TextContent(string: "Hi", fontSize: 48)),
                          frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        title.time = LayerTime(inMS: 2000, outMS: 8000)
        doc.layers.append(title)
        doc.startKeying(layerID: title.id, .motion(.scale), atDocumentTimeMS: 3000)
        doc.setKeyedValue(.number(200), layerID: title.id, .motion(.scale), atDocumentTimeMS: 6000)
        doc.materializeTracks()
        return (doc, clip, zoom, title.id)
    }

    static func zoomSpans(_ doc: PhotonzDocument, _ clip: UUID) -> [Int] {
        guard let layer = doc.layer(id: clip) else { return [] }
        return (layer.zooms ?? []).compactMap { layer.timelineSpanMS(of: $0.id) }.flatMap { [$0.start, $0.end] }
    }

    static func keys(_ doc: PhotonzDocument, _ title: UUID) -> TimelineBoxExtras {
        let lanes = Set(doc.keyLanes(layerID: title).map(\.motionID))
        return TimelineBoxExtras(keys: [title: doc.marqueeKeys(within: 0..<20_000, layerID: title,
                                                               motionIDs: lanes)])
    }

    @Test("A zoom's copy lands on its clip by the same time, and the zoom stays where it was")
    func copiesAZoom() throws {
        var (doc, clip, zoom, _) = try Self.edit()
        let extras = TimelineBoxExtras(zooms: [clip: [zoom]])
        let copied = doc.copyBoxExtras(extras, byMS: 6000)
        let made = try #require(copied)
        #expect(made.zoomCount == 1)
        #expect(made.zooms[clip]?.contains(zoom) == false)
        #expect(Self.zoomSpans(doc, clip) == [2000, 5000, 8000, 11_000])
        // The copy is the zoom: same scale and spot.
        let zooms = try #require(doc.layer(id: clip)?.zooms)
        #expect(zooms[0].scale == zooms[1].scale)
        #expect(zooms[0].center == zooms[1].center)
    }

    @Test("Keys' copies land by the same time, and the keys stay")
    func copiesKeys() throws {
        var (doc, _, _, title) = try Self.edit()
        let keys = Self.keys(doc, title)
        let copied = doc.copyBoxExtras(keys, byMS: 1000)
        let made = try #require(copied)
        #expect(made.keyCount == 2)
        #expect(TimelineBoxPickTests.keyTimes(doc, title) == [3000, 4000, 6000, 7000])
    }

    @Test("A copy that would overlap a zoom or leave its clip is refused, and nothing changes")
    func refusesWhatDoesNotFit() throws {
        var (doc, clip, zoom, title) = try Self.edit()
        let before = doc
        // Over the zoom itself.
        let over = doc.copyBoxExtras(TimelineBoxExtras(zooms: [clip: [zoom]]), byMS: 1000)
        #expect(over == nil)
        // Past the clip's start.
        let early = doc.copyBoxExtras(TimelineBoxExtras(zooms: [clip: [zoom]]), byMS: -3000)
        #expect(early == nil)
        // A zoom and keys together, where the keys would leave the title.
        var both = Self.keys(doc, title)
        both.zooms[clip] = [zoom]
        let apart = doc.copyBoxExtras(both, byMS: 6000)
        #expect(apart == nil)
        #expect(doc == before)
    }

    @Test("The copies can land only where every one of them fits")
    func whereCopiesFit() throws {
        let (doc, clip, zoom, title) = try Self.edit()
        // Nothing to copy: anywhere.
        #expect(doc.boxExtrasCopyRoom(TimelineBoxExtras()) == [Int.min...Int.max])
        #expect(doc.boxExtrasCopyShift(TimelineBoxExtras(), nearest: 1234) == 1234)
        // The zoom runs 2s to 5s on a twenty second clip: its copy fits from
        // touching its end, 3s on, to the clip's end, 15s on.
        let zoomOnly = TimelineBoxExtras(zooms: [clip: [zoom]])
        #expect(doc.boxExtrasCopyRoom(zoomOnly) == [3000...15_000])
        #expect(doc.boxExtrasCopyShift(zoomOnly, nearest: 1000) == 3000)
        #expect(doc.boxExtrasCopyShift(zoomOnly, nearest: -2000) == 3000)
        #expect(doc.boxExtrasCopyShift(zoomOnly, nearest: 9000) == 9000)
        #expect(doc.boxExtrasCopyShift(zoomOnly, nearest: 30_000) == 15_000)
        // Keys at 3s and 6s inside a title from 2s to 8s.
        #expect(doc.boxExtrasCopyRoom(Self.keys(doc, title)) == [-1000...2000])
        // Both: nowhere fits them all.
        var both = Self.keys(doc, title)
        both.zooms[clip] = [zoom]
        #expect(doc.boxExtrasCopyRoom(both).isEmpty)
        #expect(doc.boxExtrasCopyShift(both, nearest: 1000) == nil)
    }

    @Test("A second zoom on the clip splits where the copy fits in two")
    func copiesFitBetweenZooms() throws {
        var (doc, clip, zoom, _) = try Self.edit()
        let made = doc.addZoom(toClip: clip, atTimeMS: 10_000, around: nil)
        #expect(made != nil)
        let room = doc.boxExtrasCopyRoom(TimelineBoxExtras(zooms: [clip: [zoom]]))
        // After the zoom up to the second (5s to 10s, so 3s to 5s on), and
        // after the second to the clip's end (13s to 20s, so 11s to 15s on).
        #expect(room == [3000...5000, 11_000...15_000])
        #expect(doc.boxExtrasCopyShift(TimelineBoxExtras(zooms: [clip: [zoom]]), nearest: 7000) == 5000)
        #expect(doc.boxExtrasCopyShift(TimelineBoxExtras(zooms: [clip: [zoom]]), nearest: 9000) == 11_000)
    }
}

/// What the panel says about a pick of several things on the timeline: how
/// many, and of what kinds, in the words the panel's kind chip uses.
@Suite("What the panel says about several things picked")
struct TimelinePickSummaryTests {

    @Test("Several kinds: a count and each kind counted, clips first")
    func severalKinds() throws {
        let summary = try #require(TimelinePickSummary(kinds: ["Clip", "Title", "Clip", "Audio"],
                                                       pieces: 0, zooms: 2, keys: 0))
        #expect(summary.title == "6 picked")
        #expect(summary.detail == "2 clips, 1 title, 1 sound, 2 zooms")
        #expect(summary.count == 6)
    }

    @Test("Pieces and keys count too, and one of a kind is singular")
    func piecesAndKeys() throws {
        let summary = try #require(TimelinePickSummary(kinds: [], pieces: 2, zooms: 1, keys: 1))
        #expect(summary.title == "4 picked")
        #expect(summary.detail == "2 pieces, 1 zoom, 1 key")
    }

    @Test("One thing picked says nothing: the panel already describes it")
    func oneSaysNothing() {
        #expect(TimelinePickSummary(kinds: ["Clip"], pieces: 0, zooms: 0, keys: 0) == nil)
        #expect(TimelinePickSummary(kinds: [], pieces: 0, zooms: 0, keys: 0) == nil)
    }

    @Test("Kinds the timeline holds are all named")
    func everyKind() throws {
        let summary = try #require(TimelinePickSummary(
            kinds: ["Captions", "Caption", "Caption", "Instance", "Graphic"], pieces: 0, zooms: 0, keys: 0))
        #expect(summary.detail == "1 graphic, 1 instance, 1 captions track, 2 captions")
    }
}
