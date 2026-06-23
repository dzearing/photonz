import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Video trim")
struct VideoTrimTests {

    // MARK: - Defaults & full-clip

    @Test func defaultIsTheFullClip() {
        let trim = VideoTrim(duration: 10)
        #expect(trim.inPoint == 0)
        #expect(trim.outPoint == 10)
        #expect(trim.effectiveDuration == 10)
        #expect(!trim.isTrimmed)
    }

    @Test func timeRangeIsStartAndLength() {
        var trim = VideoTrim(duration: 10)
        trim.setIn(2, duration: 10)
        trim.setOut(7, duration: 10)
        let range = trim.timeRange(duration: 10)
        #expect(range.start == 2)
        #expect(range.length == 5)
        #expect(trim.effectiveDuration == 5)
        #expect(trim.isTrimmed)
    }

    // MARK: - Clamp into [0, duration]

    @Test func clampsBelowZeroAndAboveDuration() {
        var trim = VideoTrim(duration: 10)
        trim.setIn(-5, duration: 10)
        #expect(trim.inPoint == 0)
        trim.setOut(50, duration: 10)
        #expect(trim.outPoint == 10)
    }

    @Test func initClampsToDuration() {
        let trim = VideoTrim(inPoint: -3, outPoint: 99, duration: 8)
        #expect(trim.inPoint == 0)
        #expect(trim.outPoint == 8)
    }

    // MARK: - Minimum duration

    @Test func setInRespectsMinDurationByPushingOut() {
        // Setting in within min of out pushes out forward, never inverting.
        var trim = VideoTrim(duration: 10)
        trim.setOut(5, duration: 10, minDuration: 0.5)
        trim.setIn(4.9, duration: 10, minDuration: 0.5)
        #expect(trim.outPoint >= trim.inPoint + 0.5 - 1e-9)
        #expect(abs(trim.inPoint - 4.9) < 1e-9)
        #expect(abs(trim.outPoint - 5.4) < 1e-9)
    }

    @Test func setInPushesOutToDurationCeilingThenClampsIn() {
        // If pushing out would exceed duration, out pins to duration and in is
        // pulled back so the min window still fits.
        var trim = VideoTrim(duration: 10)
        trim.setIn(9.9, duration: 10, minDuration: 0.5)
        #expect(abs(trim.outPoint - 10) < 1e-9)
        #expect(abs(trim.inPoint - 9.5) < 1e-9)
    }

    @Test func setOutRespectsMinDurationByPushingIn() {
        var trim = VideoTrim(duration: 10)
        trim.setIn(5, duration: 10, minDuration: 0.5)
        trim.setOut(5.1, duration: 10, minDuration: 0.5)
        #expect(abs(trim.outPoint - 5.1) < 1e-9)
        #expect(abs(trim.inPoint - 4.6) < 1e-9)
    }

    @Test func setOutPushesInToZeroFloorThenClampsOut() {
        var trim = VideoTrim(duration: 10)
        trim.setOut(0.1, duration: 10, minDuration: 0.5)
        #expect(abs(trim.inPoint - 0) < 1e-9)
        #expect(abs(trim.outPoint - 0.5) < 1e-9)
    }

    // MARK: - Never invert

    @Test func neverInvertsRegardlessOfOrder() {
        var trim = VideoTrim(duration: 10)
        trim.setIn(8, duration: 10, minDuration: 0.5)
        trim.setOut(2, duration: 10, minDuration: 0.5)
        #expect(trim.outPoint >= trim.inPoint)
        #expect(trim.outPoint - trim.inPoint >= 0.5 - 1e-9)
    }

    // MARK: - Codable

    @Test func roundTripsThroughCodable() throws {
        var trim = VideoTrim(duration: 12)
        trim.setIn(3, duration: 12)
        trim.setOut(9, duration: 12)
        let data = try JSONEncoder().encode(trim)
        let back = try JSONDecoder().decode(VideoTrim.self, from: data)
        #expect(back == trim)
    }
}
