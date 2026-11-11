import CoreGraphics
import Foundation
import ImageIO
import PhotonzCore
import PhotonzRender
import Testing
import UniformTypeIdentifiers

/// The calm redline of the settings screenshot, drawn the way the app draws
/// it: the picture, then every caliper the redline lays, each through the
/// renderer's own `MeasureRasterizer`. It is the before and after picture of
/// a change to how a measurement looks, without a model or a running app.
///
/// `PHOTONZ_REDLINE_SHEET=<path.png>` writes the picture there.
@Suite("The calm redline drawn on its picture")
struct RedlineSheetTests {

    static func drawn(_ name: String) throws -> CGImage {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "png"))
        let picture = try #require(ImageCodec.decode(try Data(contentsOf: url)))
        let read = try RedlinePlanTests.read(name)
        let calipers = RedlinePlanTests.laid(read)
        let width = picture.width, height = picture.height
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4,
                                             space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(picture, in: whole)
        for caliper in calipers {
            // The calipers are in document space, so a document-sized bitmap
            // puts each where it lands on the canvas.
            let layer = try #require(MeasureRasterizer.rasterize(caliper, size: whole.size, pixelScale: 2))
            context.draw(layer, in: whole)
        }
        return try #require(context.makeImage())
    }

    @Test("The settings redline draws over its picture")
    func settingsSheet() throws {
        let image = try Self.drawn(RedlinePlanTests.settings)
        #expect(image.width > 0)
        if let path = ProcessInfo.processInfo.environment["PHOTONZ_REDLINE_SHEET"] {
            try Self.write(image, to: path)
        }
        // `PHOTONZ_REDLINE_SHEETS=<folder>` draws every screen the layout is
        // tested on, one picture each.
        guard let folder = ProcessInfo.processInfo.environment["PHOTONZ_REDLINE_SHEETS"] else { return }
        for name in RedlinePlanTests.screens {
            let file = name.replacingOccurrences(of: "/", with: "-") + ".png"
            try Self.write(try Self.drawn(name), to: (folder as NSString).appendingPathComponent(file))
        }
    }

    static func write(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }
}

/// The ticks across a flat measuring line are drawn into the picture, where
/// the line meets the edges it measures.
@Suite("A flat measuring line draws a tick at each end")
struct MeasureEndTickRasterTests {

    @Test("Both ends of a 120 point gap line carry a tick across the line")
    func ticksAreDrawn() throws {
        var c = MeasureContent(mode: .horizontal, unit: .points)
        c.start = CGPoint(x: 40, y: 50)
        c.end = CGPoint(x: 280, y: 50)
        c.headOffset = 0
        c.showLabel = false
        c.strokeWidth = 2
        c.strokeColorHex = "#FF0000"
        let image = try #require(MeasureRasterizer.rasterize(c, size: CGSize(width: 320, height: 100), pixelScale: 2))
        let data = try #require(image.dataProvider?.data as Data?)
        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[y * image.bytesPerRow + x * 4 + 3] }
        // Off the line, across each end: inked. Off the line in the middle: clear.
        let off = Int(MeasureBuilder.endTickHalf) - 2
        #expect(alpha(40, 50 - off) > 128)
        #expect(alpha(40, 50 + off) > 128)
        #expect(alpha(280, 50 - off) > 128)
        #expect(alpha(160, 50 - off) == 0)
    }
}
