import Foundation

// Speed stops: one piece whose speed changes across its length
// (`docs/design/mocks/pages/video-speed.html`, Premiere's time remapping).
//
// A plain piece plays at one speed (`ClipPiece.speedPercent`). A piece with
// stops plays at the speed of whichever stop it is passing, and between two
// stops it either eases from one to the next (Ramp) or keeps the first one
// until it reaches the second (Hold). That is the whole of a speed ramp: a
// screen recording sped through a dull stretch and eased back in.
//
// **A stop is nailed to a FRAME of the recording, not to a moment of the
// timeline.** Change one stop's speed and every stop after it travels with
// the frames it was on, the way Premiere's time remap keyframes do; trim or
// split the piece and the stops stay on their frames, so the two halves of a
// split ramp play exactly what the whole did.
//
// **Between stops the speed changes evenly in TIMELINE time.** Watching it,
// the picture speeds up at a steady rate, and the sums close: a ramp from
// speed a to speed b across d of recording takes 2d / (a + b) of timeline,
// with no step, no table and no rounding but the last one.
//
// Before the first stop the piece plays at the first stop's speed, and after
// the last at the last's. Nothing in here is ever pixels.

/// How a piece gets from one stop's speed to the next.
public enum SpeedRampBlend: String, Codable, CaseIterable, Sendable {
    /// Eased: the speed changes evenly from one stop to the next.
    case ramp
    /// Flat: each stretch plays at its first stop's speed.
    case hold

    /// What the panel calls it, in the mock's words.
    public var title: String {
        switch self {
        case .ramp: "Ramp"
        case .hold: "Hold"
        }
    }
}

/// One speed stop: a frame of the recording, and how fast the piece is
/// playing as it passes it.
///
/// **A stop at nought is the mock's Freeze.** The picture eases down to a
/// standstill on the stop's frame and away again, so on its own it shows that
/// one frame for an instant. Held, it stays on that frame for `holdMS` of
/// timeline before it moves off: the mock's two zeros side by side, which in a
/// ramp nailed to frames cannot be two stops (two frames apart at speed nought
/// is a stretch that never ends), so it is one stop that holds.
public struct SpeedStop: Hashable, Codable, Sendable {
    /// The moment of the recording the stop is on.
    public let sourceMS: Int
    /// How fast the piece is playing there, 100 as recorded, 0 a freeze.
    public let speedPercent: Int
    /// How long a stop at nought holds its frame, on the timeline. Always
    /// nought on a stop that moves.
    public let holdMS: Int

    public init(sourceMS: Int, speedPercent: Int, holdMS: Int = 0) {
        self.sourceMS = max(0, sourceMS)
        self.speedPercent = speedPercent <= 0
            ? 0
            : min(max(ClipPiece.slowestPercent, speedPercent), ClipPiece.fastestPercent)
        self.holdMS = self.speedPercent == 0 ? max(0, holdMS) : 0
    }

    /// Whether the picture stops here: the mock's Freeze.
    public var isFreeze: Bool { speedPercent == 0 }

    /// The same stop at another speed. A freeze keeps its hold while it stays
    /// one.
    public func atSpeed(_ percent: Int) -> SpeedStop {
        SpeedStop(sourceMS: sourceMS, speedPercent: percent, holdMS: holdMS)
    }

    /// The same stop holding its frame this long.
    public func holding(_ ms: Int) -> SpeedStop {
        SpeedStop(sourceMS: sourceMS, speedPercent: speedPercent, holdMS: ms)
    }

    /// The same stop on another frame.
    public func onFrame(_ ms: Int) -> SpeedStop {
        SpeedStop(sourceMS: ms, speedPercent: speedPercent, holdMS: holdMS)
    }

    private enum CodingKeys: String, CodingKey { case sourceMS, speedPercent, holdMS }

    /// A stop that holds nothing writes exactly what a stop always wrote.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceMS, forKey: .sourceMS)
        try c.encode(speedPercent, forKey: .speedPercent)
        if holdMS > 0 { try c.encode(holdMS, forKey: .holdMS) }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sourceMS: try c.decode(Int.self, forKey: .sourceMS),
                  speedPercent: try c.decode(Int.self, forKey: .speedPercent),
                  holdMS: try c.decodeIfPresent(Int.self, forKey: .holdMS) ?? 0)
    }
}

/// A piece's speed stops, in the order they are reached, and how it gets from
/// one to the next. Never empty: a piece with no stops carries no ramp at all.
public struct SpeedRamp: Hashable, Codable, Sendable {

    /// The stops, earliest frame first, never two on one frame.
    public let stops: [SpeedStop]
    /// Eased between stops, or flat.
    public let blend: SpeedRampBlend

    /// Nil for no stops at all. Stops given out of order are put in order, and
    /// of two on one frame the one given last is kept. A freeze straight after
    /// another plays at the slowest speed instead: two frames apart at nought
    /// is a stretch that would never end.
    public init?(stops: [SpeedStop], blend: SpeedRampBlend = .ramp) {
        var byFrame: [Int: SpeedStop] = [:]
        for stop in stops { byFrame[stop.sourceMS] = stop }
        guard !byFrame.isEmpty else { return nil }
        var sorted = byFrame.values.sorted { $0.sourceMS < $1.sourceMS }
        for index in sorted.indices.dropFirst() where sorted[index].isFreeze && sorted[index - 1].isFreeze {
            sorted[index] = sorted[index].atSpeed(ClipPiece.slowestPercent)
        }
        self.stops = sorted
        self.blend = blend
    }

    private enum CodingKeys: String, CodingKey { case stops, blend }

    /// Read back through the same door as everything else, so a file can never
    /// hold stops out of order, or none at all.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stops = try c.decode([SpeedStop].self, forKey: .stops)
        let blend = try c.decodeIfPresent(SpeedRampBlend.self, forKey: .blend) ?? .ramp
        guard let ramp = SpeedRamp(stops: stops, blend: blend) else {
            throw DecodingError.dataCorruptedError(forKey: .stops, in: c, debugDescription: "A ramp has at least one stop")
        }
        self = ramp
    }

    /// The same stops, got between another way.
    public func blending(_ blend: SpeedRampBlend) -> SpeedRamp {
        SpeedRamp(stops: stops, blend: blend) ?? self
    }

    /// The same ramp with one stop more, nil where there is one on that frame.
    public func adding(_ stop: SpeedStop) -> SpeedRamp? {
        guard !stops.contains(where: { $0.sourceMS == stop.sourceMS }) else { return nil }
        return SpeedRamp(stops: stops + [stop], blend: blend)
    }

    /// The same ramp with one stop fewer, nil where none is left.
    public func removing(stop index: Int) -> SpeedRamp? {
        guard stops.indices.contains(index) else { return self }
        var kept = stops
        kept.remove(at: index)
        return SpeedRamp(stops: kept, blend: blend)
    }

    /// The same ramp with one stop at another speed.
    public func setting(stop index: Int, toPercent percent: Int) -> SpeedRamp {
        guard stops.indices.contains(index) else { return self }
        var changed = stops
        changed[index] = changed[index].atSpeed(percent)
        return SpeedRamp(stops: changed, blend: blend) ?? self
    }

    /// The same ramp with one stop swapped for another, nil where the new one
    /// lands on another stop's frame.
    public func replacing(stop index: Int, with stop: SpeedStop) -> SpeedRamp? {
        guard stops.indices.contains(index) else { return self }
        guard !stops.enumerated().contains(where: { $0.offset != index && $0.element.sourceMS == stop.sourceMS })
        else { return nil }
        var changed = stops
        changed[index] = stop
        return SpeedRamp(stops: changed, blend: blend)
    }

    /// Whether a stop may go to nought: not beside another freeze.
    public func canFreeze(stop index: Int) -> Bool {
        guard stops.indices.contains(index) else { return false }
        if index > 0, stops[index - 1].isFreeze { return false }
        if index < stops.count - 1, stops[index + 1].isFreeze { return false }
        return true
    }

    /// Where a stop is, by the frame it is on: the stop on exactly that frame.
    public func index(ofStopAtSourceMS ms: Int) -> Int? {
        stops.firstIndex { $0.sourceMS == ms }
    }

    // MARK: - The speed at a frame

    /// How fast the piece is playing as it passes a moment of the recording,
    /// as a multiple of the recorded speed.
    public func speed(atSourceMS ms: Double) -> Double {
        let all = stretches
        return all[Self.stretchIndex(containing: ms, in: all)].speed(at: ms)
    }

    /// The same, as a whole percentage inside what a piece may play at.
    public func speedPercent(atSourceMS ms: Int) -> Int {
        let percent = Int((speed(atSourceMS: Double(ms)) * 100).rounded())
        return min(max(ClipPiece.slowestPercent, percent), ClipPiece.fastestPercent)
    }

    // MARK: - The two clocks

    /// How much timeline it takes to play from one frame of the recording to
    /// another: negative when `to` is the earlier one.
    public func timelineMS(fromSourceMS from: Double, toSourceMS to: Double) -> Double {
        guard to != from else { return 0 }
        guard to > from else { return -timelineMS(fromSourceMS: to, toSourceMS: from) }
        var total = 0.0
        for stretch in stretches where stretch.end > from && stretch.start < to {
            total += stretch.elapsed(from: max(from, stretch.start), to: min(to, stretch.end))
        }
        // A freeze's hold is spent on its frame, before the picture moves off.
        for stop in stops where stop.holdMS > 0 && Double(stop.sourceMS) >= from && Double(stop.sourceMS) < to {
            total += Double(stop.holdMS)
        }
        return total
    }

    /// The frame of the recording reached `timeline` milliseconds after
    /// `from` was playing; before it, for a negative `timeline`.
    public func sourceMS(fromSourceMS from: Double, afterTimelineMS timeline: Double) -> Double {
        let stretches = self.stretches
        let holds = self.holds
        var at = from
        var left = abs(timeline)
        var index = Self.stretchIndex(containing: from, in: stretches)
        if timeline >= 0 {
            // A freeze on the frame it starts from is held first.
            if let hold = holds[at] {
                if left <= hold { return at }
                left -= hold
            }
            while true {
                let stretch = stretches[index]
                let room = stretch.elapsed(from: at, to: stretch.end)
                if left <= room || index == stretches.count - 1 { return stretch.reach(from: at, spending: left) }
                left -= room
                at = stretch.end
                index += 1
                if let hold = holds[at] {
                    if left <= hold { return at }
                    left -= hold
                }
            }
        }
        // Going back, a frame exactly on a stop belongs to the stretch before.
        if index > 0, from <= stretches[index].start { index -= 1 }
        while true {
            let stretch = stretches[index]
            let room = stretch.elapsed(from: stretch.start, to: at)
            if left <= room || index == 0 { return stretch.reach(from: at, spending: -left) }
            left -= room
            at = stretch.start
            index -= 1
            if let hold = holds[at] {
                if left <= hold { return at }
                left -= hold
            }
        }
    }

    // MARK: - Stretches

    /// The piece cut at its stops: an open stretch before the first, one
    /// between each pair, and an open one after the last.
    ///
    /// A stretch can never sit at nought, or it would never end. Eased, a
    /// freeze is reached and left in finite time and neighbouring freezes are
    /// not allowed; flat, the stretch after a freeze plays at the next stop's
    /// speed, the freeze having been its hold; open, beyond a freeze at either
    /// end, it plays at the nearest stop that moves.
    private var stretches: [Stretch] {
        var out: [Stretch] = []
        let speeds = stops.map { Double($0.speedPercent) / 100 }
        let frames = stops.map { Double($0.sourceMS) }
        let slowest = Double(ClipPiece.slowestPercent) / 100
        let first = speeds.first { $0 > 0 } ?? 1
        let last = speeds.last { $0 > 0 } ?? 1
        let opening = speeds[0] > 0 ? speeds[0] : first
        out.append(Stretch(start: -.infinity, end: frames[0], from: opening, to: opening))
        for index in 0..<(stops.count - 1) {
            var from = speeds[index]
            var to = blend == .ramp ? speeds[index + 1] : speeds[index]
            if blend == .hold, from == 0 { from = speeds[index + 1] > 0 ? speeds[index + 1] : slowest; to = from }
            if from == 0, to == 0 { from = slowest; to = slowest }
            out.append(Stretch(start: frames[index], end: frames[index + 1], from: from, to: to))
        }
        let closing = speeds[speeds.count - 1] > 0 ? speeds[speeds.count - 1] : last
        out.append(Stretch(start: frames[frames.count - 1], end: .infinity, from: closing, to: closing))
        return out
    }

    /// Every freeze that holds, by its frame.
    private var holds: [Double: Double] {
        var out: [Double: Double] = [:]
        for stop in stops where stop.holdMS > 0 { out[Double(stop.sourceMS)] = Double(stop.holdMS) }
        return out
    }

    /// The stretch a frame falls in. A frame exactly on a stop belongs to the
    /// stretch that STARTS there.
    private static func stretchIndex(containing ms: Double, in all: [Stretch]) -> Int {
        all.lastIndex { ms >= $0.start } ?? 0
    }
}

/// One stretch between two stops: the speed eases from `from` to `to`,
/// evenly in timeline time, across the frames from `start` to `end`.
///
/// Evenly in timeline time means the square of the speed changes evenly in
/// recording time, so v(σ)² = a² + 2k(σ − start) with k = (b² − a²) / 2d, and
/// the timeline it takes to reach σ is 2(σ − start) / (a + v(σ)), which never
/// divides by k and so never fails on a flat stretch. A stretch open at one
/// end is always flat.
private struct Stretch {
    let start: Double
    let end: Double
    let from: Double
    let to: Double

    private var isFlat: Bool { from == to || !start.isFinite || !end.isFinite }

    /// How fast the speed squared climbs per millisecond of recording.
    private var climb: Double {
        isFlat ? 0 : (to * to - from * from) / (2 * (end - start))
    }

    func speed(at ms: Double) -> Double {
        guard !isFlat else { return from }
        let squared = from * from + 2 * climb * (min(max(ms, start), end) - start)
        return max(0, squared).squareRoot()
    }

    /// Timeline from `from` frame to `to` frame, both inside the stretch.
    func elapsed(from a: Double, to b: Double) -> Double {
        guard !isFlat else { return (b - a) / from }
        return clock(b) - clock(a)
    }

    /// Timeline from this stretch's start to a frame inside it.
    private func clock(_ ms: Double) -> Double {
        let into = ms - start
        guard into > 0 else { return 0 }
        return 2 * into / (from + speed(at: ms))
    }

    /// The frame reached `time` of timeline after `ms` (before it, negative).
    func reach(from ms: Double, spending time: Double) -> Double {
        guard !isFlat else { return ms + time * from }
        let at = max(0, clock(ms) + time)
        return start + from * at + climb * at * at / 2
    }
}
