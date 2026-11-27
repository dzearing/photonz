import CoreGraphics
import Foundation
@testable import PhotonzRender
import Testing

/// A picture drawn over and over is made once into the pixels its drawing
/// takes as they are, so nothing converts it again each time. A clip's
/// thumbnails, in the recording's own colours, were converted again by every
/// lane picture that painted them, and a scroll's frame on the 50 track
/// reference edit waited 9 to 10 ms for it (2026-11-27,
/// `no-frame-of-a-50-track-zoom-is-held-up-by-the-sy`, pass 3).
@Suite("A picture ready to draw")
struct PictureReadyToDrawTests {

    static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    static let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    /// What `ImageRenderer` hands back: RGBA, premultiplied, in sRGB, with a
    /// half see-through stripe so the alpha shows.
    static func rendererPicture(width: Int = 40, height: Int = 10) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: 0, space: srgb,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.45, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 0.5))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 4, height: height))
        return try #require(context.makeImage())
    }

    /// Every pixel as sRGB RGBA bytes, however the picture is stored.
    static func srgbBytes(_ image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(data: &bytes, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4, space: srgb,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    @Test("It is stored the way a drawing takes it: BGRA, premultiplied, in the colours asked for")
    func displaysOwnFormat() throws {
        let made = PictureReadyToDraw.picture(try Self.rendererPicture(), in: Self.p3)
        #expect(made.bitsPerComponent == 8)
        #expect(made.bitsPerPixel == 32)
        #expect(made.alphaInfo == .premultipliedFirst)
        #expect(made.bitmapInfo.contains(.byteOrder32Little))
        #expect(made.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test("It shows the same colours and see-through as the picture it was made from")
    func samePicture() throws {
        let original = try Self.rendererPicture()
        let made = PictureReadyToDraw.picture(original, in: Self.p3)
        #expect(made.width == original.width)
        #expect(made.height == original.height)
        let before = try Self.srgbBytes(original)
        let after = try Self.srgbBytes(made)
        let worst = zip(before, after).map { abs(Int($0) - Int($1)) }.max() ?? 0
        // Rounded to 8 bits twice, there and back, and a half see-through
        // pixel's rounding doubled by the premultiplied alpha: within 4.
        #expect(worst <= 4, "the colours moved by \(worst) of 255 going to the display's colours and back")
        // The clear quarter stays clear.
        let lastColumn = (original.width - 1) * 4
        #expect(after[lastColumn + 3] == 0)
    }

    @Test("A picture already in those terms is handed back as it is, with no copy")
    func alreadyRight() throws {
        let first = PictureReadyToDraw.picture(try Self.rendererPicture(), in: Self.p3)
        let again = PictureReadyToDraw.picture(first, in: Self.p3)
        #expect(again === first)
    }

    @Test("Colours that are not known leave the picture as it was")
    func unknownDisplay() throws {
        let original = try Self.rendererPicture()
        #expect(PictureReadyToDraw.picture(original, in: nil) === original)
    }

    /// A recording's thumbnail, as a movie's image generator hands it back:
    /// opaque, in the video's own colours.
    static func thumbnail() throws -> CGImage {
        let video = try #require(CGColorSpace(name: CGColorSpace.itur_709))
        let context = try #require(CGContext(data: nil, width: 24, height: 12, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: video,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue))
        context.setFillColor(CGColor(colorSpace: video, components: [0.8, 0.3, 0.1, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 12))
        return try #require(context.makeImage())
    }

    @Test("A thumbnail in a recording's colours is made into sRGB once, so a painting that draws it converts nothing")
    func thumbnailIntoSRGB() throws {
        let original = try Self.thumbnail()
        let made = PictureReadyToDraw.picture(original, in: Self.srgb)
        #expect(made !== original)
        #expect(made.colorSpace?.name == CGColorSpace.sRGB)
        #expect(made.alphaInfo == .premultipliedFirst)
        let before = try Self.srgbBytes(original)
        let after = try Self.srgbBytes(made)
        let worst = zip(before, after).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(worst <= 1, "the colours moved by \(worst) of 255")
        #expect(PictureReadyToDraw.picture(made, in: Self.srgb) === made)
    }
}
