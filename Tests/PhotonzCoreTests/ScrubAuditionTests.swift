import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// What you hear while you drag the playhead (`docs/design/video-audio.md` §6).
///
/// The arithmetic of a scrub is the whole of it: which file, which frames of
/// it, which way round, and how loud. Everything else is an engine node. So
/// the answer is a value, worked out from the same `audioMix()` plan that
/// playing and exporting read, and it is checked here rather than by ear.
@Suite("Hearing the sound under the playhead")
struct ScrubAuditionTests {

    static func segment(startMS: Int = 0, lengthMS: Int = 10_000,
                        sourceInMS: Int = 0, speedPercent: Int = 100,
                        gain: Double = 1, layerID: UUID = UUID(),
                        sound: SoundRef = SoundRef(durationMS: 10_000)) -> AudioMixSegment {
        AudioMixSegment(
            layerID: layerID, sound: sound, startMS: startMS, lengthMS: lengthMS,
            sourceInMS: sourceInMS, sourceLengthMS: lengthMS * speedPercent / 100,
            speedPercent: speedPercent,
            ramps: [AudioGainRamp(fromMS: startMS, toMS: startMS + lengthMS,
                                  fromGain: gain, toGain: gain)])
    }

    // MARK: - Something comes out

    @Test("Dragging forward over a sound plays the moment under the playhead")
    func forwardPlaysWhatIsUnderIt() throws {
        let windows = ScrubAudition.windows(in: [Self.segment()], movingFromMS: 2000, toMS: 2100)
        #expect(windows.count == 1)
        let one = try #require(windows.first)
        #expect(one.sourceInMS == 2100)
        #expect(one.lengthMS == ScrubAudition.windowMS)
        #expect(one.isReversed == false)
        #expect(one.gain == 1)
    }

    @Test("A hand that has stopped moving makes no sound")
    func standingStillIsSilent() {
        #expect(ScrubAudition.windows(in: [Self.segment()], movingFromMS: 2000, toMS: 2000).isEmpty)
    }

    @Test("Nothing under the playhead is silence, not a grain of the nearest sound")
    func pastTheEndIsSilent() {
        let mix = [Self.segment(startMS: 0, lengthMS: 1000)]
        #expect(ScrubAudition.windows(in: mix, movingFromMS: 1200, toMS: 1400).isEmpty)
    }

    @Test("A layer pulled all the way down stays down while you scrub it")
    func silentLayerStaysSilent() {
        let mix = [Self.segment(gain: 0)]
        #expect(ScrubAudition.windows(in: mix, movingFromMS: 2000, toMS: 2100).isEmpty)
    }

    // MARK: - Which way round

    @Test("Dragging backwards plays the moment backwards, not silence")
    func backwardsPlaysBackwards() throws {
        let windows = ScrubAudition.windows(in: [Self.segment()], movingFromMS: 2100, toMS: 2000)
        let one = try #require(windows.first)
        #expect(one.isReversed)
        // The window ENDS where the playhead is, so what you hear is the run-up
        // to the moment, played the way the hand is going.
        #expect(one.sourceInMS == 2000 - ScrubAudition.windowMS)
        #expect(one.lengthMS == ScrubAudition.windowMS)
    }

    @Test("Dragging backwards off the front of a piece shortens the grain rather than reading before it")
    func backwardsAtTheStartIsClamped() throws {
        let windows = ScrubAudition.windows(in: [Self.segment(sourceInMS: 500)],
                                            movingFromMS: 30, toMS: 10)
        let one = try #require(windows.first)
        #expect(one.sourceInMS == 500)
        #expect(one.lengthMS > 0)
        #expect(one.lengthMS <= ScrubAudition.windowMS)
    }

    @Test("A grain never reads past the end of the piece it belongs to")
    func forwardAtTheEndIsClamped() throws {
        let mix = [Self.segment(startMS: 0, lengthMS: 1000, sourceInMS: 0)]
        let windows = ScrubAudition.windows(in: mix, movingFromMS: 950, toMS: 980)
        let one = try #require(windows.first)
        #expect(one.sourceInMS == 980)
        #expect(one.sourceInMS + one.lengthMS <= 1000)
    }

    // MARK: - Where in the file

    @Test("A piece that starts part way into its file reads from where it really is")
    func sourceOffsetIsFollowed() throws {
        let mix = [Self.segment(startMS: 1000, lengthMS: 5000, sourceInMS: 4000)]
        let one = try #require(ScrubAudition.windows(in: mix, movingFromMS: 1400,
                                                      toMS: 1500).first)
        // Half a second into the piece, and the piece starts four seconds into
        // the file.
        #expect(one.sourceInMS == 4500)
    }

    @Test("A piece sped up is scrubbed at the frames it really plays")
    func speedIsFollowed() throws {
        let mix = [Self.segment(startMS: 0, lengthMS: 5000, speedPercent: 200)]
        let one = try #require(ScrubAudition.windows(in: mix, movingFromMS: 900,
                                                      toMS: 1000).first)
        // A second into a piece at double speed is two seconds into the file.
        #expect(one.sourceInMS == 2000)
    }

    // MARK: - More than one at once

    @Test("Two sounds under the playhead are both heard")
    func twoSoundsAreBothHeard() {
        let music = Self.segment(startMS: 0, lengthMS: 8000)
        let voice = Self.segment(startMS: 1000, lengthMS: 4000, sourceInMS: 0)
        let windows = ScrubAudition.windows(in: [music, voice], movingFromMS: 2000, toMS: 2100)
        #expect(windows.count == 2)
        #expect(Set(windows.map(\.layerID)) == Set([music.layerID, voice.layerID]))
    }

    @Test("Each one is heard at the level its own line says at that moment")
    func eachCarriesItsOwnLevel() throws {
        let ducked = AudioMixSegment(
            layerID: UUID(), sound: SoundRef(durationMS: 10_000), startMS: 0, lengthMS: 4000,
            sourceInMS: 0, sourceLengthMS: 4000, speedPercent: 100,
            ramps: [AudioGainRamp(fromMS: 0, toMS: 2000, fromGain: 1, toGain: 0.2),
                    AudioGainRamp(fromMS: 2000, toMS: 4000, fromGain: 0.2, toGain: 0.2)])
        let one = try #require(ScrubAudition.windows(in: [ducked], movingFromMS: 900,
                                                      toMS: 1000).first)
        #expect(abs(one.gain - 0.6) < 0.01)
    }

    // MARK: - What it costs

    @Test("A grain is short enough to be a scrub and long enough to be a word")
    func theGrainIsAScrub() {
        #expect(ScrubAudition.windowMS >= 40)
        #expect(ScrubAudition.windowMS <= 120)
    }

    @Test("A hand flying across the whole recording still plays one short grain, not the whole of it")
    func aFastDragIsStillOneGrain() throws {
        let one = try #require(ScrubAudition.windows(in: [Self.segment()], movingFromMS: 0,
                                                      toMS: 7000).first)
        #expect(one.lengthMS == ScrubAudition.windowMS)
    }
}
