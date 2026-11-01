import AppKit
import PhotonzCore

// The reworked selection on the canvas (Next, `next-transform-modes`; the
// user's approved prototype `docs/design/mocks/pages/selection-transform.html`
// building on `lang-selection.html` section 03b).
//
// One set of grips in every mode: white square corners, a white pill just
// outside each edge, and a white knob with a clockwise arrow hanging on a
// dotted stem off the top edge. A chip beside the knob picks Size or 3D. In
// 3D the same edge pills tip and swing the layer and a grip below the card
// pushes it back or pulls it forward; corners still resize and the knob still
// turns. A tag under the frame says the size, or in 3D the tip, swing and
// depth, and while the pointer rests on a grip, what that grip does.
//
// Everything is drawn flat at the card's corners as the camera sees them, so
// it is one size on screen however the card is turned. Where each grip sits,
// which one a press takes and what a drag does are `SelectionGrips`,
// `SelectionTag` and `SelectionDrag` in PhotonzCore, tested there. This file
// draws, and hands each press to the drag that already does the work: the
// frame resize, the flat turn, and the 3D turn (`CanvasSpaceHandles`).

extension CanvasNSView {

    enum GripLook {
        static let iconInk = CGColor(srgbRed: 0.227, green: 0.227, blue: 0.235, alpha: 1)
        static let tagInset = CGSize(width: 7, height: 4)
        static let tagRadius: CGFloat = 6
        static let chipRadius: CGFloat = 7
        static let chipButtonRadius: CGFloat = 5
    }

    var transformModesOffered: Bool { Experiments.shared.transformModesEnabled && tool == .select }

    /// The modes the chip offers: 3D only while turning in depth is on at all.
    var offeredTransformModes: [TransformMode] {
        Experiments.shared.turnInDepthEnabled ? TransformMode.offered : [.size]
    }

    func setUpSelectionGripChrome() {
        selectionGripsLayer.zPosition = 100
        selectionGripsLayer.isHidden = true
        layer?.addSublayer(selectionGripsLayer)
        for shape in [gripStemsLayer, gripsShapeLayer, gripGlyphsLayer, litGripLayer, litGripGlyphLayer,
                      chipPlateLayer, chipPickedLayer, chipIconsLayer, chipPickedIconLayer, gripTagLayer] {
            shape.lineWidth = SelectionGrips.lineWidth
            shape.lineCap = .round
            shape.lineJoin = .round
            selectionGripsLayer.addSublayer(shape)
        }
        gripStemsLayer.fillColor = nil
        gripStemsLayer.lineDashPattern = [2, 3]
        gripStemsLayer.lineCap = .butt
        gripsShapeLayer.fillColor = CGColor(gray: 1, alpha: 1)
        gripGlyphsLayer.fillColor = nil
        litGripGlyphLayer.fillColor = nil
        litGripGlyphLayer.strokeColor = CGColor(gray: 1, alpha: 1)
        chipPlateLayer.fillColor = CGColor(gray: 1, alpha: 1)
        chipPlateLayer.strokeColor = CGColor(gray: 0, alpha: 0.2)
        chipPlateLayer.lineWidth = 0.5
        chipPlateLayer.shadowColor = CGColor(gray: 0, alpha: 1)
        chipPlateLayer.shadowOpacity = 0.18
        chipPlateLayer.shadowRadius = 3
        chipPlateLayer.shadowOffset = CGSize(width: 0, height: 2)
        chipPickedLayer.strokeColor = nil
        chipIconsLayer.fillColor = nil
        chipIconsLayer.strokeColor = GripLook.iconInk
        chipIconsLayer.lineWidth = 1.3
        chipPickedIconLayer.fillColor = nil
        chipPickedIconLayer.strokeColor = CGColor(gray: 1, alpha: 1)
        chipPickedIconLayer.lineWidth = 1.3
        gripTagLayer.strokeColor = nil
        gripTagTextLayer.alignmentMode = .center
        gripTagTextLayer.foregroundColor = CGColor(gray: 1, alpha: 1)
        gripTagLayer.addSublayer(gripTagTextLayer)
        // Nothing here eases: a tag that cross-fades its words reads a beat
        // behind the pointer.
        let still: [String: any CAAction] = ["contents": NSNull(), "string": NSNull(), "bounds": NSNull(),
                                             "position": NSNull(), "frame": NSNull(), "path": NSNull(),
                                             "hidden": NSNull()]
        gripTagTextLayer.actions = still
        for shape in [gripStemsLayer, gripsShapeLayer, gripGlyphsLayer, litGripLayer, litGripGlyphLayer,
                      chipPlateLayer, chipPickedLayer, chipIconsLayer, chipPickedIconLayer, gripTagLayer] {
            shape.actions = still
        }
    }

    func hideSelectionGrips() {
        guard !selectionGripsLayer.isHidden || drawnSelectionGrips != nil else { return }
        selectionGripsLayer.isHidden = true
        drawnSelectionGrips = nil
        markHandles([], on: selectionGripsLayer)
        gripTagShown = nil
    }

    // MARK: Drawing

    /// Draws the grips round `quad` (the frame's four corners as seen, in view
    /// points: top left, top right, bottom right, bottom left).
    func drawSelectionGrips(for layer: Layer, quad: [CGPoint], resizes: Bool, rotates: Bool) {
        // A newly picked layer starts in Size, as the prototype does.
        if transformModeLayerID != layer.id {
            transformModeLayerID = layer.id
            transformMode = .size
        }
        let modes = offeredTransformModes
        if !modes.contains(transformMode) { transformMode = .size }
        let grips = SelectionGrips(quad: quad, mode: transformMode, rotates: rotates, resizes: resizes,
                                   modes: modes)
        drawnSelectionGrips = (layer.id, grips)
        let accent = NSColor.controlAccentColor.cgColor
        gripsShapeLayer.strokeColor = accent
        gripStemsLayer.strokeColor = accent
        gripGlyphsLayer.strokeColor = accent
        litGripLayer.fillColor = accent
        litGripLayer.strokeColor = accent
        chipPickedLayer.fillColor = accent
        gripTagLayer.fillColor = accent

        let stems = CGMutablePath()
        for stem in [grips.stem, grips.depthStem].compactMap({ $0 }) {
            stems.move(to: stem.from)
            stems.addLine(to: stem.to)
        }
        gripStemsLayer.path = stems

        let shapes = CGMutablePath(), glyphs = CGMutablePath()
        var marks: [HandleMark] = []
        for corner in grips.corners {
            shapes.addPath(Self.gripPath(.corner(corner.handle), in: grips))
            marks.append(HandleMark(center: corner.center, shape: .square(SelectionGrips.cornerSide),
                                    role: .resize(corner.handle)))
        }
        for edge in grips.edges {
            shapes.addPath(Self.gripPath(.edge(edge.handle), in: grips))
            marks.append(HandleMark(center: edge.center, shape: .square(SelectionGrips.pillLength),
                                    role: grips.mode == .space ? .grab : .resize(edge.handle)))
        }
        if let knob = grips.knob {
            shapes.addPath(Self.gripPath(.knob, in: grips))
            glyphs.addPath(Self.knobArrow(at: knob))
            marks.append(HandleMark(center: knob, shape: .circle(SelectionGrips.knobRadius * 2), role: .rotate))
        }
        if let depth = grips.depth {
            shapes.addPath(Self.gripPath(.depth, in: grips))
            glyphs.addPath(Self.depthArrows(at: depth, up: grips.up))
            marks.append(HandleMark(center: depth, shape: .square(SelectionGrips.depthSize.height), role: .grab))
        }
        gripsShapeLayer.path = shapes
        gripGlyphsLayer.path = glyphs
        markHandles(marks, on: selectionGripsLayer)

        // The chip: a white plate, the picked mode in the accent.
        if let plate = grips.chipPlate {
            chipPlateLayer.path = CGPath(roundedRect: plate, cornerWidth: GripLook.chipRadius,
                                         cornerHeight: GripLook.chipRadius, transform: nil)
            chipPlateLayer.shadowPath = chipPlateLayer.path
            let icons = CGMutablePath(), picked = CGMutablePath()
            var pickedFrame: CGRect?
            for button in grips.chip {
                let icon = Self.chipIcon(button.mode, in: button.frame)
                if button.mode == grips.mode {
                    picked.addPath(icon)
                    pickedFrame = button.frame
                } else {
                    icons.addPath(icon)
                }
            }
            chipIconsLayer.path = icons
            chipPickedIconLayer.path = picked
            chipPickedLayer.path = pickedFrame.map {
                CGPath(roundedRect: $0, cornerWidth: GripLook.chipButtonRadius,
                       cornerHeight: GripLook.chipButtonRadius, transform: nil)
            }
            for shape in [chipPlateLayer, chipPickedLayer, chipIconsLayer, chipPickedIconLayer] { shape.isHidden = false }
        } else {
            for shape in [chipPlateLayer, chipPickedLayer, chipIconsLayer, chipPickedIconLayer] {
                shape.isHidden = true
                shape.path = nil
            }
        }
        selectionGripsLayer.isHidden = false
        styleLitGrip()
        refreshGripTag(for: layer)
    }

    /// Lights the grip under the resting pointer, or the one in the hand: the
    /// accent fill, the same size (the user, 2026-11-01: hover never grows a
    /// grip), with the knob's arrow and the depth arrows turned white.
    func styleLitGrip() {
        guard let shown = drawnSelectionGrips else { return }
        let grip = heldGrip ?? hoveredGrip
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        switch grip {
        case nil, .chip?:
            litGripLayer.path = nil
            litGripGlyphLayer.path = nil
        case let grip?:
            litGripLayer.path = Self.gripPath(grip, in: shown.grips)
            switch grip {
            case .knob: litGripGlyphLayer.path = shown.grips.knob.map(Self.knobArrow(at:))
            case .depth: litGripGlyphLayer.path = shown.grips.depth.map { Self.depthArrows(at: $0, up: shown.grips.up) }
            default: litGripGlyphLayer.path = nil
            }
        }
        CATransaction.commit()
    }

    /// The tag under the frame: what the pointer rests on does, or the size
    /// (in 3D the tip, swing and depth). A drag hides it: the pill under the
    /// drag says the value in hand, in the same place and the same colour.
    func refreshGripTag(for layer: Layer) {
        guard let shown = drawnSelectionGrips, shown.layerID == layer.id, dragReadoutSubject == nil,
              resizeDrag == nil, transformDrag == nil, spaceHandleDrag == nil, moveDrag == nil else {
            hideGripTag()
            return
        }
        let words: String = {
            if let grip = hoveredGrip { return SelectionTag.does(grip, mode: shown.grips.mode) }
            let size = selectedLayerFrame.flatMap { frame in
                document?.parentSpaceFrame(layer.withSlack(frame), of: layer.id)?.size
            } ?? layer.frame.size
            return SelectionTag.resting(mode: shown.grips.mode, size: size,
                                        rotation: Double(layer.transform.rotation) * 180 / .pi,
                                        turn: document.map { $0.shownSpaceTurn(layerID: layer.id,
                                                                               atDocumentTimeMS: documentTimeMS) })
        }()
        let font = Self.dragReadoutFont
        let inset = GripLook.tagInset
        let text = CGSize(width: (words as NSString).size(withAttributes: [.font: font]).width.rounded(.up),
                          height: (font.ascender - font.descender).rounded(.up))
        let plate = shown.grips.tagFrame(size: CGSize(width: text.width + inset.width * 2,
                                                      height: text.height + inset.height * 2), in: bounds)
        gripTagLayer.path = CGPath(roundedRect: plate, cornerWidth: GripLook.tagRadius,
                                   cornerHeight: GripLook.tagRadius, transform: nil)
        gripTagTextLayer.string = words
        gripTagTextLayer.font = font
        gripTagTextLayer.fontSize = font.pointSize
        gripTagTextLayer.contentsScale = window?.backingScaleFactor ?? 2
        gripTagTextLayer.frame = CGRect(x: plate.minX + inset.width, y: plate.minY + inset.height,
                                        width: text.width, height: text.height)
        gripTagLayer.isHidden = false
        gripTagShown = words
    }

    func hideGripTag() {
        gripTagLayer.isHidden = true
        gripTagLayer.path = nil
        gripTagShown = nil
    }

    // MARK: The shapes

    static func gripPath(_ grip: SelectionGrip, in grips: SelectionGrips) -> CGPath {
        switch grip {
        case .corner(let handle):
            guard let c = grips.corners.first(where: { $0.handle == handle })?.center else { return CGMutablePath() }
            let half = SelectionGrips.cornerSide / 2
            return CGPath(roundedRect: CGRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2),
                          cornerWidth: SelectionGrips.cornerRadius, cornerHeight: SelectionGrips.cornerRadius,
                          transform: nil)
        case .edge(let handle):
            guard let e = grips.edges.first(where: { $0.handle == handle }) else { return CGMutablePath() }
            return pill(at: e.center, length: SelectionGrips.pillLength, thickness: SelectionGrips.pillThickness,
                        angle: e.angle)
        case .knob:
            guard let k = grips.knob else { return CGMutablePath() }
            let r = SelectionGrips.knobRadius
            return CGPath(ellipseIn: CGRect(x: k.x - r, y: k.y - r, width: r * 2, height: r * 2), transform: nil)
        case .depth:
            guard let d = grips.depth else { return CGMutablePath() }
            // Upright along the card's own up, its long side across the depth.
            return pill(at: d, length: SelectionGrips.depthSize.height, thickness: SelectionGrips.depthSize.width,
                        angle: atan2(grips.up.y, grips.up.x))
        case .chip(let mode):
            guard let b = grips.chip.first(where: { $0.mode == mode })?.frame else { return CGMutablePath() }
            return CGPath(roundedRect: b, cornerWidth: GripLook.chipButtonRadius,
                          cornerHeight: GripLook.chipButtonRadius, transform: nil)
        }
    }

    /// A rounded bar `length` along `angle` and `thickness` across.
    static func pill(at c: CGPoint, length: CGFloat, thickness: CGFloat, angle: CGFloat) -> CGPath {
        let rect = CGRect(x: -length / 2, y: -thickness / 2, width: length, height: thickness)
        var t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle)
        return CGPath(roundedRect: rect, cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: &t)
    }

    /// The knob's clockwise arrow (SF Symbols' arrow.clockwise, at the
    /// prototype's size): most of a circle and its head at the top.
    static func knobArrow(at k: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let start = atan2(-1.2, 4.2), end = atan2(-4.3, 1.6)
        path.addArc(center: k, radius: 4.6, startAngle: start, endAngle: end, clockwise: false)
        path.move(to: CGPoint(x: k.x + 0.6, y: k.y - 6.6))
        path.addLine(to: CGPoint(x: k.x + 3.4, y: k.y - 4.4))
        path.addLine(to: CGPoint(x: k.x + 0.4, y: k.y - 2.2))
        return path
    }

    /// The depth grip's two chevrons, one each way along the card's up.
    static func depthArrows(at d: CGPoint, up: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let across = CGPoint(x: -up.y, y: up.x)
        func p(_ a: CGFloat, _ u: CGFloat) -> CGPoint {
            CGPoint(x: d.x + across.x * a + up.x * u, y: d.y + across.y * a + up.y * u)
        }
        path.move(to: p(-4, 3)); path.addLine(to: p(0, 7)); path.addLine(to: p(4, 3))
        path.move(to: p(-4, -3)); path.addLine(to: p(0, -7)); path.addLine(to: p(4, -3))
        return path
    }

    /// The chip's icons, the prototype's 16 point drawings at 14 points.
    static func chipIcon(_ mode: TransformMode, in frame: CGRect) -> CGPath {
        let path = CGMutablePath()
        let s: CGFloat = 14 / 16
        let o = CGPoint(x: frame.midX - 7, y: frame.midY - 7)
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o.x + x * s, y: o.y + y * s) }
        switch mode {
        case .size:
            path.addRoundedRect(in: CGRect(origin: p(3, 3), size: CGSize(width: 10 * s, height: 10 * s)),
                                cornerWidth: s, cornerHeight: s)
            path.move(to: p(1.5, 3.5)); path.addLine(to: p(1.5, 1.5)); path.addLine(to: p(3.5, 1.5))
            path.move(to: p(14.5, 12.5)); path.addLine(to: p(14.5, 14.5)); path.addLine(to: p(12.5, 14.5))
        case .space:
            path.move(to: p(8, 1.8)); path.addLine(to: p(13.6, 5)); path.addLine(to: p(13.6, 11.2))
            path.addLine(to: p(8, 14.4)); path.addLine(to: p(2.4, 11.2)); path.addLine(to: p(2.4, 5))
            path.closeSubpath()
            path.move(to: p(2.4, 5)); path.addLine(to: p(8, 8.2)); path.addLine(to: p(13.6, 5))
            path.move(to: p(8, 8.2)); path.addLine(to: p(8, 14.4))
        case .reshape:
            path.move(to: p(2.5, 4)); path.addLine(to: p(13, 2.5)); path.addLine(to: p(14, 13.5))
            path.addLine(to: p(3.5, 12)); path.closeSubpath()
        }
        return path
    }

    // MARK: What a press takes

    /// The grip a press at `viewPoint` takes, or nil.
    func selectionGripHit(atView viewPoint: CGPoint) -> SelectionGrip? {
        guard transformModesOffered, let shown = drawnSelectionGrips, shown.layerID == selectedLayerID,
              !selectionGripsLayer.isHidden,
              let layer = document?.canvasLayer(id: shown.layerID), !layer.isLocked else { return nil }
        // A rounding dot inside a corner keeps its own press, so the corner's
        // generous reach never takes it away.
        if Experiments.shared.cornerHandlesEnabled, let viewport, let frame = selectedLayerFrame,
           layer.offersCornerRadiusHandles, !cornerRadiusHandlesLayer.isHidden,
           CornerRadiusHandles.hit(at: handleSpacePoint(viewport.documentPoint(fromView: viewPoint), layer: layer),
                                   frame: frame, radii: layer.roundedCornerRadii, zoom: viewport.zoom) != nil {
            return nil
        }
        return shown.grips.hit(viewPoint)
    }

    /// What the pointer reads over a grip, for the cue: nil off every grip.
    func selectionGripCue(atView viewPoint: CGPoint, layer: Layer) -> (cue: CanvasPointerCue, transform: LayerTransform)? {
        guard let grip = selectionGripHit(atView: viewPoint), let shown = drawnSelectionGrips else { return nil }
        switch grip {
        case .corner(let handle): return (.resize(handle), apparentTransform(of: layer))
        case .edge(let handle):
            return shown.grips.mode == .space ? (.grab, .identity) : (.resize(handle), apparentTransform(of: layer))
        case .knob: return (.rotate, apparentTransform(of: layer))
        case .depth: return (.grab, .identity)
        case .chip: return nil
        }
    }

    /// Notes the grip under the resting pointer, and lights it.
    func noteGripHover(at viewPoint: CGPoint?) {
        let dragging = resizeDrag != nil || transformDrag != nil || spaceHandleDrag != nil || moveDrag != nil
        let grip = dragging ? nil : viewPoint.flatMap { selectionGripHit(atView: $0) }
        guard grip != hoveredGrip else { return }
        hoveredGrip = grip
        styleLitGrip()
        if let id = drawnSelectionGrips?.layerID, let layer = document?.canvasLayer(id: id) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            refreshGripTag(for: layer)
            CATransaction.commit()
        }
    }

    /// The mark a walk sees lit: the grip under the pointer, as a handle mark.
    var litGripMark: HandleMark? {
        guard let grip = heldGrip ?? hoveredGrip, let shown = drawnSelectionGrips else { return nil }
        let marks = handleMarks[ObjectIdentifier(selectionGripsLayer)]?.marks ?? []
        let centre: CGPoint? = {
            switch grip {
            case .corner(let h): shown.grips.corners.first { $0.handle == h }?.center
            case .edge(let h): shown.grips.edges.first { $0.handle == h }?.center
            case .knob: shown.grips.knob
            case .depth: shown.grips.depth
            case .chip: nil
            }
        }()
        guard let centre else { return nil }
        return marks.first { $0.center == centre }
    }

    /// A press on one of the grips: takes hold (or switches the mode) and
    /// returns true.
    func selectionGripMouseDown(atView viewPoint: CGPoint, event: NSEvent) -> Bool {
        guard let grip = selectionGripHit(atView: viewPoint), let viewport,
              let id = selectedLayerID, let layer = document?.canvasLayer(id: id),
              let shown = drawnSelectionGrips else { return false }
        let q = viewport.documentPoint(fromView: viewPoint)
        switch grip {
        case .chip(let mode):
            setTransformMode(mode)
            return true
        case .knob:
            // A double press turns it back upright, one undo step.
            if event.clickCount >= 2 {
                if layer.transform.rotation != 0 {
                    var upright = layer.transform
                    upright.rotation = 0
                    onTransformCommit(id, upright)
                }
                refreshOverlays()
                return true
            }
            let center = layer.turnPivot
            transformDrag = TransformDragSession(
                layerID: id, kind: .rotate(grabAngle: TransformDrag.pointerAngle(q, around: center)),
                startTransform: layer.transform, center: center,
                frameSize: layer.frame.size, transform: layer.transform)
            heldGrip = .knob
            applyGrabCursor(CanvasCursor.cursor(for: .rotate, transform: apparentTransform(of: layer)))
            onDragBegin(id)
            announceTransform(.rotate)
            refreshOverlays()
            return true
        case .edge(let handle) where shown.grips.mode == .space:
            beginGripTurn(.swing, grip: .edge(handle), layer: layer, at: viewPoint)
            return true
        case .depth:
            beginGripTurn(.depth, grip: .depth, layer: layer, at: viewPoint)
            return true
        case .corner(let handle), .edge(let handle):
            guard let frame = selectedLayerFrame else { return false }
            let untransformed = layer.transform.isIdentity
            resizeDrag = ResizeDrag(
                layerID: id, handle: handle, startFrame: frame, frame: frame,
                peers: Experiments.shared.alignLayersEnabled && untransformed
                    ? (document?.snapPeers(excluding: id) ?? []) : [],
                columns: untransformed && !isOnASlant(id) ? columnBands(excluding: [id]) : [],
                snapped: Snapping.FrameResult(frame: frame))
            // The edge itself, as seen, under the pill: the drag carries the
            // few points between them so the edge never jumps to the pointer.
            // A corner pressed off its middle does the same.
            let q4 = shown.grips.quad
            let ends: (Int, Int) = switch handle {
            case .topLeft: (0, 0)
            case .top: (0, 1)
            case .topRight: (1, 1)
            case .right: (1, 2)
            case .bottomRight: (2, 2)
            case .bottom: (2, 3)
            case .bottomLeft: (3, 3)
            case .left: (3, 0)
            }
            let taken = CGPoint(x: (q4[ends.0].x + q4[ends.1].x) / 2, y: (q4[ends.0].y + q4[ends.1].y) / 2)
            let onFrame = viewport.documentPoint(fromView: taken)
            resizeDrag?.grabOffset = CGPoint(x: onFrame.x - q.x, y: onFrame.y - q.y)
            heldGrip = grip
            applyGrabCursor(CanvasCursor.cursor(for: .resize(handle), transform: apparentTransform(of: layer)))
            announceTransform(.resize(handle))
            onDragBegin(id)
            refreshOverlays()
            return true
        }
    }

    private func beginGripTurn(_ handle: SpaceHandle, grip: SelectionGrip, layer: Layer, at viewPoint: CGPoint) {
        let start = document?.shownSpaceTurn(layerID: layer.id, atDocumentTimeMS: documentTimeMS)
            ?? layer.turn3D ?? LayerTurn3D()
        spaceHandleDrag = SpaceHandleDrag(layerID: layer.id, handle: handle, start: start, press: viewPoint,
                                          turn: start, moved: false, grip: grip)
        heldGrip = grip
        applyGrabCursor(.closedHand)
        announceTransform(.tilt(handle))
        refreshOverlays()
    }

    /// Switches the chip's mode. Swapping back and forth keeps every value the
    /// layer has: a mode is a set of grips, not a state of the layer.
    func setTransformMode(_ mode: TransformMode) {
        guard mode != transformMode, offeredTransformModes.contains(mode) else { return }
        transformMode = mode
        transformModeLayerID = selectedLayerID
        hoveredGrip = nil
        refreshOverlays()
        refreshGrabCursor()
    }
}
