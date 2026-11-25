import Foundation
@testable import PhotonzCore
import Testing

/// **How loud a mix gets, worked out again only where an edit changed it**
/// (`the-timeline-of-an-hour-long-edit-scrolls-zooms`).
///
/// The reading walks every twenty milliseconds of sound there is, and an hour
/// of three tracks took 12 ms of the main thread after each edit. The reader
/// keeps what each bucket adds up to and walks only the stretches whose sounds
/// are not the ones it read last time. Its answer is the whole walk's.
@Suite("A mix reads how loud it is after an edit without reading all of it again")
struct AudioHeadroomReaderTests {

    /// A file whose level is different in every bucket, so a sum that lands in
    /// the wrong place reads wrong.
    static func shape(_ seed: Int, seconds: Int = 60) -> Waveform {
        Waveform(peaks: (0..<(seconds * 1000 / Waveform.bucketMS)).map {
            Float(($0 * 7919 + seed * 104_729) % 997) / 997
        })
    }

    /// The whole walk, one bucket of one sound at a time, off
    /// `AudioMixSegment.gain` and `Waveform.peak`: what the reader has to say.
    static func wholeWalk(of mix: [AudioMixSegment], peaks: [UUID: Waveform]) -> AudioHeadroom {
        var sums: [Int: Double] = [:]
        var assumed: Set<UUID> = []
        for segment in mix where segment.lengthMS > 0 {
            let shape = peaks[segment.sound.id].flatMap { $0.isEmpty ? nil : $0 }
            if shape == nil { assumed.insert(segment.sound.id) }
            let first = segment.startMS / Waveform.bucketMS
            for bucket in first...max(first, (segment.endMS - 1) / Waveform.bucketMS) {
                let ms = max(segment.startMS, bucket * Waveform.bucketMS)
                let into = Int(Double(max(0, ms - segment.startMS)) * (Double(max(1, segment.speedPercent)) / 100))
                let file = shape.map { Double($0.peak(atSourceMS: segment.sourceInMS + into)) } ?? 1
                let level = segment.gain(atMS: ms) * file
                if level > 0 { sums[bucket, default: 0] += level }
            }
        }
        var loudest: Double = 0, at = 0
        for bucket in sums.keys.sorted() where sums[bucket, default: 0] > loudest {
            loudest = sums[bucket, default: 0]
            at = bucket
        }
        return AudioHeadroom(peak: loudest, atMS: at * Waveform.bucketMS, assumedFiles: assumed.count)
    }

    struct Edit {
        var sounds: [SoundRef] = []
        var peaks: [UUID: Waveform] = [:]
        var mix: [AudioMixSegment] = []

        /// Three tracks of back to back clips.
        init(clips: Int) {
            for track in 0..<3 {
                let sound = SoundRef(durationMS: 60_000)
                sounds.append(sound)
                peaks[sound.id] = AudioHeadroomReaderTests.shape(track)
                for clip in 0..<clips {
                    mix.append(Self.segment(sound, startMS: clip * 4000 + track * 333, lengthMS: 4000,
                                            sourceInMS: (clip * 1700) % 50_000, gain: 0.7))
                }
            }
        }

        static func segment(_ sound: SoundRef, startMS: Int, lengthMS: Int, sourceInMS: Int = 0,
                            gain: Double = 1, speed: Int = 100) -> AudioMixSegment {
            AudioMixSegment(layerID: UUID(), sound: sound, startMS: startMS, lengthMS: lengthMS,
                            sourceInMS: sourceInMS, sourceLengthMS: lengthMS, speedPercent: speed,
                            ramps: [AudioGainRamp(fromMS: startMS, toMS: startMS + lengthMS / 3,
                                                  fromGain: 0, toGain: gain),
                                    AudioGainRamp(fromMS: startMS + lengthMS / 3, toMS: startMS + lengthMS,
                                                  fromGain: gain, toGain: gain * 0.5)])
        }
    }

    static func expectSame(_ a: AudioHeadroom, _ b: AudioHeadroom,
                           sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a.peak - b.peak) < 1e-9, sourceLocation: sourceLocation)
        #expect(a.atMS == b.atMS, sourceLocation: sourceLocation)
        #expect(a.assumedFiles == b.assumedFiles, sourceLocation: sourceLocation)
    }

    @Test("The first reading is the whole mix's, and the second reads nothing")
    func firstAndSecond() {
        let edit = Edit(clips: 40)
        var reader = AudioHeadroomReader()
        Self.expectSame(reader.reading(of: edit.mix, peaks: edit.peaks),
                        Self.wholeWalk(of: edit.mix, peaks: edit.peaks))
        #expect(reader.bucketsRead > 0)
        _ = reader.reading(of: edit.mix, peaks: edit.peaks)
        #expect(reader.bucketsRead == 0)
    }

    @Test("A clip moved, trimmed, cut, taken away or added reads the same as the whole walk, off a few seconds of it")
    func edits() {
        var edit = Edit(clips: 200)
        var reader = AudioHeadroomReader()
        _ = reader.reading(of: edit.mix, peaks: edit.peaks)
        func check(_ what: String) {
            Self.expectSame(reader.reading(of: edit.mix, peaks: edit.peaks),
                            Self.wholeWalk(of: edit.mix, peaks: edit.peaks))
            #expect(reader.bucketsRead <= 30_000 / Waveform.bucketMS, "\(what) read \(reader.bucketsRead) buckets")
        }
        let moved = edit.mix[250]
        edit.mix[250] = Edit.segment(moved.sound, startMS: moved.startMS + 517, lengthMS: 4000, sourceInMS: 900, gain: 0.7)
        check("a move")
        let trimmed = edit.mix[30]
        edit.mix[30] = Edit.segment(trimmed.sound, startMS: trimmed.startMS, lengthMS: 2511, sourceInMS: 300)
        check("a trim")
        let cut = edit.mix[400]
        edit.mix[400] = Edit.segment(cut.sound, startMS: cut.startMS, lengthMS: 1503)
        edit.mix.append(Edit.segment(cut.sound, startMS: cut.startMS + 1503, lengthMS: 2497, sourceInMS: 1503))
        check("a blade, the second half at the other end of the list")
        edit.mix.remove(at: 511)
        check("a clip taken away")
        edit.mix.insert(Edit.segment(edit.sounds[1], startMS: 799_000, lengthMS: 5000, gain: 1.4), at: 3)
        check("a clip past the end")
        edit.mix.removeAll { $0.startMS == 799_000 }
        check("...and gone again")
    }

    @Test("A mix whose sounds only change order reads nothing")
    func order() {
        var edit = Edit(clips: 50)
        var reader = AudioHeadroomReader()
        _ = reader.reading(of: edit.mix, peaks: edit.peaks)
        edit.mix.swapAt(3, 120)
        Self.expectSame(reader.reading(of: edit.mix, peaks: edit.peaks),
                        Self.wholeWalk(of: edit.mix, peaks: edit.peaks))
        #expect(reader.bucketsRead == 0)
    }

    @Test("The same sound twice in one place is counted twice, and one of them gone is counted once")
    func twins() {
        let sound = SoundRef(durationMS: 4000)
        let one = Edit.segment(sound, startMS: 1000, lengthMS: 4000)
        let peaks = [sound.id: Self.shape(1)]
        var reader = AudioHeadroomReader()
        for mix in [[one], [one, one], [one], [], [one, one, one]] {
            Self.expectSame(reader.reading(of: mix, peaks: peaks), Self.wholeWalk(of: mix, peaks: peaks))
        }
    }

    @Test("A shape that lands, or is read again off a changed file, is heard")
    func shapesLanding() {
        var edit = Edit(clips: 20)
        let late = edit.sounds[2].id
        let shape = edit.peaks.removeValue(forKey: late)
        var reader = AudioHeadroomReader()
        Self.expectSame(reader.reading(of: edit.mix, peaks: edit.peaks),
                        Self.wholeWalk(of: edit.mix, peaks: edit.peaks))
        #expect(reader.reading(of: edit.mix, peaks: edit.peaks).assumedFiles == 1)
        edit.peaks[late] = shape
        Self.expectSame(reader.reading(of: edit.mix, peaks: edit.peaks),
                        Self.wholeWalk(of: edit.mix, peaks: edit.peaks))
        edit.peaks[late] = Self.shape(44)
        Self.expectSame(reader.reading(of: edit.mix, peaks: edit.peaks),
                        Self.wholeWalk(of: edit.mix, peaks: edit.peaks))
    }

    @Test("Sped up, short, silent and not yet playing: every odd piece reads as the whole walk reads it")
    func oddPieces() {
        let sound = SoundRef(durationMS: 60_000)
        let peaks = [sound.id: Self.shape(5)]
        let mix = [
            Edit.segment(sound, startMS: 7, lengthMS: 11),
            Edit.segment(sound, startMS: 19, lengthMS: 2),
            Edit.segment(sound, startMS: 13, lengthMS: 3001, sourceInMS: 59_000, speed: 250),
            Edit.segment(sound, startMS: 3000, lengthMS: 1000, gain: 0),
            Edit.segment(sound, startMS: 5000, lengthMS: 0),
            Edit.segment(sound, startMS: 2990, lengthMS: 4000, speed: 50),
            AudioMixSegment(layerID: UUID(), sound: sound, startMS: 100, lengthMS: 500, sourceInMS: 0,
                            sourceLengthMS: 500, speedPercent: 100, ramps: []),
        ]
        var reader = AudioHeadroomReader()
        Self.expectSame(reader.reading(of: mix, peaks: peaks), Self.wholeWalk(of: mix, peaks: peaks))
        for gone in mix.indices {
            var fewer = mix
            fewer.remove(at: gone)
            Self.expectSame(reader.reading(of: fewer, peaks: peaks), Self.wholeWalk(of: fewer, peaks: peaks))
        }
    }
}
