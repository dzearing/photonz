import CoreGraphics
import Foundation

/// What the timing strip says beside its lap about the picked layer's Forever
/// motion: how long one turn takes, and whether the turn ends where it starts.
///
/// A one way Forever goes round at its own length rather than once a lap
/// (`MotionRepeat.keepsItsOwnPace`), so the lap the strip's header shows is not
/// the speed of the spinner you are tuning. The mock (`icon-loop-wt.html`)
/// names that speed in the dock, "800 ms per turn", because a rate is set by
/// watching something go round, not by typing it. Beside it the dock says
/// "ends where it starts": a loop is the one motion whose ends have to agree,
/// and the one thing nobody catches by eye.
public struct MotionTurnReading: Hashable, Sendable {
    /// How long one turn takes.
    public var turnMS: Int
    /// Whether the last picture of a turn is the first one again, so it goes
    /// round with no jump at the join.
    public var joins: Bool

    public init(turnMS: Int, joins: Bool) {
        self.turnMS = turnMS
        self.joins = joins
    }

    /// `800 ms per turn`, or `1.2 s per turn` from a second up, the way the
    /// mock prints both.
    public var lengthText: String {
        "\(Self.duration(turnMS)) per turn"
    }

    /// The mock's own words when it joins; when it does not, the same words
    /// turned round, so the two readings are told apart at a glance.
    public var joinText: String {
        joins ? "ends where it starts" : "does not end where it starts"
    }

    /// The reading for a layer's motions: its first switched-on one way
    /// Forever motion, or nil when it has none, because nothing else on the
    /// layer has a turn of its own.
    public static func reading(of motions: [LayerMotion]) -> MotionTurnReading? {
        guard let motion = motions.first(where: { $0.isOn && $0.repeats.keepsItsOwnPace })
        else { return nil }
        return MotionTurnReading(turnMS: max(1, motion.timing.durationMS),
                                 joins: endsWhereItStarts(motion))
    }

    /// Whether the turn stands in for the lap: every switched-on motion in
    /// the document goes round at its own pace, so the lap only follows them
    /// and nothing shares it. The mock's lone spinner is that case, and its
    /// dock reads "One turn" with the turn's length and no lap to type. A lap
    /// somebody typed stays, so it can still be seen and put back.
    public static func replacesTheLap(motions: [LayerMotion], lapIsAutomatic: Bool) -> Bool {
        let moving = motions.filter(\.isOn)
        return lapIsAutomatic && !moving.isEmpty
            && moving.allSatisfy(\.repeats.keepsItsOwnPace)
    }

    /// Whether To draws the same picture as From. An angle that has gone round
    /// a whole number of times has; anything else has only where the two are
    /// the same value.
    public static func endsWhereItStarts(_ motion: LayerMotion) -> Bool {
        switch (motion.from, motion.to) {
        case let (.number(from), .number(to)):
            if motion.property.wrapsEveryTurn {
                let left = (to - from).truncatingRemainder(dividingBy: 360)
                return abs(left) < tolerance || abs(abs(left) - 360) < tolerance
            }
            return abs(to - from) < tolerance
        case let (.point(from), .point(to)):
            return abs(to.x - from.x) < tolerance && abs(to.y - from.y) < tolerance
        case let (.color(from), .color(to)):
            guard let a = RGBA(hex: from), let b = RGBA(hex: to) else { return from == to }
            return abs(a.r - b.r) < colourTolerance && abs(a.g - b.g) < colourTolerance
                && abs(a.b - b.b) < colourTolerance && abs(a.a - b.a) < colourTolerance
        default:
            return false
        }
    }

    /// Less than any field shows, so a value typed to match always matches.
    static let tolerance = 0.001
    /// Half a step of an 8 bit channel.
    static let colourTolerance = 0.5 / 255

    static func duration(_ ms: Int) -> String {
        guard ms >= 1000 else { return "\(ms) ms" }
        let seconds = Double(ms) / 1000
        var text = String(format: "%.2f", seconds)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "\(text) s"
    }
}

extension MotionProperty {
    /// Whether this property is an angle, where 360 degrees is the same
    /// picture as none.
    var wrapsEveryTurn: Bool {
        switch self {
        case .rotation, .rotationX, .rotationY, .shadowDirection: true
        default: false
        }
    }
}
