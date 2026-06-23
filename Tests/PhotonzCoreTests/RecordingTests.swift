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
}
