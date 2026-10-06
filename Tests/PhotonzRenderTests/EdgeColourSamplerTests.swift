import CoreGraphics
import PhotonzCore
import Testing
@testable import PhotonzRender

/// What a Border drawn inside a picture's edge sits on: the colour of the
/// picture's outermost pixels, so the ring can be inked to stand out from it.
///
/// Found on 2026-10-06: a Border added to the dark sample recording landed in
/// graphite, at 1.3:1 against the recording's own edge, and read as nothing.
@Suite("Edge colour sampler")
struct EdgeColourSamplerTests {

    /// A picture of one colour with a different colour in a square in the
    /// middle, the way a screenshot has a window in front of its backdrop.
    private func picture(edge: (UInt8, UInt8, UInt8), middle: (UInt8, UInt8, UInt8),
                         size: Int = 64) -> CGImage {
        var data = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let inner = x > size / 4 && x < size * 3 / 4 && y > size / 4 && y < size * 3 / 4
                let c = inner ? middle : edge
                let i = (y * size + x) * 4
                data[i] = c.0; data[i + 1] = c.1; data[i + 2] = c.2; data[i + 3] = 255
            }
        }
        let context = CGContext(data: &data, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    @Test func aDarkEdgeReadsDarkWhateverIsInTheMiddle() throws {
        let edge = try #require(EdgeColourSampler.edgeColour(of: picture(edge: (48, 55, 71),
                                                                         middle: (250, 250, 250))))
        #expect(abs(edge.r - 48.0 / 255) < 0.02)
        #expect(abs(edge.g - 55.0 / 255) < 0.02)
        #expect(abs(edge.b - 71.0 / 255) < 0.02)
    }

    @Test func aLightEdgeReadsLight() throws {
        let edge = try #require(EdgeColourSampler.edgeColour(of: picture(edge: (240, 240, 240),
                                                                         middle: (10, 10, 10))))
        #expect(edge.r > 0.9)
    }

    @Test func aBorderOnADarkPictureIsInkedLight() throws {
        let edge = try #require(EdgeColourSampler.edgeColour(of: picture(edge: (48, 55, 71),
                                                                         middle: (250, 250, 250))))
        #expect(BorderInk.standingOutHex(from: Paint(hex: edge.hexString)) == BorderInk.onDark)
    }

    @Test func aPictureTooSmallToHaveAnEdgeSaysNothing() {
        #expect(EdgeColourSampler.edgeColour(of: picture(edge: (0, 0, 0), middle: (0, 0, 0), size: 1)) == nil)
    }
}
