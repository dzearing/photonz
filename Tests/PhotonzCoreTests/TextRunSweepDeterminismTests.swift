import CoreGraphics
import Foundation
@testable import PhotonzCore
import Testing

/// The sweep has to answer the same thing twice.
///
/// It did not. `components` gathered its runs in a `[Int: Box]` keyed by the
/// union-find root and handed back `Array(boxes.values)`, and a Swift
/// dictionary is walked in hash order with the seed reseeded every process. The
/// runs therefore arrived in a different order in every run of the app, the
/// biggest-first pass that drops overlapping runs kept a different one of each
/// overlapping pair, and the number of pieces left in the picture came out 355,
/// 357 or 359 for the same screenshot. Four runs of one test on one commit:
/// pass, pass, fail (359), fail (355).
///
/// So the order is pinned here, at the one place it can be pinned without a
/// seed: `components` returns its runs in the order the picture is READ, top
/// row first and left to right within a row. That is a property of the answer
/// rather than of one lucky process, so it holds whatever the seed is.
@Suite("Sweeping a picture answers the same thing every run")
struct TextRunSweepDeterminismTests {

    /// Segments laid out so that the union-find roots come out in an order that
    /// has nothing to do with reading order: the last row's segment is its own
    /// root with the lowest index of any root but the highest position, and the
    /// two rows above join into one run whose root is index 0.
    private static func scene() -> (segments: [TextRunSweep.Segment],
                                    rows: [Range<Int>], height: Int) {
        var segments: [TextRunSweep.Segment] = []
        var rows: [Range<Int>] = []
        func row(_ y: Int, _ spans: [(Int, Int)]) {
            let start = segments.count
            for span in spans { segments.append(TextRunSweep.Segment(y: y, x0: span.0, x1: span.1)) }
            rows.append(start..<segments.count)
        }
        // Three bands of three runs each, every run two rows tall so the rows
        // join and every root is a real union rather than a lone segment. Nine
        // runs means a hash order that happened to match reading order is a one
        // in three hundred and sixty thousand accident rather than a coin toss,
        // so this test says something whatever seed it runs under.
        var y = 0
        for _ in 0..<3 {
            let spans = [(10, 20), (40, 50), (70, 80)]
            row(y, spans)
            row(y + 1, spans)
            row(y + 2, [])
            row(y + 3, [])
            y += 4
        }
        return (segments, rows, y)
    }

    @Test func runsComeBackInReadingOrder() {
        let scene = Self.scene()
        let boxes = TextRunSweep.components(of: scene.segments, rowRanges: scene.rows,
                                            height: scene.height, verticalGap: 1)
        #expect(boxes.count == 9)
        #expect(boxes.map(\.y0) == [0, 0, 0, 4, 4, 4, 8, 8, 8])
        #expect(boxes.map(\.x0) == [10, 40, 70, 10, 40, 70, 10, 40, 70])
    }

    /// The same list of segments, asked twice in one process, cannot disagree
    /// with itself either. This is the weaker half of the claim — one process
    /// has one seed — but it is what catches a future rewrite that gathers the
    /// runs somewhere order does not survive.
    @Test func askingTwiceGivesTheSameAnswer() {
        let scene = Self.scene()
        let first = TextRunSweep.components(of: scene.segments, rowRanges: scene.rows,
                                            height: scene.height, verticalGap: 1)
        let second = TextRunSweep.components(of: scene.segments, rowRanges: scene.rows,
                                             height: scene.height, verticalGap: 1)
        #expect(first.map { [$0.x0, $0.y0, $0.x1, $0.y1] }
            == second.map { [$0.x0, $0.y0, $0.x1, $0.y1] })
    }
}
