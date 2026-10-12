import AppKit
import PhotonzCore

// Every transform handle answers the pointer before you click
// (`every-transform-handle-answers-the-pointer-befor`).
//
// The pointer cue (`CanvasPointerCue.swift`) already says what a press would
// do and turns the cursor to match. This file makes the HANDLE say it too:
//
// - Every drawing of handles also tells this file where it put them
//   (`markHandles`), keyed by the shape layer it drew them on, so a handle on
//   a layer that has since been hidden is never lit.
// - Each time the cue is read, the mark it belongs to is drawn lit on one
//   shared layer above all the handles: the handle's own shape, a quarter
//   larger, filled in the accent with a white rim and a soft glow
//   (`HandleHover`, PhotonzCore, tested there).
// - The 3D arcs and the depth arrow light in their own colour instead: the one
//   under the pointer thickens, the others dim, and after a short rest its name
//   appears beside the pointer.
//
// Hovering only draws. It never touches the document, never takes key, and a
// drag in flight lights nothing, because the hand already holds what it took.

extension CanvasNSView {

    enum HandleHoverLook {
        /// The arc or arrow under the pointer, and the ones that are not.
        static let litSpaceWidth: CGFloat = 4.5
        static let restingSpaceWidth: CGFloat = 2.5
        static let dimmedSpaceOpacity: Float = 0.45
        /// How far the name sits from the pointer's tip, clear of the cursor.
        static let labelOffset = CGPoint(x: 16, y: 18)
        static let labelInset = CGSize(width: 8, height: 3)
    }

    func setUpHandleHoverChrome() {
        handleHoverLayer.fillColor = NSColor.controlAccentColor.cgColor
        handleHoverLayer.strokeColor = CGColor(gray: 1, alpha: 1)
        handleHoverLayer.lineWidth = 1.5
        // A soft glow in the accent, so the lit handle reads as lit on a white
        // screenshot and a dark one alike.
        handleHoverLayer.shadowColor = NSColor.controlAccentColor.cgColor
        handleHoverLayer.shadowOpacity = 0.9
        handleHoverLayer.shadowRadius = 4
        handleHoverLayer.shadowOffset = .zero
        handleHoverLayer.isHidden = true
        // Above every handle it could be lighting (they sit at 100).
        handleHoverLayer.zPosition = 100.5
        layer?.addSublayer(handleHoverLayer)

        // The name beside the pointer on a 3D handle: the drag pill's own
        // plate, solid and dark, so it reads over any picture.
        spaceLabelLayer.fillColor = CGColor(gray: 0, alpha: 0.82)
        spaceLabelLayer.strokeColor = nil
        spaceLabelLayer.isHidden = true
        spaceLabelLayer.zPosition = 101
        spaceLabelTextLayer.alignmentMode = .center
        spaceLabelTextLayer.foregroundColor = NSColor.white.cgColor
        spaceLabelLayer.addSublayer(spaceLabelTextLayer)
        layer?.addSublayer(spaceLabelLayer)
    }

    // MARK: Where the handles are

    /// Records the handles just drawn on `shape`, replacing what it drew
    /// before. An empty list says it drew none.
    func markHandles(_ marks: [HandleMark], on shape: CALayer) {
        handleMarks[ObjectIdentifier(shape)] = marks.isEmpty ? nil : (shape, marks)
    }

    /// Whether `shape` is really on screen: it and everything it sits in are
    /// showing.
    private func isShowing(_ shape: CALayer) -> Bool {
        var current: CALayer? = shape
        while let each = current, each !== layer {
            if each.isHidden || each.opacity <= 0 { return false }
            current = each.superlayer
        }
        return current != nil
    }

    /// Every handle on screen right now.
    var visibleHandleMarks: [HandleMark] {
        var marks = handleMarks.values.filter { isShowing($0.owner) }.flatMap(\.marks)
        marks += zoomBoxMarks
        return marks
    }

    /// The picked zoom's four corners, which a SwiftUI overlay draws over the
    /// canvas (`ZoomBoxOverlay`), so they are found here rather than recorded.
    private var zoomBoxMarks: [HandleMark] {
        guard zoomOwnsPicture, let viewport, let box = zoomBoxInDocument()?.standardized else { return [] }
        let corners: [(ResizeHandle, CGPoint)] = [
            (.topLeft, CGPoint(x: box.minX, y: box.minY)), (.topRight, CGPoint(x: box.maxX, y: box.minY)),
            (.bottomRight, CGPoint(x: box.maxX, y: box.maxY)), (.bottomLeft, CGPoint(x: box.minX, y: box.maxY)),
        ]
        return corners.map {
            HandleMark(center: viewport.viewPoint(fromDocument: $0.1), shape: .square(8), role: .resize($0.0))
        }
    }

    // MARK: What the pointer is on

    /// A drag that holds something: nothing is lit while one is under way.
    private var handleDragInFlight: Bool {
        captionDrag != nil || measureHandleDrag != nil || resizeDrag != nil || spaceHandleDrag != nil
            || cornerRadiusDrag != nil || endpointDrag != nil || transformDrag != nil
            || canvasResizeDrag != nil || cropDrag != nil || moveDrag != nil || multiMove != nil
            || marquee != nil || motionPivotDrag != nil || motionPathDrag != nil
            || pathAnchorDrag != nil || pathCornerDrag != nil || handPan != nil
    }

    /// Called every time the pointer cue is read (`refreshGrabCursor`), with
    /// what it found: the cue and, for the 3D handles, which one.
    func noteHandleHover(_ cue: CanvasPointerCue?, space: SpaceHandle?, at point: CGPoint?) {
        handleHoverCue = point == nil ? nil : cue
        handleHoverPoint = point
        let space = point == nil || handleDragInFlight ? nil : space
        if space != hoveredSpaceHandle {
            hoveredSpaceHandle = space
            styleSpaceHandles()
            waitToNameSpaceHandle()
        }
        renderHandleHover()
    }

    /// Draws the lit handle, or takes it away. Also called after every overlay
    /// refresh, so a lit handle moves with the handle it lights.
    func renderHandleHover() {
        let lit: HandleMark? = {
            guard !handleDragInFlight, hoveredSpaceHandle == nil, let point = handleHoverPoint else { return nil }
            return HandleHover.lit(cue: handleHoverCue, at: point, among: visibleHandleMarks)
        }()
        guard lit != litHandle else { return }
        litHandle = lit
        // A zoom box corner is drawn by the box over the canvas, which would
        // cover a lit square drawn here, so the box is told and lights it.
        let zoomCorner: ResizeHandle? = {
            guard let lit, case .resize(let handle) = lit.role, zoomBoxMarks.contains(lit) else { return nil }
            return handle
        }()
        if zoomCorner != litZoomCorner {
            litZoomCorner = zoomCorner
            onZoomCornerLit(zoomCorner)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let lit, zoomCorner == nil {
            let rect = HandleHover.litRect(for: lit)
            switch lit.shape {
            case .square: handleHoverLayer.path = CGPath(rect: rect, transform: nil)
            case .circle: handleHoverLayer.path = CGPath(ellipseIn: rect, transform: nil)
            }
            handleHoverLayer.isHidden = false
        } else {
            handleHoverLayer.isHidden = true
            handleHoverLayer.path = nil
        }
        CATransaction.commit()
    }

    // MARK: The 3D handles

    /// Lights the arc or arrow under the pointer (or in the hand) in its own
    /// colour and thickens it, and dims the others. Called whenever the 3D
    /// handles are drawn and whenever the one under the pointer changes.
    func styleSpaceHandles() {
        let focus = spaceHandleDrag?.handle ?? hoveredSpaceHandle
        let shapes: [(SpaceHandle, CAShapeLayer)] = [(.swing, spaceSwingLayer), (.tip, spaceTipLayer),
                                                     (.depth, spaceDepthLayer)]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (handle, shape) in shapes {
            let lit = focus == handle
            shape.lineWidth = lit ? HandleHoverLook.litSpaceWidth : HandleHoverLook.restingSpaceWidth
            shape.opacity = focus == nil || lit ? 1 : HandleHoverLook.dimmedSpaceOpacity
        }
        // The dark rim under them widens with the lit one, so it stays a rim.
        spaceHandleRimLayer.lineWidth = focus == nil ? 5 : 7
        CATransaction.commit()
    }

    /// Starts the short wait before the lit 3D handle's name appears, or takes
    /// the name away when nothing is lit.
    private func waitToNameSpaceHandle() {
        spaceLabelWait?.cancel()
        spaceLabelWait = nil
        hideSpaceLabel()
        guard let handle = hoveredSpaceHandle else { return }
        spaceLabelWait = Task { [weak self] in
            try? await Task.sleep(for: .seconds(HandleHover.labelDelay))
            guard !Task.isCancelled, let self, self.hoveredSpaceHandle == handle,
                  self.spaceHandleDrag == nil else { return }
            self.showSpaceLabel(handle.hoverLabel)
        }
    }

    private func showSpaceLabel(_ words: String) {
        guard let point = handleHoverPoint else { return }
        let font = Self.dragReadoutFont
        let inset = HandleHoverLook.labelInset
        let text = CGSize(width: (words as NSString).size(withAttributes: [.font: font]).width.rounded(.up),
                          height: (font.ascender - font.descender).rounded(.up))
        let size = CGSize(width: text.width + inset.width * 2, height: text.height + inset.height * 2)
        var plate = CGRect(origin: CGPoint(x: point.x + HandleHoverLook.labelOffset.x,
                                           y: point.y + HandleHoverLook.labelOffset.y), size: size)
        // Kept inside the canvas: flipped to the other side of the pointer
        // where it would run off.
        if plate.maxX > bounds.maxX - 4 { plate.origin.x = point.x - HandleHoverLook.labelOffset.x - size.width }
        if plate.maxY > bounds.maxY - 4 { plate.origin.y = point.y - HandleHoverLook.labelOffset.y - size.height }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spaceLabelLayer.frame = bounds
        spaceLabelLayer.path = CGPath(roundedRect: plate, cornerWidth: plate.height / 2,
                                      cornerHeight: plate.height / 2, transform: nil)
        spaceLabelTextLayer.string = words
        spaceLabelTextLayer.font = font
        spaceLabelTextLayer.fontSize = font.pointSize
        spaceLabelTextLayer.contentsScale = window?.backingScaleFactor ?? 2
        spaceLabelTextLayer.frame = CGRect(x: plate.minX + inset.width, y: plate.minY + inset.height,
                                           width: text.width, height: text.height)
        spaceLabelLayer.isHidden = false
        CATransaction.commit()
        spaceLabelShown = words
    }

    func hideSpaceLabel() {
        guard spaceLabelShown != nil || !spaceLabelLayer.isHidden else { return }
        spaceLabelLayer.isHidden = true
        spaceLabelLayer.path = nil
        spaceLabelShown = nil
    }
}
