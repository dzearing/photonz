import Foundation

/// What a run of clicks on one Library tile measured (`timeTileClicks`): for
/// each click, how long from the release until a frame with the pick in it was
/// on screen, and until the window was drawing on time again. A nil reading is
/// a click that never picked the tile at all.
public struct TileClickTiming: Sendable, Equatable {
    public struct Reading: Sendable, Equatable {
        public var highlightMS: Double?
        public var settledMS: Double?

        public init(highlightMS: Double?, settledMS: Double?) {
            self.highlightMS = highlightMS
            self.settledMS = settledMS
        }
    }

    /// The middle and the worst of one measure across the clicks that picked.
    public struct Spread: Sendable, Equatable {
        public var median: Double
        public var worst: Double
        /// Which click was the worst, counting from 1.
        public var worstClick: Int

        init(median: Double, worst: Double, worstClick: Int) {
            self.median = median
            self.worst = worst
            self.worstClick = worstClick
        }

        init?(_ values: [Double?]) {
            let measured = values.enumerated().compactMap { index, value in value.map { (index, $0) } }
            guard let worst = measured.max(by: { $0.1 < $1.1 }) else { return nil }
            let sorted = measured.map(\.1).sorted()
            let middle = sorted.count / 2
            median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
            self.worst = worst.1
            worstClick = worst.0 + 1
        }
    }

    public var tile: String
    public var readings: [Reading]

    public init(tile: String, readings: [Reading]) {
        self.tile = tile
        self.readings = readings
    }

    private static let nothing = Spread(median: 0, worst: 0, worstClick: 0)

    public var highlight: Spread { Spread(readings.map(\.highlightMS)) ?? Self.nothing }
    public var settled: Spread { Spread(readings.map(\.settledMS)) ?? Self.nothing }

    /// The clicks that never picked their tile, counting from 1.
    public var missedClicks: [Int] {
        readings.enumerated().filter { $0.element.highlightMS == nil }.map { $0.offset + 1 }
    }

    /// Why this run fails its budgets, or nil when it meets them. A click that
    /// never picked the tile fails whatever the budgets are.
    public func trouble(highlightUnderMS: Double?, settledUnderMS: Double?) -> String? {
        if let missed = missedClicks.first {
            return "click \(missed) on \"\(tile)\" never picked it"
        }
        if let bound = highlightUnderMS, highlight.worst >= bound {
            return String(format: "click %d on \"%@\" took %.0fms to show the tile picked, and this walk "
                + "allows under %.0fms", highlight.worstClick, tile, highlight.worst, bound)
        }
        if let bound = settledUnderMS, settled.worst >= bound {
            return String(format: "click %d on \"%@\" took %.0fms before the window was drawing on time "
                + "again, and this walk allows under %.0fms", settled.worstClick, tile, settled.worst, bound)
        }
        return nil
    }

    /// One line for the log: both measures, median and worst.
    public var summary: String {
        let count = readings.count
        var line = String(format: "\"%@\", %d click%@: picked on screen median %.0fms worst %.0fms; "
            + "settled median %.0fms worst %.0fms", tile, count, count == 1 ? "" : "s",
            highlight.median, highlight.worst, settled.median, settled.worst)
        if !missedClicks.isEmpty {
            line += "; never picked on click " + missedClicks.map(String.init).joined(separator: ", ")
        }
        return line
    }
}
