import Foundation
import PhotonzCore
import Testing

/// Two sounds recorded together (the Mac's and the microphone's) are mixed
/// into one as they arrive, so the recording's file has its sound the moment
/// Stop is pressed.
///
/// Measured 2026-10-10: when macOS mixes the two itself it does it after Stop,
/// at about 0.45 s per recorded second (20 s for 45 s, full screen). With one
/// sound it closes the file in under 100 ms. So the recorder gives macOS one
/// sound and mixes the pair itself while recording, on the clock both share,
/// counted from the recording's first frame.
@Suite("Two sounds are mixed as they are recorded")
struct SoundMixTimelineTests {
    private let rate = 48_000.0

    private func seconds(_ frame: Int64) -> Double { Double(frame) / rate }

    private func timeline(maxLag: Double = 0.5) -> SoundMixTimeline {
        SoundMixTimeline(sources: [.mac, .microphone], channelCount: 2, sampleRate: rate,
                         maxLagSeconds: maxLag)
    }

    private func constant(_ value: Float, frames: Int, channels: Int = 2) -> [[Float]] {
        Array(repeating: Array(repeating: value, count: frames), count: channels)
    }

    private func drain(_ mix: inout SoundMixTimeline, finishing: Bool = false) -> [SoundMixTimeline.Chunk] {
        var out: [SoundMixTimeline.Chunk] = []
        while let chunk = mix.take(finishing: finishing) { out.append(chunk) }
        return out
    }

    @Test func nothingComesOutBeforeTheRecordingsFirstFrameIsKnown() {
        var mix = timeline()
        mix.add(.mac, atSeconds: 10, channels: constant(0.1, frames: 4800))
        mix.add(.microphone, atSeconds: 10, channels: constant(0.2, frames: 4800))
        let whileRecording = mix.take()
        let atStop = mix.take(finishing: true)
        #expect(whileRecording == nil)
        #expect(atStop == nil)
    }

    @Test func theTwoSoundsAreAddedSampleBySampleOnTheirSharedClock() throws {
        var mix = timeline()
        mix.setZero(atSeconds: 10)
        mix.add(.mac, atSeconds: 10, channels: constant(0.1, frames: 4800))
        mix.add(.microphone, atSeconds: 10, channels: constant(0.25, frames: 4800))
        let taken = mix.take()
        let chunk = try #require(taken)
        #expect(chunk.startFrame == 0)
        #expect(chunk.frameCount == 4800)
        #expect(chunk.channels.count == 2)
        #expect(chunk.channels.allSatisfy { $0.allSatisfy { abs($0 - 0.35) < 0.0001 } })
    }

    @Test func soundFromBeforeTheFirstFrameIsLeftOut() throws {
        var mix = timeline()
        // A tenth of a second of sound before the picture starts.
        mix.add(.mac, atSeconds: 9.9, channels: constant(0.5, frames: 9600))
        mix.add(.microphone, atSeconds: 9.9, channels: constant(0.0, frames: 9600))
        mix.setZero(atSeconds: 10)
        let taken = mix.take()
        let chunk = try #require(taken)
        #expect(chunk.startFrame == 0)
        #expect(chunk.frameCount == 4800)
    }

    @Test func aSoundArrivingLaterLinesUpWithWhereItWasHeard() throws {
        var mix = timeline()
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.1, frames: 4800))
        // The microphone's first sample was heard 50 ms in.
        mix.add(.microphone, atSeconds: 0.05, channels: constant(0.2, frames: 2400))
        let taken = mix.take(finishing: true)
        let chunk = try #require(taken)
        #expect(chunk.frameCount == 4800)
        let left = chunk.channels[0]
        #expect(abs(left[0] - 0.1) < 0.0001)
        #expect(abs(left[2399] - 0.1) < 0.0001)
        #expect(abs(left[2400] - 0.3) < 0.0001)
        #expect(abs(left[4799] - 0.3) < 0.0001)
    }

    @Test func onlyWhatBothSoundsHaveReachedComesOutWhileRecording() throws {
        var mix = timeline(maxLag: 5)
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.1, frames: 9600))
        mix.add(.microphone, atSeconds: 0, channels: constant(0.1, frames: 4800))
        let chunks = drain(&mix)
        #expect(chunks.map(\.frameCount).reduce(0, +) == 4800)
        // The rest comes once the microphone catches up.
        mix.add(.microphone, atSeconds: seconds(4800), channels: constant(0.1, frames: 4800))
        let more = drain(&mix)
        #expect(more.first?.startFrame == 4800)
        #expect(more.map(\.frameCount).reduce(0, +) == 4800)
    }

    @Test func aSoundThatFallsSilentDoesNotHoldTheOtherBackForever() {
        var mix = timeline(maxLag: 0.5)
        mix.setZero(atSeconds: 0)
        // The microphone has said nothing at all; the Mac has two seconds.
        mix.add(.mac, atSeconds: 0, channels: constant(0.1, frames: 96_000))
        let chunks = drain(&mix)
        // Everything up to half a second behind the newest sound comes out.
        #expect(chunks.map(\.frameCount).reduce(0, +) == 96_000 - 24_000)
    }

    @Test func soundArrivingForAStretchAlreadyWrittenIsDropped() throws {
        var mix = timeline(maxLag: 0.5)
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.1, frames: 96_000))
        _ = drain(&mix)
        // The microphone wakes up late with sound for the first second.
        mix.add(.microphone, atSeconds: 0, channels: constant(0.2, frames: 96_000))
        let rest = drain(&mix, finishing: true)
        let first = try #require(rest.first)
        #expect(first.startFrame == 72_000)
        // What overlaps the part not yet written is still mixed in.
        #expect(abs(first.channels[0][0] - 0.3) < 0.0001)
        #expect(rest.map(\.frameCount).reduce(0, +) == 24_000)
    }

    @Test func finishingLetsOutEverythingHeard() {
        var mix = timeline(maxLag: 5)
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.1, frames: 9600))
        mix.add(.microphone, atSeconds: 0, channels: constant(0.1, frames: 4800))
        let chunks = drain(&mix, finishing: true)
        #expect(chunks.map(\.frameCount).reduce(0, +) == 9600)
        let after = mix.take(finishing: true)
        #expect(after == nil)
    }

    @Test func chunksFollowOnWithNoGapAndNoOverlap() {
        var mix = timeline()
        mix.setZero(atSeconds: 0)
        var next: Int64 = 0
        var written: Int64 = 0
        for step in 0..<50 {
            let at = seconds(Int64(step) * 1024)
            mix.add(.mac, atSeconds: at, channels: constant(0.1, frames: 1024))
            mix.add(.microphone, atSeconds: at, channels: constant(0.1, frames: 1024))
            for chunk in drain(&mix) {
                #expect(chunk.startFrame == next)
                next += Int64(chunk.frameCount)
                written += Int64(chunk.frameCount)
            }
        }
        #expect(written == 50 * 1024)
    }

    @Test func aBufferStampedASampleOffFollowsOnFromTheLastWithoutAClick() {
        var mix = timeline()
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.1, frames: 1000))
        // Stamped 1.4 samples early: rounding, not a real overlap.
        mix.add(.mac, atSeconds: seconds(1000) - 1.4 / rate, channels: constant(0.1, frames: 1000))
        mix.add(.microphone, atSeconds: 0, channels: constant(0.0, frames: 2000))
        let chunks = drain(&mix, finishing: true)
        let samples = chunks.flatMap { $0.channels[0] }
        #expect(samples.count == 2000)
        #expect(samples.allSatisfy { abs($0 - 0.1) < 0.0001 })
    }

    @Test func aGapInOneSoundIsSilenceNotASkip() {
        var mix = timeline()
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.1, frames: 1000))
        mix.add(.mac, atSeconds: seconds(2000), channels: constant(0.1, frames: 1000))
        mix.add(.microphone, atSeconds: 0, channels: constant(0.0, frames: 3000))
        let samples = drain(&mix, finishing: true).flatMap { $0.channels[0] }
        #expect(samples.count == 3000)
        #expect(samples[999] > 0.05)
        #expect(samples[1000] == 0)
        #expect(samples[1999] == 0)
        #expect(samples[2000] > 0.05)
    }

    @Test func aOneChannelMicrophoneIsHeardOnBothSides() throws {
        var mix = timeline()
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.0, frames: 480))
        mix.add(.microphone, atSeconds: 0, channels: constant(0.3, frames: 480, channels: 1))
        let taken = mix.take(finishing: true)
        let chunk = try #require(taken)
        #expect(chunk.channels.count == 2)
        #expect(abs(chunk.channels[0][100] - 0.3) < 0.0001)
        #expect(abs(chunk.channels[1][100] - 0.3) < 0.0001)
    }

    @Test func loudSoundsTogetherNeverGoPastFullScale() throws {
        var mix = timeline()
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.8, frames: 480))
        mix.add(.microphone, atSeconds: 0, channels: constant(0.7, frames: 480))
        mix.add(.mac, atSeconds: seconds(480), channels: constant(-0.8, frames: 480))
        mix.add(.microphone, atSeconds: seconds(480), channels: constant(-0.7, frames: 480))
        let samples = drain(&mix, finishing: true).flatMap { $0.channels[0] }
        #expect(samples.max() == 1)
        #expect(samples.min() == -1)
    }

    @Test func chunksAreNeverLongerThanTheLimit() {
        var mix = timeline()
        mix.setZero(atSeconds: 0)
        mix.add(.mac, atSeconds: 0, channels: constant(0.1, frames: 100_000))
        mix.add(.microphone, atSeconds: 0, channels: constant(0.1, frames: 100_000))
        let chunks = drain(&mix, finishing: true)
        #expect(chunks.allSatisfy { $0.frameCount <= SoundMixTimeline.maxChunkFrames })
        #expect(chunks.map(\.frameCount).reduce(0, +) == 100_000)
    }
}
