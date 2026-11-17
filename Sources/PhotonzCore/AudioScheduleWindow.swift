import Foundation

/// **Which pieces of sound are on the engine** as a document plays: a
/// stretch just ahead of the playhead, topped up as it moves, so every piece
/// is on before its moment however long the edit is.
///
/// The player used to put the first 48 pieces still to come on the engine
/// when play was pressed and never look again, so a 20 minute edit played
/// from the start went silent at 6 minutes 25 seconds while the picture
/// carried on (task `find-out-whether-a-long-edit-goes-quiet-after-it`,
/// 2026-11-16: 144 pieces, never more than three sounding at once). Now the
/// engine holds what starts within `lookAheadMS` of the playhead, gives back
/// what has finished, and the budget is on what it holds AT ONCE, which is
/// what costs the engine nodes and decodes.
///
/// Pure arithmetic on spans of the document's clock: the player
/// (`DocumentAudioPlayer`) feeds it the clock and does what it says.
public struct AudioScheduleWindow: Sendable {

    /// One piece of sound on the document's clock.
    public struct Span: Hashable, Sendable {
        public let startMS: Int
        public let endMS: Int
        public init(startMS: Int, endMS: Int) {
            self.startMS = startMS
            self.endMS = endMS
        }
    }

    /// What to do to the engine now: pieces to put on, pieces to take off.
    /// Indices into the spans the window was made with.
    public struct Step: Equatable, Sendable {
        public var add: [Int] = []
        public var retire: [Int] = []
    }

    /// How far ahead of the playhead a piece is put on the engine. Far longer
    /// than the top-up's tick and than any stall the app has had since
    /// 2026-11-16, so a piece is on long before it is due; short enough that
    /// the engine holds a handful of nodes rather than an edit's worth.
    public static let lookAheadMS = 20_000

    /// How long after its end a piece stays on, so a clock read a moment
    /// early never takes the tail off a piece still sounding.
    public static let retireGraceMS = 500

    /// The most pieces on the engine at once. Each is an engine node and a
    /// decode; a stretch of twenty seconds needing more than this is one
    /// nobody is auditioning by ear.
    public static let budget = 48

    public let spans: [Span]
    public let fromMS: Int
    public let budget: Int

    /// What is on the engine now.
    public private(set) var scheduled: Set<Int> = []
    /// Pieces that were due and never put on: more were held than the budget,
    /// or the top-up did not run until they were over. Sound nobody heard.
    public private(set) var leftOut: Set<Int> = []
    /// The first span not yet looked at; spans are in order of start.
    private var next = 0

    /// `spans` in order of start (`order(of:)`), playing from `fromMS`.
    public init(spans: [Span], fromMS: Int, budget: Int = AudioScheduleWindow.budget) {
        self.spans = spans
        self.fromMS = fromMS
        self.budget = max(1, budget)
    }

    /// What goes on the engine when play is pressed.
    public mutating func start() -> Step {
        advance(toMS: fromMS)
    }

    /// The playhead is at `nowMS`: what to take off and what to put on.
    public mutating func advance(toMS nowMS: Int) -> Step {
        var step = Step()
        for index in scheduled where spans[index].endMS + Self.retireGraceMS <= nowMS {
            step.retire.append(index)
        }
        step.retire.sort()
        scheduled.subtract(step.retire)

        let horizon = max(nowMS, fromMS) + Self.lookAheadMS
        while next < spans.count, spans[next].startMS < horizon {
            let span = spans[next]
            defer { next += 1 }
            // Over before play was pressed: never wanted.
            if span.endMS <= fromMS { continue }
            // Came and went while nobody looked: wanted and not heard.
            if span.endMS <= nowMS || scheduled.count >= budget {
                leftOut.insert(next)
                continue
            }
            scheduled.insert(next)
            step.add.append(next)
        }
        return step
    }

    /// The mix's indices in order of start, the order the window wants.
    public static func order(of mix: [AudioMixSegment]) -> [Int] {
        mix.indices.sorted { (mix[$0].startMS, $0) < (mix[$1].startMS, $1) }
    }

    /// The spans of a mix already in order of start.
    public static func spans(of mix: [AudioMixSegment]) -> [Span] {
        let sorted = mix.sorted { $0.startMS < $1.startMS }
        return sorted.map { Span(startMS: $0.startMS, endMS: $0.endMS) }
    }
}
