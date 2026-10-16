import Foundation

// A transition carries the sound across the cut too (`docs/design/video-audio.md`).
//
// A dissolve that blends the picture while the sound jumps at the edit point
// is half a transition: the export has a hard audio cut, often a click, in the
// middle of a smooth picture change. So the transition on a cut shapes the
// sound of the two pieces it joins, and it does it in the one plan the player
// and the exporter both read (`PhotonzDocument.audioMix()`), which is what
// keeps what plays and what exports the same blend.
//
// Two rules, the same two the picture follows (`ClipTransitions.swift`):
//
// - **A kind that puts both shots on screen puts both sounds in the ear.** The
//   outgoing sound runs on past its out point and the incoming one starts
//   before its in point, out of the very spare the picture spends, and the two
//   cross over at equal power, the way Premiere's Constant Power crossfade and
//   Final Cut's +3 dB fade do. Equal power rather than straight lines, because
//   two different sounds faded in straight lines sag by three decibels in the
//   middle, which is the dip an editor hears and reaches to fix.
// - **A dip takes the sound through silence with the picture.** Nothing is
//   spent: each side fades inside the time it already has.
//
// A cut whose two sides read the same frames (a plain split) is left alone:
// both readings are the same samples, so cross-fading them only colours them.
// And only a clip's OWN sound is shaped. Sound taken off onto its own layer,
// and music nobody linked to anything, are not a side of any cut.
//
// **The seam either side of a stretch cleaned on its own** (Clean Noise in
// Section, `RangeSection.swift`) is the one cut with no transition on it that
// is shaped all the same. Its two sides read the same frames, but one reads
// them from the cleaned copy, so switching at the cut drops the room tone from
// one sample to the next: a click. The two readings overlap for a short fixed
// time centred on the cut (`SectionCleaningSeam`) and fade in straight lines,
// not at equal power, because they are two readings of the same recording:
// the voice in them is the same voice, and straight lines keep it at its
// level where equal power would swell it by three decibels mid-way. A cut
// somebody put a dip on keeps the dip, which already goes through silence.

/// Which side of a cut a sound is on.
public enum TransitionSoundSide: Hashable, Sendable {
    case outgoing, incoming
}

extension ClipTransition {

    /// How loud one side's sound is at a moment of a transition on a cut at
    /// `cutAtMS`, nought to one, before anything else about its level.
    ///
    /// Outside the transition each side is at its own level where it plays:
    /// the outgoing one full before, the incoming one full after.
    public func soundGain(atMS ms: Int, cutAtMS: Int, side: TransitionSoundSide) -> Double {
        if kind.needsOverlap {
            let through = Self.progress(atMS: ms, cutAtMS: cutAtMS, self)
            return side == .outgoing ? cos(through * .pi / 2) : sin(through * .pi / 2)
        }
        let dipped = 1 - Self.dipAmount(atMS: ms, cutAtMS: cutAtMS, self)
        switch side {
        case .outgoing: return ms < cutAtMS ? dipped : 0
        case .incoming: return ms < cutAtMS + holdMS ? 0 : dipped
        }
    }

    /// The moments the sound's level turns a corner over a transition on a
    /// cut at `cutAtMS`: enough along a cross-fade that straight ramps between
    /// them follow the curve, by the same measure a curved fade is followed
    /// (`AudioLevel.moments`), and the three corners of a dip.
    func soundMoments(cutAtMS: Int) -> [Int] {
        let from = cutAtMS - beforeMS, to = cutAtMS + holdMS + afterMS
        guard kind.needsOverlap else {
            return holdMS > 0 ? [from, cutAtMS, cutAtMS + holdMS, to] : [from, cutAtMS, to]
        }
        let steps = min(AudioLevel.curveSteps, max(1, lengthMS / AudioLevel.shortestCurveStepMS))
        return (0...steps).map { from + lengthMS * $0 / steps } + [to]
    }
}

/// The ease either side of a stretch of sound cleaned on its own.
public enum SectionCleaningSeam {

    /// How long the two readings overlap, centred on the cut: long enough
    /// that the room tone slides rather than steps, short enough that the
    /// cleaning still starts where the range does.
    public static let lengthMS = 200

    /// Half the seam, either side of a cut between `outgoing` and `incoming`:
    /// never more than half of either piece, so a short stretch eases over no
    /// more than itself.
    static func halfMS(outgoing: ClipPiece, incoming: ClipPiece) -> Int {
        min(lengthMS / 2, outgoing.lengthMS / 2, incoming.lengthMS / 2)
    }

    /// How loud one side is at a moment of a seam of `halfMS` either side of
    /// a cut at `cutAtMS`, nought to one: straight lines that always add up
    /// to one.
    static func gain(atMS ms: Int, cutAtMS: Int, halfMS: Int, side: TransitionSoundSide) -> Double {
        let through = halfMS <= 0 ? (ms < cutAtMS ? 0.0 : 1.0)
            : min(1, max(0, Double(ms - (cutAtMS - halfMS)) / Double(2 * halfMS)))
        return side == .outgoing ? 1 - through : through
    }
}

/// What shapes the sound over one cut: a transition somebody put on it, or the
/// seam either side of a stretch cleaned on its own.
enum SoundCrossingShape {
    case transition(ClipTransition)
    case cleaningSeam(halfMS: Int)

    /// How far the outgoing side runs on past the cut and the incoming one
    /// starts before it, where both sound at once; nil where each stays
    /// inside its own time.
    var overlap: (beforeMS: Int, afterMS: Int)? {
        switch self {
        case .transition(let transition):
            transition.kind.needsOverlap ? (transition.beforeMS, transition.afterMS) : nil
        case .cleaningSeam(let half): (half, half)
        }
    }

    func gain(atMS ms: Int, cutAtMS: Int, side: TransitionSoundSide) -> Double {
        switch self {
        case .transition(let transition): transition.soundGain(atMS: ms, cutAtMS: cutAtMS, side: side)
        case .cleaningSeam(let half):
            SectionCleaningSeam.gain(atMS: ms, cutAtMS: cutAtMS, halfMS: half, side: side)
        }
    }

    /// Where the level turns a corner: straight lines need only their ends.
    func moments(cutAtMS: Int) -> [Int] {
        switch self {
        case .transition(let transition): transition.soundMoments(cutAtMS: cutAtMS)
        case .cleaningSeam(let half): [cutAtMS - half, cutAtMS + half]
        }
    }
}

/// One piece of one layer, the way a transition names a side of its cut.
struct TransitionSoundPiece: Hashable {
    let layerID: UUID
    let index: Int
}

/// Where a piece's sound landed in the mix, and what re-shaping it needs.
struct HeardPiece {
    let at: Int
    let level: AudioLevel
    let layerInMS: Int
}

/// A cut whose sound is shaped: the two pieces it joins, where the cut is on
/// the document's clock, and what shapes it.
struct TransitionSoundCrossing {
    let outgoing: TransitionSoundPiece
    let incoming: TransitionSoundPiece
    let cutAtMS: Int
    let shape: SoundCrossingShape

    /// Whether this is a join inside one clip, whose two sides are two voices
    /// of the one layer.
    var isInsideOneClip: Bool { outgoing.layerID == incoming.layerID }
}

extension PhotonzDocument {

    /// The joins inside one clip whose sound is shaped: the transitions on
    /// them, and, where `seams` says the stretches cleaned on their own are
    /// heard, the seam either side of each.
    static func soundCrossings(inClip id: UUID, pieces: ClipPieces,
                               inMS: Int, seams: Bool = false) -> [TransitionSoundCrossing] {
        pieces.cuts.compactMap { cut in
            let shape: SoundCrossingShape
            if let drawn = cut.drawnTransition, !(drawn.kind.needsOverlap && cut.isContinuous) {
                shape = .transition(drawn)
            } else if seams, cut.isContinuous,
                      cut.outgoing.noiseReduction != cut.incoming.noiseReduction {
                shape = .cleaningSeam(halfMS: SectionCleaningSeam.halfMS(outgoing: cut.outgoing,
                                                                          incoming: cut.incoming))
            } else {
                return nil
            }
            return TransitionSoundCrossing(
                outgoing: TransitionSoundPiece(layerID: id, index: cut.index - 1),
                incoming: TransitionSoundPiece(layerID: id, index: cut.index),
                cutAtMS: inMS + cut.atMS, shape: shape)
        }
    }

    /// The transitions on the edit points between clips that shape their
    /// sound: exactly the ones the picture draws (`editPointMoments`).
    func editPointSoundCrossings() -> [TransitionSoundCrossing] {
        guard hasEditPointTransitions else { return [] }
        return layers.compactMap { incoming in
            guard incoming.arrivalTransition != nil,
                  let trackID = trackID(ofClip: incoming.id),
                  let point = editPoints(onTrack: trackID).first(where: { $0.incoming == incoming.id }),
                  let cut = editPointCut(outgoing: point.outgoing, incoming: incoming.id),
                  let drawn = cut.drawnTransition,
                  !(drawn.kind.needsOverlap && cut.isContinuous),
                  let outPieces = layer(id: point.outgoing)?.clipPieces else { return nil }
            return TransitionSoundCrossing(
                outgoing: TransitionSoundPiece(layerID: point.outgoing, index: outPieces.count - 1),
                incoming: TransitionSoundPiece(layerID: incoming.id, index: 0),
                cutAtMS: cut.atMS, shape: .transition(drawn))
        }
    }

    /// `mix` with every crossing heard: each side stretched into the spare it
    /// spends and shaped by the transition, on top of its own level.
    ///
    /// Everything a piece needs is gathered before it is rebuilt, because a
    /// piece between two transitions is the incoming side of one and the
    /// outgoing side of the next, and both have to shape it.
    static func carryingTransitions(_ crossings: [TransitionSoundCrossing],
                                    over mix: [AudioMixSegment],
                                    heard: [TransitionSoundPiece: HeardPiece]) -> [AudioMixSegment] {
        var reshapes: [Int: Reshape] = [:]
        for crossing in crossings {
            let shape = crossing.shape
            let out = heard[crossing.outgoing], into = heard[crossing.incoming]
            if let out {
                reshapes[out.at, default: Reshape(heard: out)].shapes.append(
                    (crossing.cutAtMS, shape, .outgoing))
                if let overlap = shape.overlap { reshapes[out.at]?.runOnMS = overlap.afterMS }
            }
            if let into {
                reshapes[into.at, default: Reshape(heard: into)].shapes.append(
                    (crossing.cutAtMS, shape, .incoming))
                if let overlap = shape.overlap {
                    reshapes[into.at]?.earlyMS = overlap.beforeMS
                    // Two pieces of one clip sounding at once each get a
                    // fader: the incoming one takes the voice the outgoing
                    // one is not on. The joins are visited in order, so a
                    // run of them alternates.
                    if crossing.isInsideOneClip, let out {
                        let outVoice = reshapes[out.at]?.voice ?? 0
                        reshapes[into.at]?.voice = 1 - outVoice
                    }
                }
            }
        }
        guard !reshapes.isEmpty else { return mix }
        return mix.enumerated().map { index, segment in
            reshapes[index].map { $0.applied(to: segment) } ?? segment
        }
    }

    /// What the transitions either side of one piece do to its sound.
    struct Reshape {
        let heard: HeardPiece
        var earlyMS = 0
        var runOnMS = 0
        var voice = 0
        var shapes: [(cutAtMS: Int, shape: SoundCrossingShape, side: TransitionSoundSide)] = []

        init(heard: HeardPiece) { self.heard = heard }

        func applied(to segment: AudioMixSegment) -> AudioMixSegment {
            let speed = segment.speedPercent
            // Never reading outside the file. The cut only offers a transition
            // the recording has the spare for, so this holds by construction;
            // it is here so a file shorter than it said cannot be over-read.
            var early = earlyMS, runOn = runOnMS
            if ClipPiece.scaled(early, byPercent: speed) > segment.sourceInMS {
                early = ClipPiece.unscaled(segment.sourceInMS, byPercent: speed)
            }
            let left = max(0, segment.sound.durationMS - segment.sourceOutMS)
            if ClipPiece.scaled(runOn, byPercent: speed) > left {
                runOn = ClipPiece.unscaled(left, byPercent: speed)
            }
            let earlySource = ClipPiece.scaled(early, byPercent: speed)
            let start = segment.startMS - early
            let length = segment.lengthMS + early + runOn
            let end = start + length

            // The piece's own level over the longer stretch, then the
            // transitions laid over it, sampled at every corner of either.
            let own = AudioMixSegment(
                layerID: segment.layerID, sound: segment.sound, startMS: start, lengthMS: length,
                sourceInMS: 0, sourceLengthMS: 0, speedPercent: speed,
                ramps: PhotonzDocument.ramps(for: heard.level, startMS: start, lengthMS: length,
                                             layerInMS: heard.layerInMS))
            var moments = Set(own.ramps.map(\.fromMS) + [end])
            for shape in shapes {
                for ms in shape.shape.moments(cutAtMS: shape.cutAtMS) where ms > start && ms < end {
                    moments.insert(ms)
                }
            }
            let sorted = moments.sorted()
            func gain(_ ms: Int) -> Double {
                shapes.reduce(own.gain(atMS: ms)) {
                    $0 * $1.shape.gain(atMS: ms, cutAtMS: $1.cutAtMS, side: $1.side)
                }
            }
            let ramps = zip(sorted, sorted.dropFirst()).map { from, to in
                AudioGainRamp(fromMS: from, toMS: to, fromGain: gain(from), toGain: gain(to))
            }
            return AudioMixSegment(
                layerID: segment.layerID, sound: segment.sound,
                startMS: start, lengthMS: length,
                sourceInMS: segment.sourceInMS - earlySource,
                sourceLengthMS: segment.sourceLengthMS + earlySource
                    + ClipPiece.scaled(runOn, byPercent: speed),
                speedPercent: speed, ramps: ramps, voice: voice)
        }
    }
}
