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
/// bitmap its dabs have been stamped onto.
struct BrushLiveStroke {
    var stroke: BrushStroke
    var walker: BrushPlacement.Walker
    let tip: PaintRasterizer.Tip
    let bitmap: CGContext
    let began: TimeInterval
}

extension CanvasNSView {

    func setUpBrushChrome() {
        brushLayer.isHidden = true
        brushLayer.zPosition = 95
        brushLayer.contentsGravity = .resize
        brushLayer.actions = ["contents": NSNull(), "opacity": NSNull(), "hidden": NSNull(),
                              "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(brushLayer)
    }

    // MARK: - The gesture

    /// A press with the Brush in hand. True when the brush took it.
    func brushMouseDown(at p: CGPoint, event: NSEvent) -> Bool {
        guard tool == .brush, let viewport, let document else { return false }
        clearBrushOverlay()
        let backing = window?.backingScaleFactor ?? 2
        let width = Int((bounds.width * backing).rounded(.up))
        let height = Int((bounds.height * backing).rounded(.up))
        let stroke = BrushStroke(samples: [], settings: brushSettings, colorHex: brushColorHex,
                                 seed: UInt32.random(in: 1...UInt32.max))
        guard width > 0, height > 0,
              let tip = PaintRasterizer.Tip(stroke: stroke, scale: viewport.zoom * backing),
              let bitmap = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        // Top-left view points, then canvas points: the dabs are stated in the
        // canvas's space and drawn where the view shows it.
        bitmap.translateBy(x: 0, y: CGFloat(height))
        bitmap.scaleBy(x: backing, y: -backing)
        bitmap.translateBy(x: viewport.origin.x, y: viewport.origin.y)
        bitmap.scaleBy(x: viewport.zoom, y: viewport.zoom)
        // Paint shows only inside the layer it will land on, so the live stroke
        // is cut to the same box.
        bitmap.clip(to: brushLandingBox(startingAt: p, in: document))
        brushStroke = BrushLiveStroke(
            stroke: stroke,
            walker: BrushPlacement.Walker(settings: stroke.settings, seed: stroke.seed,
                                          jitter: PaintRasterizer.jitter(for: stroke.settings.medium)),
            tip: tip, bitmap: bitmap, began: event.timestamp)
        brushLayer.frame = bounds
        brushLayer.contentsScale = backing
        brushLayer.opacity = Float(stroke.settings.opacity / 100)
        brushLayer.isHidden = false
        addBrushSample(at: p, event: event)
        return true
    }

    func brushMouseDragged(to p: CGPoint, event: NSEvent) {
        guard brushStroke != nil else { return }
        addBrushSample(at: p, event: event)
    }

    /// The pointer let go: the last dabs go down and the stroke is handed to
    /// the editor. The overlay stays up until the composite that holds the
    /// stroke arrives, so nothing flickers between the two.
    func brushMouseUp(at p: CGPoint, event: NSEvent) {
        guard var live = brushStroke else { return }
        brushStroke = nil
        PaintRasterizer.mark(live.walker.finish(), tip: live.tip, in: live.bitmap)
        brushLayer.contents = live.bitmap.makeImage()
        brushCommitImage = image
        onBrushStroke(live.stroke)
    }

    /// Takes the overlay down: the composite now holds the stroke, or there is
    /// no stroke to show.
    func clearBrushOverlay() {
        brushCommitImage = nil
        brushLayer.contents = nil
        brushLayer.isHidden = true
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
        guard var live = brushStroke else { return }
        // A tablet reports how hard it is pressed; a mouse reports nothing
        // worth keeping, so its samples carry none (the dynamics slice reads
        // these, nothing does yet).
        let isTablet = event.subtype == .tabletPoint
        let sample = StrokeSample(
            point: p,
            pressure: isTablet ? Double(event.pressure) : nil,
            tilt: isTablet ? CGPoint(x: event.tilt.x, y: event.tilt.y) : nil,
            ms: max(0, (event.timestamp - live.began) * 1000))
        live.stroke.samples.append(sample)
        let dabs = live.walker.add(sample)
        PaintRasterizer.mark(dabs, tip: live.tip, in: live.bitmap)
        brushStroke = live
        if !dabs.isEmpty { brushLayer.contents = live.bitmap.makeImage() }
    }

    /// The box the stroke will land in, in canvas points: the picked paint
    /// layer's, or the frame the stroke starts on, or the whole canvas, which
    /// is what `PhotonzDocument.paintStroke` decides.
    private func brushLandingBox(startingAt p: CGPoint, in document: PhotonzDocument) -> CGRect {
        if let id = selectedLayerID, let picked = document.layer(id: id), picked.paint != nil,
           !picked.isLocked, let box = document.canvasBounds(of: id) {
            return box
        }
        return document.frameID(under: p).flatMap { document.canvasBounds(of: $0) }
            ?? CGRect(origin: .zero, size: document.canvasSize)
    }
}
