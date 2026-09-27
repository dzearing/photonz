import Foundation

// Export keeps to the In and Out marks.
//
// Premiere's Export writes Source In/Out whenever the marks are set, and Entire
// Source when asked. Here the same: the file starts at the In and stops at the
// Out, with a way on the sheet to write the whole video instead.
//
// **The document is not trimmed to do it.** A copy of the document with the
// stretches either side taken out would re-base anything cut at the In (a title
// fading in from its own start would fade in again at the new one), and the
// file would no longer be the window's pictures. So the export keeps the whole
// document and moves its CLOCK: the picture at moment t of the file is the
// document's at In + t (`VideoFramePlan.documentTimeMS(at:)`), and the sound
// and a subtitle file beside the film are the same mix and the same cues,
// cut to the stretch and moved earlier by the In.

/// Which stretch of a document an export writes.
public enum VideoExportRange: String, Hashable, Sendable, CaseIterable {
    /// What the In and the Out enclose, or the whole document when neither
    /// is set.
    case marked
    /// All of it, marks or no marks.
    case whole

    /// The word on the sheet's Range row.
    public var title: String {
        switch self {
        case .marked: "In to Out"
        case .whole: "Whole video"
        }
    }
}

extension PhotonzDocument {

    /// The stretch of the document an export of `range` writes.
    public func exportRangeMS(_ range: VideoExportRange) -> Range<Int> {
        let whole = 0..<max(0, documentDurationMS)
        guard range == .marked, let marked = markedRangeMS else { return whole }
        return marked.clamped(to: whole)
    }

    /// Whether the marks enclose something other than the whole document, so
    /// the sheet has a choice to offer: marks around all of it write the same
    /// file either way.
    public var offersMarkedExport: Bool {
        exportRangeMS(.marked) != exportRangeMS(.whole)
    }

    /// How long captions are on screen inside a stretch, in seconds: what the
    /// sheet counts when a marked export has captions burned in.
    public func captionedSeconds(in range: Range<Int>) -> TimeInterval {
        captionLayers.reduce(0) { total, layer in
            guard let time = layer.time else { return total }
            let from = max(time.inMS, range.lowerBound)
            let to = min(time.outMS, range.upperBound)
            return total + Double(max(0, to - from)) / 1000
        }
    }
}

extension AudioMixSegment {

    /// The mix a file of `range` carries: every piece cut to the stretch, on a
    /// clock that starts at its start. A piece outside it is left out, one
    /// across an end reads less of its file, and a fade cut part way starts at
    /// the level it had reached there.
    public static func windowed(_ mix: [AudioMixSegment], to range: Range<Int>) -> [AudioMixSegment] {
        mix.compactMap { $0.windowed(to: range) }
    }

    /// This piece cut to a stretch and moved earlier by its start, or nil
    /// where none of it falls inside.
    public func windowed(to range: Range<Int>) -> AudioMixSegment? {
        let from = max(startMS, range.lowerBound)
        let to = min(endMS, range.upperBound)
        guard to > from, lengthMS > 0 else { return nil }
        let shift = range.lowerBound
        // The file is read at its own pace against the timeline's: a piece at
        // 200% reads two milliseconds of file for every one it plays.
        let pace = Double(sourceLengthMS) / Double(lengthMS)
        let head = from - startMS
        let readIn = sourceInMS + Int((Double(head) * pace).rounded())
        let readLength = max(1, Int((Double(to - from) * pace).rounded()))
        var cut: [AudioGainRamp] = ramps.compactMap { ramp in
            let rampFrom = max(ramp.fromMS, from)
            let rampTo = min(ramp.toMS, to)
            guard rampTo > rampFrom else { return nil }
            return AudioGainRamp(fromMS: rampFrom - shift, toMS: rampTo - shift,
                                 fromGain: ramp.gain(atMS: rampFrom),
                                 toGain: ramp.gain(atMS: rampTo))
        }
        // The level end to end with no hole in it, as every piece promises.
        if cut.isEmpty {
            let level = gain(atMS: from)
            cut = [AudioGainRamp(fromMS: from - shift, toMS: to - shift,
                                 fromGain: level, toGain: level)]
        }
        return AudioMixSegment(layerID: layerID, sound: sound,
                               startMS: from - shift, lengthMS: to - from,
                               sourceInMS: readIn, sourceLengthMS: readLength,
                               speedPercent: speedPercent, ramps: cut, voice: voice)
    }
}

extension CaptionCue {

    /// The cues a subtitle file beside a film of `range` carries: each one cut
    /// to the stretch, keeping only the words said inside it, on a clock that
    /// starts at its start.
    public static func windowed(_ cues: [CaptionCue], to range: Range<Int>) -> [CaptionCue] {
        let shift = range.lowerBound
        return cues.compactMap { cue in
            let from = max(cue.inMS, range.lowerBound)
            let to = min(cue.outMS, range.upperBound)
            guard to > from else { return nil }
            let words = cue.words.compactMap { word -> TranscribedWord? in
                guard word.endMS > range.lowerBound, word.startMS < range.upperBound else { return nil }
                var moved = word
                moved.startMS = max(word.startMS, range.lowerBound) - shift
                moved.endMS = min(word.endMS, range.upperBound) - shift
                return moved
            }
            guard !words.isEmpty else { return nil }
            return CaptionCue(words: words, inMS: from - shift, outMS: to - shift)
        }
    }
}
