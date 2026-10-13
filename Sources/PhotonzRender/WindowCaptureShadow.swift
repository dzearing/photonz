import CoreGraphics
import Foundation
import PhotonzCore

/// A clicked window, made into what a capture keeps: the bare window as a
/// layer wearing a lighter copy of macOS's shadow as a style
/// (`WindowShot.document`), and that document flattened into the picture the
/// capture is saved, copied and dragged out as. The shadow is drawn here, at
/// render time, from the style, so the layered copy kept beside the picture
/// can lighten it or take it away later.
public enum WindowCaptureShadow {

    public struct Built: Sendable {
        /// The window and its shadow, transparent everywhere else.
        public let image: CGImage
        /// The layers the picture was flattened from.
        public let document: PhotonzDocument
        /// Holds the bare window the document's layer points at.
        public let store: ImageStore
    }

    /// `bare` is the window as the window server drew it without a shadow,
    /// `shadowed` the same window with macOS's shadow when it could be shot,
    /// and `scale` their pixels per point. The shadow given to the window takes
    /// its shape and darkness from `shadowed`, read before it is thrown away.
    /// Nil when the render fails, so the caller can keep the bare picture
    /// rather than lose the capture.
    public static func build(bare: CGImage, scale: CGFloat, shadowed: CGImage?,
                             renderer: DocumentRenderer = DocumentRenderer()) -> Built? {
        let reading = shadowed.flatMap(edgeProfiles(of:))
            .flatMap { WindowShot.readSystemShadow($0, pixelScale: scale) }
        let window = shadowed.flatMap { windowPixels(bare: bare, shadowed: $0) } ?? bare
        return build(bare: window, scale: scale, reading: reading, renderer: renderer)
    }

    public static func build(bare: CGImage, scale: CGFloat, reading: WindowShot.Reading?,
                             renderer: DocumentRenderer = DocumentRenderer()) -> Built? {
        let store = ImageStore()
        let ref = store.register(bare)
        let document = WindowShot.document(window: ref, pixelScale: scale, reading: reading)
        // Written in the window's own colours (Display P3 on most Macs).
        guard let image = renderer.render(document, store: store, colorSpace: rgbSpace(of: bare))
        else { return nil }
        return Built(image: image, document: document, store: store)
    }

    /// The window as macOS drew it in the shot with its shadow, and nothing of
    /// the shadow. The window server draws a dark window's light rim along
    /// with its shadow, so the bare shot comes back without it and the window
    /// loses its edge on a dark page. So the window's own pixels are cut out
    /// of the shadowed shot, and the bare shot's alpha decides what is window:
    /// its rounded corners stay exactly as clear as the bare shot has them.
    /// Nil when the shadowed shot does not hold a window the bare one's size.
    public static func windowPixels(bare: CGImage, shadowed: CGImage) -> CGImage? {
        guard let found = scan(shadowed),
              Int(found.window.width) == bare.width, Int(found.window.height) == bare.height
        else { return nil }
        let width = bare.width, height = bare.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: rgbSpace(of: bare),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // The shot drawn so the window lands on this canvas exactly. CG is
        // y-up; the scan's rect is from the top.
        let window = found.window
        context.draw(shadowed, in: CGRect(x: -window.minX,
                                          y: -(CGFloat(shadowed.height) - window.maxY),
                                          width: CGFloat(shadowed.width), height: CGFloat(shadowed.height)))
        context.setBlendMode(.destinationIn)
        context.draw(bare, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// The space a shot's colours are in, or sRGB when it is not an RGB one.
    private static func rgbSpace(of image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb { return space }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    /// Alpha read outward from the middle of each edge of a window shot, to
    /// the edge of the picture. The window is found as the run of all but
    /// opaque pixels across the middle row and down the middle column, which
    /// is a straight edge on every window: the corners are where it rounds.
    /// Nil when there is no window in the middle of the picture.
    public static func edgeProfiles(of image: CGImage) -> WindowShot.EdgeProfiles? {
        scan(image)?.profiles
    }

    /// Where the window sits in a shot, in pixels from the top left, and the
    /// alpha outward from the middle of each of its edges.
    private static func scan(_ image: CGImage) -> (window: CGRect, profiles: WindowShot.EdgeProfiles)? {
        let width = image.width, height = image.height
        guard width > 2, height > 2,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Row 0 of the buffer is the top of the picture.
        func alpha(_ x: Int, _ y: Int) -> Double { Double(pixels[(y * width + x) * 4 + 3]) / 255 }
        let opaque = 250.0 / 255
        let midX = width / 2, midY = height / 2
        guard let left = (0..<width).first(where: { alpha($0, midY) >= opaque }),
              let right = (0..<width).last(where: { alpha($0, midY) >= opaque }),
              let top = (0..<height).first(where: { alpha(midX, $0) >= opaque }),
              let bottom = (0..<height).last(where: { alpha(midX, $0) >= opaque }) else { return nil }
        let x = (left + right) / 2, y = (top + bottom) / 2
        let profiles = WindowShot.EdgeProfiles(
            below: ((bottom + 1)..<height).map { alpha(x, $0) },
            above: (0..<top).reversed().map { alpha(x, $0) },
            left: (0..<left).reversed().map { alpha($0, y) },
            right: ((right + 1)..<width).map { alpha($0, y) })
        return (CGRect(x: left, y: top, width: right - left + 1, height: bottom - top + 1), profiles)
    }
}
