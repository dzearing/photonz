import CoreGraphics
import Foundation
import Testing
import PhotonzCore
@testable import PhotonzRender

/// A layer pulled forward in 3D casts a larger, softer shadow, and one pushed
/// back a tighter one (`DepthShadow`, `perspective-pill-and-a-shadow-that-
/// grows-as-a-3d`). Measured as how far the shadow reaches below the card the
/// camera sees, down its middle column.
@Suite("Depth shadow rendering")
struct DepthShadowRenderTests {

    private static func solid(_ width: Int, _ height: Int, gray: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func pixels(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let context = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// How many rows below the card the camera sees its shadow darkens the
    /// white base by more than four levels, and the card's own drawn height.
    static func reach(depth: Double) -> (shadow: Int, card: Int) {
        let store = ImageStore()
        let base = store.register(solid(400, 400, gray: 1))
        let patch = store.register(solid(100, 60, gray: 0.5))
        var doc = PhotonzDocument.withBaseImage(base)
        var layer = Layer(name: "Card", content: .image(patch), frame: CGRect(x: 150, y: 150, width: 100, height: 60))
        layer.style.shadows = [ShadowStyle(radius: 4, offset: CGSize(width: 0, height: 8), opacity: 0.6)]
        layer.turn3D = LayerTurn3D(depth: depth)
        doc.addLayer(layer)
        let out = DocumentRenderer().render(doc, store: store)!
        let data = pixels(out)
        let projection = Projection3D(camera: doc.camera, canvas: doc.canvasSize)
        let quad = Space3D.quad(of: layer.frame, through: layer.turn3D!.affine(pivot: layer.turnPivot), projection)!
        let bottom = Int(quad[2].y.rounded(.up))
        var rows = 0
        for y in bottom..<out.height {
            let v = data[(y * out.width + 200) * 4]
            if v < 251 { rows += 1 } else if rows > 0 { break }
        }
        return (rows, Int((quad[2].y - quad[1].y).rounded()))
    }

    @Test("Forward, the shadow reaches further below the card; back, less far; flat in between")
    func shadowGrowsForward() {
        let back = Self.reach(depth: -200)
        let flat = Self.reach(depth: 0)
        let forward = Self.reach(depth: 200)
        #expect(forward.shadow > flat.shadow + 6, "forward \(forward) flat \(flat)")
        #expect(back.shadow < flat.shadow, "back \(back) flat \(flat)")
        // About twice as far at the doubling depth, half at its opposite.
        #expect(Double(forward.shadow) >= Double(flat.shadow) * 1.6, "forward \(forward) flat \(flat)")
        #expect(Double(back.shadow) <= Double(flat.shadow) * 0.75, "back \(back) flat \(flat)")
    }
}
