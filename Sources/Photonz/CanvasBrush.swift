import AppKit
import PhotonzCore
import PhotonzRender

// The Brush on the canvas (Next, `next-brush`): the drag that paints a stroke,
// and the overlay that shows it while the pointer moves.
//
// Where the dabs go is `BrushPlacement` (PhotonzCore) and how they are marked
// is `PaintRasterizer` (PhotonzRender), the same two the document renderer
// uses, so the stroke that lands is the stroke that was drawn. This file only
// collects samples, stamps the new dabs onto a bitmap the size of the view,
// and hands the finished stroke to the editor (`docs/design/brushes.md`,
// decision 5: the document is not re-composited per mouse move).

/// The stroke under the hand: its samples so far, in canvas points, and the
/// stroke painting itself into its layer's own pixels (`PaintLayerStroke`).
struct BrushLiveStroke {
    var stroke: BrushStroke
    var walker: BrushPlacement.Walker
    /// Nil for a smudge with no paint under it: nothing to show, and nothing
    /// lands.
    let paint: PaintLayerStroke?
    /// The overlay: one layer over the layer's box, holding its pieces.
    let overlay: BrushOverlay
    /// The top-left corner of the layer the stroke lands on, in canvas points:
    /// the walker works in that layer's own points, the way the renderer does,
    /// so the paper grain under the live stroke is the paper it lands on.
    let origin: CGPoint
    let began: TimeInterval
}

/// What one stroke shows over the canvas until the picture holding it is up:
/// its overlay in square pieces of the layer's pixels, each a layer of its
/// own, so a move hands Core Animation only the pieces it touched (a 12
/// megapixel layer made into one picture on every move would cost more than a
/// frame). Placed over the layer's box and magnified the way the canvas
/// magnifies the picture under it, so the two agree pixel for pixel.
@MainActor
final class BrushOverlay {
    /// A move hands over every piece it touched whole, matched to the
    /// screen's colours: at 256 a 20 point brush's move turned 67,000 pixels
    /// to hand over a few hundred, a third of the move (2026-10-30).
    static let piece = 128
    static let apron: CGFloat = 2
    let layer = CALayer()
    /// The layer's box, in canvas points, and its pixels per point.
    let box: CGRect
    let scale: CGFloat
    /// Each piece and the layer's pixels it shows.
    private var pieces: [Int: (layer: CALayer, pixels: CGRect)] = [:]
    /// Once the stroke has been handed over: the composite and the sharp copy
    /// on screen then. The picture holding the stroke is up once the composite
    /// has changed, and the sharp copy too when there was one.
    var landedOver: (image: CGImage?, tile: CGImage?)?

    init(box: CGRect, scale: CGFloat) {
        self.box = box
        self.scale = scale
        layer.anchorPoint = .zero
        layer.actions = ["contents": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
                         "bounds": NSNull(), "position": NSNull(), "sublayers": NSNull()]
    }

    /// Lays the overlay over the layer's box as `viewport` shows it, each
    /// piece magnified the way the canvas magnifies its picture.
    func place(in viewport: Viewport) {
        let topLeft = viewport.viewPoint(fromDocument: box.origin)
        layer.frame = CGRect(x: topLeft.x, y: topLeft.y, width: box.width * viewport.zoom,
                             height: box.height * viewport.zoom)
        for piece in pieces.values { lay(piece.layer, over: piece.pixels, in: viewport) }
    }

    private func lay(_ piece: CALayer, over pixels: CGRect, in viewport: Viewport) {
        let pointsPerPixel = viewport.zoom / scale
        piece.frame = CGRect(x: pixels.minX * pointsPerPixel, y: pixels.minY * pointsPerPixel,
                             width: pixels.width * pointsPerPixel, height: pixels.height * pointsPerPixel)
        piece.magnificationFilter = viewport.zoom >= 2 ? .nearest : .linear
    }

    /// Hands the pieces under `touched` (the layer's pixels) their pictures,
    /// drawn side by side in `space`, the screen's colours.
    func refresh(_ touched: CGRect, from paint: PaintLayerStroke, in viewport: Viewport, space: CGColorSpace?) {
        guard !touched.isNull, !touched.isEmpty else { return }
        let size = Self.piece
        let across = (paint.width + size - 1) / size, down = (paint.height + size - 1) / size
        let x0 = max(0, Int(touched.minX) / size), x1 = min(across - 1, Int(touched.maxX.rounded(.up) - 1) / size)
        let y0 = max(0, Int(touched.minY) / size), y1 = min(down - 1, Int(touched.maxY.rounded(.up) - 1) / size)
        guard x0 <= x1, y0 <= y1 else { return }
        var due: [(layer: CALayer, pixels: CGRect)] = []
        for y in y0...y1 {
            for x in x0...x1 {
                let index = y * across + x
                if let made = pieces[index] {
                    due.append(made)
                    continue
                }
                let piece = CALayer()
                piece.anchorPoint = .zero
                piece.contentsGravity = .resize
                piece.minificationFilter = .linear
                // Side by side at a fraction of a pixel, two softened
                // edges each cover half of the pixel on their line and
                // leave a pale seam across the stroke; hard edges share
                // it out whole.
                piece.edgeAntialiasingMask = []
                piece.allowsEdgeAntialiasing = false
                piece.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
                let pixels = CGRect(x: x * size, y: y * size, width: min(size, paint.width - x * size),
                                    height: min(size, paint.height - y * size))
                lay(piece, over: pixels, in: viewport)
                pieces[index] = (piece, pixels)
                layer.addSublayer(piece)
                due.append((piece, pixels))
            }
        }
        // Each piece carries a border of its neighbours' pixels and shows only
        // its own (`contentsRect`), so where Core Animation filters across a
        // join it reads the pixels really there; cut at its own edge, every
        // join drew a faint line. Past the layer's edge the border is clear,
        // as the layer is.
        let aprons = due.map { $0.pixels.insetBy(dx: -Self.apron, dy: -Self.apron) }
        var pictures = [CGImage?](repeating: nil, count: due.count)
        pictures.withUnsafeMutableBufferPointer { out in
            let drawing = PieceDrawing(paint: paint, slots: out, aprons: aprons, space: space)
            DispatchQueue.concurrentPerform(iterations: aprons.count) { i in drawing.draw(i) }
        }
        for (i, piece) in due.enumerated() {
            piece.layer.contents = pictures[i]
            let pixels = piece.pixels, apron = aprons[i]
            piece.layer.contentsRect = CGRect(x: (pixels.minX - apron.minX) / apron.width,
                                              y: (pixels.minY - apron.minY) / apron.height,
                                              width: pixels.width / apron.width, height: pixels.height / apron.height)
        }
    }
}

/// The pieces of one move, drawn side by side. @unchecked Sendable:
/// `concurrentPerform` returns only once every piece is drawn, the stroke is
/// only read while it runs, and each piece writes its own slot.
private struct PieceDrawing: @unchecked Sendable {
    let paint: PaintLayerStroke
    let slots: UnsafeMutableBufferPointer<CGImage?>
    let aprons: [CGRect]
    let space: CGColorSpace?

    func draw(_ i: Int) {
        slots[i] = paint.picture(of: aprons[i], padded: true, in: space)
    }
}

/// The paint a brush press reads: one paint layer as it stands, at the scale
/// the canvas shows it.
struct BrushPaintRequest: Equatable, Sendable {
    let layer: UUID
    let paint: PaintContent
    /// The layer's box, in canvas points.
    let box: CGRect
    /// Pixels per point: what the renderer bakes the layer at for the picture
    /// on screen (`CanvasNSView.shownPaintScale`), so the raster the last
    /// render kept is the one it reads.
    let scale: CGFloat

    func base() -> PaintLayerBase? {
        PaintRasterCache.shared.base(paint, size: box.size, scale: scale)
    }
}

/// What `warmBrushPaint` read ahead of the next press.
struct BrushPreparedPaint {
    let request: BrushPaintRequest
    let base: PaintLayerBase
}

extension CanvasNSView {

    func setUpBrushChrome() {
        brushLayer.zPosition = 95
        brushLayer.actions = ["contents": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
                              "bounds": NSNull(), "position": NSNull(), "sublayers": NSNull()]
        layer?.addSublayer(brushLayer)
    }

    /// The pixels per point a paint layer whose box is `box` is drawn at in
    /// the picture on screen: the sharp copy's when the canvas lays one over
    /// the composite (`EditorState.refreshCrispTile`), the composite's
    /// otherwise. The live stroke is painted at exactly this, so it is the
    /// same pixels before and after it lands.
    /// The screen's colours, which the composite is drawn in too
    /// (`EditorState.canvasColorSpace`).
    var canvasColorSpace: CGColorSpace? { window?.colorSpace?.cgColorSpace }

    func shownPaintScale(box: CGSize) -> CGFloat {
        guard let viewport else { return 1 }
        let scale = viewport.zoom * (window?.backingScaleFactor ?? 2)
        guard Experiments.shared.crispZoomEnabled, scale > 1.01, document?.hasTime != true else { return 1 }
        return DocumentRenderer.bakeScale(scale, box: box)
    }

    // MARK: - The gesture

    /// A press with the Brush in hand. True when the brush took it.
    func brushMouseDown(at p: CGPoint, event: NSEvent) -> Bool {
        guard tool == .brush, let viewport, let document else { return false }
        // Stamped with when it began, so watercolour knows which earlier
        // strokes are still wet, on every replay as now.
        let stroke = BrushStroke(samples: [], settings: brushSettings, colorHex: brushColorHex,
                                 seed: UInt32.random(in: 1...UInt32.max),
                                 startedAt: Date().timeIntervalSinceReferenceDate)
        let smudging = stroke.settings.mode == .smudge
        // Paint shows only inside the layer it will land on, so the live
        // stroke is cut to the same box. A smudge lands on the paint under it,
        // or nowhere.
        let target = smudging ? document.smudgeTarget(at: p, picked: selectedLayerID) : nil
        let box = smudging ? target.flatMap { document.canvasBounds(of: $0) }
                           : brushLandingBox(startingAt: p, in: document)
        let landing = smudging ? target : pickedPaintLayer(in: document)
        let origin = box?.origin ?? .zero
        var paint: PaintLayerStroke?
        var scale: CGFloat = 1
        if let box {
            scale = shownPaintScale(box: box.size)
            // The layer as it stands at that scale: the raster the last render
            // kept, read ahead of the press by `warmBrushPaint` when nothing
            // has changed since. A stroke starting a new layer lands on fresh
            // paper. Every stroke on the layer used to be replayed on this
            // press: 420 ms with ten on a 12 megapixel canvas, 2026-10-25.
            var base: PaintLayerBase?
            if let landing, let content = document.layer(id: landing)?.paint {
                let request = BrushPaintRequest(layer: landing, paint: content, box: box, scale: scale)
                if let prepared = brushPreparedPaint, prepared.request == request {
                    base = prepared.base
                } else {
                    base = request.base()
                }
            }
            brushPreparedPaint = nil
            // A smudge with no paint under it shows nothing and lands nothing.
            if !smudging || base != nil {
                paint = PaintLayerStroke(stroke: stroke, base: base, size: box.size, scale: scale)
            }
        }
        let overlay = BrushOverlay(box: box ?? .zero, scale: scale)
        overlay.place(in: viewport)
        // A smudge's, a marker's, a wash's or oil's overlay holds what it lays over
        // the paint, already at its strength; a stroke's holds the stroke
        // alone, shown at its opacity.
        overlay.layer.opacity = Float(paint.map { $0.showsAtFullStrength ? 1 : $0.opacity } ?? 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        brushLayer.addSublayer(overlay.layer)
        CATransaction.commit()
        brushStroke = BrushLiveStroke(
            stroke: stroke,
            walker: BrushPlacement.Walker(settings: stroke.settings, seed: stroke.seed,
                                          jitter: PaintRasterizer.jitter(for: stroke.settings.medium)),
            paint: paint, overlay: overlay, origin: origin, began: event.timestamp)
        addBrushSample(at: p, event: event)
        if stroke.settings.medium == .airbrush, stroke.settings.mode == .paint { startBrushDwell() }
        return true
    }

    /// An airbrush keeps spraying while the button is down, moving or not,
    /// but the pointer only reports when it moves: so while the stroke lasts,
    /// a tick that finds no sample for a while hands the stroke one where the
    /// pointer last was. Stored with the stroke, so what lands is what built
    /// up on screen.
    private func startBrushDwell() {
        brushDwellTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.brushDwellTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        brushDwellTimer = timer
    }

    private func stopBrushDwell() {
        brushDwellTimer?.invalidate()
        brushDwellTimer = nil
    }

    private func brushDwellTick() {
        guard let live = brushStroke, let last = live.stroke.samples.last else {
            stopBrushDwell()
            return
        }
        let ms = (ProcessInfo.processInfo.systemUptime - live.began) * 1000
        // The pointer reports many times a second while it moves; only a
        // pause this long is the hand holding still.
        guard ms - last.ms >= 25 else { return }
        appendBrushSample(StrokeSample(point: last.point, pressure: last.pressure, tilt: last.tilt, ms: ms))
    }

    nonisolated static func brushBitmap(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    func brushMouseDragged(to p: CGPoint, event: NSEvent) {
        guard brushStroke != nil else { return }
        addBrushSample(at: p, event: event)
    }

    /// The pointer let go: the last dabs go down and the stroke is handed to
    /// the editor. The overlay stays up until the picture that holds the
    /// stroke is on screen, the sharp copy included when the canvas lays one
    /// over the composite, so nothing on the canvas changes as it lands.
    func brushMouseUp(at p: CGPoint, event: NSEvent) {
        stopBrushDwell()
        guard var live = brushStroke else { return }
        brushStroke = nil
        if let paint = live.paint, let viewport {
            var touched = paint.mark(live.walker.finish())
            touched = touched.union(paint.finish())
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            live.overlay.refresh(touched, from: paint, in: viewport, space: canvasColorSpace)
            CATransaction.commit()
        }
        live.overlay.landedOver = (image, crispLayer.isHidden ? nil : crispTile?.image)
        brushLandings.append(live.overlay)
        onBrushStroke(live.stroke)
    }

    /// Takes down every stroke's overlay whose picture is now on screen: the
    /// composite has changed since it was handed over, and so has the sharp
    /// copy if one was up then. Taken down sooner, the canvas showed the
    /// stretched composite under it for the tenth of a second the sharp copy
    /// took, and every stroke on the layer went soft and sharpened again.
    func settleBrushLandings() {
        guard !brushLandings.isEmpty else { return }
        let tileNow = crispLayer.isHidden ? nil : crispTile?.image
        var waiting: [BrushOverlay] = []
        for overlay in brushLandings {
            guard let over = overlay.landedOver else { continue }
            let composited = image !== over.image
            let sharpened = over.tile == nil || tileNow !== over.tile
            if composited && sharpened {
                overlay.layer.removeFromSuperlayer()
            } else {
                waiting.append(overlay)
            }
        }
        brushLandings = waiting
    }

    /// Takes every overlay down: the composite now holds the strokes, or
    /// there is no stroke to show.
    func clearBrushOverlay() {
        brushLandings.removeAll()
        brushLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
    }

    /// With the Brush in hand, the paint the next press reads (the picked
    /// paint layer at the scale it is shown at) is read in the background as
    /// soon as the document holds it, so the press finds it ready. Usually the
    /// raster the render of the last stroke kept (`PaintRasterCache`), so
    /// nothing is simulated; after a zoom to a new scale, the layer is drawn
    /// at it here rather than while the hand waits. One at a time, the newest
    /// wanted next: a pan with the brush in hand does not queue one per frame.
    func warmBrushPaint() {
        guard tool == .brush, brushStroke == nil, let document,
              let id = pickedPaintLayer(in: document), let paint = document.layer(id: id)?.paint,
              let box = document.canvasBounds(of: id) else {
            brushPaintWanted = nil
            if tool != .brush { brushPreparedPaint = nil }
            return
        }
        let request = BrushPaintRequest(layer: id, paint: paint, box: box, scale: shownPaintScale(box: box.size))
        guard brushPreparedPaint?.request != request, brushPaintWanted != request else { return }
        brushPaintWanted = request
        guard !brushPaintDrawing else { return }
        brushPaintDrawing = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let base = request.base()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.brushPaintDrawing = false
                if let base, self.brushPaintWanted == request {
                    self.brushPreparedPaint = BrushPreparedPaint(request: request, base: base)
                    self.brushPaintWanted = nil
                } else {
                    // Something newer is wanted: read that instead.
                    let wanted = self.brushPaintWanted
                    self.brushPaintWanted = nil
                    if let wanted, wanted != request { self.warmBrushPaint() }
                }
            }
        }
    }

    /// The pointer with the Brush in hand: a ring the size of the tip at this
    /// zoom, dark inside light so it reads over any picture, with a dot in the
    /// middle. Kept within what a cursor can be; a tiny tip gets a ring that
    /// can still be seen.
    var brushCursor: NSCursor {
        let zoom = viewport?.zoom ?? 1
        let diameter = min(max(CGFloat(brushSettings.size) * zoom, 7), 250).rounded()
        if let cached = brushCursorCache, cached.diameter == diameter { return cached.cursor }
        let side = diameter + 4
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let ring = NSRect(x: 2, y: 2, width: diameter, height: diameter)
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let outer = NSBezierPath(ovalIn: ring.insetBy(dx: -0.75, dy: -0.75))
            outer.lineWidth = 1.5
            outer.stroke()
            NSColor.black.withAlphaComponent(0.85).setStroke()
            let inner = NSBezierPath(ovalIn: ring)
            inner.lineWidth = 1
            inner.stroke()
            let c = side / 2
            NSColor.black.withAlphaComponent(0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: c - 1, y: c - 1, width: 2, height: 2)).fill()
            return true
        }
        let cursor = NSCursor(image: image, hotSpot: NSPoint(x: side / 2, y: side / 2))
        brushCursorCache = (diameter, cursor)
        return cursor
    }

    /// Whether a stroke is being painted right now.
    var brushIsPainting: Bool { brushStroke != nil }

    /// Escape with the Brush in hand and no stroke under way puts it down
    /// (decision 3: V or Escape). True when the brush answered the key.
    func brushKeyDown(_ event: NSEvent) -> Bool {
        guard tool == .brush, brushStroke == nil, event.keyCode == 53,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        else { return false }
        onToolChange(.select)
        return true
    }

    private func addBrushSample(at p: CGPoint, event: NSEvent) {
        guard let live = brushStroke else { return }
        // A tablet reports how hard it is pressed and how far it leans; a
        // mouse reports nothing worth keeping, so its samples carry none and
        // placement simulates a press (`BrushDynamics`).
        let isTablet = event.subtype == .tabletPoint
        var pressure: Double? = isTablet ? Double(event.pressure) : nil
        var tilt: CGPoint? = isTablet ? CGPoint(x: event.tilt.x, y: event.tilt.y) : nil
        #if PHOTONZ_PLAYTEST
        // A walk holding a pen (`pen` step): its synthesized moves carry no
        // tablet reading of their own.
        if let pen = PlaytestPointer.pen {
            pressure = pen.pressure ?? pressure
            tilt = pen.tilt ?? tilt
        }
        #endif
        appendBrushSample(StrokeSample(point: p, pressure: pressure, tilt: tilt,
                                       ms: max(0, (event.timestamp - live.began) * 1000)))
    }

    /// Adds one sample (canvas points) to the stroke under the hand and marks
    /// the dabs it settles.
    private func appendBrushSample(_ sample: StrokeSample) {
        guard var live = brushStroke else { return }
        // Never back in time: a tick and an event can cross.
        var sample = sample
        if let last = live.stroke.samples.last { sample.ms = max(sample.ms, last.ms) }
        // A pen's own press thins the end of its stroke; only a mouse
        // stroke's end is thinned in as it goes (`BrushPlacement.taperedOut`).
        if live.stroke.samples.isEmpty, sample.pressure != nil { live.paint?.tapersItsEnd = false }
        live.stroke.samples.append(sample)
        // The walker works in the landing layer's own points, as the renderer
        // does once the stroke is stored there.
        var local = sample
        local.point = CGPoint(x: sample.point.x - live.origin.x, y: sample.point.y - live.origin.y)
        let dabs = live.walker.add(local)
        brushStroke = live
        guard !dabs.isEmpty, let paint = live.paint, let viewport else { return }
        let touched = paint.mark(dabs)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        live.overlay.refresh(touched, from: paint, in: viewport, space: canvasColorSpace)
        CATransaction.commit()
    }

    /// The picked paint layer a stroke will be added to, when there is one:
    /// unlocked, the way `PhotonzDocument.paintStroke` decides.
    private func pickedPaintLayer(in document: PhotonzDocument) -> UUID? {
        guard let id = selectedLayerID, let picked = document.layer(id: id), picked.paint != nil,
              !picked.isLocked else { return nil }
        return id
    }

    /// The box the stroke will land in, in canvas points: the picked paint
    /// layer's, or the frame the stroke starts on, or the whole canvas, which
    /// is what `PhotonzDocument.paintStroke` decides.
    private func brushLandingBox(startingAt p: CGPoint, in document: PhotonzDocument) -> CGRect {
        if let id = pickedPaintLayer(in: document), let box = document.canvasBounds(of: id) {
            return box
        }
        return document.frameID(under: p).flatMap { document.canvasBounds(of: $0) }
            ?? CGRect(origin: .zero, size: document.canvasSize)
    }
}
