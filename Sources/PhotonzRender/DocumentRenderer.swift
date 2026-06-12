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

    /// Per-layer content rendered once and reused across composites: CPU
    /// rasterizations (text, annotations) keyed by content value + raster
    /// size, and CIImage wraps of stored bitmaps keyed by bitmap identity
    /// (so re-registering pixels under the same ref invalidates naturally).
    /// Bounded LRU; protected by `cacheLock` because renders come from the
    /// scheduler while sprites/thumbnails render elsewhere.
    private struct RasterKey: Hashable {
        let content: LayerContent
        let pixelWidth: Int
        let pixelHeight: Int
    }
    /// Per-cache cap; the two caches together stay within 64 entries.
    private static let cacheCapacity = 32
    private var rasterCache: [RasterKey: CIImage] = [:]
    private var rasterOrder: [RasterKey] = []
    // The CIImage retains its CGImage, so identities can't be reused while
    // an entry lives.
    private var wrapCache: [ObjectIdentifier: CIImage] = [:]
    private var wrapOrder: [ObjectIdentifier] = []
    private let cacheLock = NSLock()
    /// Test hooks: how often content was served from / added to the cache.
    private(set) var contentCacheHits = 0
    private(set) var contentCacheMisses = 0
    var contentCacheCount: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return rasterCache.count + wrapCache.count
    }

    public init() {
        // CIContext picks a Metal device by default on macOS.
        self.context = CIContext(options: [.cacheIntermediates: true])
    }

    /// The cached CIImage wrap of a stored bitmap (keyed by object identity).
    private func wrapped(_ cg: CGImage) -> CIImage {
        let key = ObjectIdentifier(cg)
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let hit = wrapCache[key] {
            contentCacheHits += 1
            return hit
        }
        contentCacheMisses += 1
        let image = CIImage(cgImage: cg)
        wrapCache[key] = image
        wrapOrder.append(key)
        if wrapOrder.count > Self.cacheCapacity {
            wrapCache[wrapOrder.removeFirst()] = nil
        }
        return image
    }

    /// The cached rasterization of value-typed content at `size`, produced by
    /// `rasterize` on a miss (returning nil caches nothing).
    private func raster(for content: LayerContent, size: CGSize,
                        rasterize: () -> CGImage?) -> CIImage? {
        let key = RasterKey(content: content,
                            pixelWidth: Int(size.width.rounded()),
                            pixelHeight: Int(size.height.rounded()))
        cacheLock.lock()
        if let hit = rasterCache[key] {
            contentCacheHits += 1
            cacheLock.unlock()
            return hit
        }
        contentCacheMisses += 1
        cacheLock.unlock()
        // Rasterize outside the lock — it's the expensive part.
        guard let cg = rasterize() else { return nil }
        let image = CIImage(cgImage: cg)
        cacheLock.lock()
        if rasterCache[key] == nil {
            rasterCache[key] = image
            rasterOrder.append(key)
            if rasterOrder.count > Self.cacheCapacity {
                rasterCache[rasterOrder.removeFirst()] = nil
            }
        }
        cacheLock.unlock()
        return image
    }

    public func render(_ document: PhotonzDocument, store: ImageStore) -> CGImage? {
        guard let output = compositeImage(document, store: store) else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    // MARK: - Incremental rendering

    /// Interactive frames accumulate in a persistent bitmap so a re-render
    /// after an edit only pays for the dirty region (RenderDiff) plus one
    /// buffer→CGImage copy — a full-canvas GPU pass + readback costs more
    /// than the entire 16ms budget at 12MP. Guarded by `interactiveLock`;
    /// only `renderInteractive` touches this state.
    private var lastDocument: PhotonzDocument?
    private var lastFrame: CGImage?
    private var frameBuffer: UnsafeMutableRawPointer?
    private var frameBufferCapacity = 0
    private var frameSize = (width: 0, height: 0)
    private let interactiveLock = NSLock()
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    /// Past this share of the canvas, patching loses to a plain full render.
    private static let fullRenderAreaShare = 0.6

    deinit {
        frameBuffer?.deallocate()
    }

    /// Latest-wins re-render for the editing session. Same output as
    /// `render(_:store:)`; unchanged documents return the previous frame
    /// object, small edits patch only their dirty region.
    public func renderInteractive(_ document: PhotonzDocument, store: ImageStore) -> CGImage? {
        let width = Int(document.canvasSize.width.rounded())
        let height = Int(document.canvasSize.height.rounded())
        guard width >= 1, height >= 1 else { return nil }

        interactiveLock.lock()
        defer { interactiveLock.unlock() }

        if let lastDocument, let lastFrame, frameBuffer != nil,
           frameSize == (width, height) {
            switch RenderDiff.dirtyRegion(from: lastDocument, to: document) {
            case .none:
                return lastFrame
            case .rect(let dirty)
                where Double(dirty.width * dirty.height)
                    < Self.fullRenderAreaShare * Double(width * height):
                return renderLocked(document, store: store, region: dirty,
                                    width: width, height: height)
            default:
                break
            }
        }
        return renderLocked(document, store: store, region: nil,
                            width: width, height: height)
    }

    /// Renders `region` (or everything) of the composite into the persistent
    /// buffer and snapshots it as a CGImage. Must hold `interactiveLock`.
    private func renderLocked(_ document: PhotonzDocument, store: ImageStore,
                              region: CGRect?, width: Int, height: Int) -> CGImage? {
        guard let output = compositeImage(document, store: store) else { return nil }
        let rowBytes = width * 4
        if frameBufferCapacity < rowBytes * height {
            frameBuffer?.deallocate()
            frameBuffer = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height,
                                                           alignment: 16)
            frameBufferCapacity = rowBytes * height
        }
        guard let buffer = frameBuffer else { return nil }
        frameSize = (width, height)

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        let dirty = (region?.intersection(canvas) ?? canvas).integral.intersection(canvas)
        guard !dirty.isNull, dirty.width >= 1, dirty.height >= 1 else {
            lastDocument = document
            return lastFrame
        }
        // CI is bottom-left; rows land top-down starting at the patch's
        // top-left corner in the (top-left-origin) buffer.
        let ciBounds = CGRect(x: dirty.minX, y: CGFloat(height) - dirty.maxY,
                              width: dirty.width, height: dirty.height)
        let offset = Int(dirty.minY) * rowBytes + Int(dirty.minX) * 4
        context.render(output, toBitmap: buffer + offset, rowBytes: rowBytes,
                       bounds: ciBounds, format: .RGBA8, colorSpace: Self.srgb)

        // Snapshot with an explicit copy: the buffer mutates on the next
        // frame while delivered CGImages may stay alive (preview holds).
        let data = Data(bytes: buffer, count: rowBytes * height)
        guard let provider = CGDataProvider(data: data as CFData),
              let frame = CGImage(width: width, height: height,
                                  bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: rowBytes, space: Self.srgb,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else {
            lastDocument = nil
            lastFrame = nil
            return nil
        }
        lastDocument = document
        lastFrame = frame
        return frame
    }

    /// The composite at an integer-or-not scale factor (2 = retina export).
    /// Upscaling happens on the assembled composite with Lanczos resampling,
    /// GPU-side, before readback.
    public func render(_ document: PhotonzDocument, store: ImageStore, scale: CGFloat) -> CGImage? {
        guard scale > 0 else { return nil }
        guard scale != 1 else { return render(document, store: store) }
        guard let output = compositeImage(document, store: store) else { return nil }
        let scaled = output.applyingFilter("CILanczosScaleTransform", parameters: [
            kCIInputScaleKey: scale,
            kCIInputAspectRatioKey: 1.0
        ])
        let extent = CGRect(x: 0, y: 0,
                            width: (document.canvasSize.width * scale).rounded(),
                            height: (document.canvasSize.height * scale).rounded())
        return context.createCGImage(scaled.cropped(to: extent), from: extent)
    }

    private func compositeImage(_ document: PhotonzDocument, store: ImageStore) -> CIImage? {
        let canvas = document.canvasSize
        guard canvas.width >= 1, canvas.height >= 1 else { return nil }
        let extent = CGRect(origin: .zero, size: canvas)

        var output = CIImage(color: .clear).cropped(to: extent)

        for layer in document.layers where layer.isVisible {
            guard let layerImage = ciImage(for: layer, in: document, store: store, backdrop: output) else { continue }
            // Zoom callouts carry canvas-space chrome (source outline + leader
            // lines) that lives outside the layer frame; composite it beneath
            // the magnified box.
            if case .zoomCallout(let callout) = layer.content,
               let overlay = ZoomCalloutOverlayRasterizer.rasterize(
                   source: callout.sourceRect.standardized.intersection(extent),
                   callout: layer.frame, style: layer.style, magnification: callout.magnification,
                   shape: callout.shape) {
                let height = CGFloat(overlay.image.height)
                let positioned = CIImage(cgImage: overlay.image)
                    .transformed(by: CGAffineTransform(translationX: overlay.origin.x,
                                                       y: canvas.height - overlay.origin.y - height))
                output = positioned.composited(over: output).cropped(to: extent)
            }
            output = composite(layerImage, over: output, mode: layer.effectiveBlendMode, extent: extent)
        }

        // The canvas defines the document's bounds: layers hanging outside it
        // (e.g. after a canvas-size change) must not grow the rendered frame.
        return output.cropped(to: extent)
    }

    /// A region of the composite as pixels ("promote selection to layer").
    /// The region is clamped to the canvas; nil if nothing overlaps. The
    /// rendered CGImage and the model share a top-left origin, so the crop
    /// rect applies directly.
    public func rasterize(region: CGRect, of document: PhotonzDocument, store: ImageStore) -> CGImage? {
        let canvasRect = CGRect(origin: .zero, size: document.canvasSize)
        let clamped = region.standardized.intersection(canvasRect)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1,
              let full = render(document, store: store) else { return nil }
        return full.cropping(to: clamped)
    }

    // MARK: - Drag-preview pieces

    /// The composite with one layer hidden — the backdrop a drag preview
    /// floats over.
    public func render(_ document: PhotonzDocument, store: ImageStore, hiding id: UUID) -> CGImage? {
        var doc = document
        doc.updateLayer(id: id) { $0.isVisible = false }
        return render(doc, store: store)
    }

    /// One layer rendered alone, with `padding` document points of clear canvas
    /// on every side so shadows/blur survive. The result is positioned by the
    /// canvas view as a Core Animation sublayer during drags.
    public func renderSprite(for id: UUID, in document: PhotonzDocument, store: ImageStore,
                             padding: CGFloat) -> CGImage? {
        guard var layer = document.layer(id: id) else { return nil }
        layer.isVisible = true
        layer.frame = CGRect(x: padding, y: padding,
                             width: layer.frame.width, height: layer.frame.height)
        let doc = PhotonzDocument(canvasSize: CGSize(width: layer.frame.width + padding * 2,
                                                     height: layer.frame.height + padding * 2),
                                  layers: [layer])
        return render(doc, store: store)
    }

    /// One layer rendered alone and downscaled for the layers panel. Renders
    /// the sprite at full size (so text/annotations rasterize at their true
    /// layout) and resamples with CoreGraphics. Never upscales.
    public func thumbnail(for id: UUID, in document: PhotonzDocument, store: ImageStore,
                          maxDimension: CGFloat) -> CGImage? {
        guard let sprite = renderSprite(for: id, in: document, store: store, padding: 0) else { return nil }
        let scale = min(1, maxDimension / CGFloat(max(sprite.width, sprite.height)))
        guard scale < 1 else { return sprite }
        let width = max(1, Int((CGFloat(sprite.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(sprite.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(sprite, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    /// `backdrop` is the composite of all visible layers below this one —
    /// zoom callouts magnify a region of it, which is what keeps them live:
    /// they reference the canvas, never a baked copy.
    private func ciImage(for layer: Layer, in document: PhotonzDocument, store: ImageStore,
                         backdrop: CIImage) -> CIImage? {
        var image: CIImage
        switch layer.content {
        case .image(let ref):
            guard let cg = store.image(for: ref) else { return nil }
            image = wrapped(cg)
        case .text(let text):
            // Rasterized at the frame's size so the scale-to-frame step below is 1:1.
            guard let raster = raster(for: layer.content, size: layer.frame.size, rasterize: {
                TextRasterizer.rasterize(text, size: layer.frame.size)
            }) else { return nil }
            image = raster
        case .annotation(let annotation):
            guard let raster = raster(for: layer.content, size: layer.frame.size, rasterize: {
                AnnotationRasterizer.rasterize(annotation, size: layer.frame.size)
            }) else { return nil }
            image = raster
        case .zoomCallout(let callout):
            let canvasRect = CGRect(origin: .zero, size: document.canvasSize)
            let source = callout.sourceRect.standardized.intersection(canvasRect)
            guard !source.isNull, source.width >= 1, source.height >= 1 else { return nil }
            let flipped = CGRect(x: source.origin.x,
                                 y: document.canvasSize.height - source.maxY,
                                 width: source.width, height: source.height)
            image = backdrop.cropped(to: flipped)
                .transformed(by: CGAffineTransform(translationX: -flipped.origin.x, y: -flipped.origin.y))
        }

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

        // Circle-shaped callouts max out the corner radius (capsule on
        // non-square boxes); everything else takes the style's radius. The
        // extent here is already frame-sized, so the radius is in box space.
        let cornerRadius: CGFloat
        if case .zoomCallout(let callout) = layer.content {
            cornerRadius = callout.effectiveCornerRadius(boxSize: image.extent.size,
                                                         styleRadius: layer.style.cornerRadius)
        } else {
            cornerRadius = layer.style.cornerRadius
        }

        // Style: corner radius — clip content to a rounded rect before the
        // geometric transform so corners rotate with the layer.
        if cornerRadius > 0 {
            let mask = roundedRectImage(rect: image.extent, radius: cornerRadius, color: .white)
            image = mask.applyingFilter("CIMultiplyCompositing",
                                        parameters: [kCIInputBackgroundImageKey: image])
                .cropped(to: mask.extent)
        }

        // Style: border — an inner stroke hugging the (possibly rounded) outline.
        if layer.style.borderWidth > 0 {
            let width = layer.style.borderWidth
            let outer = roundedRectImage(rect: image.extent,
                                         radius: cornerRadius,
                                         color: ciColor(hex: layer.style.borderColorHex))
            let innerRect = image.extent.insetBy(dx: width, dy: width)
            var ring = outer
            if !innerRect.isNull, !innerRect.isEmpty {
                let inner = roundedRectImage(rect: innerRect,
                                             radius: max(0, cornerRadius - width),
                                             color: .white)
                ring = outer.applyingFilter("CISourceOutCompositing",
                                            parameters: [kCIInputBackgroundImageKey: inner])
            }
            image = ring.composited(over: image).cropped(to: image.extent)
        }

        // Geometric transform around the layer's center. LayerTransform angles are
        // defined in top-left model space; CI is y-up, so mirror the angular
        // components (conjugation by a vertical flip negates rotation and skew;
        // flips are unaffected).
        if !layer.transform.isIdentity {
            var mirrored = layer.transform
            mirrored.rotation = -mirrored.rotation
            mirrored.skewX = -mirrored.skewX
            mirrored.skewY = -mirrored.skewY
            let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
            image = image.transformed(by: mirrored.affineTransform(around: center))
        }

        // Position on canvas: the layer's center lands on the frame's center,
        // flipping from top-left model coords to CI bottom-left. Center-based so
        // rotated/skewed extents stay anchored where the frame is. Must happen
        // before the shadow, whose expanded extent would skew the centering.
        let frameCenterY = document.canvasSize.height - layer.frame.midY
        image = image.transformed(by: CGAffineTransform(translationX: layer.frame.midX - image.extent.midX,
                                                        y: frameCenterY - image.extent.midY))

        // Style: shadow — the layer's silhouette tinted, blurred, offset
        // (model y-down → CI y-up), and composited underneath.
        if let shadow = layer.style.shadow, shadow.opacity > 0 {
            let color = ciColor(hex: shadow.colorHex, alpha: shadow.opacity)
            let silhouette = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: color.red * color.alpha),
                "inputGVector": CIVector(x: 0, y: 0, z: 0, w: color.green * color.alpha),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: color.blue * color.alpha),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: color.alpha)
            ])
            let blurred = silhouette
                .applyingGaussianBlur(sigma: shadow.radius)
                .transformed(by: CGAffineTransform(translationX: shadow.offset.width,
                                                   y: -shadow.offset.height))
            image = image.composited(over: blurred)
        }

        // Style: opacity — last, so it fades content, border, and shadow together.
        if layer.style.opacity < 1 {
            let alpha = CGFloat(max(0, min(1, layer.style.opacity)))
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
            ])
        }

        return image
    }

    // MARK: - Helpers

    private func composite(_ image: CIImage, over backdrop: CIImage, mode: BlendMode, extent: CGRect) -> CIImage {
        switch mode {
        case .normal:
            return image.composited(over: backdrop)
        case .multiply:
            return image.applyingFilter("CIMultiplyBlendMode",
                                        parameters: [kCIInputBackgroundImageKey: backdrop])
                .cropped(to: extent)
        case .screen:
            return image.applyingFilter("CIScreenBlendMode",
                                        parameters: [kCIInputBackgroundImageKey: backdrop])
                .cropped(to: extent)
        }
    }

    private func roundedRectImage(rect: CGRect, radius: CGFloat, color: CIColor) -> CIImage {
        let filter = CIFilter.roundedRectangleGenerator()
        filter.extent = rect
        filter.radius = Float(radius)
        filter.color = color
        return (filter.outputImage ?? CIImage.empty()).cropped(to: rect)
    }

    private func ciColor(hex: String, alpha: Double = 1) -> CIColor {
        let c = RGBA(hex: hex) ?? RGBA(r: 0, g: 0, b: 0)
        return CIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a * alpha)
    }
}
