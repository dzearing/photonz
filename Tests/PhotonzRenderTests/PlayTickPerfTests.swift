import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// **One tick of a playing clock on the 6 minute reference edit fits in a
/// frame** (`a-long-edit-with-transitions-plays-scrubs-and-ed`).
///
/// What the editor's main thread does each time the playing clock moves the
/// playhead (`EditorState.documentMomentChanged`): the frames under the
/// playhead and the eight ahead of it, the look ahead for the far side of each
/// cut coming up (`MoviePlayLookahead`), the moment drawn with its transitions,
/// and the mix's sound crossings. On 2026-11-12, before the document kept its
/// track layout (`DocumentDerived.swift`), this pegged the main thread and
/// the app showed 5 pictures of 1857 in a minute of play.
@Suite("One playing tick on the long edit", .serialized)
struct PlayTickPerfTests {

    static let six = ReferenceEdit.build(minutes: 6)

    /// Two seconds of ticks, 33 ms apart, across the first transition after a
    /// minute: what the clock asks while a dissolve plays.
    static func ticks(_ doc: PhotonzDocument, from start: Int) -> Int {
        var ahead = MoviePlayLookahead()
        var asked = 0
        for tick in 0..<60 {
            let ms = start + tick * MovieRef.frameStepMS
            var wanted = doc.movieFrames(atTimeMS: ms)
            for step in 1...8 { wanted += doc.movieFrames(atTimeMS: ms + step * MovieRef.frameStepMS) }
            let points = ahead.points(in: doc, atTimeMS: ms)
            let shown = doc.drawn(atTimeMS: ms)
            asked += wanted.count + points.coming.count + shown.layers.count
        }
        return asked
    }

    static func firstTransition(in doc: PhotonzDocument, after ms: Int) -> Int {
        let starts = doc.layers.filter { $0.arrivalTransition != nil }.compactMap(\.time?.inMS)
        return (starts.filter { $0 > ms }.min() ?? ms) - 1_000
    }

    @Test func aPlayingTickFitsInAFrame() {
        let doc = Self.six
        let start = Self.firstTransition(in: doc, after: 60_000)
        _ = Self.ticks(doc, from: start)
        let reading = PerfClock.calibrated(rounds: 5, rulerRounds: 3) { _ in
            _ = Self.ticks(doc, from: start)
        }
        let perTick = reading.medianMS / 60
        print("[perf] one playing tick on the 6 minute reference edit: "
              + String(format: "%.2f", perTick) + "ms (calibration machine)")
        // A tick has to leave most of a 60 fps frame for SwiftUI and the
        // canvas. 2.6ms on the calibration machine on 2026-11-13; the same
        // tick before the document kept its track layout took about 2,100ms
        // (1.6s of it the frames under and ahead of the playhead), and the
        // look ahead's first tick 8.9s. Twice the work crosses the bound.
        PerfClock.check("one playing tick on the 6 minute reference edit", ms: perTick,
                        rulerMS: reading.rulerMS, baselineMS: 2.6, tolerance: 2)
    }
}
