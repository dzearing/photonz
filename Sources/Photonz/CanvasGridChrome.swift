import AppKit
import PhotonzCore

/// The grid you build against, drawn on the canvas (Next, `next-canvas-grid`).
///
/// It is chrome, not content: it is drawn by this view rather than by the
/// renderer, so it never lands in an export or a copied picture and costs the
/// document nothing.
///
/// Four things make it behave:
///
/// - **The surround always carries it; the switch decides the picture.** The
///   grey around the canvas is the surface you are working on, and a surface
///   for building UI is graph paper, so it is graph paper whatever the switch
///   says. What the switch changes is the PICTURE: on, and the grid is drawn
///   over it, still there once you have drawn something on top; off, and the
///   grid goes UNDER the picture, so the canvas's own drop shadow falls across
///   the paper and the paper reads as the surface the picture is lying on
///   rather than as ink printed over its shadow. One set of layers either way,
///   moved rather than duplicated, so the switch costs a re-order and nothing
///   else.
///
/// - **A ladder, not a spacing.** `CanvasGridLevels` picks which rungs to draw
///   at the current zoom and how strongly, so the lines are never closer
///   together than a person can read and never disappear on the way out. Each
///   rung's lines are a subset of the finer rung's, so the rungs stack: a line
///   several rungs share comes out stronger, which is what makes every Nth line
///   countable without a second rule that could fall out of step with the fade.
/// - **Only what is on screen.** The paths hold the lines inside the view and
///   nothing else, so a huge document costs the same as a small one. With the
///   ladder's floor of eight view points that bounds the whole thing at roughly
///   the view's width over eight, whatever the spacing — and running the lines
///   out over the surround as well adds no lines at all, only length to the
///   ones already being drawn.
/// - **The accent, sunk into the surface.** The lines are the brand colour
///   mixed halfway into a neutral and drawn at a low alpha, resolved against
///   the window's own appearance so they read the same in light and dark.
extension CanvasNSView {

    /// Whether a grid can be drawn at all.
    var canvasGridEnabled: Bool { Experiments.shared.canvasGridEnabled }

    func refreshCanvasGrid() {
        refreshGridOriginMarkers()
        guard canvasGridEnabled, let settings = canvasGrid,
              let viewport, viewport.zoom > 0 else {
            hideCanvasGrid()
            return
        }
        // The whole view, picture and surround alike. The lines run right
        // across, and where the picture sits is a question of which side of it
        // these layers are on, not of where the paths stop.
        placeCanvasGrid(overPicture: settings.isVisible)
        let visible = bounds
        guard visible.width > 0.5, visible.height > 0.5 else {
            hideCanvasGrid()
            return
        }

        // `drawnSpacing`, not `spacing`: a smallest cell raises the base of the
        // ladder, so the grid is never drawn finer than the cell asked for
        // however far in you go. What a drag LANDS on is still the spacing.
        let levels = CanvasGridLevels.levels(spacing: settings.drawnSpacing,
                                             majorEvery: settings.majorEvery,
                                             zoom: viewport.zoom)
        guard !levels.isEmpty else {
            hideCanvasGrid()
            return
        }

        let topLeft = viewport.documentPoint(fromView: CGPoint(x: visible.minX, y: visible.minY))
        let bottomRight = viewport.documentPoint(fromView: CGPoint(x: visible.maxX, y: visible.maxY))
        let ink = canvasGridInk()

        for (index, shape) in canvasGridLayers.enumerated() {
            guard index < levels.count else {
                shape.path = nil
                shape.isHidden = true
                continue
            }
            let level = levels[index]
            let path = CGMutablePath()
            for x in CanvasGridLevels.lines(spacing: level.spacing,
                                            from: topLeft.x, to: bottomRight.x,
                                            origin: settings.origin.x) {
                // Whole view points keep a one point line on whole device
                // pixels, which is the difference between a hairline and a
                // grey smear.
                let vx = viewport.viewPoint(fromDocument: CGPoint(x: x, y: 0)).x.rounded()
                path.move(to: CGPoint(x: vx, y: visible.minY))
                path.addLine(to: CGPoint(x: vx, y: visible.maxY))
            }
            if settings.axes.drawsRows {
                for y in CanvasGridLevels.lines(spacing: level.spacing,
                                                from: topLeft.y, to: bottomRight.y,
                                                origin: settings.origin.y) {
                    let vy = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: y)).y.rounded()
                    path.move(to: CGPoint(x: visible.minX, y: vy))
                    path.addLine(to: CGPoint(x: visible.maxX, y: vy))
                }
            }
            shape.path = path
            shape.strokeColor = ink
            shape.opacity = Float(level.opacity)
            shape.isHidden = path.isEmpty
        }
    }

    /// The two markers that say where the grid starts, drawn only while the
    /// zero point is being placed. They run right across the view, one down and
    /// one across, in the accent at full strength: the grid they are placing is
    /// a faint wash of the same colour, so the pair reads as the thing you are
    /// holding rather than as two lines of it.
    private func refreshGridOriginMarkers() {
        guard canvasGridEnabled, let origin = gridOriginAdjust, let viewport,
              bounds.width > 0.5, bounds.height > 0.5 else {
            gridOriginLayer.path = nil
            gridOriginLayer.isHidden = true
            return
        }
        let point = viewport.viewPoint(fromDocument: origin)
        let path = CGMutablePath()
        // Whole view points, for the same reason the grid rounds: a two point
        // line off the pixel grid is a four point smear.
        let x = point.x.rounded()
        let y = point.y.rounded()
        path.move(to: CGPoint(x: x, y: bounds.minY))
        path.addLine(to: CGPoint(x: x, y: bounds.maxY))
        path.move(to: CGPoint(x: bounds.minX, y: y))
        path.addLine(to: CGPoint(x: bounds.maxX, y: y))
        gridOriginLayer.path = path
        gridOriginLayer.isHidden = false
    }

    /// What the grid is drawing RIGHT NOW, read off the layers themselves
    /// rather than recomputed from the settings: the zoom, then one strength
    /// per rung that has a path and is not hidden, and which side of the
    /// picture the grid is on. A walk asserts on this, so it is the layers'
    /// own answer that has to hold, not the ladder's.
    var playtestGridReport: String {
        guard canvasGridEnabled else { return "grid off in Experiments" }
        guard let viewport else { return "no viewport" }
        let zoom = String(format: "%.4f", Double(viewport.zoom))
        guard canvasGrid != nil else { return "zoom \(zoom) · no settings · nothing drawn" }
        let drawn = canvasGridLayers.filter { !$0.isHidden && ($0.path?.isEmpty == false) }
        guard !drawn.isEmpty else { return "zoom \(zoom) · nothing drawn" }
        let strengths = drawn.map { String(format: "%.3f", $0.opacity) }.joined(separator: " ")
        let side = canvasGrid?.isVisible == true ? "over" : "under"
        // What a drag would land on right now, beside what is being drawn, so
        // one line of the log answers "does the pull match the picture".
        let pull = canvasSnapSpacing.map { String(format: "%g", Double($0)) } ?? "nothing"
        return "zoom \(zoom) · \(drawn.count) rungs · \(strengths) · \(side) · pulls to \(pull)"
    }

    /// Whether a person can see the grid at all at this instant: something
    /// drawn, and the strongest rung strong enough to read.
    var playtestGridIsVisible: Bool {
        guard canvasGridEnabled, canvasGrid != nil else { return false }
        return canvasGridLayers.contains {
            !$0.isHidden && ($0.path?.isEmpty == false)
                && CGFloat($0.opacity) >= CanvasGridLevels.minimumDrawnOpacity
        }
    }

    private func hideCanvasGrid() {
        for shape in canvasGridLayers where !shape.isHidden {
            shape.path = nil
            shape.isHidden = true
        }
    }

    /// The accent, mixed halfway into a neutral so it belongs to the surface
    /// instead of lying on top of it, resolved against the window's own
    /// appearance so it reads in light and in dark. The strength is the rung's,
    /// applied to the layer, so one colour serves all three.
    private func canvasGridInk() -> CGColor {
        var ink = CGColor(gray: 0.5, alpha: 1)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let neutral = NSColor.secondaryLabelColor.withAlphaComponent(1)
            // Mostly neutral, with enough of the accent left in it to belong to
            // the app. Any more accent and it reads as blueprint paper laid on
            // the canvas rather than as the canvas's own surface.
            let tinted = NSColor.controlAccentColor.blended(withFraction: 0.62, of: neutral)
                ?? NSColor.controlAccentColor
            if let converted = tinted.usingColorSpace(.sRGB) {
                ink = converted.withAlphaComponent(1).cgColor
            }
        }
        return ink
    }
}
