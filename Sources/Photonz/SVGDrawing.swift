import AppKit
import PhotonzRender

/// How the app reads and draws an SVG for the renderer (`VectorArt`): macOS
/// reads one into an `NSImage` whose picture is the drawing itself, so it can
/// be drawn at any number of pixels and stay sharp.
enum SVGDrawing {
    static func install() {
        VectorArt.install(VectorArt.Reader(size: size(of:), draw: draw))
    }

    /// The size the drawing says it is, or nil for bytes that are not one.
    @Sendable static func size(of data: Data) -> CGSize? {
        NSImage(data: data)?.size
    }

    /// The drawing filling `width` by `height` pixels. A fresh image per
    /// call, because the renderer asks from its own threads and one `NSImage`
    /// is not to be drawn from two at once.
    @Sendable static func draw(_ data: Data, width: Int, height: Int) -> CGImage? {
        guard let image = NSImage(data: data),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
