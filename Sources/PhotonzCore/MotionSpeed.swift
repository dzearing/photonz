import Foundation

// How fast the preview runs (`next-motion`).
//
// Everything that moves in an icon is judged by watching it, and watching it is
// the problem: ninety milliseconds between the bell and the knob hanging off it
// is under six frames at thirty a second, which is a lag you can SET on the
// timing strip and then cannot see. Scrubbing a playhead is the usual answer
// and it is the wrong one for something that loops, because a lap is 900 ms
// long and dragging a hand through it tells you about positions rather than
// about motion.
//
// So the answer is a slower clock. One rate, applied to the one playhead
// everything reads, which means the lag slows by exactly the factor the motions
// do: there is no separate lag to remember to scale, because a lag is not a
// thing in the model, it is the distance between two starts on the same ruler.

/// How fast the preview plays: real time, or slowed so the eye can keep up.
public enum MotionSpeed: String, CaseIterable, Hashable, Codable, Sendable {
    /// Real time. What it runs at until somebody says otherwise.
    case full
    /// A quarter: a 900 ms lap takes three and a half seconds to watch, and
    /// ninety milliseconds becomes a gap you can see open.
    case quarter
    /// A tenth, for telling two nearly simultaneous things apart.
    case tenth

    /// The rates, fastest first. Three named rates rather than a slider: the
    /// number matters (a lag is judged AGAINST it) and a slider's number is one
    /// you cannot type or come back to.
    public static let choices: [MotionSpeed] = [.full, .quarter, .tenth]

    /// How much of the loop passes per second of real time.
    public var rate: Double {
        switch self {
        case .full: 1
        case .quarter: 0.25
        case .tenth: 0.1
        }
    }

    /// What the control itself shows: short, because it sits in a corner of the
    /// canvas beside four pictures.
    public var title: String {
        switch self {
        case .full: "1×"
        case .quarter: "0.25×"
        case .tenth: "0.1×"
        }
    }

    /// The row in the menu, which has room to say what the rate is FOR.
    public var menuTitle: String {
        switch self {
        case .full: "1×"
        case .quarter: "0.25× · slow"
        case .tenth: "0.1× · very slow"
        }
    }

    /// Whether the loop is running slower than life. What a readout uses to
    /// decide whether the rate is worth mentioning at all.
    public var isSlowed: Bool { self != .full }

    /// How far into the loop `seconds` of real time has carried the playhead.
    ///
    /// Anything that is not a real number of seconds that has actually passed
    /// reads as the top of the lap: a clock that jumped (the machine woke, a
    /// date went backwards) must leave the picture somewhere it can be drawn
    /// rather than at a playhead nobody can render.
    public func motionMS(afterRealSeconds seconds: Double) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let ms = (seconds * 1000 * rate).rounded()
        guard ms.isFinite, ms < Double(Int.max) else { return 0 }
        return Int(ms)
    }

    /// The other way round: how long the watching takes to reach `ms` of the
    /// loop. This is what re-anchors the clock when the rate changes while the
    /// preview is running, so slowing down carries on from where the loop had
    /// got to instead of snapping back to the top.
    public func realSeconds(forMotionMS ms: Int) -> Double {
        guard ms > 0 else { return 0 }
        return Double(ms) / 1000 / rate
    }
}
