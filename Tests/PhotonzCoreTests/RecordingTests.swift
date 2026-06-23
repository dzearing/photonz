import CoreGraphics
import Foundation
import PhotonzCore
import Testing

@Suite("Recording config & helpers")
struct RecordingTests {

    // MARK: - RecordingSource

    @Test func fullDisplaySourceCoversTheWholeDisplay() {
        let rect = RecordingSource.fullDisplay.sourceRect(displaySize: CGSize(width: 1920, height: 1080))
        #expect(rect == CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    @Test func regionSourceReturnsItsRect() {
        let region = CGRect(x: 10, y: 20, width: 300, height: 200)
        let rect = RecordingSource.region(region).sourceRect(displaySize: CGSize(width: 1920, height: 1080))
        #expect(rect == region)
    }

    // MARK: - AudioSources

    @Test func audioSourcesCombineIndependently() {
        #expect(AudioSources([]).capturesAnyAudio == false)
        let both: AudioSources = [.systemAudio, .microphone]
        #expect(both.capturesSystemAudio)
        #expect(both.capturesMicrophone)
        #expect(both.capturesAnyAudio)
        #expect(AudioSources.systemAudio.capturesMicrophone == false)
    }

    @Test func recordingConfigRoundTripsThroughCodable() throws {
        let config = RecordingConfig(source: .region(CGRect(x: 1, y: 2, width: 3, height: 4)),
                                     audio: [.systemAudio, .microphone],
                                     microphoneDeviceID: "mic-123",
                                     format: .gif)
        let data = try JSONEncoder().encode(config)
        let back = try JSONDecoder().decode(RecordingConfig.self, from: data)
        #expect(back == config)
    }

    // MARK: - RecordingClock

    @Test func elapsedStringFormatsMinutesAndSeconds() {
        #expect(RecordingClock.elapsedString(0) == "0:00")
        #expect(RecordingClock.elapsedString(7) == "0:07")
        #expect(RecordingClock.elapsedString(83) == "1:23")
        #expect(RecordingClock.elapsedString(-5) == "0:00")
    }

    @Test func elapsedStringAddsHoursPastAnHour() {
        #expect(RecordingClock.elapsedString(3600) == "1:00:00")
        #expect(RecordingClock.elapsedString(3723) == "1:02:03")
    }

    // MARK: - AnimatedExportPlanner

    @Test func planSamplesAtTargetFpsAcrossDuration() {
        let plan = AnimatedExportPlanner.plan(duration: 2, sourceSize: CGSize(width: 400, height: 300),
                                              targetFPS: 10, maxDimension: 800)
        #expect(plan.frameCount == 20)
        #expect(plan.frameDelay == 0.1)
        // No upscaling: 400×300 already fits in 800.
        #expect(plan.size == CGSize(width: 400, height: 300))
        #expect(plan.sampleTime(5) == 0.5)
    }

    @Test func planDownscalesLargeRecordingsPreservingAspect() {
        let plan = AnimatedExportPlanner.plan(duration: 1, sourceSize: CGSize(width: 1600, height: 1200),
                                              targetFPS: 15, maxDimension: 800)
        #expect(plan.size == CGSize(width: 800, height: 600))
    }

    @Test func planAlwaysEmitsAtLeastOneFrame() {
        let plan = AnimatedExportPlanner.plan(duration: 0, sourceSize: CGSize(width: 100, height: 100),
                                              targetFPS: 15, maxDimension: 800)
        #expect(plan.frameCount == 1)
    }

    @Test func untrimmedSampleTimeStartsAtZero() {
        let plan = AnimatedExportPlanner.plan(duration: 2, sourceSize: CGSize(width: 100, height: 100),
                                              targetFPS: 10, maxDimension: 800)
        #expect(plan.trimStart == 0)
        #expect(plan.sampleTime(0) == 0)
    }

    // MARK: - AnimatedExportPlanner with trim + crop (phase 13.5)

    @Test func trimmedPlanFrameCountFromTrimmedDuration() {
        // 10s clip trimmed to [2, 7] → 5s at 10fps = 50 frames.
        let trim = VideoTrim(inPoint: 2, outPoint: 7, duration: 10)
        let plan = AnimatedExportPlanner.plan(trim: trim,
                                              sourceSize: CGSize(width: 400, height: 300),
                                              targetFPS: 10, maxDimension: 800)
        #expect(plan.frameCount == 50)
        #expect(plan.frameDelay == 0.1)
    }

    @Test func trimmedPlanSampleTimeIsOffsetByTrimStart() {
        let trim = VideoTrim(inPoint: 2, outPoint: 7, duration: 10)
        let plan = AnimatedExportPlanner.plan(trim: trim,
                                              sourceSize: CGSize(width: 400, height: 300),
                                              targetFPS: 10, maxDimension: 800)
        #expect(plan.trimStart == 2)
        #expect(plan.sampleTime(0) == 2)
        #expect(abs(plan.sampleTime(5) - 2.5) < 1e-9)
    }

    @Test func trimmedPlanSampleTimeStaysWithinTheWindow() {
        let trim = VideoTrim(inPoint: 2, outPoint: 7, duration: 10)
        let plan = AnimatedExportPlanner.plan(trim: trim,
                                              sourceSize: CGSize(width: 400, height: 300),
                                              targetFPS: 10, maxDimension: 800)
        for i in 0..<plan.frameCount {
            let t = plan.sampleTime(i)
            #expect(t >= 2 - 1e-9 && t <= 7 + 1e-9)
        }
    }

    @Test func planSizeDerivesFromCropOutputSize() {
        // Crop down to 600×600 from a 1920×1080 source; max 800 keeps it as-is.
        let trim = VideoTrim(duration: 4)
        let crop = VideoCrop(rect: CGRect(x: 0, y: 0, width: 600, height: 600),
                             videoSize: CGSize(width: 1920, height: 1080))
        let plan = AnimatedExportPlanner.plan(trim: trim, crop: crop,
                                              sourceSize: CGSize(width: 1920, height: 1080),
                                              targetFPS: 15, maxDimension: 800)
        #expect(plan.size == CGSize(width: 600, height: 600))
    }

    @Test func planSizeDownscalesCropBeyondMax() {
        let trim = VideoTrim(duration: 4)
        let crop = VideoCrop(rect: CGRect(x: 0, y: 0, width: 1600, height: 1080),
                             videoSize: CGSize(width: 1920, height: 1080))
        let plan = AnimatedExportPlanner.plan(trim: trim, crop: crop,
                                              sourceSize: CGSize(width: 1920, height: 1080),
                                              targetFPS: 15, maxDimension: 800)
        // 1600×1080 fit into 800 → 800×540.
        #expect(plan.size == CGSize(width: 800, height: 540))
    }

    // MARK: - Quality presets

    @Test func qualityPresetMapsToFpsAndMaxDimension() {
        #expect(VideoExportQuality.high.targetFPS == 24)
        #expect(VideoExportQuality.high.maxDimension == 1280)
        #expect(VideoExportQuality.standard.targetFPS == 15)
        #expect(VideoExportQuality.standard.maxDimension == 800)
        #expect(VideoExportQuality.small.targetFPS == 10)
        #expect(VideoExportQuality.small.maxDimension == 480)
    }

    @Test func presetPlanUsesPresetFpsAndCap() {
        let trim = VideoTrim(duration: 2)
        let plan = AnimatedExportPlanner.plan(trim: trim, crop: nil,
                                              sourceSize: CGSize(width: 1920, height: 1080),
                                              quality: .small)
        #expect(plan.frameDelay == 0.1) // 10fps
        #expect(plan.frameCount == 20)
        // 1920×1080 capped at 480 → 480×270.
        #expect(plan.size == CGSize(width: 480, height: 270))
    }
}
