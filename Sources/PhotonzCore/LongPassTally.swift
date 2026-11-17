import Foundation

/// The long passes of the main thread over one stretch of a walk: how many ran
/// past a limit, and which were the longest.
///
/// A guard that reads only the LONGEST pass says whether anything went over;
/// a person watching a video play cares how often too. One 60 ms hitch in
/// twenty seconds of playback and one every frame are different news
/// (`playing-a-five-minute-captioned-recording-never`, 2026-11-16).
public struct LongPassTally: Sendable, Equatable {
    public struct Pass: Sendable, Equatable {
        public let ms: Double
        public let atMS: Double
    }

    /// Passes shorter than this are not kept: a run loop turns over a few
    /// hundred times a second while a video plays, and nearly all of them are
    /// nothing.
    public let floorMS: Double
    /// How many passes are kept for the list. Every pass at or over the floor
    /// is still counted (`count(atOrOverMS:)`), however many there are.
    public let keeping: Int
    public private(set) var kept: [Pass] = []
    /// Every pass at or over the floor, by length, rounded down to a tenth of
    /// a millisecond, so a count at any limit stays exact past `keeping`.
    private var lengths: [Int: Int] = [:]

    public init(floorMS: Double = 6, keeping: Int = 500) {
        self.floorMS = floorMS
        self.keeping = max(1, keeping)
    }

    public mutating func record(ms: Double, atMS: Double) {
        guard ms >= floorMS else { return }
        lengths[Self.tenths(ms), default: 0] += 1
        if kept.count < keeping {
            kept.append(Pass(ms: ms, atMS: atMS))
        } else if let shortest = kept.indices.min(by: { kept[$0].ms < kept[$1].ms }), kept[shortest].ms < ms {
            kept[shortest] = Pass(ms: ms, atMS: atMS)
        }
    }

    public mutating func reset() {
        kept = []
        lengths = [:]
    }

    /// How many passes ran this long or longer.
    public func count(atOrOverMS limit: Double) -> Int {
        let bar = Self.tenths(limit)
        let exact = lengths.reduce(0) { $0 + ($1.key >= bar ? $1.value : 0) }
        // A pass a hair under the limit rounds into its tenth: count those from
        // the kept list when it holds every pass, so 49.95 is never 50.
        guard kept.count == lengths.values.reduce(0, +) else { return exact }
        return kept.filter { $0.ms >= limit }.count
    }

    /// "5 passes at or over 50ms: 90ms at 1000, 70ms at 3000 and 3 more".
    public func summary(atOrOverMS limit: Double, listing: Int) -> String {
        let count = count(atOrOverMS: limit)
        let limitText = String(format: "%gms", limit)
        guard count > 0 else { return "no pass at or over \(limitText)" }
        let longest = kept.filter { $0.ms >= limit }.sorted { $0.ms > $1.ms }.prefix(max(0, listing))
        let listed = longest.map { String(format: "%.0fms at %.0f", $0.ms, $0.atMS) }.joined(separator: ", ")
        let more = count - longest.count
        return "\(count) pass\(count == 1 ? "" : "es") at or over \(limitText): \(listed)"
            + (more > 0 ? " and \(more) more" : "")
    }

    private static func tenths(_ ms: Double) -> Int { Int((ms * 10).rounded(.down)) }
}
