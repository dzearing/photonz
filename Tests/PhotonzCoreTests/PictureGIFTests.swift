import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **A picture that moves can leave the app as a GIF that plays the same loop
/// the timeline plays** (task `an-animated-picture-exports-as-a-gif`).
///
/// The plan says which moments are photographed, how long each is held, and
/// whether the file goes round for ever or plays once and stops where it
/// landed, all read off the document the way the canvas plays it.
@Suite("A moving picture's GIF plays the loop the timeline plays")
struct PictureGIFTests {

    static func moving(_ repeats: MotionRepeat = .foreverThereAndBack,
                       durationMS: Int = 900, cycleMS: Int? = nil) -> PhotonzDocument {
        var layer = SVGMotionExportTests.layer([
            SVGMotionExportTests.turn(-12, 12, durationMS: durationMS, repeats: repeats)
        ])
        layer.name = "Ball"
        return SVGMotionExportTests.document([layer], cycleMS: cycleMS)
    }

    static func still() -> PhotonzDocument {
        SVGMotionExportTests.document([SVGMotionExportTests.layer([])])
    }

    @Test("A still picture is never offered a GIF")
    func aStillPictureHasNoGIF() {
        #expect(!PictureGIF.offers(Self.still()))
        #expect(PictureGIF.plan(for: Self.still()) == nil)
    }

    @Test("A picture with a motion on it is offered a GIF")
    func aMovingPictureHasAGIF() {
        #expect(PictureGIF.offers(Self.moving()))
    }

    @Test("A picture with keys on a repeating lap goes round for ever, one lap long")
    func aRepeatingKeyedLapLoops() throws {
        let document = SVGHandoffTests.keyedDocument(repeats: true)
        #expect(PictureGIF.offers(document))
        let plan = try #require(PictureGIF.plan(for: document))
        #expect(plan.loops)
        #expect(plan.durationMS == 2000)
        #expect(plan.timesMS.first == 0)
        #expect(plan.timesMS.allSatisfy { $0 < 2000 })
        // Exactly one lap: the next lap's first moment is the file's first
        // frame, so the seam is never photographed twice.
        #expect(abs(plan.delaysInHundredths.reduce(0, +) - 200) <= 1)
    }

    @Test("Keys with Repeat turned off play once and hold where they landed")
    func aLapPlayedOnceStops() throws {
        let document = SVGHandoffTests.keyedDocument(repeats: false)
        let plan = try #require(PictureGIF.plan(for: document))
        #expect(!plan.loops)
        // The last picture is the landed one, at the very end of the lap.
        #expect(plan.timesMS.last == 2000)
        #expect(plan.timesMS.count == plan.delaysInHundredths.count)
    }

    @Test("A motion that goes there and back for ever loops one lap")
    func thereAndBackLoopsOneLap() throws {
        let plan = try #require(PictureGIF.plan(for: Self.moving(.foreverThereAndBack)))
        #expect(plan.loops)
        #expect(plan.durationMS == 900)
    }

    @Test("Three times plays three laps and stops")
    func threeTimesPlaysThreeLaps() throws {
        let plan = try #require(PictureGIF.plan(for: Self.moving(.times(3))))
        #expect(!plan.loops)
        #expect(plan.durationMS == 2700)
        #expect(plan.timesMS.last == 2700)
    }

    @Test("A spinner on its own pace loops where both it and the lap come round")
    func ownPaceLoopsOnACommonMultiple() throws {
        // A 900 ms lap from the other motion, a 600 ms spin: both are back
        // where they began after 1800 ms and not before.
        var document = Self.moving(.foreverThereAndBack, durationMS: 900)
        document.layers[0].motions?.append(
            SVGMotionExportTests.turn(0, 360, durationMS: 600, repeats: .forever))
        let plan = try #require(PictureGIF.plan(for: document))
        #expect(plan.loops)
        #expect(plan.durationMS == 1800)
    }

    @Test("A loop that would run past the longest a GIF is made for is cut to one lap")
    func aRunawayCommonMultipleFallsBackToTheLap() throws {
        var document = Self.moving(.foreverThereAndBack, durationMS: 997, cycleMS: 997)
        document.layers[0].motions?.append(
            SVGMotionExportTests.turn(0, 360, durationMS: 991, repeats: .forever))
        let plan = try #require(PictureGIF.plan(for: document))
        #expect(plan.durationMS == 997)
    }

    @Test("Frames are photographed often enough to look smooth, and held for whole hundredths")
    func framesAreSmooth() throws {
        let plan = try #require(PictureGIF.plan(for: SVGHandoffTests.keyedDocument(repeats: true)))
        #expect(plan.timesMS.count >= 40)
        #expect(plan.delaysInHundredths.allSatisfy { $0 >= GIFFrameTiming.shortestHundredths })
        // Moments go forward and never repeat.
        #expect(zip(plan.timesMS, plan.timesMS.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("A video is not a picture and has its own export")
    func aVideoIsNotOffered() {
        var document = Self.moving()
        document.durationMS = 4000
        #expect(document.hasTime)
        #expect(!PictureGIF.offers(document))
    }
}
