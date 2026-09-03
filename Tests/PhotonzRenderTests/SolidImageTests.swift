import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Solid color bitmaps")
struct SolidImageTests {

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
    }

    @Test("A solid fills the whole requested size, not a stretched thumbnail")
    func fullSize() throws {
        let image = try #require(SolidImage.make(size: CGSize(width: 320, height: 200), hex: "#FFFFFF"))
        #expect(image.width == 320)
        #expect(image.height == 200)
    }

    @Test("Every pixel carries the asked-for color, corners included")
    func uniformColor() throws {
        let image = try #require(SolidImage.make(size: CGSize(width: 64, height: 48), hex: "#FF0000"))
        for point in [(0, 0), (63, 0), (0, 47), (63, 47), (32, 24)] {
            let (r, g, b, a) = pixel(image, x: point.0, y: point.1)
            #expect(r == 255)
            #expect(g == 0)
            #expect(b == 0)
            #expect(a == 255)
        }
    }

    @Test("White is opaque white, which is what a blank canvas exports as")
    func opaqueWhite() throws {
        let image = try #require(SolidImage.make(size: CGSize(width: 8, height: 8), hex: "#FFFFFF"))
        let (r, g, b, a) = pixel(image, x: 4, y: 4)
        #expect(r == 255 && g == 255 && b == 255 && a == 255)
    }

    @Test("A size with no pixels in it makes no image instead of crashing")
    func rejectsEmpty() {
        #expect(SolidImage.make(size: CGSize(width: 0, height: 100), hex: "#FFFFFF") == nil)
        #expect(SolidImage.make(size: CGSize(width: 100, height: -5), hex: "#FFFFFF") == nil)
    }

    @Test("An unreadable color makes no image")
    func rejectsBadHex() {
        #expect(SolidImage.make(size: CGSize(width: 8, height: 8), hex: "not a color") == nil)
    }
}
