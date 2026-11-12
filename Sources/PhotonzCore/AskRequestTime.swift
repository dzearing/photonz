import Foundation

/// The five minutes a request has (`AskMotionLook` keeps the same five for a
/// moving icon's mend). Past them nobody is watching a spinner any more, and
/// the eval counts the request as nothing made.
///
/// Why: every request the eval recorded as "stalled at asking the model"
/// between 2026-10-23 and 2026-11-09 (18 of them) was the model answering the
/// whole time, seven to twenty-four turns of planning, until the walk's five
/// minutes ran out; the trace only looked stopped because the walk had read it
/// three seconds in (task `find-out-why-ask-sometimes-waits-five-minutes-fo`).
/// So planning stops in time and lands what it has.
public enum AskRequestTime {

    /// The latest a planning round may start, in seconds since the request
    /// was sent. A round reads and writes for 10 to 60 s, and what it plans
    /// still has to run and be looked at.
    public static let latestRound: TimeInterval = 240

    /// When a planning round still going is cut off, in seconds since the
    /// request was sent: the steps planned before it land, and running them
    /// takes seconds, so the request ends inside five minutes.
    public static let roundCut: TimeInterval = 270

    /// The five minutes themselves, which a walk may shorten (`PlaytestSetup.askSeconds`).
    public static let requestSeconds: TimeInterval = 300

    /// `latestRound`, in a request given `seconds` instead of five minutes.
    public static func latestRound(within seconds: Int?) -> TimeInterval {
        seconds.map { latestRound * Double($0) / requestSeconds } ?? latestRound
    }

    /// `roundCut`, in a request given `seconds` instead of five minutes.
    public static func roundCut(within seconds: Int?) -> TimeInterval {
        seconds.map { roundCut * Double($0) / requestSeconds } ?? roundCut
    }

    /// Whether a planning round may start `seconds` after the request was sent.
    public static func startsRound(at seconds: TimeInterval, within walk: Int? = nil) -> Bool {
        seconds < latestRound(within: walk)
    }

    /// Whether a drawing that does not read may be drawn again `seconds`
    /// after the request was sent; past it, what landed stays.
    public static func drawsAgain(at seconds: TimeInterval, within walk: Int? = nil) -> Bool {
        seconds < latestRound(within: walk)
    }

    public enum OutOfTime: Hashable, Sendable {
        /// The steps planned so far run, and the panel says what was left out.
        case offerPlanned
        /// Nothing was planned: Ask says it took too long, and nothing changes.
        case tooSlow
    }

    /// What a request whose planning ran out of time does.
    public static func whenOutOfTime(stepsPlanned: Int) -> OutOfTime {
        stepsPlanned > 0 ? .offerPlanned : .tooSlow
    }
}

/// Whether the model's server has gone quiet on a request: nothing read and
/// nothing written for `quietSeconds`. Fed the server's own count of what it
/// has read and written (`AskModelProgress`, from its `/slots`) a few times a
/// second while a turn waits.
public struct AskModelWatch: Hashable, Sendable {

    /// How long a server may go without reading or writing a token before
    /// the request is given up. Measured 2026-11-12 over every server log on
    /// this Mac (26,849 tasks): a working server logged progress at least
    /// every 15 s in 999 gaps of 1,000, and at worst 37 s apart while another
    /// model held the machine. Two and a half times that worst.
    public static let quietSeconds: TimeInterval = 90

    /// When there was last news, in the caller's seconds.
    public private(set) var lastNews: TimeInterval
    private var last: AskModelProgress?

    /// Watching starts when the request goes, at `at`.
    public init(at: TimeInterval) {
        lastNews = at
    }

    /// The server is loading its model, which has a bound of its own: the
    /// quiet time counts from when it is done.
    public mutating func loading(at: TimeInterval) {
        lastNews = at
        last = nil
    }

    /// A reading of the server at `at`; nil when it said nothing.
    public mutating func heard(_ reading: AskModelProgress?, at: TimeInterval) {
        guard let reading, reading != last else { return }
        last = reading
        lastNews = at
    }

    public func stalled(at: TimeInterval) -> Bool {
        at - lastNews >= Self.quietSeconds
    }
}
