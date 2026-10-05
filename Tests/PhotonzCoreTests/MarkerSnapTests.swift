import Foundation
import PhotonzCore
import Testing

/// Markers are something to cut and arrange to (`TimelineMarks.swift`).
///
/// In Premiere and Final Cut a clip dragged near a marker catches on it, the
/// playhead dragged along the ruler catches on it, and a marker put down in
/// the wrong place is dragged to the right one rather than removed and added
/// again.
@Suite("Markers catch, and move")
struct MarkerSnapTests {

    static func twelveSeconds() -> (doc: PhotonzDocument, clip: UUID) {
        RulerRangeTests.twelveSeconds()
    }

    // MARK: A clip's edge catches on a marker

    @Test("Every marker is an edge a clip's bar can catch on, named by its moment")
    func markersAreClipEdges() {
        var (doc, clip) = Self.twelveSeconds()
        doc.addMarker(atMS: 12_000)
        doc.addMarker(atMS: 3_400)
        let edges = doc.clipBarEdges(excluding: clip, playheadMS: nil)
        #expect(edges.contains { $0.ms == 3_400 && $0.name == "a marker at 0:03" })
        #expect(edges.contains { $0.ms == 12_000 && $0.name == "a marker at 0:12" })
    }

    @Test("The line under the drag names the marker it caught on")
    func caughtOnAMarkerSays() {
        let edge = MotionStripEdge(ms: 12_000, name: ClipBarCopy.marker(atMS: 12_000), isStart: true)
        #expect(ClipBarCopy.caught(on: edge) == "caught on a marker at 0:12")
    }

    @Test("A clip slid near a marker lands on it, within the reach the playhead has")
    func aClipCatchesOnAMarker() throws {
        var (doc, clip) = Self.twelveSeconds()
        doc.addMarker(atMS: 2_000)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        let drag = ClipBarDrag(grab: .body, pieces: pieces, clipStartMS: 0,
                               others: doc.clipBarEdges(excluding: clip, playheadMS: nil),
                               snapWithinMS: 80)
        let landing = drag.landing(byMS: 1_950)
        #expect(landing.movedMS == 2_000)
        #expect(landing.snappedTo?.name == "a marker at 0:02")
    }

    @Test("A clip's trimmed edge catches on a marker too")
    func aTrimCatchesOnAMarker() throws {
        var (doc, clip) = Self.twelveSeconds()
        doc.addMarker(atMS: 9_000)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        // The bar's right end, pulled in from 12s to just past 9s.
        let drag = ClipBarDrag(grab: .seam(after: pieces.count - 1), pieces: pieces, clipStartMS: 0,
                               others: doc.clipBarEdges(excluding: clip, playheadMS: nil),
                               snapWithinMS: 80)
        let landing = drag.landing(byMS: -2_960)
        #expect(landing.snappedTo?.name == "a marker at 0:09")
        #expect(landing.pieces.totalLengthMS == 9_000)
    }

    @Test("With snapping off nothing catches on a marker")
    func snappingOffCatchesNothing() throws {
        var (doc, clip) = Self.twelveSeconds()
        doc.addMarker(atMS: 2_000)
        let pieces = try #require(doc.layer(id: clip)?.clipPieces)
        let drag = ClipBarDrag(grab: .body, pieces: pieces, clipStartMS: 0,
                               others: doc.clipBarEdges(excluding: clip, playheadMS: nil),
                               snapWithinMS: 0)
        let landing = drag.landing(byMS: 1_950)
        #expect(landing.movedMS == 1_950)
        #expect(landing.snappedTo == nil)
    }

    // MARK: The playhead catches on a marker

    @Test("The playhead dragged along the ruler catches on keys and markers alike")
    func playheadSnapMoments() {
        var (doc, _) = Self.twelveSeconds()
        doc.addMarker(atMS: 5_000)
        let moments = doc.playheadSnapMoments(keysOf: nil)
        #expect(moments.contains(5_000))
        #expect(KeySnap.snapped(5_060, to: moments, withinMS: 80) == 5_000)
        #expect(KeySnap.snapped(5_060, to: moments, withinMS: 0) == 5_060)
    }

    // MARK: A press on a marker takes hold of it

    @Test("A press on a marker takes hold of that marker")
    func pressOnAMarker() {
        let marker = TimelineMarker(atMS: 6_000)
        let grip = RulerRange.grip(atMS: 6_040, playheadMS: 1_000, markInMS: nil, markOutMS: nil,
                                   markers: [TimelineMarker(atMS: 2_000), marker], reachMS: 80)
        #expect(grip == .marker(marker.id))
    }

    @Test("The playhead standing on a marker is what a press there takes, as in Premiere")
    func playheadWinsOverAMarker() {
        let grip = RulerRange.grip(atMS: 6_000, playheadMS: 6_000, markInMS: nil, markOutMS: nil,
                                   markers: [TimelineMarker(atMS: 6_000)], reachMS: 80)
        #expect(grip == .playhead)
    }

    @Test("An end of the marked stretch is taken before a marker on it")
    func bandEndWinsOverAMarker() {
        let grip = RulerRange.grip(atMS: 6_000, playheadMS: 1_000, markInMS: 6_000, markOutMS: 9_000,
                                   markers: [TimelineMarker(atMS: 6_000)], reachMS: 80)
        #expect(grip == .inEdge)
    }

    @Test("Away from every marker a press still draws a range")
    func pressAwayFromMarkers() {
        let grip = RulerRange.grip(atMS: 4_000, playheadMS: 1_000, markInMS: nil, markOutMS: nil,
                                   markers: [TimelineMarker(atMS: 6_000)], reachMS: 80)
        #expect(grip == .newRange)
    }

    // MARK: Moving one

    @Test("A marker dragged catches on cuts, clip ends and the playhead, never on another marker")
    func markerSnapMoments() {
        var (doc, clip) = Self.twelveSeconds()
        _ = doc.splitClip(clip, atMS: 4_000)
        doc.addMarker(atMS: 9_000)
        let moments = doc.markerSnapMoments(playheadMS: 7_500)
        #expect(moments.contains(0))
        #expect(moments.contains(4_000))
        #expect(moments.contains(7_500))
        #expect(moments.contains(12_000))
        #expect(!moments.contains(9_000))
    }

    @Test("Where a dragged marker lands: snapped within reach, and never off the ruler")
    func markerLanding() {
        #expect(RulerRange.markerMoved(toMS: 3_950, lengthMS: 12_000, snapTo: [4_000], reachMS: 80) == 4_000)
        #expect(RulerRange.markerMoved(toMS: 3_950, lengthMS: 12_000, snapTo: [4_000], reachMS: 0) == 3_950)
        #expect(RulerRange.markerMoved(toMS: -300, lengthMS: 12_000) == 0)
        #expect(RulerRange.markerMoved(toMS: 15_000, lengthMS: 12_000) == 12_000)
    }

    @Test("Moving a marker changes its moment and keeps the markers in order")
    func moveMarker() throws {
        var (doc, _) = Self.twelveSeconds()
        let firstAdded = doc.addMarker(atMS: 2_000)
        let first = try #require(firstAdded)
        doc.addMarker(atMS: 6_000)
        let moved1 = doc.moveMarker(first, toMS: 8_000)
        #expect(moved1)
        #expect(doc.markers.map(\.atMS) == [6_000, 8_000])
        #expect(doc.markers.last?.id == first)
    }

    @Test("A marker moved to where it already is, or off the ruler's end, changes nothing it need not")
    func moveMarkerNowhere() throws {
        var (doc, _) = Self.twelveSeconds()
        let idAdded = doc.addMarker(atMS: 2_000)
        let id = try #require(idAdded)
        let moved2 = doc.moveMarker(id, toMS: 2_000)
        #expect(!moved2)
        let moved3 = doc.moveMarker(id, toMS: 40_000)
        #expect(moved3)
        #expect(doc.markers.map(\.atMS) == [12_000])
        let movedNothing = doc.moveMarker(UUID(), toMS: 1_000)
        #expect(!movedNothing)
    }

    @Test("A marker dropped on another becomes one marker, as two on one frame always are")
    func moveMarkerOntoAnother() throws {
        var (doc, _) = Self.twelveSeconds()
        let movingAdded = doc.addMarker(atMS: 2_000)
        let moving = try #require(movingAdded)
        let stayingAdded = doc.addMarker(atMS: 6_000)
        let staying = try #require(stayingAdded)
        let moved4 = doc.moveMarker(moving, toMS: 6_000)
        #expect(moved4)
        #expect(doc.markers.map(\.id) == [staying])
    }

    @Test("Moving a marker is one step to undo")
    func moveMarkerUndoes() throws {
        var (doc, _) = Self.twelveSeconds()
        let idAdded = doc.addMarker(atMS: 2_000)
        let id = try #require(idAdded)
        var history = History(document: doc)
        history.perform { $0.moveMarker(id, toMS: 5_000) }
        #expect(history.current.markers.map(\.atMS) == [5_000])
        history.undo()
        #expect(history.current.markers.map(\.atMS) == [2_000])
    }

    // MARK: The walk's words for it

    @Test("A walk can hold a dragged clip to photograph its catch, and claim where a marker stands")
    func walkSteps() throws {
        let script = try PlaytestScript.decode(Data("""
        { "steps": [ { "do": "dragClip", "clip": "Talk", "byMS": 1950, "hold": "caught" },
                     { "do": "expectTimeline", "markerAtMS": 5000, "withinMS": 10 } ] }
        """.utf8))
        #expect(script.steps[0] == .dragClip(clip: "Talk", byMS: 1950, modifiers: [], hold: "caught"))
        guard case .expectTimeline(let claim) = script.steps[1] else {
            Issue.record("expected an expectTimeline step")
            return
        }
        #expect(claim.markerAtMS == 5000)
        #expect(claim.withinMS == 10)
        #expect(claim.claimsSomething)
    }
}
