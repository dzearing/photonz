import Foundation

/// What Photonz is held to in memory (`docs/design/memory.md`).
///
/// Set on 2026-10-23, after a colleague saw Photonz near 4 GB and a probe
/// that opened and closed pictures was found keeping every closed window's
/// pictures alive (1.9 GB after five 12-megapixel pictures had come and
/// gone). Counted the way Activity Monitor's Memory column counts it, the
/// process's physical footprint: Photonz itself, never the Ask helpers,
/// which are programs of their own with their own rows and their own rule
/// (they let go after a few idle minutes, `AskBuiltInServerPlan.idleSeconds`).
public enum MemoryBudget {

    /// Photonz idle with one screenshot open.
    public static let idleWithOneScreenshotMB = 300

    /// After a long session, once its windows are closed, Photonz is back
    /// within this share of where it started.
    public static let backAfterASessionPercent = 20

    /// The failure a walk reports for `reading`, or nil when it is within
    /// what `check` allows. `marks` are the readings taken earlier in the
    /// walk, by name, in order.
    public static func verdict(_ reading: MemoryReading, check: PlaytestMemoryCheck,
                               marks: [String: [MemoryReading]]) -> String? {
        let now = reading.megabytes
        if let ceiling = check.underMB, now >= ceiling {
            return "Photonz is using \(Int(now.rounded())) MB, and this walk allows under \(Int(ceiling)) MB"
        }
        if let most = check.editorsAtMost, reading.liveEditors > most {
            return "\(reading.liveEditors) editors are still in memory, and this walk allows \(most): "
                + "a closed window's editor that is never freed keeps its pictures with it"
        }
        if let name = check.withinPercentOf {
            guard let start = marks[name]?.first else {
                return "no reading was marked \"\(name)\" before this step"
            }
            let allowed = start.megabytes * (1 + check.percent / 100)
            if now > allowed {
                return "Photonz is using \(Int(now.rounded())) MB, more than \(Int(check.percent))% over the "
                    + "\(Int(start.megabytes.rounded())) MB it read at \"\(name)\""
            }
        }
        if let name = check.risingOver {
            let series = (marks[name] ?? []).map(\.footprintBytes)
            if keepsGrowing(series) {
                let said = series.map { String(Int((Double($0) / 1_048_576).rounded())) }.joined(separator: ", ")
                return "Photonz grew at every \"\(name)\" reading (\(said) MB): the same work, done again, "
                    + "keeps memory it should have given back"
            }
        }
        return nil
    }

    /// Whether readings taken after the same work, done again and again, keep
    /// climbing: a leak. The first reading is the warm-up (fonts, caches and
    /// code loaded once) and is left out; after it, the footprint has to have
    /// grown by more than 15 percent with most rounds higher than the last.
    public static func keepsGrowing(_ footprints: [Int]) -> Bool {
        let rounds = Array(footprints.dropFirst())
        guard rounds.count >= 3, let first = rounds.first, let last = rounds.last, first > 0 else { return false }
        let grewOverall = Double(last - first) / Double(first) > 0.15
        let climbs = zip(rounds, rounds.dropFirst()).filter { Double($1) > Double($0) * 1.01 }.count
        return grewOverall && climbs * 4 >= (rounds.count - 1) * 3
    }
}

/// One reading of Photonz's own memory.
public struct MemoryReading: Equatable, Sendable {
    /// Physical footprint, what Activity Monitor shows in its Memory column.
    public let footprintBytes: Int
    /// Picture editors still alive, open windows and closed ones not yet freed.
    public let liveEditors: Int

    public init(footprintBytes: Int, liveEditors: Int) {
        self.footprintBytes = footprintBytes
        self.liveEditors = liveEditors
    }

    public var megabytes: Double { Double(footprintBytes) / 1_048_576 }
}

/// A walk's `memory` step: read Photonz's footprint, remember it under a
/// name, and hold it to whatever it says.
public struct PlaytestMemoryCheck: Equatable, Sendable {
    /// Remember this reading under this name (again and again builds a series).
    public var mark: String?
    public var underMB: Double?
    public var editorsAtMost: Int?
    /// Within `percent` of the FIRST reading marked with this name.
    public var withinPercentOf: String?
    public var percent: Double
    /// Fails when the readings marked with this name keep climbing.
    public var risingOver: String?

    public init(mark: String? = nil, underMB: Double? = nil, editorsAtMost: Int? = nil,
                withinPercentOf: String? = nil, percent: Double = Double(MemoryBudget.backAfterASessionPercent),
                risingOver: String? = nil) {
        self.mark = mark
        self.underMB = underMB
        self.editorsAtMost = editorsAtMost
        self.withinPercentOf = withinPercentOf
        self.percent = percent
        self.risingOver = risingOver
    }
}
