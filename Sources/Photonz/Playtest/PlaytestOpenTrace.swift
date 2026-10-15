#if PHOTONZ_PLAYTEST
import Foundation

/// Probe-only marks along the way a recording opens, read by
/// `stopThenOpenDrill` so a slow open says which part of it was slow.
@MainActor
enum PlaytestOpenTrace {
    private static var start: Date?
    private(set) static var marks: [(String, Double)] = []

    static func begin() {
        start = Date()
        marks = []
    }

    static func mark(_ name: String) {
        guard let start else { return }
        marks.append((name, Date().timeIntervalSince(start) * 1000))
    }

    static var said: String {
        marks.map { String(format: "%@ %.0f", $0.0, $0.1) }.joined(separator: ", ")
    }
}
#endif
