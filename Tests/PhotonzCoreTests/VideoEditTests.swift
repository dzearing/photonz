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

@Suite("Video crop")
struct VideoCropTests {
    let videoSize = CGSize(width: 1920, height: 1080)

    // MARK: - Defaults

    @Test func fullFrameDefaultCoversTheWholeVideo() {
        let crop = VideoCrop(fullFrame: videoSize)
        #expect(crop.rect == CGRect(origin: .zero, size: videoSize))
        #expect(crop.aspect == .free)
        #expect(!crop.isCropped(videoSize: videoSize))
        #expect(crop.outputSize == videoSize)
    }

    @Test func aspectFullFrameFitsCentered() {
        // 16:9 video, fit a 1:1 crop → 1080×1080 centered.
        let crop = VideoCrop(fullFrame: videoSize, aspect: .square)
        #expect(crop.aspect == .square)
        #expect(crop.rect == CGRect(x: (1920 - 1080) / 2, y: 0, width: 1080, height: 1080))
        #expect(crop.isCropped(videoSize: videoSize))
    }

    // MARK: - Clamp into natural bounds

    @Test func initClampsRectIntoVideoBounds() {
        let crop = VideoCrop(rect: CGRect(x: -100, y: -50, width: 5000, height: 5000),
                             videoSize: videoSize)
        #expect(crop.rect == CGRect(origin: .zero, size: videoSize))
    }

    @Test func nullOrEmptyRectFallsBackToFullFrame() {
        let crop = VideoCrop(rect: CGRect(x: 9000, y: 9000, width: 10, height: 10),
                             videoSize: videoSize)
        // Off-canvas → clampCrop yields a degenerate rect; not equal to full,
        // but stays inside bounds.
        #expect(videoSize.width >= crop.rect.maxX)
        #expect(videoSize.height >= crop.rect.maxY)
    }

    // MARK: - Aspect-locked resize (reusing Crop geometry verbatim)

    @Test func resizeIsRatioLockedAndClampedToVideo() {
        var crop = VideoCrop(rect: CGRect(x: 100, y: 100, width: 200, height: 200),
                             videoSize: videoSize, aspect: .square)
        crop.resize(dragging: .bottomRight, to: CGPoint(x: 5000, y: 5000), videoSize: videoSize)
        // availX = 1920-100 = 1820, availY = 1080-100 = 980 → square side 980.
        #expect(crop.rect == CGRect(x: 100, y: 100, width: 980, height: 980))
    }

    @Test func moveClampsInsideVideo() {
        var crop = VideoCrop(rect: CGRect(x: 100, y: 100, width: 200, height: 200),
                             videoSize: videoSize)
        crop.move(by: CGPoint(x: -500, y: -500), videoSize: videoSize)
        #expect(crop.rect == CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    @Test func setAspectRefitsExistingRect() {
        var crop = VideoCrop(rect: CGRect(x: 0, y: 0, width: 400, height: 400),
                             videoSize: videoSize)
        crop.setAspect(.sixteenNine, videoSize: videoSize)
        #expect(crop.aspect == .sixteenNine)
        // 400-wide 16:9 box fitted/centered in the 400×400 rect → height 225.
        #expect(abs(crop.rect.height - 225) < 0.001)
    }

    // MARK: - Output size

    @Test func outputSizeIsTheCropPixelSize() {
        let crop = VideoCrop(rect: CGRect(x: 10, y: 20, width: 640, height: 480),
                             videoSize: videoSize)
        #expect(crop.outputSize == CGSize(width: 640, height: 480))
    }

    // MARK: - Codable

    @Test func roundTripsThroughCodable() throws {
        let crop = VideoCrop(rect: CGRect(x: 10, y: 20, width: 640, height: 480),
                             videoSize: videoSize, aspect: .fourThree)
        let data = try JSONEncoder().encode(crop)
        let back = try JSONDecoder().decode(VideoCrop.self, from: data)
        #expect(back == crop)
    }
}
