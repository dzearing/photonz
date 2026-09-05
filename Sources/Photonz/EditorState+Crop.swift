import AppKit
import CoreGraphics
import Observation
import PhotonzCore
import PhotonzRender
import SwiftUI
import UniformTypeIdentifiers

// Cropping, resizing and canvas size: the intents that change how big
// the document is and what part of it you keep.
//
// Split out of EditorState.swift; nothing here changed on the way over.
extension EditorState {
    // MARK: - Crop mode

    func defaultCropRect() -> CGRect? {
        guard let document else { return nil }
        let base = selection.map { Geometry.pixelAligned($0.bounds) }
            ?? CGRect(origin: .zero, size: document.canvasSize)
        return Crop.fitted(base, to: cropAspect)
    }

    /// What the crop rect is confined to: the target layer's frame for a
    /// per-layer crop, else the whole canvas.
    var cropBounds: CGRect? {
        guard activeTool == .crop, let document else { return nil }
        if let id = cropTargetLayerID, let layer = document.layer(id: id) {
            return layer.frame
        }
        return CGRect(origin: .zero, size: document.canvasSize)
    }

    /// Crop rect updates from the canvas (drags already aspect-locked and
    /// canvas-clamped by `Crop`).
    func setCropRect(_ rect: CGRect) {
        cropRect = rect
    }

    /// An aspect pick re-fits the pending rect so it holds immediately.
    func setCropAspect(_ aspect: CropAspect) {
        cropAspect = aspect
        if let rect = cropRect { cropRect = Crop.fitted(rect, to: aspect) }
    }

    /// ⏎ or the toolbar checkmark: one undo step, then back to select. A
    /// layer target gets a non-destructive content crop and stays selected;
    /// otherwise the whole document crops.
    func commitCrop() {
        guard let rect = cropRect else { return }
        let aligned = Geometry.pixelAligned(rect)
        let target = cropTargetLayerID
        if let target {
            perform { $0.updateLayer(id: target) { $0.cropContent(to: aligned) } }
        } else {
            perform { $0.crop(to: aligned) }
        }
        setTool(.select)
        selectedLayerID = target
    }

    /// ⎋ or the toolbar ✕: discard the pending rect.
    func cancelCrop() {
        setTool(.select)
    }

    /// Resize-dialog apply: scales the canvas and every layer frame in one
    /// undo step.
    func resizeDocument(to size: CGSize) {
        perform { $0.resize(to: size) }
    }

    /// Canvas-size apply: grows/shrinks the canvas around the anchor without
    /// scaling content, one undo step.
    func setCanvasSize(to size: CGSize, anchor: CanvasAnchor) {
        // Growing the canvas paints the newly exposed area with the current
        // BACKGROUND fill color (Photoshop behavior): the locked Background
        // layer's bitmap is rebuilt at canvas size — bg color under the old
        // pixels at their (anchor-shifted) position — in the same undo step.
        // Skipped when there's no plain locked background image to extend
        // (cropped/transformed backgrounds keep their exact look instead).
        var extendedBackground: (id: UUID, ref: ImageRef)?
        if let doc = document,
           size.width > doc.canvasSize.width || size.height > doc.canvasSize.height,
           let background = doc.layers.first, background.isLocked,
           let oldRef = background.imageRef, background.crop == nil,
           background.transform.isIdentity,
           let oldImage = store.image(for: oldRef) {
            let dx = (size.width - doc.canvasSize.width) * anchor.unit.x
            let dy = (size.height - doc.canvasSize.height) * anchor.unit.y
            let shifted = background.frame.offsetBy(dx: dx, dy: dy)
            if let merged = Self.backgroundExtended(oldImage, drawnAt: shifted, canvas: size,
                                                    fillHex: backgroundFillHex) {
                extendedBackground = (background.id, store.register(merged))
            }
        }
        perform { doc in
            doc.setCanvasSize(size, anchor: anchor)
            if let extendedBackground {
                doc.updateLayer(id: extendedBackground.id) { layer in
                    layer.content = .image(extendedBackground.ref)
                    layer.frame = CGRect(origin: .zero, size: size)
                }
            }
        }
    }

    /// A canvas-sized bitmap: `fillHex` everywhere, with `image` composited at
    /// `frame` (document coordinates, top-left origin).
    private static func backgroundExtended(_ image: CGImage, drawnAt frame: CGRect,
                                           canvas: CGSize, fillHex: String) -> CGImage? {
        let width = Int(canvas.width.rounded()), height = Int(canvas.height.rounded())
        guard width >= 1, height >= 1, let rgba = RGBA(hex: fillHex),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // Flip the top-left document rect into CG's bottom-left space.
        context.draw(image, in: CGRect(x: frame.minX,
                                       y: CGFloat(height) - frame.maxY,
                                       width: frame.width, height: frame.height))
        return context.makeImage()
    }
}
