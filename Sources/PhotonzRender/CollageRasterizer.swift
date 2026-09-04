import CoreGraphics
import Foundation
import PhotonzCore

/// Rasterizes a `CollageContent` at the layer's frame size: the backdrop fill
/// plus each filled slot's photo aspect-filled (centered crop) into its cell.
/// Empty slots render TRANSPARENT — the editor draws drop wells as overlay
/// chrome, so exports stay clean. Unlike the stroke rasterizers this draws in
/// the context's native bottom-left space (cell rects are flipped explicitly):
/// `CGContext.draw(_:in:)` would invert photos in a flipped context.
public enum CollageRasterizer {

    /// Draws `collage` inside `size` (the layer's box, in document points).
    ///
    /// `scale` is how many pixels the result gets per document point: a
    /// zoomed-in canvas bakes the cells at the resolution they are about to be
    /// seen at, so a photo with pixels to spare shows them instead of being
    /// squeezed into a document-sized picture and blown back up. Cell
    /// geometry stays in document points at every scale.
    public static func rasterize(_ collage: CollageContent, size: CGSize, store: ImageStore,
                                 scale: CGFloat = 1) -> CGImage? {
        guard scale > 0, scale.isFinite else { return nil }
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        guard width >= 1, height >= 1 else { return nil }

        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // Everything below lays out in document points; the context turns them
        // into however many pixels `scale` asked for.
        context.scaleBy(x: scale, y: scale)

        if let hex = collage.backdropColorHex, let rgba = RGBA(hex: hex) {
            context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
            context.fill(CGRect(origin: .zero, size: size))
        }

        let cells = Collage.slotFrames(for: collage, in: size)
        for (slot, cell) in zip(collage.slots, cells) {
            guard let ref = slot.imageRef, let image = store.image(for: ref),
                  cell.width > 0, cell.height > 0 else { continue }
            let content = CGRect(origin: .zero, size: ref.pixelSize)
            let crop = Collage.fillCrop(of: content, matchingAspect: cell.width / cell.height)
            guard crop.width > 0 else { continue }
            let flippedCell = CGRect(x: cell.minX, y: size.height - cell.maxY,
                                     width: cell.width, height: cell.height)
            // Draw the WHOLE photo scaled so the crop sub-rect lands exactly on
            // the cell, clipped to the cell. Uniform scale by construction.
            let scale = cell.width / crop.width
            let drawRect = CGRect(x: flippedCell.minX - crop.minX * scale,
                                  y: flippedCell.minY - (content.height - crop.maxY) * scale,
                                  width: content.width * scale,
                                  height: content.height * scale)
            context.saveGState()
            context.clip(to: flippedCell)
            context.interpolationQuality = .high
            context.draw(image, in: drawRect)
            context.restoreGState()
        }
        return context.makeImage()
    }
}
