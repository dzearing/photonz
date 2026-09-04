import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

@Suite("Image codec")
struct ImageCodecTests {

    private func solidImage(width: Int, height: Int, r: UInt8, g: UInt8, b: UInt8) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                                     blue: CGFloat(b) / 255, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @Test(arguments: [ImageCodec.Format.png, .jpeg, .heic])
    func encodeDecodeRoundTripsPixelSize(format: ImageCodec.Format) throws {
        let image = solidImage(width: 64, height: 48, r: 10, g: 200, b: 30)
        let data = try #require(ImageCodec.encode(image, format: format))
        #expect(!data.isEmpty)
        let decoded = try #require(ImageCodec.decode(data))
        #expect(decoded.width == 64)
        #expect(decoded.height == 48)
    }

    @Test func pngPreservesExactPixels() throws {
        let image = solidImage(width: 8, height: 8, r: 12, g: 34, b: 56)
        let data = try #require(ImageCodec.encode(image, format: .png))
        let decoded = try #require(ImageCodec.decode(data))
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        let context = CGContext(data: &pixels, width: 8, height: 8,
                                bitsPerComponent: 8, bytesPerRow: 8 * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: 8, height: 8))
        #expect(pixels[0] == 12 && pixels[1] == 34 && pixels[2] == 56)
    }

    @Test func decodeOfGarbageReturnsNil() {
        #expect(ImageCodec.decode(Data([0xDE, 0xAD, 0xBE, 0xEF])) == nil)
    }

    @Test func pixelSizeReadsAFileWithoutDecodingIt() throws {
        let image = solidImage(width: 320, height: 200, r: 1, g: 2, b: 3)
        let data = try #require(ImageCodec.encode(image, format: .png))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-pixel-size-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ImageCodec.pixelSize(ofFileAt: url) == CGSize(width: 320, height: 200))
    }

    @Test func pixelSizeMatchesWhatDecodingTheSameFileGives() throws {
        // The landing outline a drag draws is sized from the metadata while the
        // drop itself decodes the file. If the two ever disagreed the preview
        // would be a lie, so they are checked against each other.
        let image = solidImage(width: 97, height: 41, r: 9, g: 9, b: 9)
        let data = try #require(ImageCodec.encode(image, format: .jpeg))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-pixel-size-\(UUID().uuidString).jpg")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let decoded = try #require(ImageCodec.decode(try Data(contentsOf: url)))
        #expect(ImageCodec.pixelSize(ofFileAt: url)
                == CGSize(width: decoded.width, height: decoded.height))
    }

    @Test func pixelSizeOfSomethingThatIsNotAPictureIsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-not-a-picture-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ImageCodec.pixelSize(ofFileAt: url) == nil)
        #expect(ImageCodec.pixelSize(ofFileAt: URL(fileURLWithPath: "/no/such/file.png")) == nil)
    }
}
