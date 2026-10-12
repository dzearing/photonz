import CoreGraphics
import Foundation
import Testing
@testable import PhotonzCore

/// A click or a right click on something on the timeline also puts the
/// playhead where it landed: the moment under a place on a lane, and a cut
/// through every picked clip at once from a right click inside the pick.
@Suite("Pointing at the timeline")
struct TimelinePointingTests {

    // MARK: - The moment under a place on a lane

    @Test("A place along a lane is the moment the ruler puts there")
    func placeIsMoment() {
        let ruler = MotionStripRuler(documentMS: 10000)
        #expect(TimelinePointing.ms(atLaneX: 250, laneWidth: 1000, ruler: ruler) == 2500)
        #expect(TimelinePointing.ms(atLaneX: 0, laneWidth: 1000, ruler: ruler) == 0)
        #expect(TimelinePointing.ms(atLaneX: 1000, laneWidth: 1000, ruler: ruler) == 10000)
    }

    @Test("A timeline opened out measures from the left edge of what is on screen")
    func openedOut() {
        let ruler = MotionStripRuler(documentMS: 10000, zoom: TimelineZoom(scale: 5, startMS: 4000))
        #expect(TimelinePointing.ms(atLaneX: 500, laneWidth: 1000, ruler: ruler) == 5000)
    }

    @Test("Off either end of the lane, or on a lane with no width, is no moment at all")
    func offTheLane() {
        let ruler = MotionStripRuler(documentMS: 10000)
        #expect(TimelinePointing.ms(atLaneX: -1, laneWidth: 1000, ruler: ruler) == nil)
        #expect(TimelinePointing.ms(atLaneX: 1001, laneWidth: 1000, ruler: ruler) == nil)
        #expect(TimelinePointing.ms(atLaneX: 10, laneWidth: 0, ruler: ruler) == nil)
    }

    // MARK: - A cut through the whole pick

    @Test("Split at Playhead on several picked clips cuts every one the moment runs through, as one edit")
    func splitsEveryClip() throws {
        var (doc, take, _, music) = ClipLandingTests.edit()
        let cut = doc.splitClips([take, music], atMS: 3000)
        #expect(cut)
        #expect(doc.layer(id: take)?.clipPieces?.count == 2)
        #expect(doc.layer(id: music)?.clipPieces?.count == 2)
    }

    @Test("A picked clip the moment misses is left whole, and the rest are still cut")
    func missesOne() throws {
        var (doc, take, _, music) = ClipLandingTests.edit()
        // The take is eight seconds long; the music runs to fourteen.
        let cut = doc.splitClips([take, music], atMS: 10000)
        #expect(cut)
        #expect(doc.layer(id: take)?.clipPieces?.count == 1)
        #expect(doc.layer(id: music)?.clipPieces?.count == 2)
    }

    @Test("A cut that lands in none of them changes nothing and says so")
    func landsInNone() {
        var (doc, take, _, _) = ClipLandingTests.edit()
        let before = doc
        let cut = doc.splitClips([take], atMS: 9000)
        #expect(!cut)
        #expect(doc == before)
    }
}
