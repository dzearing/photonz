import Foundation

/// Where sound drops out: every stretch longer than `longerThanMS` (10 ms by
/// default) in which no sample is louder than `quietDB` (-45 dB by default).
///
/// A tone crosses nought twice a cycle, so one quiet sample means nothing; a
/// run of them as long as a 50 Hz cycle and more is a hole a person hears. The
/// same reading answers for an exported file (its samples read back) and for
/// playback (the engine's output, tapped), so the bar the export is held to is
/// the bar the player is held to (2026-11-26: a reel's music went silent from
/// 14.36 to 15.04 s where two pairs of loops met).
public enum SoundDropouts {

    public struct Dropout: Sendable, Equatable {
        public let fromMS: Double
        public let toMS: Double
        public var lengthMS: Double { toMS - fromMS }

        public init(fromMS: Double, toMS: Double) {
            self.fromMS = fromMS
            self.toMS = toMS
        }
    }

    public static func find(in samples: [Float], sampleRate: Double,
                            quietDB: Double = -45, longerThanMS: Double = 10) -> [Dropout] {
        guard sampleRate > 0, !samples.isEmpty else { return [] }
        let quiet = Float(pow(10, quietDB / 20))
        let window = Int((sampleRate * longerThanMS / 1000).rounded())
        var found: [Dropout] = []
        var runStart: Int?
        func close(at end: Int) {
            guard let start = runStart else { return }
            if end - start > window {
                found.append(Dropout(fromMS: Double(start) / sampleRate * 1000,
                                     toMS: Double(end) / sampleRate * 1000))
            }
            runStart = nil
        }
        for (index, sample) in samples.enumerated() {
            if abs(sample) < quiet {
                if runStart == nil { runStart = index }
            } else {
                close(at: index)
            }
        }
        close(at: samples.count)
        return found
    }

    /// One line for a walk's log or a test's message.
    public static func describe(_ found: [Dropout]) -> String {
        guard !found.isEmpty else { return "no dropouts" }
        let stretches = found.prefix(5).map {
            String(format: "%.3f to %.3f s", $0.fromMS / 1000, $0.toMS / 1000)
        }
        let more = found.count > 5 ? ", and \(found.count - 5) more" : ""
        return "\(found.count) dropout\(found.count == 1 ? "" : "s"): "
            + stretches.joined(separator: ", ") + more
    }
}
