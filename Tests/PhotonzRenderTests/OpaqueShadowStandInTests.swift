import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A picture with nothing see-through in it throws the shadow of its box,
/// whatever it shows, so the renderer casts that shadow from a stand-in that
/// is the same on every frame and Core Image keeps its blur from one frame to
/// the next. Cast from each frame of a recording, a clip's shadow was blurred
/// afresh every frame: 5 of the 7.5 ms on the GPU each frame of the 6 minute
/// reference edit took (`a-long-edit-with-transitions-plays-scrubs-and-ed`,
/// pass 13). None of it may change a pixel.
@Suite("An opaque picture's shadow")
struct OpaqueShadowStandInTests {

    private let canvas = CGSize(width: 160, height: 120)

    private func picture(_ width: Int, _ height: Int, alpha: CGImageAlphaInfo,
                         paint: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: alpha.rawValue)!
        paint(context)
        return context.makeImage()!
    }

    private func solid(_ width: Int, _ height: Int, alpha: CGImageAlphaInfo,
                       r: CGFloat, g: CGFloat, b: CGFloat) -> CGImage {
        picture(width, height, alpha: alpha) { context in
            context.setFillColor(CGColor(srgbRed: r, green: g, blue: b, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// A light grey canvas with one picture on it, rounded, with a soft
    /// shadow thrown down and to the right: the look of a recording on a
    /// background.
    private func document(_ store: ImageStore, patch: CGImage, zoomed: Bool = false) -> PhotonzDocument {
        let base = store.register(solid(160, 120, alpha: .premultipliedLast, r: 0.85, g: 0.85, b: 0.85))
        let ref = store.register(patch)
        var doc = PhotonzDocument(canvasSize: canvas, layers: [
            Layer(name: "Base", content: .image(base), frame: CGRect(origin: .zero, size: canvas), isLocked: true)
        ])
        let shadow = ShadowStyle(radius: 9, offset: CGSize(width: 6, height: 8), colorHex: "#000000", opacity: 0.45)
        doc.addLayer(Layer(name: "Clip", content: .image(ref), frame: CGRect(x: 30, y: 20, width: 90, height: 64),
                           style: LayerStyle(cornerRadius: 10, shadows: [shadow])))
        // Punched in on, as a clip is in the middle of a zoom: part of the
        // picture enlarged to fill the box (`ClipZoom.swift`).
        if zoomed { doc.layers[doc.layers.count - 1].zoomWindow = CGRect(x: 0.23, y: 0.31, width: 0.55, height: 0.55) }
        return doc
    }

    private func drawn(_ patch: CGImage, interactive scale: CGFloat? = nil,
                       standIn: Bool = true, zoomed: Bool = false) throws -> [UInt8] {
        let store = ImageStore()
        var doc = document(store, patch: patch, zoomed: zoomed)
        let renderer = DocumentRenderer(compositing: .linearLight)
        renderer.castsOpaqueShadowsFromAStandIn = standIn
        if let scale {
            doc = doc.magnified(by: scale)
            doc.canvasSize = CGSize(width: (canvas.width * scale).rounded(), height: (canvas.height * scale).rounded())
            return rgba(try #require(renderer.renderInteractive(doc, store: store, contentScale: scale)))
        }
        return rgba(try #require(renderer.render(doc, store: store)))
    }

    /// How far apart two renders are: the most any one channel of any pixel
    /// moved, and how many pixels moved at all.
    private func apart(_ a: [UInt8], _ b: [UInt8]) -> (most: Int, pixels: Int) {
        var most = 0, pixels = 0
        for i in stride(from: 0, to: min(a.count, b.count), by: 4) {
            let step = (0..<4).map { abs(Int(a[i + $0]) - Int(b[i + $0])) }.max() ?? 0
            if step > 0 { pixels += 1; most = max(most, step) }
        }
        return (most, pixels)
    }

    @Test("An opaque picture throws the shadow it threw when cast from its own pixels, within one level at its corners")
    func sameShadow() throws {
        // The tolerance, measured: where the picture's antialiased corner meets
        // the shadow under it a channel can land one level of 255 apart.
        // Nowhere else moves.
        let red = solid(90, 64, alpha: .noneSkipLast, r: 0.9, g: 0.1, b: 0.1)
        // A picture with something in it, so an enlarging resampler has
        // edges to ring on.
        let busy = picture(90, 64, alpha: .noneSkipLast) { context in
            for x in stride(from: 0, to: 90, by: 6) {
                context.setFillColor(CGColor(srgbRed: x % 12 == 0 ? 0.9 : 0.1, green: 0.4, blue: 0.2, alpha: 1))
                context.fill(CGRect(x: x, y: 0, width: 6, height: 64))
            }
        }
        for scale in [nil, 0.5] as [CGFloat?] {
            for (patch, zoomed) in [(red, false), (busy, false), (busy, true)] {
                let gap = apart(try drawn(patch, interactive: scale, standIn: true, zoomed: zoomed),
                                try drawn(patch, interactive: scale, standIn: false, zoomed: zoomed))
                let said = "at \(scale.map { "\($0)x" } ?? "export")\(zoomed ? ", zoomed" : "")"
                #expect(gap.most <= 1, "\(said)")
                // Mid-zoom the clip's own corner moves too: drawn once rather
                // than through an intermediate it shared with its shadow, its
                // edge comes out a hair crisper (74 pixels by one level here;
                // on the reference edit's 0:15, 425 of 7.7 million by up to 21,
                // all on the corner's antialiased edge).
                #expect(gap.pixels <= (zoomed ? 100 : 8), "\(said)")
            }
        }
    }

    @Test("Two frames of different pictures throw the same shadow")
    func everyFrameThrowsOneShadow() throws {
        let red = try drawn(solid(90, 64, alpha: .noneSkipLast, r: 0.9, g: 0.1, b: 0.1))
        let blue = try drawn(solid(90, 64, alpha: .noneSkipLast, r: 0.1, g: 0.2, b: 0.9))
        // Below and to the right of the picture, where only its shadow lands.
        let width = Int(canvas.width)
        for (x, y) in [(124, 60), (100, 88), (124, 90), (70, 90)] {
            let i = (y * width + x) * 4
            #expect(Array(red[i..<i + 4]) == Array(blue[i..<i + 4]), "at \(x),\(y)")
            #expect(red[i] < 212, "a shadow lands at \(x),\(y)")
        }
    }

    @Test("A see-through picture still throws the shadow of what it covers, not of its box")
    func seeThroughKeepsItsShape() throws {
        // The left half painted, the right half clear.
        let half = picture(90, 64, alpha: .premultipliedLast) { context in
            context.setFillColor(CGColor(srgbRed: 0.9, green: 0.1, blue: 0.1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 45, height: 64))
        }
        let pixels = try drawn(half)
        let whole = try drawn(solid(90, 64, alpha: .noneSkipLast, r: 0.9, g: 0.1, b: 0.1))
        // Under the clear half's lower right corner the box's shadow would
        // land; the half picture's does not.
        let width = Int(canvas.width)
        let i = (88 * width + 118) * 4
        #expect(whole[i] < 200)
        #expect(pixels[i] > 210)
    }
}
