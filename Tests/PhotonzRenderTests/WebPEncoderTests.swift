import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PhotonzCore
@testable import PhotonzRender

/// WebP is the one format the system cannot write, so this is the only encoder
/// in the app whose output nothing else checks. Reading stays the system's job,
/// which is what makes these round trips worth anything: every one of them
/// hands the bytes back to ImageIO, so a file that passes here is a file macOS,
/// Safari and Chrome agree is a WebP.
@Suite("WebP encoder")
struct WebPEncoderTests {

    /// A picture with a real alpha edge in it: an opaque disc fading to nothing
    /// at its rim, on an empty background. A flat square would pass an alpha
    /// test that a premultiplied-to-straight mistake fails.
    private func discWithSoftEdge(size: Int = 64) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        let colors = [CGColor(srgbRed: 1, green: 0.2, blue: 0.1, alpha: 1),
                      CGColor(srgbRed: 1, green: 0.2, blue: 0.1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  colors: colors, locations: [0, 1])!
        let middle = CGPoint(x: Double(size) / 2, y: Double(size) / 2)
        context.drawRadialGradient(gradient, startCenter: middle, startRadius: 0,
                                   endCenter: middle, endRadius: Double(size) / 2,
                                   options: [])
        return context.makeImage()!
    }

    /// Flat interface: bands of solid color with hard edges, which is what this
    /// app mostly exports and what lossless WebP is best at.
    private func flatPanels(width: Int = 96, height: Int = 64) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bands: [CGColor] = [CGColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1),
                                CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1),
                                CGColor(srgbRed: 0.20, green: 0.48, blue: 0.95, alpha: 1)]
        for (index, color) in bands.enumerated() {
            context.setFillColor(color)
            let bandHeight = Double(height) / Double(bands.count)
            context.fill(CGRect(x: 0, y: Double(index) * bandHeight,
                                width: Double(width), height: bandHeight))
        }
        return context.makeImage()!
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &bytes, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    // MARK: - The file itself

    @Test func writesARIFFContainerTheSystemRecognises() throws {
        let data = try #require(WebPEncoder.encode(flatPanels(), quality: 0.8))
        #expect(data.count > 12)
        #expect(Array(data[0..<4]) == Array("RIFF".utf8))
        #expect(Array(data[8..<12]) == Array("WEBP".utf8))
    }

    @Test func theSystemReadsBackWhatWeWrote() throws {
        let data = try #require(WebPEncoder.encode(flatPanels(width: 96, height: 64),
                                                   quality: 0.8))
        let decoded = try #require(ImageCodec.decode(data))
        #expect(decoded.width == 96)
        #expect(decoded.height == 64)
    }

    @Test func theFileIsTypedAsAWebPOnDisk() throws {
        let data = try #require(WebPEncoder.encode(flatPanels(), quality: 0.8))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photonz-webp-\(UUID().uuidString).webp")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.webP.identifier)
        #expect(ImageCodec.pixelSize(ofFileAt: url) == CGSize(width: 96, height: 64))
    }

    // MARK: - Lossless

    @Test func fullQualityIsLosslessToTheByte() throws {
        // Quality 100 means lossless for WebP, which is how the Export sheet
        // reaches it without growing a second control. Nothing weaker would do:
        // the promise is that a screenshot comes back exactly as it went in.
        let image = flatPanels()
        let data = try #require(WebPEncoder.encode(image, quality: 1))
        let decoded = try #require(ImageCodec.decode(data))
        #expect(pixels(of: decoded) == pixels(of: image))
    }

    @Test func anythingBelowFullQualityReallyThrowsPixelsAway() throws {
        let image = discWithSoftEdge(size: 128)
        let data = try #require(WebPEncoder.encode(image, quality: 0.5))
        let decoded = try #require(ImageCodec.decode(data))
        #expect(decoded.width == image.width)
        #expect(pixels(of: decoded) != pixels(of: image))
    }

    @Test func flatInterfaceIsSmallerLosslessThanLossy() throws {
        // The reason lossless is worth reaching at all, and the reason it is at
        // the TOP of the slider rather than hidden behind a switch: for the
        // pictures this app mostly makes, asking for all of the picture also
        // asks for the smaller file. Dragging right is not a trade here.
        let image = flatPanels()
        let lossless = try #require(WebPEncoder.encode(image, quality: 1))
        let lossy = try #require(WebPEncoder.encode(image, quality: 0.9))
        #expect(lossless.count < lossy.count)
        let png = try #require(ImageCodec.encode(image, format: .png))
        #expect(lossless.count < png.count)
    }

    @Test func lowerQualityMakesASmallerFile() throws {
        let image = discWithSoftEdge(size: 128)
        let rough = try #require(WebPEncoder.encode(image, quality: 0.3))
        let good = try #require(WebPEncoder.encode(image, quality: 0.9))
        #expect(rough.count < good.count)
    }

    // MARK: - Transparency

    @Test func aSoftAlphaEdgeSurvivesLossless() throws {
        let image = discWithSoftEdge()
        let data = try #require(WebPEncoder.encode(image, quality: 1))
        let decoded = try #require(ImageCodec.decode(data))
        #expect(pixels(of: decoded) == pixels(of: image))
    }

    @Test func aSoftAlphaEdgeSurvivesLossy() throws {
        // Lossy WebP keeps alpha in a separate lossless plane, so the edge is
        // still an edge: the corner stays empty and the middle stays solid.
        let image = discWithSoftEdge()
        let data = try #require(WebPEncoder.encode(image, quality: 0.85))
        let decoded = try #require(ImageCodec.decode(data))
        let source = pixels(of: image)
        let out = pixels(of: decoded)
        let corner = 3                                   // alpha of pixel (0, 0)
        let middle = ((32 * 64) + 32) * 4 + 3            // alpha of the centre
        #expect(out[corner] == 0)
        #expect(out[middle] == source[middle])
    }

    @Test func colourUnderTheEdgeIsNotDarkenedByPremultiplication() throws {
        // The trap this format sets: CGImage hands over premultiplied pixels
        // and libwebp wants straight ones. Feed it premultiplied and a fading
        // edge comes back muddy. Checked at the fading rim, not in the middle.
        let image = discWithSoftEdge()
        let data = try #require(WebPEncoder.encode(image, quality: 1))
        let decoded = try #require(ImageCodec.decode(data))
        let source = pixels(of: image)
        let out = pixels(of: decoded)
        // A ring of pixels out from the centre, where alpha is part way.
        for x in 40..<56 {
            let i = ((32 * 64) + x) * 4
            #expect(out[i] == source[i])
            #expect(out[i + 3] == source[i + 3])
        }
    }

    // MARK: - Refusals

    @Test func aPictureTooBigForTheFormatIsRefusedRatherThanWritten() {
        // WebP cannot describe a side longer than 16383 pixels. Saying no is
        // the honest answer; the caller turns it into a message.
        #expect(WebPEncoder.limit == 16383)
        #expect(!WebPEncoder.canEncode(width: 16384, height: 10))
        #expect(!WebPEncoder.canEncode(width: 10, height: 16384))
        #expect(WebPEncoder.canEncode(width: 16383, height: 16383))
    }

    // MARK: - Through ImageCodec

    @Test func imageCodecWritesWebPLikeAnyOtherFormat() throws {
        let image = flatPanels()
        let data = try #require(ImageCodec.encode(image, format: .webp, quality: 0.8))
        #expect(Array(data[8..<12]) == Array("WEBP".utf8))
        let decoded = try #require(ImageCodec.decode(data))
        #expect(decoded.width == image.width)
    }

    @Test func webPKnowsItsTypeAndItsExtension() {
        #expect(ImageCodec.Format.webp.utType == UTType.webP)
        #expect(ImageCodec.Format.webp.fileExtension == "webp")
        #expect(ImageCodec.Format(rawValue: "webp") == .webp)
    }

    @Test func webPHasAQualityLikeTheOtherLossyFormats() {
        #expect(ExportQuality.applies(toFormat: "webp"))
        // And it is the only one where the top of the slider means lossless.
        #expect(ExportQuality.isLossless(atPercent: 100, format: "webp"))
        #expect(!ExportQuality.isLossless(atPercent: 95, format: "webp"))
        #expect(!ExportQuality.isLossless(atPercent: 100, format: "jpeg"))
        #expect(ExportQuality.word(for: 100, format: "webp") == "Lossless")
        #expect(ExportQuality.word(for: 100, format: "jpeg") == "Best")
    }
}
