import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// **How loud the mix gets, and what stops it running past what a file holds**
/// (`docs/design/video-audio.md` §9).
///
/// Three sounds at the level they were recorded at sum past full scale, and
/// before this existed nothing said so: the meter did not exist, the export did
/// not warn, and the written file came out distorted. The arithmetic that
/// answers all three is here, and it is pure: a mix plan, the shape of each
/// file it plays, and one number out.
@Suite("A mix says how loud it is")
struct AudioHeadroomTests {

    /// A file that is at full scale the whole way through, which is the worst
    /// case and the one every one of these is built on.
    static func full(seconds: Double = 10) -> Waveform {
        Waveform(peaks: Array(repeating: 1, count: Int(seconds * 1000) / Waveform.bucketMS))
    }

    /// A file at a steady level below full scale.
    static func flat(_ level: Float, seconds: Double = 10) -> Waveform {
        Waveform(peaks: Array(repeating: level, count: Int(seconds * 1000) / Waveform.bucketMS))
    }

    static func segment(_ sound: SoundRef, startMS: Int, lengthMS: Int,
                        gain: Double = 1, speedPercent: Int = 100) -> AudioMixSegment {
        AudioMixSegment(
            layerID: UUID(), sound: sound, startMS: startMS, lengthMS: lengthMS,
            sourceInMS: 0, sourceLengthMS: lengthMS, speedPercent: speedPercent,
            ramps: [AudioGainRamp(fromMS: startMS, toMS: startMS + lengthMS,
                                  fromGain: gain, toGain: gain)])
    }

    // MARK: - Reading how loud it is

    @Test("One sound at the level it was recorded at is as loud as the file is, and no louder")
    func oneSoundReadsItsOwnLevel() {
        let sound = SoundRef(durationMS: 4000)
        let mix = [Self.segment(sound, startMS: 0, lengthMS: 4000)]
        let reading = AudioHeadroom.reading(of: mix, peaks: [sound.id: Self.full()])
        #expect(abs(reading.peak - 1) < 0.001)
        #expect(!reading.isOver)
        #expect(reading.trim == 1)
    }

    @Test("A sound pulled down reads quieter by exactly what the fader says")
    func theFaderMovesTheReading() {
        let sound = SoundRef(durationMS: 4000)
        let mix = [Self.segment(sound, startMS: 0, lengthMS: 4000, gain: 0.5)]
        let reading = AudioHeadroom.reading(of: mix, peaks: [sound.id: Self.full()])
        #expect(abs(reading.peak - 0.5) < 0.001)
    }

    @Test("A quiet file at full level still reads quiet: it is the sound that is measured, not the fader")
    func aQuietFileReadsQuiet() {
        let sound = SoundRef(durationMS: 4000)
        let mix = [Self.segment(sound, startMS: 0, lengthMS: 4000)]
        let reading = AudioHeadroom.reading(of: mix, peaks: [sound.id: Self.flat(0.2)])
        #expect(abs(reading.peak - 0.2) < 0.01)
        #expect(!reading.isOver)
    }

    @Test("Three sounds at the level they were recorded at are three times over, and it says where")
    func threeSoundsOverlappingAreOver() {
        let a = SoundRef(durationMS: 6000)
        let b = SoundRef(durationMS: 6000)
        let c = SoundRef(durationMS: 6000)
        let mix = [Self.segment(a, startMS: 0, lengthMS: 6000),
                   Self.segment(b, startMS: 2000, lengthMS: 6000),
                   Self.segment(c, startMS: 4000, lengthMS: 6000)]
        let peaks = [a.id: Self.full(), b.id: Self.full(), c.id: Self.full()]
        let reading = AudioHeadroom.reading(of: mix, peaks: peaks)
        #expect(abs(reading.peak - 3) < 0.01)
        #expect(reading.isOver)
        // All three are only laid over each other between four and six seconds.
        #expect(reading.atMS >= 4000 && reading.atMS < 6000)
        #expect(reading.overByDB ?? 0 > 9)
    }

    @Test("Sounds that never overlap never add up")
    func soundsSideBySideDoNotAdd() {
        let a = SoundRef(durationMS: 2000)
        let b = SoundRef(durationMS: 2000)
        let mix = [Self.segment(a, startMS: 0, lengthMS: 2000),
                   Self.segment(b, startMS: 2000, lengthMS: 2000)]
        let reading = AudioHeadroom.reading(of: mix, peaks: [a.id: Self.full(), b.id: Self.full()])
        #expect(abs(reading.peak - 1) < 0.001)
        #expect(!reading.isOver)
    }

    @Test("A file whose shape has not been read yet is counted as full scale rather than as silence")
    func anUnknownFileIsCountedAtItsLoudest() {
        let sound = SoundRef(durationMS: 4000)
        let mix = [Self.segment(sound, startMS: 0, lengthMS: 4000)]
        let reading = AudioHeadroom.reading(of: mix, peaks: [:])
        #expect(abs(reading.peak - 1) < 0.001)
        #expect(reading.assumedFiles == 1)
    }

    @Test("Nothing playing is no reading at all, not a reading of nought over")
    func anEmptyMixIsNotOver() {
        let reading = AudioHeadroom.reading(of: [], peaks: [:])
        #expect(reading.peak == 0)
        #expect(!reading.isOver)
        #expect(reading.trim == 1)
        #expect(reading.overByDB == nil)
    }

    @Test("A fade is followed: the reading at a moment is the level at that moment")
    func theReadingFollowsTheShape() {
        let sound = SoundRef(durationMS: 4000)
        let segment = AudioMixSegment(
            layerID: UUID(), sound: sound, startMS: 0, lengthMS: 4000,
            sourceInMS: 0, sourceLengthMS: 4000, speedPercent: 100,
            ramps: [AudioGainRamp(fromMS: 0, toMS: 4000, fromGain: 0, toGain: 1)])
        let peaks = [sound.id: Self.full()]
        let quiet = AudioHeadroom.level(of: [segment], peaks: peaks, atMS: 0)
        let half = AudioHeadroom.level(of: [segment], peaks: peaks, atMS: 2000)
        let loud = AudioHeadroom.level(of: [segment], peaks: peaks, atMS: 3980)
        #expect(quiet < 0.05)
        #expect(abs(half - 0.5) < 0.02)
        #expect(loud > 0.9)
    }

    @Test("Nothing under the playhead reads silent")
    func nothingUnderThePlayheadReadsSilent() {
        let sound = SoundRef(durationMS: 1000)
        let mix = [Self.segment(sound, startMS: 0, lengthMS: 1000)]
        #expect(AudioHeadroom.level(of: mix, peaks: [sound.id: Self.full()], atMS: 5000) == 0)
    }

    @Test("A piece sped up reads the part of the file it is actually playing")
    func speedMovesWhereTheFileIsRead() {
        let sound = SoundRef(durationMS: 4000)
        // Loud only in the second second of the file.
        var peaks = [Float](repeating: 0.1, count: 4000 / Waveform.bucketMS)
        for index in (1000 / Waveform.bucketMS)..<(2000 / Waveform.bucketMS) { peaks[index] = 1 }
        let shape = Waveform(peaks: peaks)
        // At double speed the second second of the file lands half a second in.
        let fast = AudioMixSegment(
            layerID: UUID(), sound: sound, startMS: 0, lengthMS: 2000,
            sourceInMS: 0, sourceLengthMS: 4000, speedPercent: 200,
            ramps: [AudioGainRamp(fromMS: 0, toMS: 2000, fromGain: 1, toGain: 1)])
        #expect(AudioHeadroom.level(of: [fast], peaks: [sound.id: shape], atMS: 700) > 0.9)
        #expect(AudioHeadroom.level(of: [fast], peaks: [sound.id: shape], atMS: 100) < 0.2)
    }

    // MARK: - Stopping it running past what a file holds

    @Test("A mix that is over comes back trimmed to the ceiling, and no further")
    func limitingBringsItToTheCeiling() {
        let a = SoundRef(durationMS: 6000)
        let b = SoundRef(durationMS: 6000)
        let mix = [Self.segment(a, startMS: 0, lengthMS: 6000),
                   Self.segment(b, startMS: 0, lengthMS: 6000)]
        let peaks = [a.id: Self.full(), b.id: Self.full()]
        let held = AudioHeadroom.limited(mix, peaks: peaks)
        let after = AudioHeadroom.reading(of: held, peaks: peaks)
        #expect(abs(after.peak - AudioHeadroom.ceiling) < 0.01)
        #expect(!after.isOver)
    }

    @Test("A mix that fits is handed back untouched: nothing is quietly turned down")
    func aMixThatFitsIsUntouched() {
        let sound = SoundRef(durationMS: 4000)
        let mix = [Self.segment(sound, startMS: 0, lengthMS: 4000, gain: 0.5)]
        let held = AudioHeadroom.limited(mix, peaks: [sound.id: Self.full()])
        #expect(held == mix)
    }

    @Test("Trimming twice trims once: the plan can be held down wherever it is read")
    func limitingIsIdempotent() {
        let a = SoundRef(durationMS: 6000)
        let b = SoundRef(durationMS: 6000)
        let c = SoundRef(durationMS: 6000)
        let mix = [Self.segment(a, startMS: 0, lengthMS: 6000),
                   Self.segment(b, startMS: 0, lengthMS: 6000),
                   Self.segment(c, startMS: 0, lengthMS: 6000)]
        let peaks = [a.id: Self.full(), b.id: Self.full(), c.id: Self.full()]
        let once = AudioHeadroom.limited(mix, peaks: peaks)
        let twice = AudioHeadroom.limited(once, peaks: peaks)
        #expect(once == twice)
    }

    @Test("Holding the mix down keeps the difference between one sound and three")
    func trimmingKeepsTheBalance() {
        let a = SoundRef(durationMS: 6000)
        let b = SoundRef(durationMS: 6000)
        let c = SoundRef(durationMS: 6000)
        let mix = [Self.segment(a, startMS: 0, lengthMS: 6000),
                   Self.segment(b, startMS: 2000, lengthMS: 6000),
                   Self.segment(c, startMS: 4000, lengthMS: 6000)]
        let peaks = [a.id: Self.full(), b.id: Self.full(), c.id: Self.full()]
        let held = AudioHeadroom.limited(mix, peaks: peaks)
        let alone = AudioHeadroom.level(of: held, peaks: peaks, atMS: 1000)
        let together = AudioHeadroom.level(of: held, peaks: peaks, atMS: 5000)
        #expect(alone > 0.1)
        #expect(together > alone * 2.5)
        #expect(together <= AudioHeadroom.ceiling + 0.001)
    }

    @Test("A shape is trimmed all the way along rather than flattened")
    func trimmingKeepsTheShape() {
        let sound = SoundRef(durationMS: 4000)
        let segment = AudioMixSegment(
            layerID: UUID(), sound: sound, startMS: 0, lengthMS: 4000,
            sourceInMS: 0, sourceLengthMS: 4000, speedPercent: 100,
            ramps: [AudioGainRamp(fromMS: 0, toMS: 2000, fromGain: 0, toGain: 2),
                    AudioGainRamp(fromMS: 2000, toMS: 4000, fromGain: 2, toGain: 2)])
        let held = AudioHeadroom.limited([segment], peaks: [sound.id: Self.full()])
        let ramps = try! #require(held.first).ramps
        #expect(ramps.count == 2)
        #expect(ramps[0].fromGain == 0)
        #expect(ramps[0].toGain < 2)
        #expect(abs(ramps[0].toGain - ramps[1].fromGain) < 0.0001)
    }

    // MARK: - Saying it

    @Test("A mix that is over says so in decibels; one that fits says where it peaks")
    func theLabelSaysWhatHappened() {
        let a = SoundRef(durationMS: 6000)
        let b = SoundRef(durationMS: 6000)
        let over = AudioHeadroom.reading(
            of: [Self.segment(a, startMS: 0, lengthMS: 6000),
                 Self.segment(b, startMS: 0, lengthMS: 6000)],
            peaks: [a.id: Self.full(), b.id: Self.full()])
        #expect(over.label.contains("over"))
        #expect(over.label.contains("dB"))

        let fits = AudioHeadroom.reading(
            of: [Self.segment(a, startMS: 0, lengthMS: 6000, gain: 0.25)],
            peaks: [a.id: Self.full()])
        #expect(!fits.label.contains("over"))
        #expect(fits.label.contains("dB"))

        let silent = AudioHeadroom.reading(of: [], peaks: [:])
        #expect(silent.label == "Silent")
    }

    @Test("The meter has somewhere to put every level: silence at the bottom, the ceiling near the top")
    func theMeterScaleLeavesRoomAtTheTop() {
        #expect(AudioHeadroom.meterFraction(ofLevel: 0) == 0)
        let ceiling = AudioHeadroom.meterFraction(ofLevel: AudioHeadroom.ceiling)
        #expect(ceiling > 0.85 && ceiling < 1)
        // A quiet sound has room to move rather than being pinned to the floor,
        // which is the whole reason the scale is not a straight line in gain.
        #expect(AudioHeadroom.meterFraction(ofLevel: 0.1) > 0.25)
        #expect(AudioHeadroom.meterFraction(ofLevel: 2) == 1)
        // It only ever goes up.
        #expect(AudioHeadroom.meterFraction(ofLevel: 0.2) > AudioHeadroom.meterFraction(ofLevel: 0.1))
    }

    // MARK: - A whole document

    @Test("A document with three sounds laid over each other reads over, and holds itself down")
    func aDocumentReadsItsOwnMix() {
        var doc = PhotonzDocument(canvasSize: CGSize(width: 100, height: 100), layers: [])
        let a = SoundRef(durationMS: 6000)
        let b = SoundRef(durationMS: 6000)
        let c = SoundRef(durationMS: 6000)
        _ = doc.addSound(a, name: "one", atMS: 0)
        _ = doc.addSound(b, name: "two", atMS: 2000)
        _ = doc.addSound(c, name: "three", atMS: 4000)
        let peaks = [a.id: Self.full(), b.id: Self.full(), c.id: Self.full()]
        let mix = doc.audioMix()
        #expect(mix.count == 3)
        #expect(AudioHeadroom.reading(of: mix, peaks: peaks).isOver)
        #expect(!AudioHeadroom.reading(of: AudioHeadroom.limited(mix, peaks: peaks),
                                       peaks: peaks).isOver)
    }
}
