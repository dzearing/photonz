import Foundation
import PhotonzCore
import Testing

// A pass above double speed decodes a recording's samples itself, skipping
// the ones no other frame is decoded from (`MoviePlayPass.skipsUnreferenced`).
// The decoder hands frames back in the order they were decoded, which with
// B-frames is not the order they are shown: 9.750, 9.817, 9.783, 9.883 on the
// reference recordings (2026-11-13). These put them back in order.
@Suite("Putting decoded frames back in the order they are shown")
struct MovieDecodeReorderTests {

    @Test("Frames decoded out of order come out in order, holding back only a few")
    func reorders() {
        var reorder = MovieDecodeReorder<String>(depth: 2)
        var out: [Double] = []
        for ms in [9750.0, 9817, 9783, 9883, 9850, 9950, 9917, 10017, 9983] {
            reorder.insert(ms, "f")
            while let next = reorder.next() { out.append(next.ms) }
        }
        #expect(out == [9750, 9783, 9817, 9850, 9883, 9917, 9950])
        while let next = reorder.drain() { out.append(next.ms) }
        #expect(out == [9750, 9783, 9817, 9850, 9883, 9917, 9950, 9983, 10017])
    }

    @Test("A frame later than one already handed on is dropped, never handed on out of order")
    func dropsLate() {
        var reorder = MovieDecodeReorder<Int>(depth: 1)
        reorder.insert(100, 1)
        reorder.insert(200, 2)
        #expect(reorder.next()?.ms == 100)
        reorder.insert(50, 3)
        reorder.insert(300, 4)
        #expect(reorder.next()?.ms == 200)
        #expect(reorder.next() == nil)
        #expect(reorder.drain()?.ms == 300)
        #expect(reorder.drain() == nil)
    }
}
