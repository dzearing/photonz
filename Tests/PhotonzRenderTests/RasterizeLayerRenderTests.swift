import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// End-to-end pixel check for "Rasterize Layer": baking a styled annotation
/// into a bitmap and swapping it in must leave the composite looking the same.
@Suite("Rasterize layer rendering")
struct RasterizeLayerRenderTests {

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

    private func pixels(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height,
                                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    /// The exact operation EditorState.rasterizeLayer performs, minus the
    /// undo/UI plumbing: render the padded footprint of one layer, register it,
    /// and swap the layer's content for the bitmap.
    private func rasterize(_ id: UUID, in doc: inout PhotonzDocument,
                           store: ImageStore, renderer: DocumentRenderer) {
        guard let layer = doc.layer(id: id) else { return }
        var bounds = layer.frame
        if !layer.transform.isIdentity {
            let corners = layer.transformedCorners
            if let first = corners.first {
                bounds = corners.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
                    $0.union(CGRect(origin: $1, size: .zero))
                }
            }
        }
        let pad = layer.style.previewPadding
        let region = Geometry.clampCrop(bounds.insetBy(dx: -pad, dy: -pad), toCanvas: doc.canvasSize)
        var temp = doc
        var only = layer
        only.isVisible = true
        temp.layers = [only]
        guard let raster = renderer.rasterize(region: region, of: temp, store: store) else {
            Issue.record("rasterize returned nil")
            return
        }
        let ref = store.register(raster)
        doc.rasterizeLayer(id: id, rasterized: ref, frame: region)
    }

    @Test("A styled rectangle looks identical after rasterizing")
    func styledRectangleIsPixelStableAfterRasterize() {
        let store = ImageStore()
        let renderer = DocumentRenderer()
        let base = store.register(solidImage(width: 200, height: 160, r: 40, g: 120, b: 200))
        var doc = PhotonzDocument.withBaseImage(base)

        var style = LayerStyle(opacity: 0.8, cornerRadius: 10, borderWidth: 3,
                               borderColorHex: "#FFFFFF",
                               shadow: ShadowStyle(radius: 8, offset: CGSize(width: 4, height: 6)))
        style.blurRadius = 0
        var shape = AnnotationContent(shape: .rectangle, colorHex: "#FF3B30")
        shape.fillColorHex = "#FF3B30"
        let rect = Layer(name: "Box", content: .annotation(shape),
                         frame: CGRect(x: 50, y: 40, width: 90, height: 60), style: style)
        doc.addLayer(rect)

        let before = renderer.render(doc, store: store)
        #expect(before != nil)
        rasterize(rect.id, in: &doc, store: store, renderer: renderer)
        // Content actually became a bitmap.
        if case .image = doc.layer(id: rect.id)?.content {} else {
            Issue.record("layer did not become an image")
        }
        let after = renderer.render(doc, store: store)

        guard let before, let after else { return }
        #expect(before.width == after.width && before.height == after.height)
        let a = pixels(before), b = pixels(after)
        var maxDelta = 0
        var worstCount = 0
        for i in stride(from: 0, to: min(a.count, b.count), by: 1) {
            let d = abs(Int(a[i]) - Int(b[i]))
            if d > maxDelta { maxDelta = d }
            if d > 6 { worstCount += 1 }
        }
        // Allow tiny resampling/antialias drift, but the images must match.
        #expect(maxDelta <= 12, "max per-channel delta \(maxDelta)")
        let tolerated = Double(worstCount) / Double(a.count)
        #expect(tolerated < 0.02, "\(worstCount) channels drifted >6 (\(tolerated * 100)%)")
    }
}
