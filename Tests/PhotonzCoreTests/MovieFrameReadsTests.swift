import CoreGraphics
import Foundation
import PhotonzCore
import Testing

/// A recording opens on a sharp first frame (`a-recording-opens-on-a-sharp-first-frame`).
///
/// The first frame of a recording was asked for before the canvas had fitted
/// itself to the window, so it was read an eighth of the size. The fit asked
/// for it again at full size while that small read was still under way, and a
/// frame already being read was not read again, so the small one landed and
/// stayed, stretched, until the playhead moved.
@Suite("A bigger read of a frame is never lost to a smaller one")
struct MovieFrameReadsTests {

    static let frame = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    @Test("A frame nobody has read is read")
    func firstRead() {
        var reads = MovieFrameReads()
        let r1 = reads.start(Self.frame, width: 160, filedWidth: nil)
        #expect(r1)
        #expect(reads.isReading(Self.frame))
    }

    @Test("A frame already filed big enough is not read again")
    func filedBigEnough() {
        var reads = MovieFrameReads()
        let r2 = reads.start(Self.frame, width: 1280, filedWidth: 1280)
        #expect(!r2)
        let r3 = reads.start(Self.frame, width: 640, filedWidth: 1280)
        #expect(!r3)
        #expect(!reads.isReading(Self.frame))
    }

    @Test("A frame filed smaller than it is now shown is read again")
    func filedTooSmall() {
        var reads = MovieFrameReads()
        let r4 = reads.start(Self.frame, width: 1280, filedWidth: 160)
        #expect(r4)
    }

    @Test("Asking again at the same size while it is being read starts nothing")
    func sameSizeInFlight() {
        var reads = MovieFrameReads()
        let r5 = reads.start(Self.frame, width: 160, filedWidth: nil)
        #expect(r5)
        let r6 = reads.start(Self.frame, width: 160, filedWidth: nil)
        #expect(!r6)
        let r7 = reads.start(Self.frame, width: 100, filedWidth: nil)
        #expect(!r7)
    }

    @Test("The canvas fitting the window while a small read is under way reads it again bigger")
    func biggerWhileSmallerInFlight() {
        var reads = MovieFrameReads()
        let r8 = reads.start(Self.frame, width: 160, filedWidth: nil)
        #expect(r8)
        let r9 = reads.start(Self.frame, width: 1280, filedWidth: nil)
        #expect(r9)
        // ...and the bigger one is now what counts as under way.
        let r10 = reads.start(Self.frame, width: 1280, filedWidth: nil)
        #expect(!r10)
    }

    @Test("The small read landing first is filed, and the frame is still being read bigger")
    func smallLandsFirst() {
        var reads = MovieFrameReads()
        _ = reads.start(Self.frame, width: 160, filedWidth: nil)
        _ = reads.start(Self.frame, width: 1280, filedWidth: nil)
        let r11 = reads.finish(Self.frame, width: 160, landedWidth: 160, filedWidth: nil)
        #expect(r11)
        #expect(reads.isReading(Self.frame))
        let r12 = reads.finish(Self.frame, width: 1280, landedWidth: 1280, filedWidth: 160)
        #expect(r12)
        #expect(!reads.isReading(Self.frame))
    }

    @Test("The small read landing after the big one never replaces it")
    func smallLandsLast() {
        var reads = MovieFrameReads()
        _ = reads.start(Self.frame, width: 160, filedWidth: nil)
        _ = reads.start(Self.frame, width: 1280, filedWidth: nil)
        let r13 = reads.finish(Self.frame, width: 1280, landedWidth: 1280, filedWidth: nil)
        #expect(r13)
        let r14 = reads.finish(Self.frame, width: 160, landedWidth: 160, filedWidth: 1280)
        #expect(!r14)
        #expect(!reads.isReading(Self.frame))
    }

    @Test("A read that fails files nothing and lets the frame be asked for again")
    func failedRead() {
        var reads = MovieFrameReads()
        _ = reads.start(Self.frame, width: 1280, filedWidth: nil)
        let r15 = reads.finish(Self.frame, width: 1280, landedWidth: nil, filedWidth: nil)
        #expect(!r15)
        #expect(!reads.isReading(Self.frame))
        let r16 = reads.start(Self.frame, width: 1280, filedWidth: nil)
        #expect(r16)
    }

    @Test("A frame read again because it was dropped from the store is filed")
    func refillAfterDrop() {
        var reads = MovieFrameReads()
        _ = reads.start(Self.frame, width: 1280, filedWidth: nil)
        let r17 = reads.finish(Self.frame, width: 1280, landedWidth: 1280, filedWidth: nil)
        #expect(r17)
        let r18 = reads.start(Self.frame, width: 1280, filedWidth: nil)
        #expect(r18)
        let r19 = reads.finish(Self.frame, width: 1280, landedWidth: 1280, filedWidth: nil)
        #expect(r19)
    }
}
