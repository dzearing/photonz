import CoreGraphics
import Testing
@testable import PhotonzCore

/// What the three choices on the Export sheet MEAN once a recording is a
/// video file rather than an animated picture, and why the weight under them
/// can be believed.
@Suite("Video export recipe")
struct VideoExportRecipeTests {

    private let hd = CGSize(width: 1920, height: 1080)
    private let retina = CGSize(width: 2880, height: 1800)

    // MARK: - What each choice means for an MP4

    @Test("High keeps the recording as it is: every pixel, every frame")
    func highKeepsEverything() {
        let recipe = VideoExportQuality.high.recipe(format: .mp4, sourceSize: retina,
                                                    sourceFPS: 60)
        #expect(recipe.size == retina)
        #expect(recipe.fps == 60)
    }

    @Test("Standard fits the long side inside 1440 and halves a 60 fps capture")
    func standardFitsForSending() {
        let recipe = VideoExportQuality.standard.recipe(format: .mp4, sourceSize: retina,
                                                        sourceFPS: 60)
        #expect(recipe.size == CGSize(width: 1440, height: 900))
        #expect(recipe.fps == 30)
    }

    @Test("Small fits the long side inside 960")
    func smallFitsAChatWindow() {
        let recipe = VideoExportQuality.small.recipe(format: .mp4, sourceSize: retina,
                                                     sourceFPS: 60)
        #expect(recipe.size == CGSize(width: 960, height: 600))
        #expect(recipe.fps == 30)
    }

    @Test("A recording already smaller than the cap is never blown up")
    func neverUpscales() {
        let little = CGSize(width: 640, height: 400)
        for quality in VideoExportQuality.allCases {
            let recipe = quality.recipe(format: .mp4, sourceSize: little, sourceFPS: 24)
            #expect(recipe.size == little)
            #expect(recipe.fps == 24)
        }
    }

    @Test("Every MP4 side is even, because H.264 cannot describe an odd one")
    func sidesAreEven() {
        let odd = CGSize(width: 1281, height: 801)
        for quality in VideoExportQuality.allCases {
            let recipe = quality.recipe(format: .mp4, sourceSize: odd, sourceFPS: 30)
            #expect(Int(recipe.size.width) % 2 == 0)
            #expect(Int(recipe.size.height) % 2 == 0)
        }
    }

    @Test("A recording made at an odd frame rate keeps it rather than being rounded up")
    func doesNotInventFrames() {
        let recipe = VideoExportQuality.high.recipe(format: .mp4, sourceSize: hd, sourceFPS: 23.976)
        #expect(recipe.fps == 23.976)
    }

    @Test("A frame rate that could not be read falls back to something sane")
    func brokenFrameRate() {
        let recipe = VideoExportQuality.high.recipe(format: .mp4, sourceSize: hd, sourceFPS: 0)
        #expect(recipe.fps == 30)
    }

    // MARK: - What each choice means for an animated picture

    @Test("GIF and HEIC keep the meaning they already had")
    func animatedIsUnchanged() {
        for format in [RecordingFormat.gif, .heic] {
            let recipe = VideoExportQuality.standard.recipe(format: format, sourceSize: hd,
                                                            sourceFPS: 60)
            #expect(recipe.fps == 15)
            #expect(recipe.size == Geometry.downscaledToFit(hd, maxDimension: 800))
            // Nothing is asked of a bitrate: an animated picture is frames, not
            // a stream with a budget.
            #expect(recipe.videoBitsPerSecond == 0)
        }
    }

    // MARK: - The budget, which is what makes the weight predictable

    @Test("The bitrate falls with the choice, so Small really is smaller")
    func bitrateFallsWithTheChoice() {
        let high = VideoExportQuality.high.recipe(format: .mp4, sourceSize: hd, sourceFPS: 30)
        let standard = VideoExportQuality.standard.recipe(format: .mp4, sourceSize: hd, sourceFPS: 30)
        let small = VideoExportQuality.small.recipe(format: .mp4, sourceSize: hd, sourceFPS: 30)
        #expect(high.videoBitsPerSecond > standard.videoBitsPerSecond)
        #expect(standard.videoBitsPerSecond > small.videoBitsPerSecond)
    }

    @Test("The budget is worked out per pixel and per frame, not picked out of the air")
    func bitrateFollowsThePicture() {
        let big = VideoExportQuality.high.recipe(format: .mp4, sourceSize: retina, sourceFPS: 30)
        let smallPicture = VideoExportQuality.high.recipe(format: .mp4,
                                                          sourceSize: CGSize(width: 720, height: 450),
                                                          sourceFPS: 30)
        #expect(big.videoBitsPerSecond > smallPicture.videoBitsPerSecond * 3)
    }

    @Test("Even a tiny picture gets enough bits to be watchable")
    func bitrateHasAFloor() {
        let recipe = VideoExportQuality.small.recipe(format: .mp4,
                                                     sourceSize: CGSize(width: 160, height: 100),
                                                     sourceFPS: 10)
        #expect(recipe.videoBitsPerSecond >= 400_000)
    }

    @Test("What a second of it costs is the budget, in bytes")
    func expectedBytes() {
        var recipe = VideoExportRecipe(size: CGSize(width: 1280, height: 800), fps: 30,
                                       videoBitsPerSecond: 8_000_000,
                                       audioBitsPerSecond: 128_000)
        // Ten seconds of 8 Mbps is 10 MB of picture, and the sound is extra.
        #expect(recipe.expectedBytes(seconds: 10, hasAudio: false) == 10_000_000)
        #expect(recipe.expectedBytes(seconds: 10, hasAudio: true) == 10_160_000)
        recipe.videoBitsPerSecond = 0
        #expect(recipe.expectedBytes(seconds: 10, hasAudio: false) == 0)
    }

    @Test("A recording of no length costs nothing")
    func noLength() {
        let recipe = VideoExportQuality.standard.recipe(format: .mp4, sourceSize: hd, sourceFPS: 30)
        #expect(recipe.expectedBytes(seconds: 0, hasAudio: true) == 0)
        #expect(recipe.expectedBytes(seconds: -4, hasAudio: true) == 0)
    }

    // MARK: - Who each one is for

    @Test("Each choice says who it is for, in words about where the file is going")
    func purposeSaysWhoFor() {
        let purposes = VideoExportQuality.allCases.map { $0.purpose(for: .mp4) }
        #expect(Set(purposes).count == 3)
        for purpose in purposes {
            #expect(!purpose.isEmpty)
            #expect(!purpose.contains("—"))
            #expect(purpose.first == purpose.first?.uppercased().first)
        }
        #expect(VideoExportQuality.high.purpose(for: .mp4)
            != VideoExportQuality.high.purpose(for: .gif))
    }
}
