import Foundation

// The speed curve under a clip (`docs/design/mocks/pages/video-speed.html`,
// the timeline dock's `.scplot`): how fast the clip plays at every moment of
// it, on the clip's own clock, with a handle on every stop.
//
// Between two stops the speed changes evenly in TIMELINE time
// (`SpeedRamp.swift`), so on the clip's clock the curve is a straight line
// from stop to stop, exactly as the mock draws it, and nothing here samples.
// A Hold is a step at each stop; a freeze that holds is flat at nought for its
// hold, the mock's two zeros side by side, the second a handle of its own.
//
// Worked out here, pure, so the lane only says where to draw it.

/// The four kinds of speed the mock tints: its legend's Slow-mo, Normal, Fast
/// and Freeze, held, at the edges its own code draws them.
public enum SpeedBand: String, CaseIterable, Hashable, Sendable {
    case slow
    case normal
    case fast
    case freeze

    public init(speed: Double) {
        if speed <= 0.05 { self = .freeze }
        else if speed < 0.85 { self = .slow }
        else if speed <= 1.15 { self = .normal }
        else { self = .fast }
    }

    /// The mock's swatch (`.sw.slow`, `.sw.norm`, `.sw.fast`, and the light
    /// stripe of `.sw.frz`, whose dark stripe is `freezeStripeHex`).
    public var hex: String {
        switch self {
        case .slow: "#12c2e9"
        case .normal: "#9a5cff"
        case .fast: "#ff5d8f"
        case .freeze: "#febc2e"
        }
    }

    /// The dark stripe of the freeze's hatching.
    public static let freezeStripeHex = "#c98f18"

    /// The mock's legend.
    public var title: String {
        switch self {
        case .slow: "Slow-mo"
        case .normal: "Normal"
        case .fast: "Fast"
        case .freeze: "Freeze, held"
        }
    }
}

/// A clip's speed at every moment of it, and a handle on every stop.
public struct SpeedCurve: Hashable, Sendable {

    /// A corner of the line: a moment of the clip and the speed there, as a
    /// multiple of the recorded speed.
    public struct Point: Hashable, Sendable {
        public let timelineMS: Double
        public let speed: Double

        public init(_ timelineMS: Double, _ speed: Double) {
            self.timelineMS = timelineMS
            self.speed = speed
        }
    }

    /// What a handle on the curve is.
    public enum HandleKind: Hashable, Sendable {
        /// A speed stop: drags along and up and down.
        case stop
        /// The far end of a freeze's hold, the mock's second zero: drags along.
        case holdEnd
    }

    /// A handle on the curve: which stop of which piece, and where it sits.
    public struct Handle: Hashable, Sendable {
        public let piece: Int
        public let stop: Int
        public let kind: HandleKind
        public let timelineMS: Double
        public let speed: Double
    }

    /// A stretch of the clip in one band.
    public struct BandRun: Hashable, Sendable {
        public let band: SpeedBand
        public let startMS: Double
        public let endMS: Double
    }

    /// The top of the mock's scale, 3x. Faster stops draw at the top.
    public static let topSpeed: Double = 3
    /// The speeds the mock's scale prints, top to bottom.
    public static let scale: [String] = ["3x", "1x", "0"]

    public let lengthMS: Int
    /// The line, first moment to last. Two corners at one moment are a step.
    public let points: [Point]
    public let handles: [Handle]

    public init(_ clip: ClipPieces) {
        var points: [Point] = []
        var handles: [Handle] = []
        func add(_ point: Point) {
            if let last = points.last, abs(last.timelineMS - point.timelineMS) < 1e-9,
               abs(last.speed - point.speed) < 1e-9 { return }
            points.append(point)
        }
        for (index, piece) in clip.pieces.enumerated() {
            let start = Double(clip.startMS(ofPiece: index))
            let length = Double(piece.lengthMS)
            guard let ramp = piece.speedRamp else {
                let speed = Double(piece.speedPercent) / 100
                add(Point(start, speed))
                add(Point(start + length, speed))
                continue
            }
            let shape = Self.shape(of: ramp, from: piece.sourceInMS)
            for point in Self.clipped(shape.points, to: length) {
                add(Point(start + point.timelineMS, point.speed))
            }
            for handle in shape.handles where handle.timelineMS >= -0.5 && handle.timelineMS <= length + 0.5 {
                handles.append(Handle(piece: index, stop: handle.stop, kind: handle.kind,
                                      timelineMS: start + min(max(handle.timelineMS, 0), length),
                                      speed: handle.speed))
            }
        }
        self.lengthMS = clip.totalLengthMS
        self.points = points
        self.handles = handles
    }

    /// How fast the clip plays at a moment of it. At a step, the speed after.
    public func speed(atMS ms: Double) -> Double {
        guard let first = points.first else { return 1 }
        guard let index = points.lastIndex(where: { $0.timelineMS <= ms }) else { return first.speed }
        guard index + 1 < points.count else { return points[index].speed }
        let a = points[index], b = points[index + 1]
        let span = b.timelineMS - a.timelineMS
        guard span > 0 else { return b.speed }
        return a.speed + (b.speed - a.speed) * (ms - a.timelineMS) / span
    }

    /// The clip cut where the line crosses from one band into another.
    public var bands: [BandRun] {
        var runs: [BandRun] = []
        func add(_ band: SpeedBand, _ start: Double, _ end: Double) {
            guard end > start else { return }
            if let last = runs.last, last.band == band, abs(last.endMS - start) < 1e-9 {
                runs[runs.count - 1] = BandRun(band: band, startMS: last.startMS, endMS: end)
            } else {
                runs.append(BandRun(band: band, startMS: start, endMS: end))
            }
        }
        for (a, b) in zip(points, points.dropFirst()) where b.timelineMS > a.timelineMS {
            var cuts = [a.timelineMS]
            for edge in [0.05, 0.85, 1.15] where (a.speed - edge) * (b.speed - edge) < 0 {
                cuts.append(a.timelineMS + (edge - a.speed) / (b.speed - a.speed) * (b.timelineMS - a.timelineMS))
            }
            cuts.append(b.timelineMS)
            cuts.sort()
            for (from, to) in zip(cuts, cuts.dropFirst()) {
                let middle = (from + to) / 2
                let speed = a.speed + (b.speed - a.speed) * (middle - a.timelineMS) / (b.timelineMS - a.timelineMS)
                add(SpeedBand(speed: speed), from, to)
            }
        }
        return runs
    }

    // MARK: - The hand

    /// How far up the scale a speed sits, nought at the floor and one at 3x.
    public static func height(ofSpeed speed: Double) -> Double {
        min(max(speed, 0), topSpeed) / topSpeed
    }

    /// A speed pulled near one of the mock's round ones lands on it.
    public static func snapped(_ speed: Double) -> Double {
        var best = speed
        var gap = 0.09
        for nice in [0, 0.25, 0.5, 1, 1.5, 2, 2.5, 3] where abs(speed - nice) < gap {
            best = nice
            gap = abs(speed - nice)
        }
        return best
    }

    /// The whole percentage a speed under the hand stores: inside the scale,
    /// and either a freeze or at least the slowest a piece can play.
    public static func percent(forSpeed speed: Double) -> Int {
        let percent = Int((min(max(speed, 0), topSpeed) * 100).rounded())
        guard percent > 0, percent < ClipPiece.slowestPercent else { return percent }
        return percent * 2 < ClipPiece.slowestPercent ? 0 : ClipPiece.slowestPercent
    }

    // MARK: - One ramp

    private struct RampHandle {
        let stop: Int
        let kind: HandleKind
        let timelineMS: Double
        let speed: Double
    }

    /// A ramp's line and handles on its piece's own clock, running on past
    /// both ends: flat before the first stop and after the last.
    private static func shape(of ramp: SpeedRamp, from sourceIn: Int)
        -> (points: [Point], handles: [RampHandle]) {
        let stops = ramp.stops
        let speeds = stops.map { Double($0.speedPercent) / 100 }
        let times = stops.map { ramp.timelineMS(fromSourceMS: Double(sourceIn), toSourceMS: Double($0.sourceMS)) }
        let slowest = Double(ClipPiece.slowestPercent) / 100
        let opening = speeds[0] > 0 ? speeds[0] : (speeds.first { $0 > 0 } ?? 1)
        let closing = speeds[speeds.count - 1] > 0 ? speeds[speeds.count - 1] : (speeds.last { $0 > 0 } ?? 1)
        let far = 1e9
        var points = [Point(times[0] - far, opening), Point(times[0], opening)]
        var handles: [RampHandle] = []
        for index in stops.indices {
            let t = times[index]
            let hold = Double(stops[index].holdMS)
            if ramp.blend == .hold, index > 0 {
                let previous = speeds[index - 1] > 0 ? speeds[index - 1] : (speeds[index] > 0 ? speeds[index] : slowest)
                points.append(Point(t, previous))
            }
            points.append(Point(t, speeds[index]))
            handles.append(RampHandle(stop: index, kind: .stop, timelineMS: t, speed: speeds[index]))
            if hold > 0 {
                points.append(Point(t + hold, 0))
                handles.append(RampHandle(stop: index, kind: .holdEnd, timelineMS: t + hold, speed: 0))
            }
            if ramp.blend == .hold, index < stops.count - 1, speeds[index] == 0 {
                points.append(Point(t + hold, speeds[index + 1] > 0 ? speeds[index + 1] : slowest))
            }
        }
        let end = times[times.count - 1] + Double(stops[stops.count - 1].holdMS)
        points.append(Point(end, closing))
        points.append(Point(end + far, closing))
        return (points, handles)
    }

    /// The part of a line from nought to `length`, with a corner at each end.
    private static func clipped(_ line: [Point], to length: Double) -> [Point] {
        func at(_ ms: Double) -> Point? {
            for (a, b) in zip(line, line.dropFirst()) where a.timelineMS < ms && ms < b.timelineMS {
                return Point(ms, a.speed + (b.speed - a.speed) * (ms - a.timelineMS) / (b.timelineMS - a.timelineMS))
            }
            return nil
        }
        var out: [Point] = []
        let inside = line.filter { $0.timelineMS >= -0.5 && $0.timelineMS <= length + 0.5 }
            .map { Point(min(max($0.timelineMS, 0), length), $0.speed) }
        if inside.first?.timelineMS != 0, let start = at(0) { out.append(start) }
        out += inside
        if out.last?.timelineMS != length, let end = at(length) { out.append(end) }
        return out
    }
}
