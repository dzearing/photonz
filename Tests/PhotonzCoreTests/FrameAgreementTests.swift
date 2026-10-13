import Testing
@testable import PhotonzCore

@Suite("How much of a frame differs from a fresh render")
struct FrameAgreementTests {

    @Test func identicalFramesAgreeEverywhere() {
        let frame: [UInt8] = [10, 20, 30, 255, 40, 50, 60, 255]
        #expect(FrameAgreement.differingShare(frame, frame) == 0)
    }

    @Test func aPixelOffByMoreThanTheToleranceCounts() {
        let fresh: [UInt8] = [10, 20, 30, 255, 40, 50, 60, 255, 0, 0, 0, 255, 9, 9, 9, 255]
        var shown = fresh
        shown[4] = 80          // second pixel's red is 40 off
        shown[9] = 5           // third pixel's green is 5 off: inside the tolerance
        #expect(FrameAgreement.differingShare(shown, fresh, tolerance: 8) == 0.25)
    }

    @Test func alphaCountsToo() {
        let fresh: [UInt8] = [0, 0, 0, 255]
        let shown: [UInt8] = [0, 0, 0, 0]
        #expect(FrameAgreement.differingShare(shown, fresh) == 1)
    }

    @Test func framesOfDifferentSizesNeverAgree() {
        #expect(FrameAgreement.differingShare([0, 0, 0, 255], [0, 0, 0, 255, 0, 0, 0, 255]) == 1)
        #expect(FrameAgreement.differingShare([], []) == 1)
    }
}
