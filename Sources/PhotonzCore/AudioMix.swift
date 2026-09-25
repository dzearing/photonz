import Foundation

// How loud a layer plays, and the one plan both playing and exporting read
// (`docs/design/video-audio.md`).
//
// The acceptance item nobody can settle by ear is *what you hear while playing
// matches what exports*. The way it is settled here is by leaving nothing to
// agree about: **`audioMix()` is the only answer to what plays, and the player
// and the exporter are both handed it.** Neither works anything out for itself,
// so neither can drift from the other.
//
// Underneath, a fade and a duck are the same thing: a level that changes as
// the layer runs. A fade in is a point at nought and a point at full a second
// and a half later; a duck is a point either side of a dip. So the model is a
// fader and points, and the panel's Fades section (`pages/video-audio.html`)
// reads its In and Out off those points and writes them back as points. The
// one thing a point cannot say is the SHAPE of the rise, so that is the one
// thing kept beside them: `fadeCurve`, which bends the two fade stretches and
// nothing else.

/// One moment where the level is a known value, measured from the layer's own
/// start rather than the document's, so moving a layer takes its shape along.
public struct AudioLevelPoint: Hashable, Codable, Sendable, Comparable {
    public var atMS: Int
    /// Nought is silence, one is the level it was recorded at.
    public var gain: Double

    public init(atMS: Int, gain: Double) {
        self.atMS = max(0, atMS)
        self.gain = AudioLevel.bounded(gain)
    }

    public static func < (a: AudioLevelPoint, b: AudioLevelPoint) -> Bool { a.atMS < b.atMS }
}

/// How loud a layer plays: a fader, and a shape it follows as it runs.
///
/// The two multiply. The fader is the level of the whole thing, the points are
/// where it goes up and down inside that, and pulling the fader down takes the
/// whole shape with it — which is what a person means by turning the music
/// down when the music is already ducking under a voice.
public struct AudioLevel: Hashable, Codable, Sendable {

    /// The level a sound plays at when nobody has touched it.
    public static let unityGain: Double = 1
    /// As loud as anything may be asked to play: twice, which is six decibels
    /// of room. Past that a level control is a distortion control.
    public static let loudestGain: Double = 2

    /// The fader: the level of the whole layer.
    public var gain: Double
    /// Where the level is pinned as the layer runs, in order, one per moment.
    public private(set) var points: [AudioLevelPoint]
    /// How the fade in rises and the fade out falls, from the one list of
    /// curves (`EasingCurve`). The fade out is the fade in played backwards,
    /// as the mock draws it. Straight unless somebody picked one, which is
    /// what every fade written before the curve existed does.
    public var fadeCurve: EasingCurve

    public init(gain: Double = AudioLevel.unityGain, points: [AudioLevelPoint] = [],
                fadeCurve: EasingCurve = .linear) {
        self.gain = Self.bounded(gain)
        self.points = Self.tidied(points)
        self.fadeCurve = fadeCurve
    }

    /// A level held inside what a level control may ask for.
    public static func bounded(_ gain: Double) -> Double {
        guard gain.isFinite else { return unityGain }
        return min(max(0, gain), loudestGain)
    }

    /// In time order, one per moment: a second point where one already is
    /// replaces it, so a curve can never double back on itself.
    static func tidied(_ points: [AudioLevelPoint]) -> [AudioLevelPoint] {
        var byMoment: [Int: AudioLevelPoint] = [:]
        for point in points { byMoment[point.atMS] = point }
        return byMoment.values.sorted()
    }

    // MARK: - Reading it

    /// Whether this layer makes no sound at all however it is asked.
    public var isSilent: Bool {
        gain == 0 || (!points.isEmpty && points.allSatisfy { $0.gain == 0 })
    }

    /// Whether the level changes as the layer runs.
    public var changesOverTime: Bool { points.count > 1 && !isSilent }

    /// How loud the layer is this far into itself.
    ///
    /// Before the first point and after the last the level HOLDS, which is what
    /// makes a duck stay ducked until somebody brings it back rather than
    /// sliding away on its own.
    public func gain(atLayerMS ms: Int) -> Double {
        gain * shape(atLayerMS: ms)
    }

    /// The points' own answer, before the fader is applied.
    public func shape(atLayerMS ms: Int) -> Double {
        guard let first = points.first, let last = points.last else { return 1 }
        if ms <= first.atMS { return first.gain }
        if ms >= last.atMS { return last.gain }
        guard let next = points.firstIndex(where: { $0.atMS > ms }), next > 0 else { return last.gain }
        let before = points[next - 1], after = points[next]
        let span = after.atMS - before.atMS
        guard span > 0 else { return after.gain }
        let through = Double(ms - before.atMS) / Double(span)
        if fadeCurve != .linear {
            // A curve can overshoot on its way; it may never ask for less
            // than silence.
            if next == 1, fadeInStretch != nil {
                return max(0, after.gain * fadeCurve.value(at: through))
            }
            if next == points.count - 1, fadeOutStretch != nil {
                return max(0, before.gain * fadeCurve.value(at: 1 - through))
            }
        }
        return before.gain + (after.gain - before.gain) * through
    }

    /// The fade in as it stands in the points: silence pinned at the very
    /// start and the next point up.
    private var fadeInStretch: ClosedRange<Int>? {
        guard points.count >= 2, points[0].atMS == 0, points[0].gain == 0, points[1].gain > 0
        else { return nil }
        return 0...points[1].atMS
    }

    /// The fall into silence the points end on. Read off the points alone, so
    /// it bends what is heard wherever the layer's end has since been moved.
    private var fadeOutStretch: ClosedRange<Int>? {
        guard points.count >= 2, let last = points.last, last.gain == 0 else { return nil }
        let before = points[points.count - 2]
        guard before.gain > 0, before.atMS < last.atMS else { return nil }
        return before.atMS...last.atMS
    }

    /// The moments the level turns a corner between `fromMS` and `toMS`, both
    /// ends included, in order: every point, and along a curved fade enough
    /// moments that straight lines between them follow the curve. The lane
    /// draws its line through these and the mix plays a ramp between each two,
    /// so what is drawn and what is heard are the same shape.
    public func moments(fromMS: Int, toMS: Int) -> [Int] {
        guard toMS > fromMS else { return [fromMS] }
        var found = Set([fromMS, toMS])
        for point in points where point.atMS > fromMS && point.atMS < toMS { found.insert(point.atMS) }
        if fadeCurve != .linear {
            for stretch in [fadeInStretch, fadeOutStretch].compactMap({ $0 }) {
                let span = stretch.upperBound - stretch.lowerBound
                let steps = min(Self.curveSteps, max(1, span / Self.shortestCurveStepMS))
                for step in 1..<max(steps, 1) {
                    let ms = stretch.lowerBound + span * step / steps
                    if ms > fromMS && ms < toMS { found.insert(ms) }
                }
            }
        }
        return found.sorted()
    }

    /// How finely a curved fade is followed: at most this many straight
    /// pieces, none shorter than `shortestCurveStepMS`. Forty over a second
    /// and a half is under forty milliseconds a piece, which the ear cannot
    /// tell from the curve itself.
    static let curveSteps = 40
    static let shortestCurveStepMS = 10

    // MARK: - Editing it

    /// Pin the level at a moment. A point where one already is moves it.
    public mutating func setPoint(atMS ms: Int, gain: Double) {
        points = Self.tidied(points + [AudioLevelPoint(atMS: ms, gain: gain)])
    }

    /// Take a point out. The level between its neighbours closes up by itself,
    /// because there is nothing between them any more.
    public mutating func removePoint(atMS ms: Int) {
        points.removeAll { $0.atMS == ms }
    }

    public mutating func clearPoints() { points = [] }

    /// Whether this is the level a layer has when nobody has touched it, which
    /// is what decides whether it is written down at all.
    public var isUntouched: Bool { gain == Self.unityGain && points.isEmpty && fadeCurve == .linear }

    // MARK: - Fades

    /// How long the sound takes to rise out of silence at its start: silence
    /// pinned at the very start and the next point up at the level. Nought
    /// where it starts at its level.
    public var fadeInMS: Int {
        guard points.count >= 2, points[0].atMS == 0, points[0].gain == 0, points[1].gain > 0
        else { return 0 }
        return points[1].atMS
    }

    /// How long the sound takes to fall into silence at its end, for a layer
    /// `lengthMS` long: silence pinned at (or past) the end, and the point
    /// before it up at the level.
    public func fadeOutMS(lengthMS: Int) -> Int {
        guard points.count >= 2, let last = points.last, last.gain == 0, last.atMS >= lengthMS
        else { return 0 }
        let before = points[points.count - 2]
        guard before.gain > 0 else { return 0 }
        return max(0, lengthMS - before.atMS)
    }

    /// Fade in over `ms`, which is two points: silence at the start and the
    /// level the shape already had at `ms`, so a duck after it is kept.
    /// Nought takes the fade away. It never runs into the fade out.
    public mutating func setFadeIn(_ ms: Int, lengthMS: Int) {
        let fadeOut = fadeOutMS(lengthMS: lengthMS)
        if fadeInMS > 0 { points.removeFirst(2) }
        let length = min(max(0, ms), max(0, lengthMS - fadeOut))
        guard length > 0 else { return }
        let top = shape(atLayerMS: length)
        points = Self.tidied(points.filter { $0.atMS > length }
            + [AudioLevelPoint(atMS: 0, gain: 0), AudioLevelPoint(atMS: length, gain: top)])
    }

    /// Fade out over the last `ms` of a layer `lengthMS` long: the level the
    /// shape had there, falling to silence at the end.
    public mutating func setFadeOut(_ ms: Int, lengthMS: Int) {
        let fadeIn = fadeInMS
        if fadeOutMS(lengthMS: lengthMS) > 0 { points.removeLast(2) }
        let length = min(max(0, ms), max(0, lengthMS - fadeIn))
        guard length > 0 else { return }
        let start = lengthMS - length
        let top = shape(atLayerMS: start)
        points = Self.tidied(points.filter { $0.atMS < start }
            + [AudioLevelPoint(atMS: start, gain: top), AudioLevelPoint(atMS: lengthMS, gain: 0)])
    }

    // MARK: - Saying it out loud

    /// A fade's length as the Fades section says it: seconds, one place.
    public static func fadeLabel(ms: Int) -> String {
        String(format: "%.1fs", Double(max(0, ms)) / 1000)
    }

    /// A fade length somebody typed, in seconds, with or without the s.
    /// Below nought is nought; anything that is not a number is nil.
    public static func fadeMS(typed: String) -> Int? {
        var text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasSuffix("s") { text = String(text.dropLast()).trimmingCharacters(in: .whitespaces) }
        guard let seconds = Double(text), seconds.isFinite else { return nil }
        return max(0, Int((seconds * 1000).rounded()))
    }

    /// A level in decibels, or nil for silence, which has no number.
    public static func decibels(forGain gain: Double) -> Double? {
        guard gain > 0 else { return nil }
        return 20 * log10(gain)
    }

    public static func gain(forDecibels dB: Double) -> Double {
        bounded(pow(10, dB / 20))
    }

    /// What the panel says: `0.0 dB` at the level it was recorded at, and
    /// `Silent` where there is no number to give.
    public var label: String {
        guard let dB = Self.decibels(forGain: gain) else { return "Silent" }
        return String(format: "%.1f dB", dB)
    }

    private enum CodingKeys: String, CodingKey { case gain, points, fadeCurve }

    /// A level nobody has touched writes nothing, so every document written
    /// before sound existed reads back identical.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if gain != Self.unityGain { try c.encode(gain, forKey: .gain) }
        if !points.isEmpty { try c.encode(points, forKey: .points) }
        if fadeCurve != .linear { try c.encode(fadeCurve, forKey: .fadeCurve) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(gain: try c.decodeIfPresent(Double.self, forKey: .gain) ?? Self.unityGain,
                  points: try c.decodeIfPresent([AudioLevelPoint].self, forKey: .points) ?? [],
                  fadeCurve: try c.decodeIfPresent(EasingCurve.self, forKey: .fadeCurve) ?? .linear)
    }
}

// MARK: - The plan

/// A stretch over which the level slides from one value to another, in the
/// DOCUMENT's own clock.
///
/// Said this way on purpose: it is exactly what an export's volume ramps take,
/// and exactly what the player needs to know to follow the same shape live.
public struct AudioGainRamp: Hashable, Sendable {
    public let fromMS: Int
    public let toMS: Int
    public let fromGain: Double
    public let toGain: Double

    public init(fromMS: Int, toMS: Int, fromGain: Double, toGain: Double) {
        self.fromMS = fromMS
        self.toMS = max(fromMS, toMS)
        self.fromGain = fromGain
        self.toGain = toGain
    }

    public var isFlat: Bool { fromGain == toGain }

    public func gain(atMS ms: Int) -> Double {
        guard toMS > fromMS else { return toGain }
        let through = Double(min(max(fromMS, ms), toMS) - fromMS) / Double(toMS - fromMS)
        return fromGain + (toGain - fromGain) * through
    }
}

/// One piece of sound that plays: which file, where it lands, what it reads,
/// how fast, and how loud it is the whole way through.
///
/// **This is the whole of what plays.** The player schedules these and the
/// exporter writes these, which is what makes what you hear and what you export
/// the same thing rather than two implementations of the same intention.
public struct AudioMixSegment: Hashable, Sendable {
    public let layerID: UUID
    public let sound: SoundRef
    /// Where it lands on the document's timeline.
    public let startMS: Int
    public let lengthMS: Int
    /// Where in the file it reads from, and how much of the file that is.
    public let sourceInMS: Int
    public let sourceLengthMS: Int
    /// 100 is the speed it was recorded at. The sound goes with the picture, so
    /// a piece sped up rises in pitch (`ClipPiece.soundRatePercent`).
    public let speedPercent: Int
    /// The level end to end, with no hole in it: the first ramp starts at
    /// `startMS` and the last ends at `endMS`.
    public let ramps: [AudioGainRamp]

    public init(layerID: UUID, sound: SoundRef, startMS: Int, lengthMS: Int,
                sourceInMS: Int, sourceLengthMS: Int, speedPercent: Int,
                ramps: [AudioGainRamp]) {
        self.layerID = layerID
        self.sound = sound
        self.startMS = startMS
        self.lengthMS = lengthMS
        self.sourceInMS = sourceInMS
        self.sourceLengthMS = sourceLengthMS
        self.speedPercent = speedPercent
        self.ramps = ramps
    }

    public var endMS: Int { startMS + lengthMS }
    public var sourceOutMS: Int { sourceInMS + sourceLengthMS }

    public func contains(ms: Int) -> Bool { ms >= startMS && ms < endMS }

    /// How loud this piece is at a moment of the document.
    public func gain(atMS ms: Int) -> Double {
        guard let first = ramps.first else { return 1 }
        if ms <= first.fromMS { return first.fromGain }
        guard let ramp = ramps.last(where: { $0.fromMS <= ms }) else { return first.fromGain }
        return ramp.gain(atMS: ms)
    }

    /// Whether anything can be heard here at all.
    public var isAudible: Bool { ramps.contains { $0.fromGain > 0 || $0.toGain > 0 } }
}

extension PhotonzDocument {

    /// Everything that plays, in one list.
    ///
    /// One entry per piece of every layer that has a sound, is switched on, and
    /// is not pulled all the way down. A held frame contributes nothing,
    /// because one frame has no sound under it.
    public func audioMix() -> [AudioMixSegment] {
        // A muted or outsoloed track is not heard (`DocumentTracks.swift`).
        let silenced = layersSilencedByTrack()
        // Visited rather than flattened: asked on every step of the playhead,
        // and a captioned talk has 170 layers with no sound to copy past.
        var mix: [AudioMixSegment] = []
        forEachLayer { layer in
            guard let sound = layer.sound, layer.isVisible, !silenced.contains(layer.id),
                  let time = layer.time,
                  let pieces = layer.clipPieces
            else { return }
            let level = layer.soundLevel ?? AudioLevel()
            guard !level.isSilent else { return }
            mix += pieces.playback.compactMap { piece in
                guard piece.playsSound else { return nil }
                let start = time.inMS + piece.startMS
                return AudioMixSegment(
                    layerID: layer.id, sound: sound,
                    startMS: start, lengthMS: piece.lengthMS,
                    sourceInMS: piece.sourceInMS, sourceLengthMS: piece.sourceLengthMS,
                    speedPercent: piece.speedPercent,
                    ramps: Self.ramps(for: level, startMS: start, lengthMS: piece.lengthMS,
                                      layerInMS: time.inMS))
            }
        }
        return mix
    }

    /// What can be heard at a moment: everything laid over it, which is what a
    /// mix is. Empty where there is nothing but picture.
    public func audioMix(atMS ms: Int) -> [AudioMixSegment] {
        audioMix().filter { $0.contains(ms: ms) }
    }

    /// The level over one piece, as ramps on the document's own clock.
    ///
    /// Every corner that falls inside the piece becomes a boundary (every
    /// point, and the steps along a curved fade), and the stretches either
    /// side of them are ramps, so the list covers the piece end
    /// to end with no hole in it. A level nobody has shaped comes back as one
    /// flat ramp, which keeps the player and the exporter from ever needing a
    /// special case for the ordinary thing.
    static func ramps(for level: AudioLevel, startMS: Int, lengthMS: Int,
                      layerInMS: Int) -> [AudioGainRamp] {
        let endMS = startMS + lengthMS
        // Points are measured from the layer's start; the ramps are measured
        // from the document's, so every moment moves along by the layer's in.
        // The same corners the lane draws, so a curved fade plays as drawn.
        let moments = level.moments(fromMS: startMS - layerInMS, toMS: endMS - layerInMS)
            .map { layerInMS + $0 }
        guard moments.count > 1 else {
            let gain = level.gain(atLayerMS: startMS - layerInMS)
            return [AudioGainRamp(fromMS: startMS, toMS: endMS, fromGain: gain, toGain: gain)]
        }
        return (0..<(moments.count - 1)).map { index in
            let from = moments[index], to = moments[index + 1]
            return AudioGainRamp(fromMS: from, toMS: to,
                                 fromGain: level.gain(atLayerMS: from - layerInMS),
                                 toGain: level.gain(atLayerMS: to - layerInMS))
        }
    }
}
