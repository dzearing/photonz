import Foundation

// How loud the mix gets, and what stops it running past what a file can hold
// (`docs/design/video-audio.md` §9).
//
// Sound adds up. Three things playing at the level they were recorded at are
// three times full scale where they overlap, and a sound file has no room for
// that: everything past the top is clipped off flat, which is not three sounds
// any more, it is noise. Before this existed the app said nothing about it —
// no meter, no mark on the export, and a written file you only found out about
// by listening to it.
//
// **One piece of arithmetic answers all of that**, and it is the same rule the
// rest of this module lives by: there is ONE plan (`PhotonzDocument.audioMix()`)
// and everything reads it rather than working anything out. Here the plan is
// read twice:
//
// * `reading(of:peaks:)` walks the whole mix and says the loudest it ever gets,
//   where that happens, and by how much it is over. That is what marks an
//   export before it is written.
// * `level(of:peaks:atMS:)` says how loud it is at ONE moment, which is what
//   the meter in the transport draws — so the meter moves while you drag the
//   playhead, not only while it plays, and it can be checked by a test.
//
// And `limited(_:peaks:)` hands back the same plan held under the ceiling, so
// the player and the exporter are both given a mix that cannot clip. Trimming
// an already-trimmed mix changes nothing, which is what lets it be applied
// wherever the plan is read without anybody having to track whether it was
// applied already.
//
// **It measures the sound, not the fader.** A layer at full level playing a
// quiet recording is quiet, and the only way to know that is to look at the
// shape of the file — which the app has already read to draw the waveform
// (`Waveform`). A file whose shape has not landed yet is counted as full
// scale, which is the safe way round: the guess is quieter than the truth,
// never louder.
//
// **It is a worst case, deliberately.** Peaks are summed rather than combined
// by power, so two sounds that happen to line up are assumed to line up. A
// ceiling that holds only for sounds that disagree is not a ceiling.

/// How loud a mix gets, and what it would take to keep it inside a file.
public struct AudioHeadroom: Hashable, Sendable {

    /// The loudest a written file is allowed to get: full scale, and not a
    /// fraction under it.
    ///
    /// Deliberately not "full scale minus a decibel for safety". A recording
    /// that already peaks at full scale is a perfectly legal file, and a
    /// ceiling under it would pull that file down on the way out for no reason
    /// anybody could hear or asked for. The rule is the plain one: a mix is
    /// allowed to reach the top and is not allowed to go past it.
    public static let ceiling: Double = 1

    /// The quietest the meter draws before it reads as silence.
    static let meterFloorDB: Double = -48

    /// The loudest the meter can draw, which is as loud as a fader goes.
    static let meterTopDB: Double = 6

    /// The loudest the mix ever gets. One is full scale; more than one is more
    /// than a file can hold.
    public let peak: Double
    /// The moment it gets there, on the document's own clock.
    public let atMS: Int
    /// How many of the sounds in the mix had no shape read yet and so were
    /// counted at full scale. Nought once the waveforms have landed.
    public let assumedFiles: Int

    public init(peak: Double, atMS: Int, assumedFiles: Int) {
        self.peak = peak.isFinite ? max(0, peak) : 0
        self.atMS = max(0, atMS)
        self.assumedFiles = max(0, assumedFiles)
    }

    /// Whether this mix would be clipped if it were written as it stands.
    ///
    /// The slack is there so a mix that has already been held down to the
    /// ceiling does not read as over on the way back through.
    public var isOver: Bool { peak > Self.ceiling + 1e-9 }

    /// What every level has to be multiplied by to bring the mix inside the
    /// ceiling. One where it already fits, so a mix nobody needs to hold down
    /// is handed back exactly as it was.
    public var trim: Double {
        guard isOver, peak > 0 else { return 1 }
        return Self.ceiling / peak
    }

    /// The loudest moment in decibels, or nil where nothing makes a sound.
    public var peakDB: Double? {
        guard peak > 0 else { return nil }
        return 20 * log10(peak)
    }

    /// How far past the ceiling it goes, in decibels. Nil where it fits.
    public var overByDB: Double? {
        guard isOver else { return nil }
        return 20 * log10(peak / Self.ceiling)
    }

    /// What the transport and the export notice say, in plain words.
    public var label: String {
        guard let peakDB else { return "Silent" }
        if let overByDB {
            return String(format: "The mix is %.1f dB over and is being held down", overByDB)
        }
        return String(format: "The mix peaks at %.1f dB", peakDB)
    }

    // MARK: - Reading the plan

    /// The loudest the whole mix ever gets, and where.
    ///
    /// Walked in the same twenty millisecond buckets a waveform is kept in, so
    /// the answer is exactly as fine-grained as the shape it is read off and
    /// costs one pass over the sound in the document.
    public static func reading(of mix: [AudioMixSegment],
                               peaks: [UUID: Waveform]) -> AudioHeadroom {
        var sums: [Int: Double] = [:]
        var assumed: Set<UUID> = []
        for segment in mix where segment.lengthMS > 0 {
            let shape = self.shape(of: segment, in: peaks)
            if shape == nil { assumed.insert(segment.sound.id) }
            let first = segment.startMS / Waveform.bucketMS
            let last = max(first, (segment.endMS - 1) / Waveform.bucketMS)
            for bucket in first...last {
                let ms = max(segment.startMS, bucket * Waveform.bucketMS)
                let level = self.level(of: segment, shape: shape, atMS: ms)
                if level > 0 { sums[bucket, default: 0] += level }
            }
        }
        var loudest: Double = 0
        var loudestBucket = 0
        for bucket in sums.keys.sorted() where sums[bucket, default: 0] > loudest {
            loudest = sums[bucket, default: 0]
            loudestBucket = bucket
        }
        return AudioHeadroom(peak: loudest, atMS: loudestBucket * Waveform.bucketMS,
                             assumedFiles: assumed.count)
    }

    /// How loud the mix is at one moment: everything laid over it, added up.
    public static func level(of mix: [AudioMixSegment], peaks: [UUID: Waveform],
                             atMS ms: Int) -> Double {
        var total: Double = 0
        for segment in mix where segment.contains(ms: ms) {
            total += level(of: segment, shape: shape(of: segment, in: peaks), atMS: ms)
        }
        return total
    }

    /// The shape of the file a segment plays, or nil where it has not been read
    /// yet and the segment is to be counted at full scale.
    private static func shape(of segment: AudioMixSegment,
                              in peaks: [UUID: Waveform]) -> Waveform? {
        guard let shape = peaks[segment.sound.id], !shape.isEmpty else { return nil }
        return shape
    }

    /// One piece at one moment: how loud its file is where it is being read
    /// from, times how loud its level says it should play.
    private static func level(of segment: AudioMixSegment, shape: Waveform?,
                              atMS ms: Int) -> Double {
        let gain = segment.gain(atMS: ms)
        guard gain > 0 else { return 0 }
        guard let shape else { return gain }
        // A piece sped up reads further into its file than it has been playing
        // for, which is exactly what makes its waveform draw the part it plays.
        let into = max(0, ms - segment.startMS)
        let speed = Double(max(1, segment.speedPercent)) / 100
        let sourceMS = segment.sourceInMS + Int(Double(into) * speed)
        return gain * Double(shape.peak(atSourceMS: sourceMS))
    }

    // MARK: - Holding it down

    /// The same plan, quiet enough to be written.
    ///
    /// A mix that already fits comes back untouched: nothing is ever quietly
    /// turned down. A mix that is over has every level multiplied by the same
    /// number, so the balance between the layers and the shape of every fade
    /// survive — it is the whole thing brought down, not a limiter chewing at
    /// the loud parts.
    public static func limited(_ mix: [AudioMixSegment],
                               peaks: [UUID: Waveform]) -> [AudioMixSegment] {
        limited(mix, by: reading(of: mix, peaks: peaks).trim)
    }

    /// The same plan with every level multiplied by one number.
    public static func limited(_ mix: [AudioMixSegment], by trim: Double) -> [AudioMixSegment] {
        guard trim.isFinite, trim < 1, trim >= 0 else { return mix }
        return mix.map { segment in
            AudioMixSegment(
                layerID: segment.layerID, sound: segment.sound,
                startMS: segment.startMS, lengthMS: segment.lengthMS,
                sourceInMS: segment.sourceInMS, sourceLengthMS: segment.sourceLengthMS,
                speedPercent: segment.speedPercent,
                ramps: segment.ramps.map {
                    AudioGainRamp(fromMS: $0.fromMS, toMS: $0.toMS,
                                  fromGain: $0.fromGain * trim, toGain: $0.toGain * trim)
                })
        }
    }

    // MARK: - Drawing it

    /// Where a level sits on the meter, nought at the bottom and one at the top.
    ///
    /// In decibels rather than straight gain, because straight gain spends
    /// three quarters of the meter on the top six decibels and leaves a voice
    /// at a sensible level sitting on the floor. Forty eight decibels of range
    /// puts the ceiling a little under the top and gives the quiet end
    /// somewhere to move.
    public static func meterFraction(ofLevel level: Double) -> Double {
        guard level > 0, level.isFinite else { return 0 }
        let dB = 20 * log10(level)
        let through = (dB - meterFloorDB) / (meterTopDB - meterFloorDB)
        return min(max(0, through), 1)
    }
}
