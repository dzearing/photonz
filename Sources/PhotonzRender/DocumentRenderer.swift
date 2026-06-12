import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import PhotonzCore

/// Composites a PhotonzDocument into a CGImage using Core Image
/// (GPU-accelerated via Metal where available).
///
/// Coordinate convention: the document model is top-left origin (UI-style);
/// Core Image is bottom-left. This renderer flips layer frames accordingly.
public final class DocumentRenderer: @unchecked Sendable {
    private let context: CIContext

    public init() {
        // CIContext picks a Metal device by default on macOS.
        self.context = CIContext(options: [.cacheIntermediates: true])
    }

    public func render(_ document: PhotonzDocument, store: ImageStore) -> CGImage? {
        let canvas = document.canvasSize
        guard canvas.width >= 1, canvas.height >= 1 else { return nil }
        let extent = CGRect(origin: .zero, size: canvas)

        var output = CIImage(color: .clear).cropped(to: extent)

        for layer in document.layers where layer.isVisible {
            guard let layerImage = ciImage(for: layer, in: document, store: store) else { continue }
            output = layerImage.composited(over: output)
        }

        return context.createCGImage(output, from: extent)
    }

    private func ciImage(for layer: Layer, in document: PhotonzDocument, store: ImageStore) -> CIImage? {
        guard case .image(let ref) = layer.content, let cg = store.image(for: ref) else {
            // Text/annotation/zoom-callout rasterization arrives in later phases.
            return nil
        }
        var image = CIImage(cgImage: cg)

        // Layer-local crop.
        if let crop = layer.crop {
            let flipped = CGRect(x: crop.origin.x,
                                 y: image.extent.height - crop.maxY,
                                 width: crop.width, height: crop.height)
            image = image.cropped(to: flipped)
            image = image.transformed(by: CGAffineTransform(translationX: -flipped.origin.x, y: -flipped.origin.y))
        }

        // Scale content into the layer's frame.
        let contentSize = image.extent.size
        if contentSize.width > 0, contentSize.height > 0 {
            let sx = layer.frame.width / contentSize.width
            let sy = layer.frame.height / contentSize.height
            image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }

        // Style: blur (clamped first so edges don't fade to transparent).
        if layer.style.blurRadius > 0 {
            let blurred = image.clampedToExtent()
                .applyingGaussianBlur(sigma: layer.style.blurRadius)
                .cropped(to: image.extent)
            image = blurred
        }

        // Style: opacity.
        if layer.style.opacity < 1 {
            let alpha = CGFloat(max(0, min(1, layer.style.opacity)))
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
            ])
        }

        // Position on canvas, flipping from top-left model coords to CI bottom-left.
        let flippedY = document.canvasSize.height - layer.frame.maxY
        return image.transformed(by: CGAffineTransform(translationX: layer.frame.origin.x, y: flippedY))
    }
}
