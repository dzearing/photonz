import PhotonzCore
import Testing

@Suite("DisplayScale")
struct DisplayScaleTests {
    @Test func retinaScreenshotDPIsMapToScale() {
        #expect(DisplayScale.pixelScale(forDPI: 144) == 2)   // 2× screenshot
        #expect(DisplayScale.pixelScale(forDPI: 216) == 3)   // 3× screenshot
    }

    @Test func ordinaryDPIsStayOne() {
        #expect(DisplayScale.pixelScale(forDPI: 72) == 1)
        #expect(DisplayScale.pixelScale(forDPI: 96) == 1)
        #expect(DisplayScale.pixelScale(forDPI: 300) == 1)   // print scan, not 4×
        #expect(DisplayScale.pixelScale(forDPI: 150) == 1)   // near 2× but not clean
    }

    @Test func toleratesTinyRounding() {
        #expect(DisplayScale.pixelScale(forDPI: 145) == 2)
        #expect(DisplayScale.pixelScale(forDPI: 143) == 2)
    }

    @Test func degenerateInputIsOne() {
        #expect(DisplayScale.pixelScale(forDPI: 0) == 1)
        #expect(DisplayScale.pixelScale(forDPI: -100) == 1)
        #expect(DisplayScale.pixelScale(forDPI: .nan) == 1)
    }
}
