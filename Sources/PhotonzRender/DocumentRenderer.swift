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
        /// Distinguishes rasterizations of the same content+size that differ by
        /// style not carried in `content` (e.g. a text glyph outline from the
        /// layer's border). Empty for content whose pixels depend only on itself.
        let variant: String
    }
    /// A frame's surface gradient, drawn once and reused. Keyed by the paint
    /// and the size it was drawn at, neither of which changes while a screen
    /// is merely being worked in, so re-rendering a screen with a gradient
    /// behind it costs what re-rendering a flat one costs.
    private struct SurfaceKey: Hashable {
        let paint: Paint
        let pixelWidth: Int
        let pixelHeight: Int
    }
    private var surfaceCache: [SurfaceKey: CIImage] = [:]
    private var surfaceOrder: [SurfaceKey] = []
    /// How big a surface gradient is ever drawn, on its longer side. A
    /// gradient is smooth, so drawing it small and stretching it is the same
    /// picture; drawing a sweep at the size of a 12-megapixel screen is a
    /// second and a half of asking every pixel what angle it sits at.
    private static let surfaceRasterCap: CGFloat = 1024
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

    /// A single process-wide CIContext shared by every renderer instance.
    /// CIContext is thread-safe and expensive to create; Apple's guidance is to
    /// make one and reuse it. Creating one per instance meant a session that
    /// spins up many renderers — or runs the render suite in parallel — built
    /// dozens of Metal contexts at once, exhausting GPU resources on
    /// constrained machines (e.g. CI VMs), observed as a full stall. The
    /// per-renderer raster/wrap caches below stay per-instance.
    private static let sharedContext = CIContext(options: [.cacheIntermediates: true])

    public init() {
        self.context = DocumentRenderer.sharedContext
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
    private func raster(for content: LayerContent, size: CGSize, variant: String = "",
                        rasterize: () -> CGImage?) -> CIImage? {
        let key = RasterKey(content: content,
                            pixelWidth: Int(size.width.rounded()),
                            pixelHeight: Int(size.height.rounded()),
                            variant: variant)
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

    /// A frame's surface gradient, sized to its own box, drawn at most
    /// `surfaceRasterCap` across and stretched back up. Nil for a flat paint,
    /// which has a cheaper way to be a color.
    private func surface(_ paint: Paint, size: CGSize) -> CIImage? {
        guard paint.isGradient, size.width >= 1, size.height >= 1 else { return nil }
        let shrink = min(1, Self.surfaceRasterCap / max(size.width, size.height))
        let rasterSize = CGSize(width: max((size.width * shrink).rounded(), 1),
                                height: max((size.height * shrink).rounded(), 1))
        let key = SurfaceKey(paint: paint,
                             pixelWidth: Int(rasterSize.width), pixelHeight: Int(rasterSize.height))
        cacheLock.lock()
        if let hit = surfaceCache[key] {
            cacheLock.unlock()
            return stretched(hit, to: size)
        }
        cacheLock.unlock()
        // Draw outside the lock — it's the expensive part.
        guard let cg = GradientPainter.image(paint, size: rasterSize) else { return nil }
        let image = CIImage(cgImage: cg)
        cacheLock.lock()
        if surfaceCache[key] == nil {
            surfaceCache[key] = image
            surfaceOrder.append(key)
            if surfaceOrder.count > Self.cacheCapacity {
                surfaceCache[surfaceOrder.removeFirst()] = nil
            }
        }
        cacheLock.unlock()
        return stretched(image, to: size)
    }

    private func stretched(_ image: CIImage, to size: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }
        return image.transformed(by: CGAffineTransform(scaleX: size.width / extent.width,
                                                       y: size.height / extent.height))
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

        let output = compositeLayers(document.layers, origin: .zero,
                                     onto: CIImage(color: .clear).cropped(to: extent),
                                     underlay: nil, in: document, store: store, clip: extent,
                                     onDesignedSurface: false)

        // The canvas defines the document's bounds: layers hanging outside it
        // (e.g. after a canvas-size change) must not grow the rendered frame.
        return output.cropped(to: extent)
    }

    /// Draws a stack of layers (bottom-up) onto `base`.
    ///
    /// `origin` is where their coordinate space starts on the canvas: `.zero`
    /// for the document's own stack, the group's canvas origin for a group's
    /// children, since a child's frame is stored against its parent.
    /// `underlay` is what sits beneath `base` on the canvas while `base` is a
    /// group's private buffer, so a zoom callout inside a group still magnifies
    /// the real canvas instead of the transparency around its group.
    /// `onDesignedSurface` says whether a component or a screen with a painted
    /// background sits above these layers, which is what tells a label on a
    /// button apart from a caption over a screenshot (`Layer.drawnShadow`).
    private func compositeLayers(_ layers: [Layer], origin: CGPoint, onto base: CIImage,
                                 underlay: CIImage?, in document: PhotonzDocument,
                                 store: ImageStore, clip: CGRect,
                                 onDesignedSurface: Bool) -> CIImage {
        var output = base
        for layer in layers where layer.isVisible {
            let frame = layer.frame.offsetBy(dx: origin.x, dy: origin.y)
            // A component's own styling is its own; what it HOLDS is inside it.
            let holdsInside = onDesignedSurface || layer.startsDesignedSurface

            // A group with no styling of its own is a container, not an object:
            // its children draw straight onto whatever is already there, so
            // grouping changes no pixels and a highlight inside a group still
            // multiplies with the canvas below it. Only a group that carries
            // styling composites into its own buffer first (`groupImage`).
            // A FRAME is never a pass-through: it has a surface to paint and an
            // edge to cut at, so it always draws as one object.
            if let group = layer.group, !group.isFrame, layer.style.isPlain {
                output = compositeLayers(group.children, origin: frame.origin, onto: output,
                                         underlay: underlay, in: document, store: store, clip: clip,
                                         onDesignedSurface: holdsInside)
                continue
            }

            // What a zoom callout magnifies: everything under it on the canvas,
            // which inside a group means its group's contents so far over the
            // canvas beneath the group.
            var backdrop = output
            if case .zoomCallout = layer.content, let underlay {
                backdrop = output.composited(over: underlay)
            }
            guard let layerImage = ciImage(for: layer, origin: origin, in: document, store: store,
                                           backdrop: backdrop,
                                           onDesignedSurface: onDesignedSurface) else { continue }
            // Zoom callouts carry canvas-space chrome (source outline + leader
            // lines) that lives outside the layer frame; composite it beneath
            // the magnified box.
            if case .zoomCallout(let callout) = layer.content,
               let overlay = ZoomCalloutOverlayRasterizer.rasterize(
                   source: callout.sourceRect.standardized
                       .intersection(CGRect(origin: .zero, size: document.canvasSize)),
                   callout: frame, style: layer.style, magnification: callout.magnification,
                   shape: callout.shape) {
                let height = CGFloat(overlay.image.height)
                let positioned = CIImage(cgImage: overlay.image)
                    .transformed(by: CGAffineTransform(translationX: overlay.origin.x,
                                                       y: document.canvasSize.height - overlay.origin.y - height))
                output = positioned.composited(over: output).cropped(to: clip)
            }
            output = composite(layerImage, over: output, mode: layer.effectiveBlendMode, extent: clip)
        }
        return output
    }

    /// A group drawn as one thing: its children composite into a private buffer
    /// first, then the group's own blur, rounded corners, border, shadow and
    /// opacity apply once, to that single picture. A card with a shadow looks
    /// like a card rather than three overlapping shadows.
    ///
    /// The buffer is sized by the group's `renderBounds` — its box grown by how
    /// far everything inside it reaches — so a child's shadow or blur is never
    /// clipped by the edge of the group. The group's own box (`localBounds`) is
    /// what rounded corners and the border follow.
    ///
    /// Blending is isolated here: a child that multiplies sees the group's
    /// contents below it, not the canvas. That is the price of being one
    /// object, and it is why a group with no styling passes through instead.
    private func groupImage(_ layer: Layer, group: GroupContent, origin: CGPoint,
                            in document: PhotonzDocument, store: ImageStore,
                            backdrop: CIImage, onDesignedSurface: Bool) -> CIImage? {
        let height = document.canvasSize.height
        let box = flipped(layer.localBounds.offsetBy(dx: origin.x, dy: origin.y), canvasHeight: height)
        // A clipping frame's buffer IS its box: everything drawn into it that
        // reaches past the edge is simply not in the picture, which is the
        // whole of what clipping means here.
        let reach = layer.clipsToFrame ? layer.localBounds : layer.renderBounds
        let buffer = flipped(reach.offsetBy(dx: origin.x, dy: origin.y), canvasHeight: height)
        guard buffer.width >= 1, buffer.height >= 1 else { return nil }

        // Children are stored against the group's origin, so their space starts
        // where the group sits.
        let childOrigin = CGPoint(x: origin.x + layer.frame.origin.x,
                                  y: origin.y + layer.frame.origin.y)
        // A frame's surface: the screen its contents sit on, painted first so
        // everything inside lands on top of it.
        let surface: CIImage
        if group.isFrame, let background = group.background {
            let area = box.intersection(buffer)
            // A ramp is aimed at the SCREEN, so it is drawn across the frame's
            // whole box and then cropped to whatever of it is in the picture:
            // a screen half off the canvas is not a differently aimed screen.
            if let gradient = self.surface(background, size: box.size) {
                surface = gradient
                    .transformed(by: CGAffineTransform(translationX: box.minX, y: box.minY))
                    .cropped(to: area)
            } else {
                surface = CIImage(color: ciColor(hex: background.hex)).cropped(to: area)
            }
        } else {
            surface = CIImage(color: .clear).cropped(to: buffer)
        }
        var image = compositeLayers(group.children, origin: childOrigin,
                                    onto: surface,
                                    underlay: backdrop, in: document, store: store, clip: buffer,
                                    onDesignedSurface: onDesignedSurface || layer.startsDesignedSurface)
            .cropped(to: buffer)

        image = blurred(image, radius: layer.style.blurRadius)
        image = rounded(image, box: box, radius: layer.style.cornerRadius)
        image = bordered(image, box: box, radius: layer.style.cornerRadius, style: layer.style)
        image = shadowed(image, shadow: layer.drawnShadow(onDesignedSurface: onDesignedSurface))
        return faded(image, opacity: layer.style.opacity)
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
        // Drawn alone, the layer has lost the component or the screen that was
        // above it, so the rule it draws under comes from the document it came
        // out of: a label inside a button must not sprout a halo in a drag
        // preview or a layers-list thumbnail that the canvas does not show.
        if document.isOnDesignedSurface(id) {
            layer.style.shadow = layer.drawnShadow(onDesignedSurface: true)
        }
        // The box the layer occupies: its frame, or for a group the box its
        // contents make (a group's own frame is an anchor with no size). Slide
        // it so that box starts `padding` in from the top left.
        let box = layer.localBounds
        guard box.width >= 1, box.height >= 1 else { return nil }
        layer.frame = layer.frame.offsetBy(dx: padding - box.minX, dy: padding - box.minY)
        let doc = PhotonzDocument(canvasSize: CGSize(width: box.width + padding * 2,
                                                     height: box.height + padding * 2),
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
    private func ciImage(for layer: Layer, origin: CGPoint, in document: PhotonzDocument,
                         store: ImageStore, backdrop: CIImage,
                         onDesignedSurface: Bool) -> CIImage? {
        if let group = layer.group {
            return groupImage(layer, group: group, origin: origin, in: document,
                              store: store, backdrop: backdrop,
                              onDesignedSurface: onDesignedSurface)
        }
        // The layer's frame in canvas coordinates: identical to its own frame
        // at the top level, shifted by its parents' origins inside a group.
        let frame = layer.frame.offsetBy(dx: origin.x, dy: origin.y)
        var image: CIImage
        switch layer.content {
        case .image(let ref):
            guard let cg = store.image(for: ref) else { return nil }
            image = wrapped(cg)
        case .text(let text):
            // Rasterized at the frame's size so the scale-to-frame step below is
            // 1:1. A border outlines the GLYPHS (inside the rasterizer); the box
            // border below is suppressed for text.
            let textBorder = layer.style.borderWidth
            let textBorderHex = layer.style.borderColorHex
            let variant = textBorder > 0 ? "outline:\(textBorder):\(textBorderHex)" : ""
            guard let raster = raster(for: layer.content, size: layer.frame.size, variant: variant, rasterize: {
                TextRasterizer.rasterize(text, size: layer.frame.size,
                                         borderWidth: textBorder, borderColorHex: textBorderHex)
            }) else { return nil }
            image = raster
        case .annotation(let annotation):
            guard let raster = raster(for: layer.content, size: layer.frame.size, rasterize: {
                AnnotationRasterizer.rasterize(annotation, size: layer.frame.size)
            }) else { return nil }
            image = raster
        case .measure(let measure):
            // The label text depends on the document's pixelScale (points
            // readout), which isn't part of the cache key's content.
            let variant = "scale:\(document.pixelScale)"
            guard let raster = raster(for: layer.content, size: layer.frame.size, variant: variant, rasterize: {
                MeasureRasterizer.rasterize(measure, size: layer.frame.size,
                                            pixelScale: document.pixelScale)
            }) else { return nil }
            image = raster
        case .collage(let collage):
            guard let raster = raster(for: layer.content, size: layer.frame.size, rasterize: {
                CollageRasterizer.rasterize(collage, size: layer.frame.size, store: store)
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
        // Handled above, before the switch: a group has no pixels of its own,
        // it draws what it holds.
        case .group:
            return nil
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
            let sx = frame.width / contentSize.width
            let sy = frame.height / contentSize.height
            image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }

        // Style: blur (clamped first so edges don't fade to transparent).
        image = blurred(image, radius: layer.style.blurRadius)

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

        // Style: corner radius, then border — both follow the layer's box, and
        // both happen before the geometric transform so they rotate with it.
        // Text is exempt from the border: its border outlines the glyphs (done
        // in the rasterizer), not the box.
        let box = image.extent
        image = rounded(image, box: box, radius: cornerRadius)
        let isTextLayer: Bool = { if case .text = layer.content { return true } else { return false } }()
        if !isTextLayer {
            image = bordered(image, box: box, radius: cornerRadius, style: layer.style)
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
        let frameCenterY = document.canvasSize.height - frame.midY
        image = image.transformed(by: CGAffineTransform(translationX: frame.midX - image.extent.midX,
                                                        y: frameCenterY - image.extent.midY))

        // Style: shadow, then opacity last so it fades content, border and
        // shadow together. Text on a designed surface leaves its contrast halo
        // undrawn: a label on a control is not a caption over a screenshot.
        image = shadowed(image, shadow: layer.drawnShadow(onDesignedSurface: onDesignedSurface))
        return faded(image, opacity: layer.style.opacity)
    }

    // MARK: - Style pieces
    //
    // Shared by a leaf layer and a group: a leaf styles its own content in its
    // frame, a group styles the composite of everything inside it, in the box
    // its contents make. Same order either way — blur, corners, border,
    // shadow, opacity.

    /// Blur, clamped first so edges don't fade to transparent.
    private func blurred(_ image: CIImage, radius: CGFloat) -> CIImage {
        guard radius > 0 else { return image }
        return image.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: image.extent)
    }

    /// Clips to a rounded rect, which is also what makes a group with rounded
    /// corners clip what it holds.
    private func rounded(_ image: CIImage, box: CGRect, radius: CGFloat) -> CIImage {
        guard radius > 0 else { return image }
        let mask = roundedRectImage(rect: box, radius: radius, color: .white)
        return mask.applyingFilter("CIMultiplyCompositing",
                                   parameters: [kCIInputBackgroundImageKey: image])
            .cropped(to: mask.extent)
    }

    /// An inner stroke hugging the (possibly rounded) outline of `box`.
    private func bordered(_ image: CIImage, box: CGRect, radius: CGFloat,
                          style: LayerStyle) -> CIImage {
        guard style.borderWidth > 0 else { return image }
        let width = style.borderWidth
        let outer = roundedRectImage(rect: box, radius: radius,
                                     color: ciColor(hex: style.borderColorHex))
        let innerRect = box.insetBy(dx: width, dy: width)
        var ring = outer
        if !innerRect.isNull, !innerRect.isEmpty {
            let inner = roundedRectImage(rect: innerRect,
                                         radius: max(0, radius - width),
                                         color: .white)
            ring = outer.applyingFilter("CISourceOutCompositing",
                                        parameters: [kCIInputBackgroundImageKey: inner])
        }
        return ring.composited(over: image).cropped(to: image.extent)
    }

    /// The silhouette tinted, blurred, offset (model y-down → CI y-up), and
    /// composited underneath. For a group the silhouette is the whole group,
    /// which is what makes a card cast one shadow instead of three.
    private func shadowed(_ image: CIImage, shadow: ShadowStyle?) -> CIImage {
        guard let shadow, shadow.opacity > 0 else { return image }
        let color = ciColor(hex: shadow.colorHex, alpha: shadow.opacity)
        var silhouette = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: color.red * color.alpha),
            "inputGVector": CIVector(x: 0, y: 0, z: 0, w: color.green * color.alpha),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: color.blue * color.alpha),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: color.alpha)
        ])
        // Spread: grow/shrink the silhouette SHAPE before blurring. Dilate
        // (max) for positive spread, erode (min) for negative — distinct
        // from blur (softness) and offset (distance).
        if shadow.spread > 0 {
            silhouette = silhouette.applyingFilter("CIMorphologyMaximum",
                                                   parameters: ["inputRadius": shadow.spread])
        } else if shadow.spread < 0 {
            silhouette = silhouette.applyingFilter("CIMorphologyMinimum",
                                                   parameters: ["inputRadius": -shadow.spread])
        }
        let cast = silhouette
            .applyingGaussianBlur(sigma: shadow.radius)
            .transformed(by: CGAffineTransform(translationX: shadow.offset.width,
                                               y: -shadow.offset.height))
        return image.composited(over: cast)
    }

    /// Fades the whole picture. For a group that is one fade for the group, not
    /// one per child, so overlapping pieces don't show through each other.
    private func faded(_ image: CIImage, opacity: Double) -> CIImage {
        guard opacity < 1 else { return image }
        let alpha = CGFloat(max(0, min(1, opacity)))
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)
        ])
    }

    // MARK: - Helpers

    /// A rect in the document's top-left space, in Core Image's bottom-left one.
    private func flipped(_ rect: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: canvasHeight - rect.maxY, width: rect.width, height: rect.height)
    }

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
