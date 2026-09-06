import AppKit
import PhotonzCore

/// Guides pinned onto the grid (Next, `next-canvas-grid`): drawing them, and
/// the three things a press means while the grid is being adjusted.
///
/// A guide is chrome, like the grid: drawn by this view rather than by the
/// renderer, so it never lands in an export or a copied picture. Unlike the
/// grid it does NOT come and go with the Show grid switch. You pinned it on
/// purpose and the grid was only the ruler you pinned it with, so it stays on
/// screen, and things go on catching it, with the grid switched off.
///
/// **Two yellows, told apart by weight.** A pinned guide is one point wide at
/// half strength and simply there. A snap guide — the one that says a drag just
/// lined up with something — is two points at full strength and only appears
/// while the drag holds. So when a drag catches a pinned guide the bright line
/// lights directly on top of the quiet one, which reads as the guide answering
/// rather than as a second line arriving. The same full strength yellow lights
/// the line under the pointer inside the mode, for the same reason: it is the
/// line you are about to get.
extension CanvasNSView {

    // MARK: - Drawing

    /// The pinned guides, the line under the pointer, and the zero point's
    /// knob. Called from the overlay refresh, and cheap: a handful of lines.
    func refreshGuideChrome() {
        guard canvasGridEnabled, let viewport, bounds.width > 0.5, bounds.height > 0.5 else {
            pinnedGuideLayer.isHidden = true
            guideHighlightLayer.isHidden = true
            gridOriginKnobLayer.isHidden = true
            return
        }
        let held = gridAdjust != nil ? selectedGuideID : nil
        let pinned = CGMutablePath()
        let bright = CGMutablePath()
        var selected: CanvasGuide?
        for guide in canvasGuides {
            // The guide being held draws in the bright path, so what you picked
            // up is unmistakably what you picked up.
            let path = guide.id == held ? bright : pinned
            if guide.id == held { selected = guide }
            appendGuide(guide.line, to: path, in: viewport)
        }
        // The line a click would pin. Only while adjusting, and never on top of
        // a guide that is already there.
        if gridAdjust != nil, !guideDragging, let highlight = guideHighlight,
           CanvasGuides.nearest(canvasGuides,
                                to: highlightPoint(highlight),
                                within: CanvasGuides.sameLine) == nil {
            appendGuide(highlight, to: bright, in: viewport)
        }
        pinnedGuideLayer.path = pinned
        pinnedGuideLayer.isHidden = pinned.isEmpty
        guideHighlightLayer.path = bright
        guideHighlightLayer.isHidden = bright.isEmpty
        refreshSelectedGuideKnob(selected, in: viewport)
        refreshGridOriginKnob(in: viewport)
    }

    private func highlightPoint(_ line: CanvasGuideLine) -> CGPoint {
        line.axis == .vertical ? CGPoint(x: line.position, y: 0)
                               : CGPoint(x: 0, y: line.position)
    }

    /// One guide, right across the whole view — surround included, the way the
    /// grid itself runs — so a guide marking a margin is still visible where the
    /// picture is scrolled off screen.
    private func appendGuide(_ line: CanvasGuideLine, to path: CGMutablePath,
                             in viewport: Viewport) {
        // Whole view points, for the same reason the grid rounds: a one point
        // line off the pixel grid is a grey smear.
        switch line.axis {
        case .vertical:
            let x = viewport.viewPoint(fromDocument: CGPoint(x: line.position, y: 0)).x.rounded()
            path.move(to: CGPoint(x: x, y: bounds.minY))
            path.addLine(to: CGPoint(x: x, y: bounds.maxY))
        case .horizontal:
            let y = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: line.position)).y.rounded()
            path.move(to: CGPoint(x: bounds.minX, y: y))
            path.addLine(to: CGPoint(x: bounds.maxX, y: y))
        }
    }

    /// The handle on the zero point: a dot where its two markers cross. Inside
    /// the mode a press anywhere else pins or picks up a guide, so the zero
    /// point needs something to aim at rather than the whole canvas.
    ///
    /// It grows while the pointer is anywhere the zero point would answer a
    /// press, which is the whole length of both markers rather than the dot
    /// alone. See `gridOriginHot`.
    private func refreshGridOriginKnob(in viewport: Viewport) {
        guard let origin = gridAdjust else {
            gridOriginKnobLayer.path = nil
            gridOriginKnobLayer.isHidden = true
            return
        }
        let point = viewport.viewPoint(fromDocument: origin)
        let radius: CGFloat = gridOriginHot || gridOriginDragging ? 7 : 5
        let box = CGRect(x: point.x.rounded() - radius, y: point.y.rounded() - radius,
                         width: radius * 2, height: radius * 2)
        gridOriginKnobLayer.path = CGPath(ellipseIn: box, transform: nil)
        gridOriginKnobLayer.isHidden = false
    }

    /// The knob on the guide that is SELECTED: a dot on the line, halfway down
    /// the view. A guide had no selected state at all before, only the same
    /// bright yellow the line under the pointer wears, so there was no way to
    /// tell which guide a press of \u{232B} was about to take off the picture. The
    /// knob is the difference: the line under the pointer is a bare line, and
    /// the one you have hold of wears the handle.
    private func refreshSelectedGuideKnob(_ guide: CanvasGuide?, in viewport: Viewport) {
        guard gridAdjust != nil, let guide else {
            selectedGuideKnobLayer.path = nil
            selectedGuideKnobLayer.isHidden = true
            return
        }
        let radius: CGFloat = 5
        let centre: CGPoint
        switch guide.axis {
        case .vertical:
            let x = viewport.viewPoint(fromDocument: CGPoint(x: guide.position, y: 0)).x.rounded()
            centre = CGPoint(x: x, y: bounds.midY.rounded())
        case .horizontal:
            let y = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: guide.position)).y.rounded()
            centre = CGPoint(x: bounds.midX.rounded(), y: y)
        }
        let box = CGRect(x: centre.x - radius, y: centre.y - radius,
                         width: radius * 2, height: radius * 2)
        selectedGuideKnobLayer.path = CGPath(ellipseIn: box, transform: nil)
        selectedGuideKnobLayer.isHidden = false
    }

    // MARK: - Hovering

    /// Light the grid line a click would pin a guide onto. The axis already lit
    /// keeps it until the other is clearly nearer, so the highlight does not
    /// flip back and forth where two lines cross. See `CanvasGuidePick`.
    func refreshGuideHighlight(at viewPoint: CGPoint) {
        guard gridAdjust != nil, let viewport, let settings = canvasGrid else {
            guideHighlight = nil
            gridOriginHot = false
            return
        }
        let zoom = max(viewport.zoom, 0.0001)
        let point = viewport.documentPoint(fromView: viewPoint)
        // What lights up is what a press will do. Anywhere along the zero
        // point's two markers a press takes hold of the ZERO POINT, so no grid
        // line lights there: the markers thicken and their knob grows instead.
        // Lighting a guide there was the canvas offering one thing and doing
        // another.
        gridOriginHot = grabsGridOrigin(at: point)
        guard !gridOriginHot else {
            guideHighlight = nil
            refreshOverlays()
            return
        }
        guideHighlight = CanvasGuidePick.line(near: point,
                                              spacing: settings.liveSpacing(atZoom: zoom),
                                              origin: canvasGridOrigin,
                                              axes: settings.axes,
                                              holding: guideHighlight?.axis,
                                              slack: CanvasGuidePick.axisSlackOnScreen / zoom)
        refreshOverlays()
    }

    /// What the pointer says inside the mode: the open hand over the zero
    /// point's knob or markers, and a crosshair everywhere else, where a click
    /// pins or picks up a guide.
    func gridAdjustCursor(at documentPoint: CGPoint) -> NSCursor? {
        grabsGridOrigin(at: documentPoint) || grabsGuide(at: documentPoint) != nil
            ? .openHand : .crosshair
    }

    // MARK: - Pressing

    /// A press inside the mode, in the order the three meanings are tried.
    func beginGridAdjustPress(at viewPoint: CGPoint, freeing: Bool) {
        guard let viewport else { return }
        let point = viewport.documentPoint(fromView: viewPoint)
        // 1. The zero point, by its knob or either of its markers.
        if grabsGridOrigin(at: point) {
            gridOriginDragging = true
            moveGridOrigin(toViewPoint: viewPoint, freeing: freeing)
            return
        }
        // 2. A guide already pinned under the pointer: pick it up to move it.
        if let guide = grabsGuide(at: point) {
            onGuideSelect(guide.id)
            guideDragging = true
            refreshOverlays()
            return
        }
        // 3. Anywhere else: pin the line the pointer is lighting. The highlight
        // is recomputed here rather than trusted, because a click can arrive
        // without a hover having reached this view first.
        refreshGuideHighlight(at: viewPoint)
        guard let line = guideHighlight else { return }
        onGuidePin(line)
        guideDragging = true
        refreshOverlays()
    }

    /// The held guide following the pointer, line by line: it lands on grid
    /// lines exactly the way pinning one does, so a guide dragged about is
    /// always on a line you can see.
    func dragHeldGuide(toViewPoint viewPoint: CGPoint) {
        guard let viewport, let settings = canvasGrid,
              let held = canvasGuides.first(where: { $0.id == selectedGuideID }) else { return }
        let zoom = max(viewport.zoom, 0.0001)
        let point = viewport.documentPoint(fromView: viewPoint)
        let spacing = settings.liveSpacing(atZoom: zoom)
        guard spacing.isFinite, spacing > 0 else { return }
        // A guide keeps the way it runs while it is being dragged: picking a
        // vertical one up and sliding it sideways must not turn it into a
        // horizontal one halfway across.
        let position: CGFloat = held.axis == .vertical
            ? canvasGridOrigin.x + ((point.x - canvasGridOrigin.x) / spacing).rounded() * spacing
            : canvasGridOrigin.y + ((point.y - canvasGridOrigin.y) / spacing).rounded() * spacing
        onGuideMove(CanvasGuideLine(axis: held.axis, position: position))
        refreshOverlays()
    }

    // MARK: - What is under the pointer

    /// Whether a press at this document point takes hold of the zero point.
    /// Also what the hover asks, so the highlight and the press can never
    /// disagree about who owns the pointer.
    func grabsGridOrigin(at point: CGPoint) -> Bool {
        guard let origin = gridAdjust, let viewport else { return false }
        let reach = Self.gridOriginGrabOnScreen / max(viewport.zoom, 0.0001)
        return abs(point.x - origin.x) <= reach || abs(point.y - origin.y) <= reach
    }

    /// The pinned guide a press at this document point picks up, if any.
    private func grabsGuide(at point: CGPoint) -> CanvasGuide? {
        guard gridAdjust != nil, let viewport else { return nil }
        let reach = Self.guideGrabOnScreen / max(viewport.zoom, 0.0001)
        return CanvasGuides.nearest(canvasGuides, to: point, within: reach)
    }
}

#if PHOTONZ_PLAYTEST
extension EditorState {
    /// The guides on this picture as a walk reads them: where each one is and
    /// which way it runs, plus whether the mode is holding one. Read off the
    /// document (or the working copy) rather than off the layers, because what
    /// a walk is checking is that a guide is THERE, not that it is drawn.
    var playtestGuidesReport: String {
        let guides = canvasGuides
        guard !guides.isEmpty else { return isAdjustingGrid ? "adjusting, none" : "none" }
        let listed = guides.map { guide in
            let axis = guide.axis == .vertical ? "x" : "y"
            let held = guide.id == selectedGuideID ? "*" : ""
            return "\(axis)\(CanvasGridNumber.text(guide.position))\(held)"
        }.joined(separator: " ")
        return (isAdjustingGrid ? "adjusting · " : "") + listed
    }
}
#endif
