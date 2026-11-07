import AppKit
import PhotonzCore

/// An icon's artboard ruled into its units, drawn on the canvas (Next,
/// `a-24-unit-artboard-rules-itself-into-units`). Where the lines fall is
/// `IconUnits`; the rule this follows is UX-PATTERNS D16.
///
/// - **The Grid's own switch.** Nothing here to set and nothing shown with the
///   Grid off, which is how the mock has it: its artboard is plain until step 1
///   turns the grid on.
/// - **Under the keylines, over the drawing.** They are added just below the
///   keyline group, so a keyline is never crossed out by a unit, and a filled
///   shape does not hide the units it is sitting on.
/// - **The grid's ink.** The same colour and the same strength as a rung of the
///   canvas grid, so this reads as the grid getting finer on the artboard and
///   not as a third kind of line beside the violet keylines. The fourth units
///   are the same strength drawn again, as a shared rung is.
/// - **In the canvas grid's place.** It steps round whatever is ruled, because
///   two grids counted from different places cannot be read at once. Too far
///   out to rule, it runs across the artboard as it always did.
/// - **A dot on every crossing of the live area while the units pull**, the
///   mock's step 3: the lines say where the units are, the dots say a point
///   will land on them. View ▸ Snap in Icons ▸ Grid off takes the dots away and
///   leaves the lines, which is how the two read apart.
extension CanvasNSView {

    /// Whether the Grid has asked for units at all. While the grid's zero point
    /// is being placed the person is working on the canvas grid, so its lines
    /// come back across the artboard for as long as that lasts.
    private var iconUnitsAsked: Bool {
        framesEnabled && canvasGridEnabled && Experiments.shared.iconFramesEnabled
            && canvasGrid?.isVisible == true && gridAdjust == nil
    }

    /// Rules every icon on screen and hands back where each one is, in view
    /// points, for the canvas grid to step round.
    @discardableResult
    func refreshIconUnitChrome() -> [CGRect] {
        drawnIconUnits = []
        guard iconUnitsAsked, let viewport, let document, document.hasIconFrames,
              bounds.width > 0.5, bounds.height > 0.5 else {
            hideIconUnitChrome()
            return []
        }
        let topLeft = viewport.documentPoint(fromView: CGPoint(x: bounds.minX, y: bounds.minY))
        let bottomRight = viewport.documentPoint(fromView: CGPoint(x: bounds.maxX, y: bounds.maxY))
        let showing = CGRect(x: topLeft.x, y: topLeft.y,
                             width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y)

        let units = CGMutablePath()
        let strong = CGMutablePath()
        let dots = CGMutablePath()
        var dotCount = 0
        var ruled: [CGRect] = []
        for id in document.shownIconIDs {
            // A frame's box follows a drag; a canvas made as an icon has no layer.
            guard let box = id == PhotonzDocument.iconCanvasID ? document.iconBox(of: id)
                                                               : liveCanvasBounds(of: id),
                  box.intersects(showing),
                  let ruling = IconUnits.ruling(of: box, zoom: viewport.zoom, showing: showing,
                                                unit: document.iconUnit(of: id))
            else { continue }
            let onScreen = viewRect(forDocRect: box, in: viewport)
            addIconUnitLines(columns: ruling.columns, rows: ruling.rows,
                             across: onScreen, to: units, in: viewport)
            addIconUnitLines(columns: ruling.strongColumns, rows: ruling.strongRows,
                             across: onScreen, to: strong, in: viewport)
            if iconSnapsToUnits {
                let unit = document.iconUnit(of: id)
                let crossings = IconUnits.crossings(of: ruling, zoom: viewport.zoom, unit: unit)
                addIconUnitDots(crossings, gap: viewport.zoom * unit, to: dots, in: viewport)
                dotCount += crossings.count
            }
            drawnIconUnits.append(ruling)
            ruled.append(onScreen)
        }
        let ink = canvasGridInk()
        for (shape, path) in zip(iconUnitLayers, [units, strong]) {
            shape.path = path
            shape.strokeColor = ink
            shape.opacity = Float(CanvasGridLevels.maximumOpacity)
            shape.isHidden = path.isEmpty
        }
        iconUnitDotLayer.path = dots
        iconUnitDotLayer.fillColor = NSColor.controlAccentColor.cgColor
        iconUnitDotLayer.opacity = Self.iconUnitDotOpacity
        iconUnitDotLayer.isHidden = dots.isEmpty
        drawnIconUnitDots = dotCount
        return ruled
    }

    /// The mock's dots at the mock's strength (`.ig-dots`).
    private static let iconUnitDotOpacity: Float = 0.34

    /// Each dot sits where its two lines cross on screen, rounded the way
    /// `addIconUnitLines` rounds them, so a dot is never a pixel beside its
    /// crossing. The mock's radius is seven hundredths of a unit; it is held
    /// between one point and two so it stays a dot at every zoom one is drawn.
    private func addIconUnitDots(_ crossings: [CGPoint], gap: CGFloat,
                                 to path: CGMutablePath, in viewport: Viewport) {
        let radius = min(max(gap * 0.07, 1), 2)
        for crossing in crossings {
            let view = viewport.viewPoint(fromDocument: crossing)
            path.addEllipse(in: CGRect(x: view.x.rounded() + 0.5 - radius,
                                       y: view.y.rounded() + 0.5 - radius,
                                       width: radius * 2, height: radius * 2))
        }
    }

    /// A line on every position, edge to edge of the artboard, snapped exactly
    /// as a keyline is (`addIconKeylineLine`). Most keylines sit ON a unit, and
    /// any other rounding puts the two side by side a pixel apart.
    private func addIconUnitLines(columns: [CGFloat], rows: [CGFloat], across box: CGRect,
                                  to path: CGMutablePath, in viewport: Viewport) {
        for x in columns {
            let vx = viewport.viewPoint(fromDocument: CGPoint(x: x, y: 0)).x.rounded() + 0.5
            path.move(to: CGPoint(x: vx, y: box.minY.rounded()))
            path.addLine(to: CGPoint(x: vx, y: box.maxY.rounded()))
        }
        for y in rows {
            let vy = viewport.viewPoint(fromDocument: CGPoint(x: 0, y: y)).y.rounded() + 0.5
            path.move(to: CGPoint(x: box.minX.rounded(), y: vy))
            path.addLine(to: CGPoint(x: box.maxX.rounded(), y: vy))
        }
    }

    private func hideIconUnitChrome() {
        for shape in iconUnitLayers + [iconUnitDotLayer] where !shape.isHidden {
            shape.path = nil
            shape.isHidden = true
        }
        drawnIconUnitDots = 0
    }

    // MARK: What a drag lands on

    /// The lines a drag of these layers lands on: the units of the artboard
    /// holding them while it is ruled, otherwise the canvas grid. What you land
    /// on is always something you can see yourself land on.
    func canvasGridPull(holding ids: [UUID]) -> CanvasGridPull {
        gridPull(onUnitsOf: viewport.flatMap { document?.iconUnitBox(holding: ids, zoom: $0.zoom) })
    }

    /// The same, for a point being put down rather than a layer being moved.
    func canvasGridPull(at point: CGPoint) -> CanvasGridPull {
        gridPull(onUnitsOf: viewport.flatMap { document?.iconUnitBox(under: point, zoom: $0.zoom) })
    }

    /// The canvas's own lines, whatever is on it.
    var plainCanvasGridPull: CanvasGridPull {
        CanvasGridPull(spacing: canvasSnapSpacing, origin: canvasSnapOrigin, axes: canvasSnapAxes)
    }

    /// With either magnet off nothing pulls: the canvas grid's lines are not
    /// drawn in here, so they are not what a drag falls back to.
    private func gridPull(onUnitsOf box: CGRect?) -> CanvasGridPull {
        guard iconUnitsAsked, let box else { return plainCanvasGridPull }
        let pulls = canvasGrid?.snapsToGrid == true && IconSnapStore.shared.choices.grid
        let unit = document?.iconUnit(ofBox: box) ?? 1
        return CanvasGridPull(spacing: pulls ? unit : nil, origin: box.origin, axes: .columnsAndRows)
    }

    /// What is ruled RIGHT NOW, for a scripted walk to read: the counts each
    /// artboard was drawn with and how far apart the units are on screen.
    var playtestIconUnitReport: String {
        guard let viewport else { return "no viewport" }
        guard !drawnIconUnits.isEmpty, iconUnitLayers.contains(where: { !$0.isHidden }) else {
            return "nothing ruled"
        }
        let gap = String(format: "%g", Double(viewport.zoom))
        return drawnIconUnits.map { ruling in
            "\(Int(ruling.frame.width)) unit artboard · \(ruling.columns.count) columns"
                + " \(ruling.rows.count) rows · \(ruling.strongColumns.count) strong"
                + " columns \(ruling.strongRows.count) strong rows"
        }.joined(separator: " | ") + " · \(gap) points apart · \(drawnIconUnitDots) dots"
    }
}
